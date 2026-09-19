#include "zisla/core/OpenCodeSessionScanner.hpp"
#include "zisla/core/detail/BoundedRecent.hpp"

#include <sqlite3.h>
#include <yyjson.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;
using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

constexpr std::size_t maximum_identifier_bytes = 512;
constexpr std::size_t maximum_title_bytes = 512;
constexpr std::size_t maximum_model_bytes = 512;
constexpr int sqlite_busy_timeout_ms = 500;

struct MessageSummary {
    std::string type;
    std::optional<std::int64_t> completed_at_unix_ms;
    std::optional<std::string> finish;
    std::optional<std::string> model;
    std::optional<std::string> tool_status;
};

struct DatabaseScanResult {
    bool usable{false};
    std::vector<AIProgressTask> tasks;
};

struct StorageCandidate {
    fs::path path;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct StorageSession {
    std::string id;
    std::string title;
    std::int64_t updated_at_unix_ms{0};
    bool archived{false};
};

struct StorageMessage {
    std::string session_id;
    MessageSummary summary;
    std::int64_t updated_at_unix_ms{0};
};

std::string_view trim_ascii(std::string_view value) noexcept {
    const auto is_space = [](unsigned char character) noexcept {
        return character == ' ' || character == '\t' || character == '\r'
            || character == '\n' || character == '\f' || character == '\v';
    };
    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return value;
}

std::string ascii_lower(std::string_view value) {
    std::string result;
    result.reserve(value.size());
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        result.push_back(byte >= 'A' && byte <= 'Z'
            ? static_cast<char>(byte + ('a' - 'A'))
            : character);
    }
    return result;
}

std::optional<int> decimal_field(
    std::string_view value,
    std::size_t offset,
    std::size_t length) noexcept {
    if (offset > value.size() || length > value.size() - offset) {
        return std::nullopt;
    }
    int result = 0;
    for (std::size_t index = offset; index < offset + length; ++index) {
        const auto character = value[index];
        if (character < '0' || character > '9') {
            return std::nullopt;
        }
        result = result * 10 + (character - '0');
    }
    return result;
}

std::optional<std::int64_t> parse_rfc3339_unix_ms(
    std::string_view value) noexcept {
    value = trim_ascii(value);
    if (value.size() < 20 || value[4] != '-' || value[7] != '-'
        || (value[10] != 'T' && value[10] != 't') || value[13] != ':'
        || value[16] != ':') {
        return std::nullopt;
    }
    const auto year = decimal_field(value, 0, 4);
    const auto month = decimal_field(value, 5, 2);
    const auto day = decimal_field(value, 8, 2);
    const auto hour = decimal_field(value, 11, 2);
    const auto minute = decimal_field(value, 14, 2);
    const auto second = decimal_field(value, 17, 2);
    if (!year || !month || !day || !hour || !minute || !second
        || *hour > 23 || *minute > 59 || *second > 59) {
        return std::nullopt;
    }
    const std::chrono::year_month_day date{
        std::chrono::year{*year},
        std::chrono::month{static_cast<unsigned>(*month)},
        std::chrono::day{static_cast<unsigned>(*day)},
    };
    if (!date.ok()) {
        return std::nullopt;
    }

    std::size_t position = 19;
    int fractional_ms = 0;
    if (position < value.size() && value[position] == '.') {
        ++position;
        const auto fraction_start = position;
        int digits_used = 0;
        while (position < value.size() && value[position] >= '0'
            && value[position] <= '9') {
            if (digits_used < 3) {
                fractional_ms = fractional_ms * 10 + (value[position] - '0');
                ++digits_used;
            }
            ++position;
        }
        if (position == fraction_start) {
            return std::nullopt;
        }
        while (digits_used < 3) {
            fractional_ms *= 10;
            ++digits_used;
        }
    }

    int offset_minutes = 0;
    if (position < value.size()
        && (value[position] == 'Z' || value[position] == 'z')) {
        ++position;
    } else {
        if (position + 6 != value.size()
            || (value[position] != '+' && value[position] != '-')
            || value[position + 3] != ':') {
            return std::nullopt;
        }
        const auto offset_hour = decimal_field(value, position + 1, 2);
        const auto offset_minute = decimal_field(value, position + 4, 2);
        if (!offset_hour || !offset_minute || *offset_hour > 23
            || *offset_minute > 59) {
            return std::nullopt;
        }
        offset_minutes = (*offset_hour * 60 + *offset_minute)
            * (value[position] == '+' ? 1 : -1);
        position += 6;
    }
    if (position != value.size()) {
        return std::nullopt;
    }
    const auto time = std::chrono::sys_days{date}
        + std::chrono::hours{*hour} + std::chrono::minutes{*minute}
        + std::chrono::seconds{*second} + std::chrono::milliseconds{fractional_ms}
        - std::chrono::minutes{offset_minutes};
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               time.time_since_epoch())
        .count();
}

