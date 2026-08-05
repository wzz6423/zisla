#include "zisla/core/GrokSessionScanner.hpp"

#include <yyjson.h>

#include <algorithm>
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
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

struct EventCandidate {
    fs::path event_path;
    std::string directory_session_id;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct SessionState {
    bool active{false};
    bool has_error{false};
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
    std::optional<std::string> session_id;
    std::optional<std::string> model;
    std::unordered_map<std::string, std::size_t> pending_permissions_by_id;
    std::size_t anonymous_permission_count{0};
};

std::string_view trim(std::string_view value) noexcept {
    constexpr auto is_space = [](unsigned char character) noexcept {
        return character == ' ' || character == '\t' || character == '\n'
            || character == '\r' || character == '\f' || character == '\v';
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

std::optional<std::string_view> json_string(yyjson_val* value) noexcept {
    const auto* text = yyjson_get_str(value);
    if (!text) {
        return std::nullopt;
    }
    return std::string_view{text, yyjson_get_len(value)};
}

std::optional<std::string> string_member(yyjson_val* object, const char* key) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    const auto text = json_string(yyjson_obj_get(object, key));
    if (!text) {
        return std::nullopt;
    }
    const auto normalized = trim(*text);
    return normalized.empty() ? std::nullopt
                              : std::optional<std::string>{std::string(normalized)};
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

std::optional<std::int64_t> numeric_timestamp(yyjson_val* value) noexcept {
    const auto seconds_to_milliseconds = [](std::int64_t timestamp)
        -> std::optional<std::int64_t> {
        if (timestamp > std::numeric_limits<std::int64_t>::max() / 1'000
            || timestamp < std::numeric_limits<std::int64_t>::min() / 1'000) {
            return std::nullopt;
        }
        return timestamp * 1'000;
    };
    if (yyjson_is_sint(value)) {
        const auto timestamp = yyjson_get_sint(value);
        return timestamp > 1'000'000'000'000LL
            ? std::optional<std::int64_t>{timestamp}
            : seconds_to_milliseconds(timestamp);
    }
    if (yyjson_is_uint(value)) {
        const auto timestamp = yyjson_get_uint(value);
        if (timestamp > static_cast<std::uint64_t>(
                            std::numeric_limits<std::int64_t>::max())) {
            return std::nullopt;
        }
        const auto result = static_cast<std::int64_t>(timestamp);
        return result > 1'000'000'000'000LL
            ? std::optional<std::int64_t>{result}
            : seconds_to_milliseconds(result);
    }
    if (!yyjson_is_real(value)) {
        return std::nullopt;
    }
    auto timestamp = yyjson_get_real(value);
    if (!std::isfinite(timestamp)) {
        return std::nullopt;
    }
    if (std::abs(timestamp) <= 1'000'000'000'000.0) {
        timestamp *= 1'000.0;
    }
    if (timestamp < static_cast<double>(std::numeric_limits<std::int64_t>::min())
        || timestamp > static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
        return std::nullopt;
    }
    return static_cast<std::int64_t>(timestamp);
}

std::optional<std::int64_t> timestamp_member(
    yyjson_val* object,
    const char* key) noexcept {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    auto* value = yyjson_obj_get(object, key);
    if (const auto text = json_string(value)) {
        if (const auto parsed = parse_rfc3339_unix_ms(*text)) {
            return parsed;
        }
    }
    return numeric_timestamp(value);
}

std::int64_t record_timestamp(yyjson_val* root, std::int64_t fallback) noexcept {
    if (const auto timestamp = timestamp_member(root, "ts")) {
        return *timestamp;
    }
    if (const auto timestamp = timestamp_member(root, "timestamp")) {
        return *timestamp;
    }
    return fallback;
}

JsonDocument parse_json(std::string_view json) noexcept {
    return JsonDocument{
        yyjson_read(json.data(), json.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
}

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::int64_t unix_milliseconds(fs::file_time_type time) noexcept {
    const auto system_time = std::chrono::file_clock::to_sys(time);
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

std::string utf8_filename(const fs::path& path) {
    const auto encoded = path.filename().u8string();
    std::string result;
    result.reserve(encoded.size());
    for (const auto character : encoded) {
        result.push_back(static_cast<char>(character));
    }
    return result;
}

std::vector<EventCandidate> recent_event_files(const GrokSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(options.sessions_directory, root_error);
    if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<EventCandidate> candidates;
    std::error_code error;
    fs::recursive_directory_iterator iterator(
        options.sessions_directory,
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
        if (!status_error && !has_hidden_name(entry.path())
            && entry.path().filename() == fs::path{"events.jsonl"}
            && fs::is_regular_file(status) && !fs::is_symlink(status)) {
            const auto session_id = utf8_filename(entry.path().parent_path());
            std::error_code time_error;
            const auto modified_at = entry.last_write_time(time_error);
            if (!session_id.empty() && !time_error) {
                candidates.push_back({
                    .event_path = entry.path(),
                    .directory_session_id = session_id,
                    .modified_at = modified_at,
                    .modified_at_unix_ms = unix_milliseconds(modified_at),
                });
            }
        }
        iterator.increment(error);
    }

    std::sort(candidates.begin(), candidates.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.event_path.native() < rhs.event_path.native();
    });
    if (candidates.size() > options.max_session_files) {
        candidates.resize(options.max_session_files);
    }
    return candidates;
}

std::optional<std::string> read_complete_tail(
    const fs::path& path,
    std::size_t maximum_bytes) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return std::nullopt;
    }
    stream.seekg(0, std::ios::end);
    const auto end_position = stream.tellg();
    if (end_position < std::streampos{0}) {
        return std::nullopt;
    }
    const auto file_size = static_cast<std::uintmax_t>(
        static_cast<std::streamoff>(end_position));
    const auto requested = std::min<std::uintmax_t>(
        file_size,
        std::max<std::size_t>(1, maximum_bytes));
    const bool starts_inside_file = requested < file_size;
    const auto lookback = requested + (starts_inside_file ? 1U : 0U);
    if (lookback > static_cast<std::uintmax_t>(
                       std::numeric_limits<std::streamsize>::max())) {
        return std::nullopt;
    }
    stream.seekg(-static_cast<std::streamoff>(lookback), std::ios::end);
    if (!stream) {
        return std::nullopt;
    }
    std::string contents(static_cast<std::size_t>(lookback), '\0');
    stream.read(contents.data(), static_cast<std::streamsize>(contents.size()));
    contents.resize(static_cast<std::size_t>(stream.gcount()));
    if (starts_inside_file) {
        if (contents.empty()) {
            return std::string{};
        }
        const bool starts_at_line_boundary = contents.front() == '\n';
        contents.erase(contents.begin());
        if (!starts_at_line_boundary) {
            const auto boundary = contents.find('\n');
            if (boundary == std::string::npos) {
                return std::string{};
            }
            contents.erase(0, boundary + 1);
        }
    }
    return contents;
}

std::optional<std::string> event_outcome(yyjson_val* root) {
    if (const auto outcome = string_member(root, "outcome")) {
        return outcome;
    }
    return string_member(yyjson_obj_get(root, "data"), "outcome");
}

std::optional<std::string> request_id(yyjson_val* root) {
    if (const auto id = string_member(root, "request_id")) {
        return id;
    }
    if (const auto id = string_member(root, "requestId")) {
        return id;
    }
    auto* data = yyjson_obj_get(root, "data");
    if (const auto id = string_member(data, "request_id")) {
        return id;
    }
    return string_member(data, "requestId");
}

bool is_permission_blocked(const SessionState& state) noexcept {
    return !state.pending_permissions_by_id.empty()
        || state.anonymous_permission_count > 0;
}

void clear_permissions(SessionState& state) {
    state.pending_permissions_by_id.clear();
    state.anonymous_permission_count = 0;
}

void apply_record(
    yyjson_val* root,
    SessionState& state,
    std::int64_t fallback_timestamp) {
    if (!yyjson_is_obj(root)) {
        return;
    }
    const auto type = string_member(root, "type");
    const auto normalized_type = type ? ascii_lower(*type) : std::string{};
    const auto timestamp = record_timestamp(root, fallback_timestamp);

    if (normalized_type == "turn_started") {
        state.active = true;
        state.has_error = false;
        state.started_at_unix_ms = timestamp;
        state.updated_at_unix_ms = timestamp;
        if (const auto session_id = string_member(root, "session_id")) {
            state.session_id = *session_id;
        }
        if (const auto model = string_member(root, "model_id")) {
            state.model = *model;
        }
        clear_permissions(state);
        return;
    }

    if (normalized_type == "turn_ended") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        clear_permissions(state);
        const auto outcome = event_outcome(root);
        const auto normalized_outcome = outcome ? ascii_lower(*outcome) : std::string{};
        if (normalized_outcome == "error") {
            state.has_error = true;
            state.active = true;
        } else {
            state.active = false;
            if (normalized_outcome == "completed" || normalized_outcome == "cancelled") {
                state.has_error = false;
            }
        }
        return;
    }

    if (normalized_type == "permission_requested") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (!state.active && !state.has_error) {
            return;
        }
        if (const auto id = request_id(root)) {
            ++state.pending_permissions_by_id[*id];
        } else {
            ++state.anonymous_permission_count;
        }
        return;
    }

    if (normalized_type == "permission_resolved") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (const auto id = request_id(root)) {
            const auto pending = state.pending_permissions_by_id.find(*id);
            if (pending != state.pending_permissions_by_id.end()) {
                if (pending->second <= 1) {
                    state.pending_permissions_by_id.erase(pending);
                } else {
                    --pending->second;
                }
            }
        } else if (state.anonymous_permission_count > 0) {
            --state.anonymous_permission_count;
        }
        return;
    }

