#include "zisla/core/CodexActivityParser.hpp"

#include <yyjson.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cctype>
#include <cstddef>
#include <cstdint>
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

enum class LifecycleKind {
    started,
    completed,
    aborted,
};

struct LifecycleEvent {
    LifecycleKind kind;
    std::string turn_id;
    std::int64_t timestamp_unix_ms;
};

enum class SignalKind {
    blocked,
    output,
};

struct StatusSignal {
    SignalKind kind;
    std::string turn_id;
    std::optional<std::string> call_id;
    bool failed{false};
    std::int64_t timestamp_unix_ms{0};
};

struct ParsedRollout {
    std::vector<LifecycleEvent> events;
    std::vector<StatusSignal> signals;
    std::unordered_map<std::string, std::string> models_by_turn_id;
    std::unordered_map<std::string, std::string> efforts_by_turn_id;
    std::optional<std::string> session_id;
};

struct EventRecord {
    LifecycleEvent event;
    std::int64_t activity_unix_ms;
    std::optional<std::string> model;
    std::optional<std::string> effort;
    std::optional<std::string> session_id;
};

std::optional<std::string_view> json_string(yyjson_val* value) noexcept {
    const auto* text = yyjson_get_str(value);
    if (!text) {
        return std::nullopt;
    }
    return std::string_view{text, yyjson_get_len(value)};
}

std::string_view trim(std::string_view value) noexcept {
    while (!value.empty()
           && std::isspace(static_cast<unsigned char>(value.front())) != 0) {
        value.remove_prefix(1);
    }
    while (!value.empty()
           && std::isspace(static_cast<unsigned char>(value.back())) != 0) {
        value.remove_suffix(1);
    }
    return value;
}

