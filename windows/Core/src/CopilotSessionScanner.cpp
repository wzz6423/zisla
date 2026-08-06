#include "zisla/core/CopilotSessionScanner.hpp"
#include "zisla/core/detail/BoundedRecent.hpp"

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

constexpr std::size_t maximum_identifier_bytes = 512;
constexpr std::size_t maximum_working_directory_bytes = 16U * 1024U;
constexpr std::size_t maximum_workspace_state_bytes = 256U * 1024U;

struct TranscriptCandidate {
    fs::path path;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct TranscriptState {
    std::optional<std::string> session_id;
    bool active{false};
    bool has_error{false};
    bool current_turn_has_tool_requests{false};
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
};

struct CLISession {
    std::string id;
    std::optional<std::string> working_directory;
    std::optional<std::int64_t> started_at_unix_ms;
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

std::optional<std::int64_t> numeric_timestamp(yyjson_val* value) noexcept {
    const auto seconds_to_milliseconds = [](std::int64_t timestamp)
        -> std::optional<std::int64_t> {
        if (timestamp > std::numeric_limits<std::int64_t>::max() / 1'000
            || timestamp < std::numeric_limits<std::int64_t>::min() / 1'000) {
            return std::nullopt;
        }
        return timestamp * 1'000;
    };
    if (value && yyjson_is_sint(value)) {
        const auto timestamp = yyjson_get_sint(value);
        return timestamp > 1'000'000'000'000LL
            ? std::optional<std::int64_t>{timestamp}
            : seconds_to_milliseconds(timestamp);
    }
    if (value && yyjson_is_uint(value)) {
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
    if (!value || !yyjson_is_real(value)) {
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
    if (normalized.empty()) {
        return std::nullopt;
    }
    return std::string(normalized);
}

std::optional<std::int64_t> json_timestamp(yyjson_val* value) noexcept {
    if (const auto text = json_string(value, 128)) {
        if (const auto timestamp = parse_rfc3339_unix_ms(*text)) {
            return timestamp;
        }
    }
    return numeric_timestamp(value);
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

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::string utf8_filename(const fs::path& path) {
    const auto encoded = path.filename().u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

bool has_jsonl_extension(const fs::path& path) {
    const auto extension = path.extension().u8string();
    return ascii_lower({
        reinterpret_cast<const char*>(extension.data()),
        extension.size(),
    }) == ".jsonl";
}

std::vector<TranscriptCandidate> recent_transcript_files(
    const CopilotSessionScanOptions& options) {
    std::vector<TranscriptCandidate> candidates;
    candidates.reserve(options.max_transcript_files);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.path.native() < rhs.path.native();
    };

    for (const auto& root : options.workspace_storage_roots) {
        std::error_code root_error;
        const auto root_status = fs::symlink_status(root, root_error);
        if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
            continue;
        }

        std::error_code error;
        fs::recursive_directory_iterator iterator(
            root,
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
                && has_jsonl_extension(entry.path())
                && utf8_filename(entry.path().parent_path()) == "chatSessions") {
                std::error_code time_error;
                const auto modified_at = entry.last_write_time(time_error);
                if (!time_error) {
                    const auto normalized = entry.path().lexically_normal();
                    const bool already_seen = std::any_of(
                        candidates.begin(), candidates.end(), [&normalized](const auto& candidate) {
                            return candidate.path.lexically_normal() == normalized;
                        });
                    if (!already_seen) {
                        detail::retain_newest(
                            candidates,
                            TranscriptCandidate{
                                .path = entry.path(),
                                .modified_at = modified_at,
                                .modified_at_unix_ms = unix_milliseconds(modified_at),
                            },
                            options.max_transcript_files,
                            newer);
                    }
                }
            }
            iterator.increment(error);
        }
    }

    std::sort(candidates.begin(), candidates.end(), newer);
    return candidates;
}

std::optional<std::string> read_complete_tail(
    const fs::path& path,
    std::size_t maximum_bytes) {
    std::error_code status_error;
    const auto status = fs::symlink_status(path, status_error);
    if (status_error || !fs::is_regular_file(status) || fs::is_symlink(status)) {
        return std::nullopt;
    }

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
    if (stream.gcount() != static_cast<std::streamsize>(contents.size())) {
        return std::nullopt;
    }
    if (starts_inside_file) {
        const auto newline = contents.find('\n');
        if (newline == std::string::npos) {
            return std::nullopt;
        }
        contents.erase(0, newline + 1);
    }
    return contents;
}

void apply_transcript_record(
    yyjson_val* root,
    TranscriptState& state,
    std::int64_t fallback_timestamp) {
    if (!root || !yyjson_is_obj(root)) {
        return;
    }
    const auto type_value = json_string(yyjson_obj_get(root, "type"), 128);
    const auto type = type_value ? ascii_lower(*type_value) : std::string{};
    auto* data = yyjson_obj_get(root, "data");
    if (!data || !yyjson_is_obj(data)) {
        data = nullptr;
    }
    const auto timestamp = json_timestamp(yyjson_obj_get(root, "timestamp"))
        .value_or(fallback_timestamp);
    state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);

    if (data) {
        if (const auto session_id = json_string(yyjson_obj_get(data, "sessionId"))) {
            state.session_id = *session_id;
        }
    }

    if (type == "session.start") {
        if (data) {
            if (const auto session_id = json_string(yyjson_obj_get(data, "sessionId"))) {
                state.session_id = *session_id;
            }
            state.started_at_unix_ms = json_timestamp(
                yyjson_obj_get(data, "startTime")).value_or(timestamp);
        } else {
            state.started_at_unix_ms = timestamp;
        }
        return;
    }
    if (type == "user.message") {
        state.active = true;
        state.has_error = false;
        state.current_turn_has_tool_requests = false;
        state.started_at_unix_ms = state.started_at_unix_ms.value_or(timestamp);
        return;
    }
    if (type == "assistant.turn_start") {
        state.active = true;
        return;
    }
    if (type == "assistant.message") {
        auto* tool_requests = data ? yyjson_obj_get(data, "toolRequests") : nullptr;
        state.current_turn_has_tool_requests = tool_requests && yyjson_is_arr(tool_requests)
            && yyjson_arr_size(tool_requests) > 0;
        return;
    }
    if (type == "assistant.turn_end") {
        state.active = state.current_turn_has_tool_requests;
        state.current_turn_has_tool_requests = false;
        return;
    }
    if (type == "tool.execution_complete") {
        auto* success = data ? yyjson_obj_get(data, "success") : nullptr;
        if (success && yyjson_is_bool(success) && !yyjson_get_bool(success)) {
            state.active = true;
            state.has_error = true;
        }
        return;
    }
    if (type == "session.shutdown") {
        state.active = false;
    }
}

void apply_transcript_jsonl(
    std::string_view jsonl,
    TranscriptState& state,
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
        if (!trim_ascii(line).empty()) {
            const JsonDocument document{
                yyjson_read(line.data(), line.size(), YYJSON_READ_NOFLAG),
                &yyjson_doc_free,
            };
            if (document) {
                apply_transcript_record(
                    yyjson_doc_get_root(document.get()),
                    state,
                    fallback_timestamp);
            }
        }
        line_start = line_end + 1;
    }
}

std::optional<AIProgressTask> scan_transcript(
    const TranscriptCandidate& candidate,
    const CopilotSessionScanOptions& options) {
    const auto contents = read_complete_tail(candidate.path, options.initial_tail_bytes);
    if (!contents) {
        return std::nullopt;
    }
    TranscriptState state;
    apply_transcript_jsonl(*contents, state, candidate.modified_at_unix_ms);
    if ((!state.active && !state.has_error) || !state.session_id) {
        return std::nullopt;
    }
    return AIProgressTask{
        .id = CopilotSessionScanner::vscode_task_id(*state.session_id),
        .provider = AIProvider::copilot,
        .title = "GitHub Copilot (VS Code)",
        .detail = std::nullopt,
        .progress = std::nullopt,
        .status = state.has_error ? AIProgressStatus::error : AIProgressStatus::running,
        .updated_at_unix_ms = std::max(
            state.updated_at_unix_ms,
            candidate.modified_at_unix_ms),
        .session_uri = std::nullopt,
        .effort = std::nullopt,
        .started_at_unix_ms = state.started_at_unix_ms,
    };
}

std::optional<std::string> yaml_value(
    std::string_view contents,
    std::string_view requested_key,
    std::size_t maximum_bytes) {
    std::size_t line_start = 0;
    while (line_start < contents.size()) {
        const auto line_end = contents.find('\n', line_start);
        const auto line = contents.substr(
            line_start,
            (line_end == std::string_view::npos ? contents.size() : line_end) - line_start);
        const auto trimmed = trim_ascii(line);
        const auto separator = trimmed.find(':');
        if (separator != std::string_view::npos
            && trim_ascii(trimmed.substr(0, separator)) == requested_key) {
            auto value = trim_ascii(trimmed.substr(separator + 1));
            if (value.size() >= 2
                && ((value.front() == '\"' && value.back() == '\"')
                    || (value.front() == '\'' && value.back() == '\''))) {
                value.remove_prefix(1);
                value.remove_suffix(1);
            }
            value = trim_ascii(value);
            if (!value.empty() && value.size() <= maximum_bytes) {
                return std::string(value);
            }
            return std::nullopt;
        }
        if (line_end == std::string_view::npos) {
            break;
        }
        line_start = line_end + 1;
    }
    return std::nullopt;
}

std::optional<std::string> read_bounded_file(
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

std::optional<std::int64_t> yaml_timestamp(
    std::string_view contents,
    std::string_view key) {
    const auto value = yaml_value(contents, key, 128);
    return value ? parse_rfc3339_unix_ms(*value) : std::nullopt;
}

std::vector<CLISession> cli_sessions(const CopilotSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(
        options.cli_session_state_directory,
        root_error);
    if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<CLISession> sessions;
    sessions.reserve(options.max_cli_sessions);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.updated_at_unix_ms != rhs.updated_at_unix_ms) {
            return lhs.updated_at_unix_ms > rhs.updated_at_unix_ms;
        }
        return lhs.id < rhs.id;
    };
    std::error_code error;
    fs::directory_iterator iterator(
        options.cli_session_state_directory,
        fs::directory_options::skip_permission_denied,
        error);
    const fs::directory_iterator end;
    while (!error && iterator != end) {
        const auto entry = *iterator;
        std::error_code status_error;
        const auto status = entry.symlink_status(status_error);
        if (!status_error && fs::is_directory(status) && !fs::is_symlink(status)
            && !has_hidden_name(entry.path())) {
            const auto workspace = entry.path() / "workspace.yaml";
            const auto contents = read_bounded_file(
                workspace,
                maximum_workspace_state_bytes);
            if (contents) {
                const auto id = yaml_value(
                    *contents,
                    "id",
                    maximum_identifier_bytes);
                if (id) {
                    std::error_code time_error;
                    const auto modified_at = fs::last_write_time(workspace, time_error);
                    const auto fallback = time_error ? 0 : unix_milliseconds(modified_at);
                    detail::retain_newest(
                        sessions,
                        CLISession{
                            .id = *id,
                            .working_directory = yaml_value(
                                *contents,
                                "cwd",
                                maximum_working_directory_bytes),
                            .started_at_unix_ms = yaml_timestamp(*contents, "created_at"),
                            .updated_at_unix_ms = yaml_timestamp(*contents, "updated_at")
                                .value_or(fallback),
                        },
                        options.max_cli_sessions,
                        newer);
                }
            }
        }
        iterator.increment(error);
    }

