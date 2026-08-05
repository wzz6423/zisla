#include "zisla/core/ClaudeActivityParser.hpp"

#include <yyjson.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

struct SessionState {
    bool active{false};
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
    std::optional<std::string> model;
    std::unordered_set<std::string> pending_ask_tool_use_ids;
    bool has_error{false};
    bool vscode{false};
};

std::optional<std::string_view> json_string(yyjson_val* value) noexcept {
    const auto* text = yyjson_get_str(value);
    if (!text) {
        return std::nullopt;
    }
    return std::string_view{text, yyjson_get_len(value)};
}

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

std::optional<std::string> copied_trimmed_string(yyjson_val* value) {
    const auto text = json_string(value);
    if (!text) {
        return std::nullopt;
    }
    const auto normalized = trim(*text);
    if (normalized.empty()) {
        return std::nullopt;
    }
    return std::string(normalized);
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
        time.time_since_epoch()).count();
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
        if (timestamp > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) {
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

std::int64_t timestamp_from_root(yyjson_val* root, std::int64_t fallback) noexcept {
    auto* timestamp = yyjson_obj_get(root, "timestamp");
    if (const auto text = json_string(timestamp)) {
        if (const auto parsed = parse_rfc3339_unix_ms(*text)) {
            return *parsed;
        }
    }
    if (const auto parsed = numeric_timestamp(timestamp)) {
        return *parsed;
    }
    return fallback;
}

JsonDocument parse_json(std::string_view json) noexcept {
    return JsonDocument{
        yyjson_read(json.data(), json.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
}

template <typename Callback>
void for_each_complete_line(std::string_view jsonl, Callback&& callback) {
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
            callback(line);
        }
        line_start = line_end + 1;
    }
}

template <typename Callback>
void for_each_content_item(yyjson_val* message, Callback&& callback) {
    if (!yyjson_is_obj(message)) {
        return;
    }
    auto* content = yyjson_obj_get(message, "content");
    if (yyjson_is_obj(content)) {
        callback(content);
        return;
    }
    if (!yyjson_is_arr(content)) {
        return;
    }

    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* item = nullptr;
    yyjson_arr_foreach(content, index, maximum, item) {
        if (yyjson_is_obj(item)) {
            callback(item);
        }
    }
}

bool bool_member(yyjson_val* object, const char* key) noexcept {
    auto* value = yyjson_obj_get(object, key);
    return yyjson_is_bool(value) && yyjson_get_bool(value);
}

bool has_non_null_member(yyjson_val* object, const char* key) noexcept {
    auto* value = yyjson_obj_get(object, key);
    return value && !yyjson_is_null(value);
}

std::optional<std::string> extract_model(yyjson_val* root) {
    if (const auto model = copied_trimmed_string(yyjson_obj_get(root, "model"))) {
        return model;
    }
    auto* message = yyjson_obj_get(root, "message");
    return yyjson_is_obj(message)
        ? copied_trimmed_string(yyjson_obj_get(message, "model"))
        : std::nullopt;
}

void apply_user_record(
    yyjson_val* root,
    std::int64_t timestamp,
    SessionState& state) {
    auto* message = yyjson_obj_get(root, "message");
    if (!yyjson_is_obj(message)) {
        message = root;
    }

    bool had_tool_result = false;
    for_each_content_item(message, [&](yyjson_val* item) {
        const auto type = json_string(yyjson_obj_get(item, "type"));
        if (!type || ascii_lower(trim(*type)) != "tool_result") {
            return;
        }
        had_tool_result = true;
        if (const auto id = copied_trimmed_string(yyjson_obj_get(item, "tool_use_id"))) {
            state.pending_ask_tool_use_ids.erase(*id);
        } else if (const auto id = copied_trimmed_string(yyjson_obj_get(item, "toolUseId"))) {
            state.pending_ask_tool_use_ids.erase(*id);
        }
        state.has_error = bool_member(item, "is_error") || bool_member(item, "isError");
    });
    if (had_tool_result) {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        return;
    }

    state.active = true;
    state.has_error = false;
    state.pending_ask_tool_use_ids.clear();
    state.started_at_unix_ms = timestamp;
    state.updated_at_unix_ms = timestamp;
}

void apply_assistant_record(
    yyjson_val* root,
    std::int64_t timestamp,
    SessionState& state) {
    if (bool_member(root, "isApiErrorMessage")
        || has_non_null_member(root, "apiErrorStatus")
        || has_non_null_member(root, "error")) {
        state.active = true;
        state.has_error = true;
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (!state.started_at_unix_ms) {
            state.started_at_unix_ms = timestamp;
        }
        return;
    }

    auto* message = yyjson_obj_get(root, "message");
    const auto stop_reason = yyjson_is_obj(message)
        ? copied_trimmed_string(yyjson_obj_get(message, "stop_reason"))
        : copied_trimmed_string(yyjson_obj_get(root, "stop_reason"));
    bool has_tool_use = false;
    for_each_content_item(message, [&](yyjson_val* item) {
        const auto type = json_string(yyjson_obj_get(item, "type"));
        if (!type || ascii_lower(trim(*type)) != "tool_use") {
            return;
        }
        has_tool_use = true;
        const auto name = json_string(yyjson_obj_get(item, "name"));
        if (!name || ascii_lower(trim(*name)) != "askuserquestion") {
            return;
        }
        if (const auto id = copied_trimmed_string(yyjson_obj_get(item, "id"))) {
            state.pending_ask_tool_use_ids.insert(*id);
        }
    });

    state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
    if (!state.started_at_unix_ms) {
        state.started_at_unix_ms = timestamp;
    }

    const auto normalized_stop_reason = stop_reason
        ? ascii_lower(trim(*stop_reason))
        : std::string{};
    if (normalized_stop_reason == "tool_use") {
        state.active = true;
    } else if (normalized_stop_reason == "end_turn"
               || normalized_stop_reason == "stop_sequence") {
        state.active = !state.pending_ask_tool_use_ids.empty() || state.has_error;
    } else if (!stop_reason && has_tool_use) {
        state.active = true;
    }
}

std::optional<AIProgressTask> task_from_transcript(
    const ClaudeTranscriptSnapshot& transcript) {
    std::unordered_map<std::string, SessionState> states;
    std::string fallback_session_id = std::string(trim(transcript.fallback_session_id));

    for_each_complete_line(transcript.jsonl, [&](std::string_view line) {
        const auto document = parse_json(line);
        if (!document) {
            return;
        }
        auto* root = yyjson_doc_get_root(document.get());
        if (!yyjson_is_obj(root)) {
            return;
        }
        const auto type = json_string(yyjson_obj_get(root, "type"));
        if (!type) {
            return;
        }

        if (const auto session_id = copied_trimmed_string(yyjson_obj_get(root, "sessionId"))) {
            fallback_session_id = *session_id;
        } else if (const auto session_id = copied_trimmed_string(
                       yyjson_obj_get(root, "session_id"))) {
            fallback_session_id = *session_id;
        }
        if (fallback_session_id.empty()) {
            return;
        }

        auto& state = states[fallback_session_id];
        const auto entrypoint = json_string(yyjson_obj_get(root, "entrypoint"));
        if (entrypoint && ascii_lower(trim(*entrypoint)) == "claude-vscode") {
            state.vscode = true;
        }
        if (const auto model = extract_model(root)) {
            state.model = *model;
        }
        const auto timestamp = timestamp_from_root(
            root,
            transcript.modified_at_unix_ms);
        const auto normalized_type = ascii_lower(trim(*type));
        if (normalized_type == "user") {
            apply_user_record(root, timestamp, state);
        } else if (normalized_type == "assistant") {
            apply_assistant_record(root, timestamp, state);
        }
    });

    const auto active = std::max_element(
        states.begin(),
        states.end(),
        [](const auto& lhs, const auto& rhs) {
            const auto lhs_visible = lhs.second.active || lhs.second.has_error;
            const auto rhs_visible = rhs.second.active || rhs.second.has_error;
            if (lhs_visible != rhs_visible) {
                return !lhs_visible;
            }
            if (lhs.second.updated_at_unix_ms != rhs.second.updated_at_unix_ms) {
                return lhs.second.updated_at_unix_ms < rhs.second.updated_at_unix_ms;
            }
            return lhs.first > rhs.first;
        });
    if (active == states.end() || (!active->second.active && !active->second.has_error)) {
        return std::nullopt;
    }

    const auto& [session_id, state] = *active;
    const auto status = state.has_error
        ? AIProgressStatus::error
        : !state.pending_ask_tool_use_ids.empty()
        ? AIProgressStatus::blocked
        : AIProgressStatus::running;
    AIProgressTask task{
        .id = ClaudeActivityParser::task_id(session_id),
        .provider = AIProvider::claude,
        .title = state.vscode ? "Claude Code (VS Code)" : "Claude",
        .detail = state.model,
        .status = status,
        .updated_at_unix_ms = std::max(
            state.updated_at_unix_ms,
            transcript.modified_at_unix_ms),
        .started_at_unix_ms = state.started_at_unix_ms,
    };
    if (state.vscode) {
        task.session_uri = "vscode://anthropic.claude-code/open?session=" + session_id;
    }
    return task;
}

}  // namespace

std::vector<AIProgressTask> ClaudeActivityParser::active_tasks(
    std::span<const ClaudeTranscriptSnapshot> transcripts) {
    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    for (const auto& transcript : transcripts) {
        const auto task = task_from_transcript(transcript);
        if (!task) {
            continue;
        }
        const auto existing = tasks_by_id.find(task->id);
        if (existing == tasks_by_id.end()
            || existing->second.updated_at_unix_ms <= task->updated_at_unix_ms) {
            tasks_by_id[task->id] = *task;
        }
    }

    std::vector<AIProgressTask> tasks;
    tasks.reserve(tasks_by_id.size());
    for (auto& [_, task] : tasks_by_id) {
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

std::string ClaudeActivityParser::task_id(std::string_view session_id) {
    return "claude-session-" + std::string(session_id);
}

}  // namespace zisla::core
