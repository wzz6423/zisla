#include "zisla/core/QoderSessionScanner.hpp"

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
constexpr std::size_t maximum_model_bytes = 512;

enum class CandidateKind {
    structured,
    text,
};

struct LogCandidate {
    fs::path path;
    CandidateKind kind;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct StructuredRecord {
    std::string type;
    std::optional<std::string> session_id;
    std::optional<std::string> tool_call_id;
    std::optional<std::string> model;
    std::optional<std::string> status;
    std::optional<std::string> reason;
    std::optional<std::int64_t> exit_code;
    bool is_error{false};
    bool denied_by_permission{false};
    bool has_error_payload{false};
    std::int64_t timestamp_unix_ms{0};
    std::int64_t sequence{0};
    std::string path_key;
    std::size_t line_number{0};
};

struct StructuredState {
    std::optional<std::string> session_id;
    std::optional<std::string> model;
    bool active{false};
    bool has_error{false};
    std::unordered_set<std::string> pending_permission_ids;
    std::size_t anonymous_permission_count{0};
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
};

struct TextState {
    bool active{false};
    bool has_error{false};
    std::unordered_set<std::string> pending_request_ids;
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

bool contains(std::string_view value, std::string_view marker) noexcept {
    return value.find(marker) != std::string_view::npos;
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

std::optional<std::int64_t> json_integer(yyjson_val* value) noexcept {
    if (value && yyjson_is_sint(value)) {
        return yyjson_get_sint(value);
    }
    if (value && yyjson_is_uint(value)) {
        const auto result = yyjson_get_uint(value);
        if (result <= static_cast<std::uint64_t>(
                          std::numeric_limits<std::int64_t>::max())) {
            return static_cast<std::int64_t>(result);
        }
    }
    if (const auto text = json_string(value, 64)) {
        std::int64_t result = 0;
        const auto* begin = text->data();
        const auto* end = begin + text->size();
        const auto parsed = std::from_chars(begin, end, result);
        if (parsed.ec == std::errc{} && parsed.ptr == end) {
            return result;
        }
    }
    return std::nullopt;
}

bool json_true(yyjson_val* value) noexcept {
    return value && yyjson_is_bool(value) && yyjson_get_bool(value);
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

std::string path_key(const fs::path& path) {
    const auto encoded = path.lexically_normal().generic_u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

std::string utf8_filename(const fs::path& path) {
    const auto encoded = path.filename().u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

bool is_jsonl(const fs::path& path) {
    const auto extension = path.extension().u8string();
    return ascii_lower({
        reinterpret_cast<const char*>(extension.data()),
        extension.size(),
    }) == ".jsonl";
}

bool is_structured_candidate(const fs::path& path) {
    return is_jsonl(path);
}

bool is_text_candidate(const fs::path& path) {
    const auto name = ascii_lower(utf8_filename(path));
    if (name == "qoder-agent-sdk.log") {
        return true;
    }
    const auto extension = path.extension().u8string();
    const auto normalized_extension = ascii_lower({
        reinterpret_cast<const char*>(extension.data()),
        extension.size(),
    });
    return contains(name, "qoder")
        && (normalized_extension == ".log" || normalized_extension == ".txt");
}

std::vector<LogCandidate> discover_candidates(
    const QoderSessionScanOptions& options) {
    std::vector<LogCandidate> candidates;
    std::unordered_set<std::string> seen_paths;

    const auto append_tree = [&candidates, &seen_paths](
                                 const fs::path& root,
                                 CandidateKind kind,
                                 const auto& accept) {
        std::error_code root_error;
        const auto root_status = fs::symlink_status(root, root_error);
        if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
            return;
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
                && accept(entry.path())) {
                std::error_code time_error;
                const auto modified_at = entry.last_write_time(time_error);
                if (!time_error) {
                    const auto key = path_key(entry.path());
                    if (seen_paths.insert(key).second) {
                        candidates.push_back({
                            .path = entry.path(),
                            .kind = kind,
                            .modified_at = modified_at,
                            .modified_at_unix_ms = unix_milliseconds(modified_at),
                        });
                    }
                }
            }
            iterator.increment(error);
        }
    };

    for (const auto& root : options.config_roots) {
        append_tree(
            root / "logs" / "sessions",
            CandidateKind::structured,
            is_structured_candidate);
    }
    for (const auto& root : options.text_log_roots) {
        append_tree(root, CandidateKind::text, is_text_candidate);
    }

    std::sort(candidates.begin(), candidates.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.path.native() < rhs.path.native();
    });
    if (candidates.size() > options.max_log_files) {
        candidates.resize(options.max_log_files);
    }
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

std::optional<std::string> object_string(
    yyjson_val* object,
    const char* key,
    std::size_t maximum_bytes = maximum_identifier_bytes) {
    return object && yyjson_is_obj(object)
        ? json_string(yyjson_obj_get(object, key), maximum_bytes)
        : std::nullopt;
}

std::optional<std::string> first_string(
    yyjson_val* root,
    yyjson_val* ids,
    yyjson_val* data,
    const char* snake_case_key,
    const char* camel_case_key,
    std::size_t maximum_bytes = maximum_identifier_bytes) {
    for (auto* object : {root, ids, data}) {
        if (const auto value = object_string(object, snake_case_key, maximum_bytes)) {
            return value;
        }
        if (const auto value = object_string(object, camel_case_key, maximum_bytes)) {
            return value;
        }
    }
    return std::nullopt;
}

std::optional<StructuredRecord> parse_structured_record(
    std::string_view line,
    std::int64_t fallback_timestamp,
    std::int64_t fallback_sequence,
    std::string path,
    std::size_t line_number) {
    const JsonDocument document{
        yyjson_read(line.data(), line.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!root || !yyjson_is_obj(root)) {
        return std::nullopt;
    }
    const auto type = object_string(root, "type", 128);
    if (!type) {
        return std::nullopt;
    }
    auto* ids = yyjson_obj_get(root, "ids");
    if (!ids || !yyjson_is_obj(ids)) {
        ids = nullptr;
    }
    auto* data = yyjson_obj_get(root, "data");
    if (!data || !yyjson_is_obj(data)) {
        data = nullptr;
    }

    auto root_timestamp = json_timestamp(yyjson_obj_get(root, "ts"));
    if (!root_timestamp) {
        root_timestamp = json_timestamp(yyjson_obj_get(root, "timestamp"));
    }
    const auto sequence = json_integer(yyjson_obj_get(root, "seq"))
        .value_or(fallback_sequence);
    auto exit_code = data
        ? json_integer(yyjson_obj_get(data, "exit_code"))
        : std::optional<std::int64_t>{};
    if (!exit_code && data) {
        exit_code = json_integer(yyjson_obj_get(data, "exitCode"));
    }
    const auto has_error_payload = data && yyjson_obj_get(data, "error")
        && !yyjson_is_null(yyjson_obj_get(data, "error"));

    return StructuredRecord{
        .type = ascii_lower(*type),
        .session_id = first_string(root, ids, data, "session_id", "sessionId"),
        .tool_call_id = first_string(root, ids, data, "tool_call_id", "toolCallId"),
        .model = object_string(data, "model", maximum_model_bytes),
        .status = object_string(data, "status", 128),
        .reason = object_string(data, "reason", 128),
        .exit_code = exit_code,
        .is_error = data && (json_true(yyjson_obj_get(data, "is_error"))
            || json_true(yyjson_obj_get(data, "isError"))),
        .denied_by_permission = data && json_true(
            yyjson_obj_get(data, "denied_by_permission")),
        .has_error_payload = has_error_payload,
        .timestamp_unix_ms = root_timestamp.value_or(fallback_timestamp),
        .sequence = sequence,
        .path_key = std::move(path),
        .line_number = line_number,
    };
}

void apply_structured_record(const StructuredRecord& record, StructuredState& state) {
    if (record.session_id) {
        state.session_id = *record.session_id;
    }
    const auto timestamp = record.timestamp_unix_ms;
    if (record.type == "turn.started") {
        state.active = true;
        state.has_error = false;
        state.pending_permission_ids.clear();
        state.anonymous_permission_count = 0;
        state.started_at_unix_ms = timestamp;
        state.updated_at_unix_ms = timestamp;
        if (record.model) {
            state.model = *record.model;
        }
        return;
    }
    if (record.type == "permission.requested") {
        state.active = true;
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (record.tool_call_id) {
            state.pending_permission_ids.insert(*record.tool_call_id);
        } else {
            ++state.anonymous_permission_count;
        }
        return;
    }
    if (record.type == "permission.resolved") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (record.tool_call_id) {
            state.pending_permission_ids.erase(*record.tool_call_id);
        } else if (state.anonymous_permission_count > 0) {
            --state.anonymous_permission_count;
        }
        return;
    }
    if (record.type == "permission.failed") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        state.has_error = true;
        state.active = true;
        if (record.tool_call_id) {
            state.pending_permission_ids.erase(*record.tool_call_id);
        } else if (state.anonymous_permission_count > 0) {
            --state.anonymous_permission_count;
        }
        return;
    }
    if (record.type == "tool.execution.finished") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (record.tool_call_id) {
            state.pending_permission_ids.erase(*record.tool_call_id);
        }
        const auto status = record.status ? ascii_lower(*record.status) : std::string{};
        if (record.is_error || record.denied_by_permission || status == "error"
            || status == "failed" || status == "failure" || status == "denied") {
            state.has_error = true;
        } else if (status == "success" || status == "succeeded"
                   || status == "completed" || status == "ok") {
            state.has_error = false;
        }
        return;
    }
    if (record.type == "tool.shell.finished") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (record.tool_call_id) {
            state.pending_permission_ids.erase(*record.tool_call_id);
        }
        if (record.exit_code && *record.exit_code != 0) {
            state.has_error = true;
        } else if (record.exit_code) {
            state.has_error = false;
        }
        return;
    }
    if (record.type == "tool.shell.failed") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        state.has_error = true;
        return;
    }
    if (record.type == "turn.finished") {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        state.pending_permission_ids.clear();
        state.anonymous_permission_count = 0;
        const auto reason = record.reason ? ascii_lower(*record.reason) : std::string{};
        if (reason == "error" || record.has_error_payload) {
            state.has_error = true;
            state.active = true;
        } else {
            state.has_error = false;
            state.active = false;
        }
    }
}