std::optional<std::int64_t> normalize_timestamp(std::int64_t timestamp) noexcept {
    if (timestamp > 1'000'000'000'000LL
        || timestamp < -1'000'000'000'000LL) {
        return timestamp;
    }
    if (timestamp > std::numeric_limits<std::int64_t>::max() / 1'000
        || timestamp < std::numeric_limits<std::int64_t>::min() / 1'000) {
        return std::nullopt;
    }
    return timestamp * 1'000;
}

std::optional<std::int64_t> numeric_timestamp(yyjson_val* value) noexcept {
    if (value && yyjson_is_sint(value)) {
        return normalize_timestamp(yyjson_get_sint(value));
    }
    if (value && yyjson_is_uint(value)) {
        const auto unsigned_value = yyjson_get_uint(value);
        if (unsigned_value <= static_cast<std::uint64_t>(
                                  std::numeric_limits<std::int64_t>::max())) {
            return normalize_timestamp(static_cast<std::int64_t>(unsigned_value));
        }
        return std::nullopt;
    }
    if (!value || !yyjson_is_real(value)) {
        return std::nullopt;
    }
    auto number = yyjson_get_real(value);
    if (!std::isfinite(number)) {
        return std::nullopt;
    }
    if (std::abs(number) <= 1'000'000'000'000.0) {
        number *= 1'000.0;
    }
    if (number < static_cast<double>(std::numeric_limits<std::int64_t>::min())
        || number > static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
        return std::nullopt;
    }
    return static_cast<std::int64_t>(number);
}

std::optional<std::string> json_string(
    yyjson_val* value,
    std::size_t maximum_bytes = maximum_identifier_bytes) {
    if (!value || !yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto* raw = yyjson_get_str(value);
    const auto size = yyjson_get_len(value);
    if (!raw || size == 0 || size > maximum_bytes) {
        return std::nullopt;
    }
    const auto normalized = trim_ascii({raw, size});
    return normalized.empty()
        ? std::nullopt
        : std::optional<std::string>{std::string(normalized)};
}

std::optional<std::int64_t> json_timestamp(yyjson_val* value) noexcept {
    if (const auto text = json_string(value, 128)) {
        if (const auto timestamp = parse_rfc3339_unix_ms(*text)) {
            return timestamp;
        }
        std::int64_t numeric = 0;
        const auto* begin = text->data();
        const auto* end = begin + text->size();
        const auto result = std::from_chars(begin, end, numeric);
        if (result.ec == std::errc{} && result.ptr == end) {
            return normalize_timestamp(numeric);
        }
    }
    return numeric_timestamp(value);
}

std::int64_t unix_milliseconds(fs::file_time_type time) noexcept {
    const auto system_time = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
        time - fs::file_time_type::clock::now() + std::chrono::system_clock::now());
    const auto count = std::chrono::duration_cast<std::chrono::milliseconds>(
                           system_time.time_since_epoch())
                           .count();
    if constexpr (sizeof(count) > sizeof(std::int64_t)) {
        return count > std::numeric_limits<std::int64_t>::max()
            ? std::numeric_limits<std::int64_t>::max()
            : count < std::numeric_limits<std::int64_t>::min()
            ? std::numeric_limits<std::int64_t>::min()
            : static_cast<std::int64_t>(count);
    }
    return static_cast<std::int64_t>(count);
}

std::int64_t current_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