    if (normalized_type == "tool_completed") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (const auto outcome = event_outcome(root)) {
            const auto normalized_outcome = ascii_lower(*outcome);
            if (normalized_outcome == "error" || normalized_outcome == "failed") {
                state.has_error = true;
            } else if (normalized_outcome == "success"
                       || normalized_outcome == "succeeded"
                       || normalized_outcome == "completed") {
                state.has_error = false;
            }
        }
    }
}

void apply_jsonl(
    std::string_view jsonl,
    SessionState& state,
    std::int64_t fallback_timestamp) {
    std::size_t line_start = 0;
    while (line_start < jsonl.size()) {
        const auto line_end = jsonl.find('\n', line_start);
        if (line_end == std::string_view::npos) {
            return;
        }
        auto line = jsonl.substr(line_start, line_end - line_start);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        if (!trim(line).empty()) {
            const auto document = parse_json(line);
            if (document) {
                apply_record(
                    yyjson_doc_get_root(document.get()),
                    state,
                    fallback_timestamp);
            }
        }
        line_start = line_end + 1;
    }
}

std::optional<AIProgressTask> make_task(
    const EventCandidate& candidate,
    const SessionState& state) {
    const auto pending_blocked = is_permission_blocked(state);
    if (!state.active && !state.has_error && !pending_blocked) {
        return std::nullopt;
    }
    const auto status = state.has_error ? AIProgressStatus::error
        : pending_blocked                ? AIProgressStatus::blocked
                                         : AIProgressStatus::running;
    return AIProgressTask{
        .id = GrokSessionScanner::task_id(
            state.session_id.value_or(candidate.directory_session_id)),
        .provider = AIProvider::grok,
        .title = "Grok",
        .detail = state.model,
        .progress = std::nullopt,
        .status = status,
        .updated_at_unix_ms = std::max(
            state.updated_at_unix_ms,
            candidate.modified_at_unix_ms),
        .session_uri = std::nullopt,
        .effort = std::nullopt,
        .started_at_unix_ms = state.started_at_unix_ms,
    };
}

}  // namespace

GrokSessionScanner::GrokSessionScanner(GrokSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_session_files = std::max<std::size_t>(1, options_.max_session_files);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
}

std::vector<AIProgressTask> GrokSessionScanner::active_tasks() const {
    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    for (const auto& candidate : recent_event_files(options_)) {
        const auto contents = read_complete_tail(
            candidate.event_path,
            options_.initial_tail_bytes);
        if (!contents) {
            continue;
        }
        SessionState state;
        apply_jsonl(*contents, state, candidate.modified_at_unix_ms);
        const auto task = make_task(candidate, state);
        if (!task) {
            continue;
        }
        const auto existing = tasks_by_id.find(task->id);
        if (existing == tasks_by_id.end()
            || existing->second.updated_at_unix_ms < task->updated_at_unix_ms) {
            tasks_by_id.insert_or_assign(task->id, *task);
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
    return tasks;
}

std::string GrokSessionScanner::task_id(std::string_view session_id) {
    return "grok-session-" + std::string(session_id);
}

}  // namespace zisla::core