std::optional<std::string> copied_trimmed_string(yyjson_val* value) {
    const auto text = json_string(value);
    if (!text) {
        return std::nullopt;
    }
    const auto trimmed = trim(*text);
    if (trimmed.empty()) {
        return std::nullopt;
    }
    return std::string(trimmed);
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
    if (value.size() < 20
        || value[4] != '-'
        || value[7] != '-'
        || (value[10] != 'T' && value[10] != 't')
        || value[13] != ':'
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
        while (position < value.size()
               && value[position] >= '0' && value[position] <= '9') {
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
        if (!offset_hour || !offset_minute
            || *offset_hour > 23 || *offset_minute > 59) {
            return std::nullopt;
        }
        offset_minutes = (*offset_hour * 60 + *offset_minute)
            * (value[position] == '+' ? 1 : -1);
        position += 6;
    }
    if (position != value.size()) {
        return std::nullopt;
    }

    const auto local_time = std::chrono::sys_days{date}
        + std::chrono::hours{*hour}
        + std::chrono::minutes{*minute}
        + std::chrono::seconds{*second}
        + std::chrono::milliseconds{fractional_ms}
        - std::chrono::minutes{offset_minutes};
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        local_time.time_since_epoch()).count();
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

JsonDocument parse_json(std::string_view json) noexcept {
    return JsonDocument{
        yyjson_read(json.data(), json.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
}

bool requires_approval(std::string_view input) {
    std::string compact;
    compact.reserve(input.size());
    for (const auto character : input) {
        const auto byte = static_cast<unsigned char>(character);
        if (std::isspace(byte) == 0) {
            compact.push_back(byte >= 'A' && byte <= 'Z'
                ? static_cast<char>(byte + ('a' - 'A'))
                : character);
        }
    }
    return compact.find("sandbox_permissions:\"require_escalated\"")
            != std::string::npos
        || compact.find("\"sandbox_permissions\":\"require_escalated\"")
            != std::string::npos
        || compact.find("sandbox_permissions:'require_escalated'")
            != std::string::npos
        || compact.find("'sandbox_permissions':'require_escalated'")
            != std::string::npos;
}

std::optional<std::int64_t> integer_value(yyjson_val* value) noexcept {
    if (yyjson_is_sint(value)) {
        return yyjson_get_sint(value);
    }
    if (yyjson_is_uint(value)) {
        const auto number = yyjson_get_uint(value);
        if (number <= static_cast<std::uint64_t>(INT64_MAX)) {
            return static_cast<std::int64_t>(number);
        }
        return std::nullopt;
    }
    const auto text = json_string(value);
    if (!text) {
        return std::nullopt;
    }
    const auto normalized = trim(*text);
    std::int64_t number = 0;
    const auto [end, error] = std::from_chars(
        normalized.data(),
        normalized.data() + normalized.size(),
        number);
    if (error != std::errc{} || end != normalized.data() + normalized.size()) {
        return std::nullopt;
    }
    return number;
}

bool output_indicates_error(yyjson_val* value, unsigned depth = 0) noexcept {
    if (!value || yyjson_is_null(value) || depth > 8) {
        return false;
    }
    if (yyjson_is_arr(value)) {
        std::size_t index = 0;
        std::size_t maximum = 0;
        yyjson_val* item = nullptr;
        yyjson_arr_foreach(value, index, maximum, item) {
            if (output_indicates_error(item, depth + 1)) {
                return true;
            }
        }
        return false;
    }
    if (yyjson_is_obj(value)) {
        const auto is_error = yyjson_obj_get(value, "isError");
        if (yyjson_is_bool(is_error) && yyjson_get_bool(is_error)) {
            return true;
        }
        const auto exit_code = yyjson_obj_get(value, "exit_code")
            ? yyjson_obj_get(value, "exit_code")
            : yyjson_obj_get(value, "exitCode");
        if (const auto code = integer_value(exit_code); code && *code != 0) {
            return true;
        }
        if (const auto status = json_string(yyjson_obj_get(value, "status"))) {
            const auto lowered = ascii_lower(trim(*status));
            if (lowered == "error" || lowered == "failed" || lowered == "failure") {
                return true;
            }
        }
        constexpr const char* nested_keys[] = {
            "structuredContent",
            "result",
            "text",
        };
        for (const auto* key : nested_keys) {
            if (output_indicates_error(yyjson_obj_get(value, key), depth + 1)) {
                return true;
            }
        }
        return false;
    }
    if (const auto text = json_string(value)) {
        const auto nested = parse_json(*text);
        return nested && output_indicates_error(
            yyjson_doc_get_root(nested.get()), depth + 1);
    }
    return false;
}

std::optional<std::int64_t> timestamp_from_root(yyjson_val* root) noexcept {
    const auto timestamp = json_string(yyjson_obj_get(root, "timestamp"));
    return timestamp ? parse_rfc3339_unix_ms(*timestamp) : std::nullopt;
}

void parse_rollout_line(
    std::string_view line,
    ParsedRollout& rollout,
    std::unordered_map<std::string, std::string>& turn_ids_by_call_id) {
    const auto document = parse_json(line);
    if (!document) {
        return;
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        return;
    }
    const auto type = json_string(yyjson_obj_get(root, "type"));
    auto* payload = yyjson_obj_get(root, "payload");
    if (!type || !yyjson_is_obj(payload)) {
        return;
    }

    if (*type == "session_meta") {
        rollout.session_id = copied_trimmed_string(yyjson_obj_get(payload, "id"));
        return;
    }
    if (*type == "turn_context") {
        const auto turn_id = copied_trimmed_string(yyjson_obj_get(payload, "turn_id"));
        const auto model = copied_trimmed_string(yyjson_obj_get(payload, "model"));
        if (!turn_id || !model) {
            return;
        }
        rollout.models_by_turn_id[*turn_id] = *model;
        auto effort = copied_trimmed_string(yyjson_obj_get(payload, "effort"));
        if (!effort) {
            effort = copied_trimmed_string(yyjson_obj_get(payload, "reasoning_effort"));
        }
        if (effort) {
            rollout.efforts_by_turn_id[*turn_id] = *effort;
        }
        return;
    }
    if (*type == "event_msg") {
        const auto timestamp = timestamp_from_root(root);
        const auto payload_type = json_string(yyjson_obj_get(payload, "type"));
        const auto turn_id = copied_trimmed_string(yyjson_obj_get(payload, "turn_id"));
        if (!timestamp || !payload_type || !turn_id) {
            return;
        }
        std::optional<LifecycleKind> kind;
        if (*payload_type == "task_started") {
            kind = LifecycleKind::started;
        } else if (*payload_type == "task_complete") {
            kind = LifecycleKind::completed;
        } else if (*payload_type == "turn_aborted") {
            kind = LifecycleKind::aborted;
        }
        if (kind) {
            rollout.events.push_back({*kind, *turn_id, *timestamp});
        }
        return;
    }
    if (*type != "response_item") {
        return;
    }

    const auto timestamp = timestamp_from_root(root);
    const auto payload_type = json_string(yyjson_obj_get(payload, "type"));
    if (!timestamp || !payload_type) {
        return;
    }
    std::optional<std::string> turn_id;
    if (auto* metadata = yyjson_obj_get(
            payload,
            "internal_chat_message_metadata_passthrough");
        yyjson_is_obj(metadata)) {
        turn_id = copied_trimmed_string(yyjson_obj_get(metadata, "turn_id"));
    }
    const auto call_id = copied_trimmed_string(yyjson_obj_get(payload, "call_id"));
    if (call_id && turn_id) {
        turn_ids_by_call_id[*call_id] = *turn_id;
    }
    if (!turn_id && call_id) {
        if (const auto mapped = turn_ids_by_call_id.find(*call_id);
            mapped != turn_ids_by_call_id.end()) {
            turn_id = mapped->second;
        }
    }
    if (!turn_id) {
        return;
    }

    if (*payload_type == "function_call" || *payload_type == "custom_tool_call") {
        const auto name = json_string(yyjson_obj_get(payload, "name"));
        auto input = json_string(yyjson_obj_get(payload, "arguments"));
        if (!input) {
            input = json_string(yyjson_obj_get(payload, "input"));
        }
        const auto normalized_name = name ? ascii_lower(*name) : std::string{};
        if (call_id && (normalized_name == "request_user_input"
                        || (input && requires_approval(*input)))) {
            rollout.signals.push_back({
                SignalKind::blocked,
                *turn_id,
                call_id,
                false,
                *timestamp,
            });
        }
        return;
    }
    if (*payload_type == "function_call_output"
        || *payload_type == "custom_tool_call_output") {
        rollout.signals.push_back({
            SignalKind::output,
            *turn_id,
            call_id,
            output_indicates_error(yyjson_obj_get(payload, "output")),
            *timestamp,
        });
    }
}

ParsedRollout parse_rollout(std::string_view jsonl) {
    ParsedRollout result;
    std::unordered_map<std::string, std::string> turn_ids_by_call_id;
    for_each_complete_line(jsonl, [&](std::string_view line) {
        parse_rollout_line(line, result, turn_ids_by_call_id);
    });
    return result;
}

std::unordered_map<std::string, std::string> parse_session_titles(
    std::string_view jsonl) {
    std::unordered_map<std::string, std::string> result;
    for_each_complete_line(jsonl, [&](std::string_view line) {
        const auto document = parse_json(line);
        if (!document) {
            return;
        }
        auto* root = yyjson_doc_get_root(document.get());
        if (!yyjson_is_obj(root)) {
            return;
        }
        const auto id = copied_trimmed_string(yyjson_obj_get(root, "id"));
        const auto title = copied_trimmed_string(yyjson_obj_get(root, "thread_name"));
        if (id && title) {
            result[*id] = *title;
        }
    });
    return result;
}

AIProvider provider_for_model(const std::optional<std::string>& model) {
    if (!model) {
        return AIProvider::codex;
    }
    const auto lowered = ascii_lower(*model);
    if (lowered.find("codex") != std::string::npos) {
        return AIProvider::codex;
    }
    if (lowered.find("gpt") != std::string::npos
        || lowered.find("chatgpt") != std::string::npos) {
        return AIProvider::gpt;
    }
    return AIProvider::codex;
}

int lifecycle_sort_order(LifecycleKind kind) noexcept {
    return kind == LifecycleKind::started ? 0 : 1;
}

AIProgressStatus status_for(
    std::string_view turn_id,
    std::int64_t started_at_unix_ms,
    const std::vector<StatusSignal>& signals) {
    std::vector<const StatusSignal*> relevant;
    for (const auto& signal : signals) {
        if (signal.turn_id == turn_id
            && signal.timestamp_unix_ms >= started_at_unix_ms) {
            relevant.push_back(&signal);
        }
    }
    std::stable_sort(relevant.begin(), relevant.end(), [](const auto* lhs, const auto* rhs) {
        return lhs->timestamp_unix_ms < rhs->timestamp_unix_ms;
    });

    std::unordered_set<std::string> blocked_call_ids;
    bool has_error = false;
    for (const auto* signal : relevant) {
        if (signal->kind == SignalKind::blocked) {
            if (signal->call_id) {
                blocked_call_ids.insert(*signal->call_id);
            }
        } else {
            if (signal->call_id) {
                blocked_call_ids.erase(*signal->call_id);
            }
            has_error = signal->failed;
        }
    }
    if (has_error) {
        return AIProgressStatus::error;
    }
    return blocked_call_ids.empty()
        ? AIProgressStatus::running
        : AIProgressStatus::blocked;
}

std::string uri_path_segment(std::string_view value) {
    constexpr char hex[] = "0123456789ABCDEF";
    std::string result;
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        const bool unreserved = (byte >= 'A' && byte <= 'Z')
            || (byte >= 'a' && byte <= 'z')
            || (byte >= '0' && byte <= '9')
            || byte == '-' || byte == '.' || byte == '_' || byte == '~';
        if (unreserved) {
            result.push_back(character);
        } else {
            result.push_back('%');
            result.push_back(hex[(byte >> 4) & 0x0F]);
            result.push_back(hex[byte & 0x0F]);
        }
    }
    return result;
}

}  // namespace

std::vector<AIProgressTask> CodexActivityParser::active_tasks(
    std::span<const CodexRolloutSnapshot> rollouts,
    std::string_view session_index_jsonl) {
    const auto titles_by_session_id = parse_session_titles(session_index_jsonl);
    std::vector<EventRecord> records;
    std::vector<StatusSignal> signals;

    for (const auto& snapshot : rollouts) {
        auto rollout = parse_rollout(snapshot.jsonl);
        signals.insert(
            signals.end(),
            std::make_move_iterator(rollout.signals.begin()),
            std::make_move_iterator(rollout.signals.end()));

        std::optional<std::size_t> latest_started_index;
        for (std::size_t index = 0; index < rollout.events.size(); ++index) {
            if (rollout.events[index].kind == LifecycleKind::started
                && (!latest_started_index
                    || rollout.events[index].timestamp_unix_ms
                        >= rollout.events[*latest_started_index].timestamp_unix_ms)) {
                latest_started_index = index;
            }
        }

        for (std::size_t index = 0; index < rollout.events.size(); ++index) {
            auto& event = rollout.events[index];
            const auto model = rollout.models_by_turn_id.find(event.turn_id);
            const auto effort = rollout.efforts_by_turn_id.find(event.turn_id);
            const auto activity = event.kind == LifecycleKind::started
                    && latest_started_index == index
                ? std::max(event.timestamp_unix_ms, snapshot.modified_at_unix_ms)
                : event.timestamp_unix_ms;
            records.push_back({
                std::move(event),
                activity,
                model == rollout.models_by_turn_id.end()
                    ? std::nullopt
                    : std::optional<std::string>{model->second},
                effort == rollout.efforts_by_turn_id.end()
                    ? std::nullopt
                    : std::optional<std::string>{effort->second},
                rollout.session_id,
            });
        }
    }

    std::stable_sort(records.begin(), records.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.event.timestamp_unix_ms != rhs.event.timestamp_unix_ms) {
            return lhs.event.timestamp_unix_ms < rhs.event.timestamp_unix_ms;
        }
        return lifecycle_sort_order(lhs.event.kind)
            < lifecycle_sort_order(rhs.event.kind);
    });

    std::unordered_map<std::string, EventRecord> active;
    for (const auto& record : records) {
        if (record.event.kind == LifecycleKind::started) {
            active.insert_or_assign(record.event.turn_id, record);
        } else {
            active.erase(record.event.turn_id);
        }
    }

    std::vector<AIProgressTask> result;
    result.reserve(active.size());
    for (const auto& [turn_id, record] : active) {
        const auto provider = provider_for_model(record.model);
        auto title = provider == AIProvider::gpt ? std::string{"ChatGPT"} : std::string{"Codex"};
        if (record.session_id) {
            if (const auto known_title = titles_by_session_id.find(*record.session_id);
                known_title != titles_by_session_id.end()) {
                title = known_title->second;
            }
        }

        result.push_back({
            .id = task_id(turn_id),
            .provider = provider,
            .title = std::move(title),
            .detail = record.model,
            .progress = std::nullopt,
            .status = status_for(turn_id, record.event.timestamp_unix_ms, signals),
            .updated_at_unix_ms = record.activity_unix_ms,
            .session_uri = record.session_id
                ? std::optional<std::string>{
                    "codex://threads/" + uri_path_segment(*record.session_id)}
                : std::nullopt,
            .effort = record.effort,
            .started_at_unix_ms = record.event.timestamp_unix_ms,
        });
    }
    std::sort(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.updated_at_unix_ms != rhs.updated_at_unix_ms) {
            return lhs.updated_at_unix_ms > rhs.updated_at_unix_ms;
        }
        return lhs.id < rhs.id;
    });
    return result;
}

std::string CodexActivityParser::task_id(std::string_view turn_id) {
    return "codex-turn-" + std::string(turn_id);
}

}  // namespace zisla::core