std::int64_t recency_cutoff(
    std::int64_t now_unix_ms,
    std::int64_t threshold_ms) noexcept {
    if (threshold_ms <= 0) {
        return now_unix_ms;
    }
    return now_unix_ms <= std::numeric_limits<std::int64_t>::min() + threshold_ms
        ? std::numeric_limits<std::int64_t>::min()
        : now_unix_ms - threshold_ms;
}

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::string path_key(const fs::path& path) {
    const auto encoded = path.lexically_normal().generic_u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

std::string utf8_filename(const fs::path& path) {
    const auto encoded = path.filename().u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

bool has_json_extension(const fs::path& path) {
    const auto extension = path.extension().u8string();
    const std::string text{
        reinterpret_cast<const char*>(extension.data()),
        extension.size(),
    };
    return ascii_lower(text) == ".json";
}

std::optional<std::string> sqlite_text(
    sqlite3_stmt* statement,
    int column,
    std::size_t maximum_bytes) {
    if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
        return std::nullopt;
    }
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size <= 0 || static_cast<std::size_t>(size) > maximum_bytes) {
        return std::nullopt;
    }
    const std::string_view raw{
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
    const auto normalized = trim_ascii(raw);
    return normalized.empty()
        ? std::nullopt
        : std::optional<std::string>{std::string(normalized)};
}

bool table_exists(sqlite3* database, std::string_view name) noexcept {
    sqlite3_stmt* raw = nullptr;
    constexpr auto sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1";
    if (sqlite3_prepare_v2(database, sql, -1, &raw, nullptr) != SQLITE_OK) {
        return false;
    }
    std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(
        raw,
        &sqlite3_finalize);
    if (sqlite3_bind_text(
            statement.get(),
            1,
            name.data(),
            static_cast<int>(name.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        return false;
    }
    return sqlite3_step(statement.get()) == SQLITE_ROW;
}

MessageSummary parse_message_summary(
    std::string_view json,
    std::string_view column_type = {}) {
    MessageSummary summary;
    if (column_type.size() <= maximum_identifier_bytes) {
        summary.type = ascii_lower(column_type);
    }
    const JsonDocument document{
        yyjson_read(json.data(), json.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return summary;
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!root || !yyjson_is_obj(root)) {
        return summary;
    }
    auto* data = yyjson_obj_get(root, "data");
    if (!data || !yyjson_is_obj(data)) {
        data = root;
    }
    const auto string_from = [](yyjson_val* object, const char* key, std::size_t limit)
        -> std::optional<std::string> {
        return object && yyjson_is_obj(object)
            ? json_string(yyjson_obj_get(object, key), limit)
            : std::nullopt;
    };
    const auto first_string = [&string_from](
                                  yyjson_val* first,
                                  yyjson_val* second,
                                  const char* key,
                                  std::size_t limit) {
        if (const auto result = string_from(first, key, limit)) {
            return result;
        }
        return string_from(second, key, limit);
    };
    if (summary.type.empty()) {
        if (const auto role = first_string(data, root, "role", 128)) {
            summary.type = ascii_lower(*role);
        } else if (const auto type = first_string(data, root, "type", 128)) {
            summary.type = ascii_lower(*type);
        }
    }
    summary.finish = first_string(data, root, "finish", 128);
    summary.model = first_string(data, root, "modelID", maximum_model_bytes);
    if (!summary.model) {
        summary.model = first_string(data, root, "model", maximum_model_bytes);
    }
    summary.tool_status = first_string(data, root, "status", 128);
    if (!summary.tool_status) {
        summary.tool_status = first_string(data, root, "state", 128);
    }
    auto* time = yyjson_obj_get(data, "time");
    if (!time || !yyjson_is_obj(time)) {
        time = yyjson_obj_get(root, "time");
    }
    if (time && yyjson_is_obj(time)) {
        summary.completed_at_unix_ms = json_timestamp(yyjson_obj_get(time, "completed"));
    }
    return summary;
}

std::optional<AIProgressStatus> active_status_for(const MessageSummary& summary) {
    const auto type = ascii_lower(summary.type);
    if (type == "user") {
        return AIProgressStatus::running;
    }
    if (type == "assistant") {
        if (summary.completed_at_unix_ms
            && summary.finish
            && ascii_lower(*summary.finish) == "stop") {
            return std::nullopt;
        }
        if (summary.finish && ascii_lower(*summary.finish) == "error") {
            return AIProgressStatus::error;
        }
        return AIProgressStatus::running;
    }
    if (type == "tool") {
        const auto status = summary.tool_status
            ? ascii_lower(*summary.tool_status)
            : std::string{};
        if (status == "error" || status == "failed") {
            return AIProgressStatus::error;
        }
        if (status == "pending" || status == "running") {
            return AIProgressStatus::running;
        }
    }
    return std::nullopt;
}

void merge_task(
    AIProgressTask task,
    std::unordered_map<std::string, AIProgressTask>& tasks_by_id) {
    const auto existing = tasks_by_id.find(task.id);
    if (existing == tasks_by_id.end()
        || existing->second.updated_at_unix_ms <= task.updated_at_unix_ms) {
        tasks_by_id.insert_or_assign(task.id, std::move(task));
    }
}

DatabaseScanResult scan_database(
    const fs::path& path,
    const OpenCodeSessionScanOptions& options,
    std::int64_t cutoff) {
    std::error_code status_error;
    const auto status = fs::symlink_status(path, status_error);
    if (status_error || !fs::is_regular_file(status) || fs::is_symlink(status)) {
        return {};
    }
    sqlite3* raw = nullptr;
    const auto encoded_path = path.u8string();
    const std::string utf8_path{
        reinterpret_cast<const char*>(encoded_path.data()),
        encoded_path.size(),
    };
    if (sqlite3_open_v2(
            utf8_path.c_str(),
            &raw,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nullptr) != SQLITE_OK) {
        sqlite3_close(raw);
        return {};
    }
    std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(raw, &sqlite3_close);
    (void)sqlite3_busy_timeout(database.get(), sqlite_busy_timeout_ms);
    if (!table_exists(database.get(), "session")) {
        return {};
    }
    const bool uses_current_messages = table_exists(database.get(), "session_message");
    const bool uses_legacy_messages = !uses_current_messages && table_exists(database.get(), "message");
    if (!uses_current_messages && !uses_legacy_messages) {
        return {.usable = true};
    }

    const char* sql = uses_current_messages
        ? R"sql(
            SELECT s.id, s.title, s.time_updated, sm.type, sm.data
            FROM "session" AS s
            LEFT JOIN session_message AS sm
                ON sm.rowid = (
                    SELECT sm2.rowid
                    FROM session_message AS sm2
                    WHERE sm2.session_id = s.id
                    ORDER BY sm2.time_updated DESC, sm2.rowid DESC
                    LIMIT 1
                )
            WHERE s.time_archived IS NULL
            ORDER BY s.time_updated DESC, s.id ASC
            LIMIT ?
        )sql"
        : R"sql(
            SELECT s.id, s.title, s.time_updated, '' AS type, m.data
            FROM "session" AS s
            LEFT JOIN message AS m
                ON m.rowid = (
                    SELECT m2.rowid
                    FROM message AS m2
                    WHERE m2.session_id = s.id
                    ORDER BY m2.time_updated DESC, m2.rowid DESC
                    LIMIT 1
                )
            WHERE s.time_archived IS NULL
            ORDER BY s.time_updated DESC, s.id ASC
            LIMIT ?
        )sql";
    sqlite3_stmt* raw_statement = nullptr;
    if (sqlite3_prepare_v2(database.get(), sql, -1, &raw_statement, nullptr) != SQLITE_OK) {
        return {};
    }
    std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(
        raw_statement,
        &sqlite3_finalize);
    if (sqlite3_bind_int64(
            statement.get(),
            1,
            static_cast<sqlite3_int64>(options.max_sessions)) != SQLITE_OK) {
        return {};
    }

    DatabaseScanResult result{.usable = true};
    while (sqlite3_step(statement.get()) == SQLITE_ROW) {
        const auto session_id = sqlite_text(
            statement.get(),
            0,
            maximum_identifier_bytes);
        if (!session_id) {
            continue;
        }
        const auto raw_updated = sqlite3_column_int64(statement.get(), 2);
        const auto updated_at = normalize_timestamp(raw_updated);
        if (!updated_at || *updated_at <= cutoff) {
            continue;
        }
        const auto data = sqlite_text(
            statement.get(),
            4,
            options.maximum_json_bytes);
        if (!data) {
            continue;
        }
        const auto column_type = sqlite_text(statement.get(), 3, 128).value_or("");
        const auto summary = parse_message_summary(*data, column_type);
        const auto active_status = active_status_for(summary);
        if (!active_status) {
            continue;
        }
        result.tasks.push_back({
            .id = OpenCodeSessionScanner::task_id(*session_id),
            .provider = AIProvider::opencode,
            .title = sqlite_text(statement.get(), 1, maximum_title_bytes).value_or("opencode"),
            .detail = summary.model,
            .progress = std::nullopt,
            .status = *active_status,
            .updated_at_unix_ms = *updated_at,
            .session_uri = std::nullopt,
            .effort = std::nullopt,
            .started_at_unix_ms = std::nullopt,
        });
    }
    return result;
}

std::optional<std::string> read_bounded_json(
    const fs::path& path,
    std::size_t maximum_bytes) {
    std::error_code status_error;
    const auto status = fs::symlink_status(path, status_error);
    if (status_error || !fs::is_regular_file(status) || fs::is_symlink(status)) {
        return std::nullopt;
    }
    std::error_code size_error;
    const auto size = fs::file_size(path, size_error);
    if (size_error || size == 0 || size > maximum_bytes
        || size > static_cast<std::uintmax_t>(
                      std::numeric_limits<std::streamsize>::max())) {
        return std::nullopt;
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return std::nullopt;
    }
    std::string contents(static_cast<std::size_t>(size), '\0');
    stream.read(contents.data(), static_cast<std::streamsize>(contents.size()));
    return stream.gcount() == static_cast<std::streamsize>(contents.size())
        ? std::optional<std::string>{std::move(contents)}
        : std::nullopt;
}

bool has_component(std::string_view normalized_path, std::string_view component) {
    return normalized_path.find(component) != std::string_view::npos;
}

std::vector<StorageCandidate> storage_candidates(
    const std::vector<fs::path>& roots,
    std::size_t maximum_files,
    bool messages) {
    std::vector<StorageCandidate> candidates;
    candidates.reserve(maximum_files);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.path.native() < rhs.path.native();
    };
    for (const auto& root : roots) {
        for (const auto& scan_root : {root / "storage", root / "project"}) {
            std::error_code root_error;
            const auto root_status = fs::symlink_status(scan_root, root_error);
            if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
                continue;
            }
            std::error_code error;
            fs::recursive_directory_iterator iterator(
                scan_root,
                fs::directory_options::skip_permission_denied,
                error);
            const fs::recursive_directory_iterator end;
            while (!error && iterator != end) {
                const auto entry = *iterator;
                std::error_code status_error;
                const auto status = entry.symlink_status(status_error);
                if (!status_error && fs::is_directory(status)
                    && (fs::is_symlink(status) || has_hidden_name(entry.path()))) {
                    iterator.disable_recursion_pending();
                }
                if (!status_error && fs::is_regular_file(status)
                    && !fs::is_symlink(status) && !has_hidden_name(entry.path())
                    && has_json_extension(entry.path())) {
                    const auto normalized = ascii_lower(path_key(entry.path()));
                    const bool message_path = has_component(normalized, "/storage/message/")
                        || has_component(normalized, "\\storage\\message\\")
                        || has_component(normalized, "/storage/session/message/")
                        || has_component(normalized, "\\storage\\session\\message\\");
                    const bool part_path = has_component(normalized, "/storage/part/")
                        || has_component(normalized, "\\storage\\part\\")
                        || has_component(normalized, "/storage/session/part/")
                        || has_component(normalized, "\\storage\\session\\part\\");
                    const bool session_path = has_component(normalized, "/storage/session/")
                        || has_component(normalized, "\\storage\\session\\");
                    if ((messages && (!message_path || part_path))
                        || (!messages && (!session_path || message_path || part_path))) {
                        iterator.increment(error);
                        continue;
                    }
                    std::error_code time_error;
                    const auto modified_at = entry.last_write_time(time_error);
                    const auto key = path_key(entry.path());
                    const bool already_seen = std::any_of(
                        candidates.begin(), candidates.end(), [&key](const auto& candidate) {
                            return path_key(candidate.path) == key;
                        });
                    if (!time_error && !already_seen) {
                        detail::retain_newest(
                            candidates,
                            StorageCandidate{
                                .path = entry.path(),
                                .modified_at = modified_at,
                                .modified_at_unix_ms = unix_milliseconds(modified_at),
                            },
                            maximum_files,
                            newer);
                    }
                }
                iterator.increment(error);
            }
        }
    }
    std::sort(candidates.begin(), candidates.end(), newer);
    return candidates;
}

