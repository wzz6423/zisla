#include "zisla/core/QwenSessionScanner.hpp"
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

struct RuntimeCandidate {
    fs::path runtime_path;
    fs::file_time_type runtime_modified_at;
    std::int64_t runtime_modified_at_unix_ms{0};
    fs::path transcript_path;
    fs::file_time_type transcript_modified_at{fs::file_time_type::min()};
    std::int64_t transcript_modified_at_unix_ms{0};

    [[nodiscard]] fs::file_time_type activity_modified_at() const noexcept {
        return std::max(runtime_modified_at, transcript_modified_at);
    }

    [[nodiscard]] std::int64_t activity_modified_at_unix_ms() const noexcept {
        return std::max(runtime_modified_at_unix_ms, transcript_modified_at_unix_ms);
    }
};

struct RuntimeSidecar {
    std::uint32_t pid{0};
    std::string session_id;
    std::optional<std::string> qwen_version;
    std::optional<std::int64_t> started_at_unix_ms;
};

struct TurnState {
    bool active{false};
    bool has_error{false};
    bool pending_ask_user{false};
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
    std::optional<std::string> model;
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
    if (const auto timestamp = timestamp_member(root, "timestamp")) {
        return *timestamp;
    }
    if (const auto timestamp = timestamp_member(root, "ts")) {
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

std::optional<std::uint32_t> parse_process_id(yyjson_val* value) noexcept {
    if (yyjson_is_uint(value)) {
        const auto pid = yyjson_get_uint(value);
        if (pid == 0 || pid > std::numeric_limits<std::uint32_t>::max()) {
            return std::nullopt;
        }
        return static_cast<std::uint32_t>(pid);
    }
    if (yyjson_is_sint(value)) {
        const auto pid = yyjson_get_sint(value);
        if (pid <= 0 || pid > static_cast<std::int64_t>(
                            std::numeric_limits<std::uint32_t>::max())) {
            return std::nullopt;
        }
        return static_cast<std::uint32_t>(pid);
    }
    const auto text = json_string(value);
    if (!text || text->empty()) {
        return std::nullopt;
    }
    std::uint64_t result = 0;
    for (const auto character : *text) {
        if (character < '0' || character > '9') {
            return std::nullopt;
        }
        const auto digit = static_cast<std::uint64_t>(character - '0');
        if (result > (std::numeric_limits<std::uint32_t>::max() - digit) / 10) {
            return std::nullopt;
        }
        result = result * 10 + digit;
    }
    return result == 0 ? std::nullopt
                       : std::optional<std::uint32_t>{static_cast<std::uint32_t>(result)};
}

std::optional<RuntimeSidecar> parse_runtime(
    const fs::path& path,
    std::size_t maximum_bytes) {
    const auto read_bounded_file = [maximum_bytes](const fs::path& file)
        -> std::optional<std::string> {
        std::ifstream stream(file, std::ios::binary);
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
        if (file_size > std::max<std::size_t>(1, maximum_bytes)
            || file_size > static_cast<std::uintmax_t>(
                               std::numeric_limits<std::streamsize>::max())) {
            return std::nullopt;
        }
        stream.seekg(0, std::ios::beg);
        std::string contents(static_cast<std::size_t>(file_size), '\0');
        stream.read(contents.data(), static_cast<std::streamsize>(contents.size()));
        contents.resize(static_cast<std::size_t>(stream.gcount()));
        return contents;
    };

    const auto contents = read_bounded_file(path);
    if (!contents) {
        return std::nullopt;
    }
    const auto document = parse_json(*contents);
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        return std::nullopt;
    }
    const auto pid = parse_process_id(yyjson_obj_get(root, "pid"));
    auto session_id = string_member(root, "session_id");
    if (!session_id) {
        session_id = string_member(root, "sessionId");
    }
    if (!pid || !session_id) {
        return std::nullopt;
    }
    return RuntimeSidecar{
        .pid = *pid,
        .session_id = *session_id,
        .qwen_version = string_member(root, "qwen_version"),
        .started_at_unix_ms = timestamp_member(root, "started_at"),
    };
}

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
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

bool is_runtime_file(const fs::path& path) {
    return path.extension() == fs::path{".json"}
        && path.stem().extension() == fs::path{".runtime"};
}

fs::path transcript_path_for(const fs::path& runtime_path) {
    auto base = runtime_path.stem();
    if (base.extension() == fs::path{".runtime"}) {
        base = base.stem();
    }
    base += ".jsonl";
    return runtime_path.parent_path() / base;
}

std::vector<RuntimeCandidate> recent_runtimes(const QwenSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(options.projects_directory, root_error);
    if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<RuntimeCandidate> candidates;
    candidates.reserve(options.max_runtime_files);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.activity_modified_at() != rhs.activity_modified_at()) {
            return lhs.activity_modified_at() > rhs.activity_modified_at();
        }
        return lhs.runtime_path.native() < rhs.runtime_path.native();
    };
    std::error_code error;
    fs::recursive_directory_iterator iterator(
        options.projects_directory,
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
            && is_runtime_file(entry.path()) && fs::is_regular_file(status)
            && !fs::is_symlink(status)) {
            std::error_code runtime_time_error;
            const auto runtime_modified_at = entry.last_write_time(runtime_time_error);
            if (!runtime_time_error) {
                RuntimeCandidate candidate{
                    .runtime_path = entry.path(),
                    .runtime_modified_at = runtime_modified_at,
                    .runtime_modified_at_unix_ms = unix_milliseconds(runtime_modified_at),
                    .transcript_path = transcript_path_for(entry.path()),
                };
                std::error_code transcript_status_error;
                const auto transcript_status = fs::symlink_status(
                    candidate.transcript_path,
                    transcript_status_error);
                if (!transcript_status_error && fs::is_regular_file(transcript_status)
                    && !fs::is_symlink(transcript_status)) {
                    std::error_code transcript_time_error;
                    const auto transcript_modified_at = fs::last_write_time(
                        candidate.transcript_path,
                        transcript_time_error);
                    if (!transcript_time_error) {
                        candidate.transcript_modified_at = transcript_modified_at;
                        candidate.transcript_modified_at_unix_ms = unix_milliseconds(
                            transcript_modified_at);
                    }
                }
                const bool may_enter = candidates.size() < options.max_runtime_files
                    || newer(
                        candidate,
                        *std::max_element(candidates.begin(), candidates.end(), newer));
                if (may_enter) {
                    const auto sidecar = parse_runtime(
                        candidate.runtime_path,
                        options.maximum_runtime_bytes);
                    if (sidecar && options.is_process_alive(sidecar->pid)) {
                        detail::retain_newest(
                            candidates,
                            std::move(candidate),
                            options.max_runtime_files,
                            newer);
                    }
                }
            }
        }
        iterator.increment(error);
    }

    std::sort(candidates.begin(), candidates.end(), newer);
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