fs::path structured_session_directory(const fs::path& path) {
    const auto parent = path.parent_path();
    return utf8_filename(parent) == "segments" ? parent.parent_path() : parent;
}

std::optional<AIProgressTask> parse_structured_group(
    const std::vector<LogCandidate>& candidates,
    std::string_view session_key,
    const QoderSessionScanOptions& options) {
    std::vector<StructuredRecord> records;
    std::string fallback_session_id;
    std::int64_t latest_modified_at = 0;
    for (const auto& candidate : candidates) {
        latest_modified_at = std::max(
            latest_modified_at,
            candidate.modified_at_unix_ms);
        if (fallback_session_id.empty()) {
            fallback_session_id = utf8_filename(structured_session_directory(candidate.path));
        }
        const auto contents = read_complete_tail(
            candidate.path,
            options.initial_tail_bytes);
        if (!contents) {
            continue;
        }
        std::size_t line_start = 0;
        std::size_t line_number = 0;
        while (line_start < contents->size()) {
            const auto line_end = contents->find('\n', line_start);
            if (line_end == std::string::npos) {
                break;
            }
            auto line = std::string_view(*contents).substr(
                line_start,
                line_end - line_start);
            if (!line.empty() && line.back() == '\r') {
                line.remove_suffix(1);
            }
            if (!trim_ascii(line).empty()) {
                if (const auto record = parse_structured_record(
                        line,
                        candidate.modified_at_unix_ms,
                        static_cast<std::int64_t>(line_number),
                        path_key(candidate.path),
                        line_number)) {
                    records.push_back(*record);
                }
            }
            ++line_number;
            line_start = line_end + 1;
        }
    }
    std::sort(records.begin(), records.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.timestamp_unix_ms != rhs.timestamp_unix_ms) {
            return lhs.timestamp_unix_ms < rhs.timestamp_unix_ms;
        }
        if (lhs.sequence != rhs.sequence) {
            return lhs.sequence < rhs.sequence;
        }
        if (lhs.path_key != rhs.path_key) {
            return lhs.path_key < rhs.path_key;
        }
        return lhs.line_number < rhs.line_number;
    });

    StructuredState state;
    if (!fallback_session_id.empty()) {
        state.session_id = fallback_session_id;
    }
    for (const auto& record : records) {
        apply_structured_record(record, state);
    }
    const bool blocked = !state.pending_permission_ids.empty()
        || state.anonymous_permission_count > 0;
    if (!state.active && !state.has_error && !blocked) {
        return std::nullopt;
    }
    const auto status = state.has_error ? AIProgressStatus::error
        : blocked                         ? AIProgressStatus::blocked
                                          : AIProgressStatus::running;
    const auto id = state.session_id
        ? QoderSessionScanner::session_task_id(*state.session_id)
        : QoderSessionScanner::log_task_id(session_key);
    return AIProgressTask{
        .id = id,
        .provider = AIProvider::coder,
        .title = "Qoder",
        .detail = std::string{"CLI"},
        .progress = std::nullopt,
        .status = status,
        .updated_at_unix_ms = std::max(
            state.updated_at_unix_ms,
            latest_modified_at),
        .session_uri = std::nullopt,
        .effort = std::nullopt,
        .started_at_unix_ms = state.started_at_unix_ms,
    };
}