    std::sort(sessions.begin(), sessions.end(), newer);
    return sessions;
}

}  // namespace

CopilotSessionScanner::CopilotSessionScanner(CopilotSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_transcript_files = std::max<std::size_t>(
        1,
        options_.max_transcript_files);
    options_.max_cli_sessions = std::max<std::size_t>(1, options_.max_cli_sessions);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
}

std::vector<AIProgressTask> CopilotSessionScanner::active_tasks() const {
    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    for (const auto& candidate : recent_transcript_files(options_)) {
        const auto task = scan_transcript(candidate, options_);
        if (!task) {
            continue;
        }
        const auto existing = tasks_by_id.find(task->id);
        if (existing == tasks_by_id.end()
            || existing->second.updated_at_unix_ms < task->updated_at_unix_ms) {
            tasks_by_id.insert_or_assign(task->id, *task);
        }
    }
    for (const auto& session : cli_sessions(options_)) {
        AIProgressTask task{
            .id = cli_task_id(session.id),
            .provider = AIProvider::copilot,
            .title = "GitHub Copilot CLI",
            .detail = session.working_directory,
            .progress = std::nullopt,
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = session.updated_at_unix_ms,
            .session_uri = std::nullopt,
            .effort = std::nullopt,
            .started_at_unix_ms = session.started_at_unix_ms,
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
    return tasks;
}

std::string CopilotSessionScanner::vscode_task_id(std::string_view session_id) {
    return "copilot-vscode-session-" + std::string(session_id);
}

std::string CopilotSessionScanner::cli_task_id(std::string_view session_id) {
    return "copilot-cli-session-" + std::string(session_id);
}

}  // namespace zisla::core