template <typename Callback>
void for_each_message_part(yyjson_val* root, Callback&& callback) {
    auto* message = yyjson_obj_get(root, "message");
    auto* parts = yyjson_is_obj(message) ? yyjson_obj_get(message, "parts") : nullptr;
    if (!yyjson_is_arr(parts) && yyjson_is_obj(message)) {
        parts = yyjson_obj_get(message, "content");
    }
    if (!yyjson_is_arr(parts)) {
        parts = yyjson_obj_get(root, "parts");
    }
    if (!yyjson_is_arr(parts)) {
        return;
    }

    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* part = nullptr;
    yyjson_arr_foreach(parts, index, maximum, part) {
        if (yyjson_is_obj(part)) {
            callback(part);
        }
    }
}

void apply_assistant_record(
    yyjson_val* root,
    TurnState& state,
    std::int64_t timestamp) {
    state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);

    bool has_function_calls = false;
    bool has_ask_user = false;
    for_each_message_part(root, [&](yyjson_val* part) {
        yyjson_val* call = nullptr;
        if (auto* function_call = yyjson_obj_get(part, "functionCall");
            yyjson_is_obj(function_call)) {
            call = function_call;
        } else if (auto* legacy_function_call = yyjson_obj_get(part, "function_call");
                   yyjson_is_obj(legacy_function_call)) {
            call = legacy_function_call;
        } else if (const auto type = string_member(part, "type"); type
                   && ascii_lower(*type) == "function_call") {
            call = part;
        }
        if (!call) {
            return;
        }
        has_function_calls = true;
        auto name = string_member(call, "name");
        if (!name) {
            name = string_member(call, "functionName");
        }
        if (name) {
            const auto normalized_name = ascii_lower(*name);
            has_ask_user = has_ask_user || normalized_name == "ask_user_question"
                || normalized_name == "askuserquestion";
        }
    });

    if (!has_function_calls) {
        if (!state.has_error) {
            state.active = false;
        }
        state.pending_ask_user = false;
        return;
    }
    state.active = true;
    state.pending_ask_user = has_ask_user;
}

