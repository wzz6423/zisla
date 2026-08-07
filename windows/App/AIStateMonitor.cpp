#include "pch.h"
#include "AIStateMonitor.h"

#include <shlobj.h>

#include <array>
#include <cstddef>
#include <iterator>
#include <memory>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 30'000;
constexpr DWORD token_poll_interval_ms = 1'000;
constexpr DWORD change_settle_interval_ms = 100;
constexpr DWORD notification_buffer_bytes = 16 * 1'024;

}

AIStateMonitor::AIStateMonitor(std::filesystem::path state_directory)
    : state_directory_(std::move(state_directory)),
      snapshot_(std::make_shared<const ActivityList>()) {}

AIStateMonitor::~AIStateMonitor() {
    stop();
}

bool AIStateMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0 || state_directory_.empty()) {
        return false;
    }

    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stop_event_) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
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

void AIStateMonitor::stop() noexcept {
    if (stop_event_) {
        (void)SetEvent(stop_event_);
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    if (stop_event_) {
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
    }
    running_.store(false, std::memory_order_release);
    target_ = nullptr;
    changed_message_ = 0;
}

bool AIStateMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const AIStateMonitor::ActivityList>
AIStateMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

AIStateMonitor::NoticeList AIStateMonitor::takeNotices() {
    std::scoped_lock lock(pending_notices_mutex_);
    NoticeList result;
    result.swap(pending_notices_);
    return result;
}

std::optional<std::filesystem::path>
AIStateMonitor::defaultStateDirectory() noexcept {
    PWSTR local_app_data = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_NO_PACKAGE_REDIRECTION,
            nullptr,
            &local_app_data))) {
        return std::nullopt;
    }

    try {
        auto result = std::filesystem::path{local_app_data} / L"zisla";
        CoTaskMemFree(local_app_data);
        return result;
    } catch (...) {
        CoTaskMemFree(local_app_data);
        return std::nullopt;
    }
}

void AIStateMonitor::run() noexcept {
    while (!waitForStop(0)) {
        std::error_code directory_error;
        std::filesystem::create_directories(state_directory_, directory_error);
        if (directory_error) {
            if (waitForStop(retry_interval_ms)) {
                break;
            }
            continue;
        }

        const auto raw_directory = CreateFileW(
            state_directory_.c_str(),
            FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
            nullptr);
        if (raw_directory == INVALID_HANDLE_VALUE) {
            if (waitForStop(retry_interval_ms)) {
                break;
            }
            continue;
        }

        winrt::handle directory;
        directory.attach(raw_directory);
        scanAndPublish(true);
        if (watchDirectory(directory.get())) {
            break;
        }
        if (waitForStop(token_poll_interval_ms)) {
            break;
        }
    }

    running_.store(false, std::memory_order_release);
}

bool AIStateMonitor::watchDirectory(HANDLE directory) noexcept {
    winrt::handle changed_event;
    changed_event.attach(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!changed_event) {
        return waitForStop(0);
    }

    alignas(DWORD) std::array<std::byte, notification_buffer_bytes> buffer{};
    const HANDLE events[] = {stop_event_, changed_event.get()};

    while (!waitForStop(0)) {
        (void)ResetEvent(changed_event.get());
        OVERLAPPED overlapped{};
        overlapped.hEvent = changed_event.get();
        if (!ReadDirectoryChangesW(
                directory,
                buffer.data(),
                static_cast<DWORD>(buffer.size()),
                FALSE,
                FILE_NOTIFY_CHANGE_FILE_NAME
                    | FILE_NOTIFY_CHANGE_SIZE
                    | FILE_NOTIFY_CHANGE_LAST_WRITE
                    | FILE_NOTIFY_CHANGE_CREATION,
                nullptr,
                &overlapped,
                nullptr)) {
            return false;
        }

        DWORD wait_result = WAIT_TIMEOUT;
        while (wait_result == WAIT_TIMEOUT) {
            wait_result = WaitForMultipleObjects(
                static_cast<DWORD>(std::size(events)),
                events,
                FALSE,
                token_poll_interval_ms);
            if (wait_result == WAIT_TIMEOUT) {
                scanAndPublish(false);
            }
        }
        if (wait_result == WAIT_OBJECT_0) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            return true;
        }
        if (wait_result != WAIT_OBJECT_0 + 1) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            return waitForStop(0);
        }

        DWORD bytes_returned = 0;
        if (!GetOverlappedResult(
                directory,
                &overlapped,
                &bytes_returned,
                FALSE)) {
            scanAndPublish(false);
            return waitForStop(0);
        }
        (void)bytes_returned;
        if (waitForStop(change_settle_interval_ms)) {
            return true;
        }
        scanAndPublish(false);
    }
    return true;
}

void AIStateMonitor::scanAndPublish(bool force) noexcept {
    try {
        const zisla::core::AIStateRepository repository(state_directory_);
        const auto before = repository.storage_change_token();
        if (!force && token_initialized_ && before == last_token_) {
            return;
        }
        auto state = repository.load(false);
        auto next = std::make_shared<const ActivityList>(std::move(state.tasks));
        auto notices = repository.take_notices();
        if (!notices.empty()) {
            try {
                std::scoped_lock lock(pending_notices_mutex_);
                if (pending_notices_.empty()) {
                    pending_notices_.swap(notices);
                } else {
                    pending_notices_.reserve(
                        pending_notices_.size() + notices.size());
                    pending_notices_.insert(
                        pending_notices_.end(),
                        std::make_move_iterator(notices.begin()),
                        std::make_move_iterator(notices.end()));
                }
            } catch (...) {
                repository.enqueue_notices(notices);
                throw;
            }
        }
        snapshot_.store(std::move(next), std::memory_order_release);
        last_token_ = repository.storage_change_token();
        token_initialized_ = true;
        (void)PostMessageW(target_, changed_message_, 0, 0);
    } catch (...) {
    }
}

bool AIStateMonitor::waitForStop(DWORD timeout_ms) const noexcept {
    if (!stop_event_) {
        return true;
    }
    return WaitForSingleObject(stop_event_, timeout_ms) != WAIT_TIMEOUT;
}

}
