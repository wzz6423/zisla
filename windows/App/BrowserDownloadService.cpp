#include "pch.h"
#include "BrowserDownloadService.h"

#include <sqlite3.h>
#include <shlobj.h>

#include <algorithm>
#include <chrono>
#include <climits>
#include <optional>
#include <string_view>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 100;
constexpr int max_open_retries = 3;
constexpr auto completed_retention = std::chrono::seconds(3);

class SqliteDatabase {
public:
    SqliteDatabase() = default;
    ~SqliteDatabase() {
        if (value_) {
            (void)sqlite3_close(value_);
        }
    }

    SqliteDatabase(const SqliteDatabase&) = delete;
    SqliteDatabase& operator=(const SqliteDatabase&) = delete;

    [[nodiscard]] sqlite3** put() noexcept {
        return &value_;
    }

    [[nodiscard]] sqlite3* get() const noexcept {
        return value_;
    }

    void reset() noexcept {
        if (value_) {
            (void)sqlite3_close(value_);
            value_ = nullptr;
        }
    }

private:
    sqlite3* value_{nullptr};
};

class SqliteStatement {
public:
    SqliteStatement() = default;
    ~SqliteStatement() {
        if (value_) {
            (void)sqlite3_finalize(value_);
        }
    }

    SqliteStatement(const SqliteStatement&) = delete;
    SqliteStatement& operator=(const SqliteStatement&) = delete;

    [[nodiscard]] sqlite3_stmt** put() noexcept {
        return &value_;
    }

    [[nodiscard]] sqlite3_stmt* get() const noexcept {
        return value_;
    }

private:
    sqlite3_stmt* value_{nullptr};
};

std::optional<std::wstring> known_folder_path(REFKNOWNFOLDERID folder_id) {
    wchar_t* raw_path = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &raw_path))) {
        return std::nullopt;
    }
    std::wstring result{raw_path};
    CoTaskMemFree(raw_path);
    return result;
}

std::optional<std::string> utf8_from_wide(std::wstring_view value) noexcept {
    if (value.empty() || value.size() > static_cast<std::size_t>(INT_MAX)) {
        return value.empty() ? std::optional<std::string>{std::string{}}
                             : std::nullopt;
    }
    const auto length = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (length <= 0) {
        return std::nullopt;
    }
    std::string result(static_cast<std::size_t>(length), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length,
            nullptr,
            nullptr) != length) {
        return std::nullopt;
    }
    return result;
}

std::optional<std::vector<std::filesystem::path>> history_databases(
    const std::filesystem::path& browser_root) {
    std::vector<std::filesystem::path> result;
    std::error_code error;
    if (!std::filesystem::is_directory(browser_root, error) || error) {
        return std::nullopt;
    }

    const auto add_history = [&result](const std::filesystem::path& path) {
        std::error_code path_error;
        if (std::filesystem::is_regular_file(path, path_error) && !path_error) {
            result.push_back(path);
        }
    };
    add_history(browser_root / L"History");

    std::filesystem::directory_iterator iterator(
        browser_root,
        std::filesystem::directory_options::skip_permission_denied,
        error);
    const std::filesystem::directory_iterator end;
    while (!error && iterator != end) {
        const auto entry = *iterator;
        std::error_code entry_error;
        if (entry.is_directory(entry_error) && !entry_error) {
            const auto name = entry.path().filename().wstring();
            if (name == L"Default"
                || name.starts_with(L"Profile ")
                || name == L"Guest Profile"
                || name == L"System Profile") {
                add_history(entry.path() / L"History");
            }
        }
        iterator.increment(error);
    }
    if (error) {
        return std::nullopt;
    }

    std::sort(result.begin(), result.end());
    result.erase(std::unique(result.begin(), result.end()), result.end());
    return result;
}

bool wait_for_retry(HANDLE stop_event) noexcept {
    return !stop_event
        || WaitForSingleObject(stop_event, retry_interval_ms) == WAIT_TIMEOUT;
}