std::optional<std::string> leading_timestamp(std::string_view line) {
    const auto trimmed = trim_ascii(line);
    const auto separator = trimmed.find_first_of(" \t");
    return separator == std::string_view::npos
        ? (parse_rfc3339_unix_ms(trimmed)
                ? std::optional<std::string>{std::string(trimmed)}
                : std::nullopt)
        : std::optional<std::string>{std::string(trimmed.substr(0, separator))};
}

std::optional<std::string> extract_token(std::string_view line, std::string_view key) {
    const auto marker = std::string(key) + "=";
    const auto position = line.find(marker);
    if (position == std::string_view::npos) {
        return std::nullopt;
    }
    auto value = line.substr(position + marker.size());
    const auto end = value.find_first_of(" \t\r\n");
    value = trim_ascii(value.substr(0, end));
    if (value.empty() || value.size() > maximum_identifier_bytes) {
        return std::nullopt;
    }
    return std::string(value);
}

void apply_text_line(
    std::string_view line,
    TextState& state,
    std::int64_t fallback_timestamp) {
    const auto prefix = leading_timestamp(line);
    const auto timestamp = prefix
        ? parse_rfc3339_unix_ms(*prefix).value_or(fallback_timestamp)
        : fallback_timestamp;
    if (contains(line, "[QueryRunner] outbound session_message sent type=user")) {
        state.active = true;
        state.has_error = false;
        state.started_at_unix_ms = timestamp;
        state.updated_at_unix_ms = timestamp;
        return;
    }
    if (contains(line, "inbound session_message received type=result")) {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (contains(line, "subtype=error_during_execution")) {
            state.has_error = true;
            state.active = true;
        } else if (contains(line, "subtype=success")) {
            state.has_error = false;
            state.active = false;
            state.pending_request_ids.clear();
        }
        return;
    }
    if (contains(line, "inbound control_request received")
        && contains(line, "subtype=can_use_tool")) {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (const auto request_id = extract_token(line, "request_id")) {
            state.pending_request_ids.insert(*request_id);
        }
        return;
    }
    if (contains(line, "inbound control_response sent")
        && contains(line, "subtype=can_use_tool")) {
        state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, timestamp);
        if (const auto request_id = extract_token(line, "request_id")) {
            state.pending_request_ids.erase(*request_id);
        }
        const auto status = extract_token(line, "status");
        if (status && ascii_lower(*status) != "success"
            && ascii_lower(*status) != "ok") {
            state.has_error = true;
            state.active = true;
        }
    }
}