std::optional<std::string> object_string(
    yyjson_val* object,
    const char* key,
    std::size_t maximum_bytes = maximum_identifier_bytes) {
    return object && yyjson_is_obj(object)
        ? json_string(yyjson_obj_get(object, key), maximum_bytes)
        : std::nullopt;
}

std::optional<std::int64_t> object_timestamp(yyjson_val* object, const char* key) {
    return object && yyjson_is_obj(object)
        ? json_timestamp(yyjson_obj_get(object, key))
        : std::nullopt;
}

std::optional<StorageSession> parse_storage_session(
    const StorageCandidate& candidate,
    const OpenCodeSessionScanOptions& options) {
    const auto contents = read_bounded_json(candidate.path, options.maximum_json_bytes);
    if (!contents) {
        return std::nullopt;
    }
    const JsonDocument document{
        yyjson_read(contents->data(), contents->size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    auto* root = document ? yyjson_doc_get_root(document.get()) : nullptr;
    if (!root || !yyjson_is_obj(root)) {
        return std::nullopt;
    }
    const auto id = object_string(root, "id").value_or(utf8_filename(candidate.path.stem()));
    if (id.empty() || id.size() > maximum_identifier_bytes) {
        return std::nullopt;
    }
    auto* time = yyjson_obj_get(root, "time");
    if (!time || !yyjson_is_obj(time)) {
        time = nullptr;
    }
    auto updated_at = object_timestamp(root, "time_updated");
    if (!updated_at) {
        updated_at = object_timestamp(time, "updated");
    }
    const auto archived_time = object_timestamp(root, "time_archived")
        ? object_timestamp(root, "time_archived")
        : object_timestamp(time, "archived");
    const bool archived_flag = yyjson_obj_get(root, "archived")
        && yyjson_is_bool(yyjson_obj_get(root, "archived"))
        && yyjson_get_bool(yyjson_obj_get(root, "archived"));
    return StorageSession{
        .id = id,
        .title = object_string(root, "title", maximum_title_bytes).value_or("opencode"),
        .updated_at_unix_ms = updated_at.value_or(candidate.modified_at_unix_ms),
        .archived = archived_flag || (archived_time && *archived_time > 0),
    };
}

std::optional<StorageMessage> parse_storage_message(
    const StorageCandidate& candidate,
    const OpenCodeSessionScanOptions& options) {
    const auto contents = read_bounded_json(candidate.path, options.maximum_json_bytes);
    if (!contents) {
        return std::nullopt;
    }
    const JsonDocument document{
        yyjson_read(contents->data(), contents->size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    auto* root = document ? yyjson_doc_get_root(document.get()) : nullptr;
    if (!root || !yyjson_is_obj(root)) {
        return std::nullopt;
    }
    auto* data = yyjson_obj_get(root, "data");
    if (!data || !yyjson_is_obj(data)) {
        data = root;
    }
    auto session_id = object_string(root, "session_id");
    if (!session_id) {
        session_id = object_string(root, "sessionID");
    }
    if (!session_id) {
        session_id = object_string(data, "session_id");
    }
    if (!session_id) {
        session_id = object_string(data, "sessionID");
    }
    if (!session_id) {
        session_id = utf8_filename(candidate.path.parent_path());
    }
    if (session_id->empty() || session_id->size() > maximum_identifier_bytes) {
        return std::nullopt;
    }
    auto timestamp = object_timestamp(root, "time_updated");
    if (!timestamp) {
        auto* time = yyjson_obj_get(data, "time");
        timestamp = object_timestamp(time, "updated");
    }
    const auto type = object_string(root, "type", 128).value_or(
        object_string(data, "type", 128).value_or(""));
    return StorageMessage{
        .session_id = *session_id,
        .summary = parse_message_summary(*contents, type),
        .updated_at_unix_ms = timestamp.value_or(candidate.modified_at_unix_ms),
    };
}

std::vector<AIProgressTask> scan_storage(
    const OpenCodeSessionScanOptions& options,
    std::int64_t cutoff) {
    std::unordered_map<std::string, StorageSession> sessions;
    for (const auto& candidate : storage_candidates(
             options.data_roots,
             options.max_storage_files,
             false)) {
        const auto session = parse_storage_session(candidate, options);
        if (!session) {
            continue;
        }
        const auto existing = sessions.find(session->id);
        if (existing == sessions.end()
            || existing->second.updated_at_unix_ms <= session->updated_at_unix_ms) {
            sessions.insert_or_assign(session->id, *session);
        }
    }
    std::unordered_map<std::string, StorageMessage> messages;
    for (const auto& candidate : storage_candidates(
             options.data_roots,
             options.max_storage_files,
             true)) {
        const auto message = parse_storage_message(candidate, options);
        if (!message) {
            continue;
        }
        const auto existing = messages.find(message->session_id);
        if (existing == messages.end()
            || existing->second.updated_at_unix_ms <= message->updated_at_unix_ms) {
            messages.insert_or_assign(message->session_id, *message);
        }
    }

    std::vector<AIProgressTask> tasks;
    for (const auto& [id, session] : sessions) {
        if (session.archived) {
            continue;
        }
        const auto message = messages.find(id);
        if (message == messages.end()) {
            continue;
        }
        const auto updated_at = std::max(
            session.updated_at_unix_ms,
            message->second.updated_at_unix_ms);
        if (updated_at <= cutoff) {
            continue;
        }
        const auto active_status = active_status_for(message->second.summary);
        if (!active_status) {
            continue;
        }
        tasks.push_back({
            .id = OpenCodeSessionScanner::task_id(id),
            .provider = AIProvider::opencode,
            .title = session.title.empty() ? "opencode" : session.title,
            .detail = message->second.summary.model,
            .progress = std::nullopt,
            .status = *active_status,
            .updated_at_unix_ms = updated_at,
            .session_uri = std::nullopt,
            .effort = std::nullopt,
            .started_at_unix_ms = std::nullopt,
        });
    }
    return tasks;
}

}  // namespace

OpenCodeSessionScanner::OpenCodeSessionScanner(OpenCodeSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_sessions = std::max<std::size_t>(1, options_.max_sessions);
    options_.max_storage_files = std::max<std::size_t>(1, options_.max_storage_files);
    options_.maximum_json_bytes = std::max<std::size_t>(1, options_.maximum_json_bytes);
    options_.recency_threshold_ms = std::max<std::int64_t>(
        0,
        options_.recency_threshold_ms);
}

std::vector<AIProgressTask> OpenCodeSessionScanner::active_tasks() const {
    const auto now_unix_ms = options_.now_unix_ms == 0
        ? current_unix_milliseconds()
        : options_.now_unix_ms;
    const auto cutoff = recency_cutoff(
        now_unix_ms,
        options_.recency_threshold_ms);

    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    bool has_usable_database = false;
    std::unordered_set<std::string> seen_databases;
    for (const auto& path : options_.database_paths) {
        if (!seen_databases.insert(path_key(path)).second) {
            continue;
        }
        const auto result = scan_database(path, options_, cutoff);
        has_usable_database = has_usable_database || result.usable;
        for (const auto& task : result.tasks) {
            merge_task(task, tasks_by_id);
        }
    }
    if (!has_usable_database) {
        for (const auto& task : scan_storage(options_, cutoff)) {
            merge_task(task, tasks_by_id);
        }
    }

    std::vector<AIProgressTask> tasks;
    tasks.reserve(tasks_by_id.size());
    for (auto& [id, task] : tasks_by_id) {
        (void)id;
        tasks.push_back(std::move(task));
    }
    std::sort(tasks.begin(), tasks.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.updated_at_unix_ms != rhs.updated_at_unix_ms) {
            return lhs.updated_at_unix_ms > rhs.updated_at_unix_ms;
        }
        return lhs.id < rhs.id;
    });
    if (tasks.size() > options_.max_sessions) {
        tasks.resize(options_.max_sessions);
    }
    return tasks;
}

std::string OpenCodeSessionScanner::task_id(std::string_view session_id) {
    return "opencode-session-" + std::string(session_id);
}

}  // namespace zisla::core