std::string row_identity(
    const std::filesystem::path& history_path,
    std::int64_t id) {
    const auto path = utf8_from_wide(history_path.wstring()).value_or(std::string{});
    std::string result = path;
    result.push_back('#');
    result.append(std::to_string(id));
    return result;
}

}  // namespace

BrowserDownloadService::BrowserDownloadService()
    : snapshot_(std::make_shared<const BrowserDownloadServiceSnapshot>()) {}

BrowserDownloadService::~BrowserDownloadService() {
    stop();
}

bool BrowserDownloadService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_.load(std::memory_order_acquire)
        || thread_.joinable()
        || !target
        || changed_message == 0) {
        return false;
    }

    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stop_event_) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    trackers_.clear();
    revision_ = 0;
    first_scan_ = true;
    snapshot_.store(
        std::make_shared<const BrowserDownloadServiceSnapshot>(),
        std::memory_order_release);
    running_.store(true, std::memory_order_release);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_.store(false, std::memory_order_release);
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void BrowserDownloadService::stop() noexcept {
    HANDLE stop_event = nullptr;
    {
        std::lock_guard lock(mutex_);
        if (!running_.load(std::memory_order_acquire) && !thread_.joinable()) {
            return;
        }
        running_.store(false, std::memory_order_release);
        stop_event = stop_event_;
    }
    if (stop_event) {
        (void)SetEvent(stop_event);
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    if (stop_event_) {
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
    }
    target_ = nullptr;
    changed_message_ = 0;
}

std::shared_ptr<const BrowserDownloadServiceSnapshot>
BrowserDownloadService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void BrowserDownloadService::run() noexcept {
    std::size_t consecutive_idle_scans = 0;
    while (running_.load(std::memory_order_acquire)) {
        try {
            std::vector<ScanRow> rows;
            if (scanAllBrowsers(rows)) {
                updateTracking(rows);
                publish();
            } else {
                publish("浏览器下载数据库暂时不可读");
            }
        } catch (...) {
            publish("浏览器下载状态读取失败");
        }

        const auto current = snapshot();
        const bool has_visible_activity = current
            && (current->summary.total_active_count > 0
                || !current->recently_completed.empty());
        consecutive_idle_scans = has_visible_activity
            ? 0
            : std::min(consecutive_idle_scans + 1, std::size_t{3});
        const auto interval = zisla::core::BrowserDownloadPollingPolicy::next_interval(
            has_visible_activity,
            consecutive_idle_scans);
        if (stop_event_
            && WaitForSingleObject(
                    stop_event_,
                    static_cast<DWORD>(interval.count())) == WAIT_OBJECT_0) {
            break;
        }
    }
    running_.store(false, std::memory_order_release);
}

bool BrowserDownloadService::scanAllBrowsers(
    std::vector<ScanRow>& rows) {
    rows.clear();
    const auto local = known_folder_path(FOLDERID_LocalAppData);
    const auto roaming = known_folder_path(FOLDERID_RoamingAppData);
    if (!local && !roaming) {
        return false;
    }

    bool success = true;
    const auto scan = [this, &rows, &success](
                          zisla::core::BrowserDownloadSource source,
                          const std::optional<std::wstring>& root,
                          std::wstring_view relative) {
        if (!root) {
            return;
        }
        success = scanBrowserRoot(
            source,
            std::filesystem::path{*root}
                / std::filesystem::path{std::wstring{relative}},
            rows) && success;
    };

    scan(zisla::core::BrowserDownloadSource::chrome,
        local,
        L"Google\\Chrome\\User Data");
    scan(zisla::core::BrowserDownloadSource::edge,
        local,
        L"Microsoft\\Edge\\User Data");
    scan(zisla::core::BrowserDownloadSource::brave,
        local,
        L"BraveSoftware\\Brave-Browser\\User Data");
    scan(zisla::core::BrowserDownloadSource::vivaldi,
        local,
        L"Vivaldi\\User Data");
    scan(zisla::core::BrowserDownloadSource::arc,
        local,
        L"The Browser Company\\Arc\\User Data");
    scan(zisla::core::BrowserDownloadSource::arc,
        local,
        L"TheBrowserCompany\\Arc\\User Data");
    scan(zisla::core::BrowserDownloadSource::opera,
        roaming,
        L"Opera Software\\Opera Stable");
    scan(zisla::core::BrowserDownloadSource::opera,
        roaming,
        L"Opera Software\\Opera GX Stable");
    scan(zisla::core::BrowserDownloadSource::opera,
        local,
        L"Opera Software\\Opera Stable");

    return success;
}

bool BrowserDownloadService::scanBrowserRoot(
    zisla::core::BrowserDownloadSource source,
    const std::filesystem::path& browser_root,
    std::vector<ScanRow>& rows) {
    std::error_code error;
    if (!std::filesystem::exists(browser_root, error) && !error) {
        return true;
    }
    if (error) {
        return false;
    }

    const auto histories = history_databases(browser_root);
    if (!histories) {
        return false;
    }
    if (histories->empty()) {
        return true;
    }
    bool success = true;
    for (const auto& history : *histories) {
        success = scanHistoryDatabase(source, history, rows) && success;
    }
    return success;
}

bool BrowserDownloadService::scanHistoryDatabase(
    zisla::core::BrowserDownloadSource source,
    const std::filesystem::path& history_path,
    std::vector<ScanRow>& rows) {
    const auto utf8_path = utf8_from_wide(history_path.wstring());
    if (!utf8_path) {
        return false;
    }

    SqliteDatabase database;
    int open_result = SQLITE_ERROR;
    for (int attempt = 0; attempt < max_open_retries; ++attempt) {
        open_result = sqlite3_open_v2(
            utf8_path->c_str(),
            database.put(),
            SQLITE_OPEN_READONLY,
            nullptr);
        if (open_result == SQLITE_OK) {
            break;
        }
        database.reset();
        if ((open_result != SQLITE_BUSY && open_result != SQLITE_LOCKED
                && open_result != SQLITE_CANTOPEN)
            || attempt + 1 >= max_open_retries
            || !wait_for_retry(stop_event_)) {
            return false;
        }
    }
    if (open_result != SQLITE_OK || !database.get()) {
        return false;
    }
    (void)sqlite3_busy_timeout(database.get(), 250);

    constexpr char query[] =
        "SELECT id, target_path, current_path, state, received_bytes, "
        "total_bytes, start_time, end_time FROM downloads "
        "ORDER BY start_time DESC LIMIT 100";
    SqliteStatement statement;
    const auto prepare_result = sqlite3_prepare_v2(
            database.get(),
            query,
            -1,
            statement.put(),
            nullptr);
    if (prepare_result != SQLITE_OK) {
        const std::string_view message = sqlite3_errmsg(database.get());
        return message.find("no such table") != std::string_view::npos;
    }

    while (true) {
        const auto step = sqlite3_step(statement.get());
        if (step == SQLITE_DONE) {
            break;
        }
        if (step != SQLITE_ROW) {
            return false;
        }

        const auto id = zisla::core::ChromiumDownloadRowReader::read_int64(
            statement.get(),
            0);
        const auto state_code = zisla::core::ChromiumDownloadRowReader::read_int(
            statement.get(),
            3);
        if (!id || !state_code) {
            continue;
        }

        zisla::core::BrowserDownloadItem item;
        item.id = *id;
        item.source = source;
        item.state = zisla::core::BrowserDownloadStateMapper::map_chromium_state(
            *state_code);
        if (item.state != zisla::core::BrowserDownloadState::in_progress
            && item.state != zisla::core::BrowserDownloadState::complete) {
            continue;
        }
        if (const auto target = zisla::core::ChromiumDownloadRowReader::read_string(
                statement.get(),
                1)) {
            item.target_path = zisla::core::BrowserDownloadPathCleaner::remove_temporary_extension(
                *target);
        }
        if (const auto current = zisla::core::ChromiumDownloadRowReader::read_string(
                statement.get(),
                2)) {
            item.current_path = *current;
        }
        if (const auto received = zisla::core::ChromiumDownloadRowReader::read_int64(
                statement.get(),
                4)) {
            item.received_bytes = *received;
        }
        if (const auto total = zisla::core::ChromiumDownloadRowReader::read_int64(
                statement.get(),
                5)) {
            item.total_bytes = *total;
        }
        item.progress = zisla::core::BrowserDownloadProgressCalculator::calculate_progress(
            item.received_bytes,
            item.total_bytes);
        if (const auto start = zisla::core::ChromiumDownloadRowReader::read_int64(
                statement.get(),
                6)) {
            item.start_time_unix_ms = zisla::core::ChromiumTimeConverter::to_unix_ms(*start);
        }
        if (const auto end = zisla::core::ChromiumDownloadRowReader::read_int64(
                statement.get(),
                7)) {
            item.end_time_unix_ms = zisla::core::ChromiumTimeConverter::to_unix_ms(*end);
        }

        rows.push_back({
            .identity = row_identity(history_path, item.id),
            .item = std::move(item),
        });
    }
    return true;
}

void BrowserDownloadService::updateTracking(const std::vector<ScanRow>& rows) {
    const auto now = std::chrono::steady_clock::now();
    for (auto& [identity, tracker] : trackers_) {
        (void)identity;
        tracker.seen = false;
    }

    for (const auto& row : rows) {
        const auto existing = trackers_.find(row.identity);
        if (existing == trackers_.end()) {
            if (first_scan_
                && row.item.state != zisla::core::BrowserDownloadState::in_progress) {
                continue;
            }
            DownloadTracker tracker;
            tracker.item = row.item;
            if (row.item.state == zisla::core::BrowserDownloadState::complete) {
                tracker.completed_at = now;
            }
            tracker.seen = true;
            trackers_.emplace(row.identity, std::move(tracker));
            continue;
        }

        auto& tracker = existing->second;
        if (tracker.item.state == zisla::core::BrowserDownloadState::in_progress
            && row.item.state == zisla::core::BrowserDownloadState::complete) {
            tracker.completed_at = now;
        }
        if (row.item.state == zisla::core::BrowserDownloadState::complete
            && tracker.completed_at.time_since_epoch().count() == 0) {
            tracker.completed_at = now;
        }
        tracker.item = row.item;
        tracker.seen = true;
    }

    for (auto iterator = trackers_.begin(); iterator != trackers_.end();) {
        const auto& tracker = iterator->second;
        const bool expired = tracker.item.state
                == zisla::core::BrowserDownloadState::complete
            && tracker.completed_at.time_since_epoch().count() != 0
            && now - tracker.completed_at >= completed_retention;
        if ((!tracker.seen && !tracker.completed_at.time_since_epoch().count())
            || expired) {
            iterator = trackers_.erase(iterator);
        } else {
            ++iterator;
        }
    }
    first_scan_ = false;
}

void BrowserDownloadService::publish(std::string_view error) noexcept {
    try {
        BrowserDownloadServiceSnapshot next;
        next.revision = ++revision_;
        next.error = std::string{error};

        std::vector<zisla::core::BrowserDownloadItem> active;
        active.reserve(trackers_.size());
        const auto now = std::chrono::steady_clock::now();
        for (const auto& [identity, tracker] : trackers_) {
            if (tracker.item.state == zisla::core::BrowserDownloadState::in_progress) {
                active.push_back(tracker.item);
            } else if (tracker.item.state == zisla::core::BrowserDownloadState::complete
                && tracker.completed_at.time_since_epoch().count() != 0
                && now - tracker.completed_at < completed_retention) {
                next.recently_completed.push_back({identity, tracker.item});
            }
        }
        next.summary = zisla::core::BrowserDownloadSummarizer::summarize(active);
        snapshot_.store(
            std::make_shared<const BrowserDownloadServiceSnapshot>(std::move(next)),
            std::memory_order_release);
        notifyChanged();
    } catch (...) {
    }
}

void BrowserDownloadService::notifyChanged() const noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