std::string host_detail(const fs::path& path) {
    const auto normalized = ascii_lower(path_key(path));
    const auto is_vscode = contains(normalized, "/code/")
        || contains(normalized, "\\code\\")
        || contains(normalized, "/cursor/")
        || contains(normalized, "\\cursor\\")
        || contains(normalized, "/vscodium/")
        || contains(normalized, "\\vscodium\\")
        || contains(normalized, "/windsurf/")
        || contains(normalized, "\\windsurf\\");
    if (is_vscode) {
        return "VS Code";
    }
    if (contains(normalized, "jetbrains") || contains(normalized, "intellij")
        || contains(normalized, "webstorm")) {
        return "JetBrains";
    }
    if (contains(normalized, "qoderwork") || contains(normalized, "qoderwake")
        || contains(normalized, "qoder")) {
        return "Desktop";
    }
    return "Host";
}

std::optional<AIProgressTask> parse_text_log(
    const LogCandidate& candidate,
    const QoderSessionScanOptions& options) {
    const auto contents = read_complete_tail(candidate.path, options.initial_tail_bytes);
    if (!contents) {
        return std::nullopt;
    }
    TextState state;
    std::size_t line_start = 0;
    while (line_start < contents->size()) {
        const auto line_end = contents->find('\n', line_start);
        if (line_end == std::string::npos) {
            break;
        }
        auto line = std::string_view(*contents).substr(
            line_start,
            line_end - line_start);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        if (!trim_ascii(line).empty()) {
            apply_text_line(line, state, candidate.modified_at_unix_ms);
        }
        line_start = line_end + 1;
    }
    const bool blocked = !state.pending_request_ids.empty();
    if (!state.active && !state.has_error && !blocked) {
        return std::nullopt;
    }
    const auto status = state.has_error ? AIProgressStatus::error
        : blocked                         ? AIProgressStatus::blocked
                                          : AIProgressStatus::running;
    return AIProgressTask{
        .id = QoderSessionScanner::log_task_id(path_key(candidate.path)),
        .provider = AIProvider::coder,
        .title = "Qoder",
        .detail = host_detail(candidate.path),
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

std::optional<std::string> session_id_from_task_id(std::string_view task_id) {
    constexpr std::string_view prefix = "qoder-session-";
    if (!task_id.starts_with(prefix) || task_id.size() == prefix.size()) {
        return std::nullopt;
    }
    return std::string(task_id.substr(prefix.size()));
}

std::string percent_encode_component(std::string_view value) {
    constexpr char hexadecimal[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(value.size());
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        const bool unreserved = (byte >= 'a' && byte <= 'z')
            || (byte >= 'A' && byte <= 'Z')
            || (byte >= '0' && byte <= '9')
            || byte == '-' || byte == '.' || byte == '_' || byte == '~';
        if (unreserved) {
            result.push_back(static_cast<char>(byte));
        } else {
            result.push_back('%');
            result.push_back(hexadecimal[(byte >> 4U) & 0x0FU]);
            result.push_back(hexadecimal[byte & 0x0FU]);
        }
    }
    return result;
}

AIProgressStatus dominant_status(
    AIProgressStatus lhs,
    AIProgressStatus rhs) noexcept {
    if (lhs == AIProgressStatus::error || rhs == AIProgressStatus::error) {
        return AIProgressStatus::error;
    }
    if (lhs == AIProgressStatus::blocked || rhs == AIProgressStatus::blocked) {
        return AIProgressStatus::blocked;
    }
    return lhs;
}

bool is_same_desktop_turn(
    const AIProgressTask& structured,
    const AIProgressTask& text) noexcept {
    if (structured.detail != "CLI" || text.detail != "Desktop"
        || !structured.started_at_unix_ms || !text.started_at_unix_ms) {
        return false;
    }
    const auto lhs = *structured.started_at_unix_ms;
    const auto rhs = *text.started_at_unix_ms;
    const auto difference = lhs >= rhs ? lhs - rhs : rhs - lhs;
    return difference <= 2'000;
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

}  // namespace

QoderSessionScanner::QoderSessionScanner(QoderSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_log_files = std::max<std::size_t>(1, options_.max_log_files);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
}

std::vector<AIProgressTask> QoderSessionScanner::active_tasks() const {
    std::unordered_map<std::string, std::vector<LogCandidate>> structured_groups;
    std::vector<LogCandidate> text_candidates;
    for (const auto& candidate : discover_candidates(options_)) {
        if (candidate.kind == CandidateKind::structured) {
            structured_groups[path_key(structured_session_directory(candidate.path))]
                .push_back(candidate);
        } else {
            text_candidates.push_back(candidate);
        }
    }

    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    for (const auto& [session_key, candidates] : structured_groups) {
        if (const auto task = parse_structured_group(candidates, session_key, options_)) {
            merge_task(*task, tasks_by_id);
        }
    }
    for (const auto& candidate : text_candidates) {
        const auto text_task = parse_text_log(candidate, options_);
        if (!text_task) {
            continue;
        }
        std::vector<std::string> duplicate_ids;
        for (const auto& [id, structured_task] : tasks_by_id) {
            if (is_same_desktop_turn(structured_task, *text_task)) {
                duplicate_ids.push_back(id);
            }
        }
        if (duplicate_ids.size() != 1) {
            merge_task(*text_task, tasks_by_id);
            continue;
        }
        auto& structured_task = tasks_by_id.at(duplicate_ids.front());
        structured_task.detail = "Desktop";
        if (const auto session_id = session_id_from_task_id(structured_task.id)) {
            structured_task.session_uri = "qoder-work-cn://notification-click?chatId="
                + percent_encode_component(*session_id);
        }
        structured_task.status = dominant_status(
            structured_task.status,
            text_task->status);
        structured_task.updated_at_unix_ms = std::max(
            structured_task.updated_at_unix_ms,
            text_task->updated_at_unix_ms);
        if (!structured_task.started_at_unix_ms
            || (text_task->started_at_unix_ms
                && *text_task->started_at_unix_ms
                    < *structured_task.started_at_unix_ms)) {
            structured_task.started_at_unix_ms = text_task->started_at_unix_ms;
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

std::string QoderSessionScanner::session_task_id(std::string_view session_id) {
    return "qoder-session-" + std::string(session_id);
}

std::string QoderSessionScanner::log_task_id(std::string_view path) {
    std::uint64_t hash = 0xcbf29ce484222325ULL;
    for (const auto character : path) {
        hash ^= static_cast<unsigned char>(character);
        hash *= 0x100000001b3ULL;
    }
    constexpr char hexadecimal[] = "0123456789abcdef";
    std::string encoded;
    do {
        encoded.push_back(hexadecimal[hash & 0x0FU]);
        hash >>= 4U;
    } while (hash != 0);
    std::reverse(encoded.begin(), encoded.end());
    return "qoder-log-" + encoded;
}

}  // namespace zisla::core
