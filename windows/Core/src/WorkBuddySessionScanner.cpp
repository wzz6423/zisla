#include "zisla/core/WorkBuddySessionScanner.hpp"

#include <yyjson.h>

#include <algorithm>
#include <chrono>
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
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;
using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

constexpr std::size_t maximum_conversation_id_bytes = 512;

std::string_view trim_ascii(std::string_view value) noexcept {
    while (!value.empty()
        && (value.front() == ' ' || value.front() == '\t'
            || value.front() == '\r' || value.front() == '\n')) {
        value.remove_prefix(1);
    }
    while (!value.empty()
        && (value.back() == ' ' || value.back() == '\t'
            || value.back() == '\r' || value.back() == '\n')) {
        value.remove_suffix(1);
    }
    return value;
}

std::optional<int> decimal_field(
    std::string_view value,
    std::size_t offset,
    std::size_t length) noexcept {
    if (offset > value.size() || length > value.size() - offset) {
        return std::nullopt;
    }
    int result = 0;
    for (std::size_t index = 0; index < length; ++index) {
        const auto character = value[offset + index];
        if (character < '0' || character > '9') {
            return std::nullopt;
        }
        result = result * 10 + (character - '0');
    }
    return result;
}

std::optional<std::int64_t> parse_rfc3339_unix_ms(std::string_view value) noexcept {
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

std::optional<std::string> json_string(
    yyjson_val* value,
    std::size_t maximum_bytes) {
    if (!yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto length = yyjson_get_len(value);
    const auto* contents = yyjson_get_str(value);
    if (!contents || length == 0 || length > maximum_bytes) {
        return std::nullopt;
    }
    const auto trimmed = trim_ascii({contents, length});
    if (trimmed.empty()) {
        return std::nullopt;
    }
    return std::string(trimmed);
}

std::optional<std::string> read_index(
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
    if (stream.gcount() != static_cast<std::streamsize>(contents.size())) {
        return std::nullopt;
    }
    return contents;
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

}  // namespace

WorkBuddySessionScanner::WorkBuddySessionScanner(WorkBuddySessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_sessions = std::max<std::size_t>(1, options_.max_sessions);
    options_.maximum_file_bytes = std::max<std::size_t>(1, options_.maximum_file_bytes);
    options_.recency_threshold_ms = std::max<std::int64_t>(
        0,
        options_.recency_threshold_ms);
}

std::vector<AIProgressTask> WorkBuddySessionScanner::active_tasks() const {
    const auto contents = read_index(
        options_.sessions_file,
        options_.maximum_file_bytes);
    if (!contents) {
        return {};
    }

    const JsonDocument document{
        yyjson_read(contents->data(), contents->size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return {};
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        return {};
    }
    auto* sessions = yyjson_obj_get(root, "sessions");
    if (!yyjson_is_arr(sessions)) {
        return {};
    }

    const auto now_unix_ms = options_.now_unix_ms == 0
        ? current_unix_milliseconds()
        : options_.now_unix_ms;
    const auto cutoff = recency_cutoff(now_unix_ms, options_.recency_threshold_ms);
    std::unordered_map<std::string, AIProgressTask> tasks_by_id;

    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* session = nullptr;
    yyjson_arr_foreach(sessions, index, maximum, session) {
        if (!yyjson_is_obj(session)) {
            continue;
        }
        const auto conversation_id = json_string(
            yyjson_obj_get(session, "conversationId"),
            maximum_conversation_id_bytes);
        const auto started_at = json_string(yyjson_obj_get(session, "startedAt"), 64);
        const auto resumed_at = json_string(yyjson_obj_get(session, "resumedAt"), 64);
        if (!conversation_id || !started_at || !resumed_at) {
            continue;
        }
        const auto started_at_unix_ms = parse_rfc3339_unix_ms(*started_at);
        const auto resumed_at_unix_ms = parse_rfc3339_unix_ms(*resumed_at);
        if (!started_at_unix_ms || !resumed_at_unix_ms) {
            continue;
        }
        const auto updated_at_unix_ms = std::max(*started_at_unix_ms, *resumed_at_unix_ms);
        if (updated_at_unix_ms <= cutoff) {
            continue;
        }

        AIProgressTask task{
            .id = task_id(*conversation_id),
            .provider = AIProvider::harness,
            .title = "WorkBuddy",
            .detail = std::string{"Desktop"},
            .progress = std::nullopt,
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = updated_at_unix_ms,
            .session_uri = std::nullopt,
            .effort = std::nullopt,
            .started_at_unix_ms = *started_at_unix_ms,
        };
        const auto existing = tasks_by_id.find(task.id);
        if (existing == tasks_by_id.end()
            || existing->second.updated_at_unix_ms < task.updated_at_unix_ms) {
            tasks_by_id.insert_or_assign(task.id, std::move(task));
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

std::string WorkBuddySessionScanner::task_id(std::string_view conversation_id) {
    return "workbuddy-session-" + std::string(conversation_id);
}

}  // namespace zisla::core