std::optional<std::string> tool_result_status(yyjson_val* root) {
    auto* result = yyjson_obj_get(root, "toolCallResult");
    if (const auto status = string_member(result, "status")) {
        return status;
    }
    result = yyjson_obj_get(root, "tool_call_result");
    if (const auto status = string_member(result, "status")) {
        return status;
    }
    return string_member(root, "status");
}

void apply_transcript_record(
    yyjson_val* root,
    TurnState& state,
    std::int64_t fallback_timestamp) {
    if (!yyjson_is_obj(root)) {
        return;
    }
    if (const auto model = string_member(root, "model")) {
        state.model = *model;
    }
    if (auto* message = yyjson_obj_get(root, "message"); yyjson_is_obj(message)) {
        if (const auto model = string_member(message, "model")) {
            state.model = *model;
        }
    }

    const auto type = string_member(root, "type");
    const auto normalized_type = type ? ascii_lower(*type) : std::string{};
    const auto timestamp = record_timestamp(root, fallback_timestamp);
    if (normalized_type == "user") {
        state.active = true;
        state.has_error = false;
        state.pending_ask_user = false;
        state.started_at_unix_ms = timestamp;
        state.updated_at_unix_ms = timestamp;
        return;
    }
    if (normalized_type == "assistant") {
        apply_assistant_record(root, state, timestamp);
        return;
    }
    if (normalized_type != "tool_result") {
        return;
    }

    state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
    if (const auto status = tool_result_status(root)) {
        const auto normalized_status = ascii_lower(*status);
        if (normalized_status == "error" || normalized_status == "failed"
            || normalized_status == "failure") {
            state.has_error = true;
            state.active = true;
        } else if (normalized_status == "success" || normalized_status == "succeeded"
                   || normalized_status == "completed" || normalized_status == "ok") {
            state.has_error = false;
        }
    }
    state.pending_ask_user = false;
}

void apply_jsonl(
    std::string_view jsonl,
    TurnState& state,
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
                apply_transcript_record(
                    yyjson_doc_get_root(document.get()),
                    state,
                    fallback_timestamp);
            }
        }
        line_start = line_end + 1;
    }
}

std::optional<AIProgressTask> make_task(
    const RuntimeCandidate& candidate,
    const RuntimeSidecar& sidecar,
    const TurnState& state) {
    if (!state.active && !state.has_error && !state.pending_ask_user) {
        return std::nullopt;
    }
    const auto status = state.has_error ? AIProgressStatus::error
        : state.pending_ask_user         ? AIProgressStatus::blocked
                                         : AIProgressStatus::running;
    return AIProgressTask{
        .id = QwenSessionScanner::task_id(sidecar.session_id),
        .provider = AIProvider::qwen,
        .title = "千问",
        .detail = state.model ? state.model : sidecar.qwen_version,
        .progress = std::nullopt,
        .status = status,
        .updated_at_unix_ms = std::max(
            state.updated_at_unix_ms,
            candidate.activity_modified_at_unix_ms()),
        .session_uri = std::nullopt,
        .effort = std::nullopt,
        .started_at_unix_ms = state.started_at_unix_ms,
    };
}

}  // namespace

QwenSessionScanner::QwenSessionScanner(QwenSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_runtime_files = std::max<std::size_t>(1, options_.max_runtime_files);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
    options_.maximum_runtime_bytes = std::max<std::size_t>(
        1,
        options_.maximum_runtime_bytes);
    if (!options_.is_process_alive) {
        options_.is_process_alive = [](std::uint32_t) { return false; };
    }
}

std::vector<AIProgressTask> QwenSessionScanner::active_tasks() const {
    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    std::size_t live_candidate_count = 0;
    for (const auto& candidate : recent_runtimes(options_)) {
        const auto sidecar = parse_runtime(
            candidate.runtime_path,
            options_.maximum_runtime_bytes);
        if (!sidecar || !options_.is_process_alive(sidecar->pid)) {
            continue;
        }
        ++live_candidate_count;
        if (live_candidate_count > options_.max_runtime_files) {
            break;
        }

        const auto contents = read_complete_tail(
            candidate.transcript_path,
            options_.initial_tail_bytes);
        if (!contents) {
            continue;
        }
        TurnState state;
        if (sidecar->started_at_unix_ms) {
            state.started_at_unix_ms = sidecar->started_at_unix_ms;
            state.updated_at_unix_ms = *sidecar->started_at_unix_ms;
        }
        apply_jsonl(*contents, state, candidate.activity_modified_at_unix_ms());
        const auto task = make_task(candidate, *sidecar, state);
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

std::string QwenSessionScanner::task_id(std::string_view session_id) {
    return "qwen-session-" + std::string(session_id);
}

}  // namespace zisla::core
