#include "zisla/core/TraeSessionScanner.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
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

constexpr std::size_t maximum_identifier_bytes = 512;

struct LogCandidate {
    fs::path path;
    fs::file_time_type modified_at;
};

struct TaskState {
    std::string session_id;
    std::optional<std::int64_t> started_at_unix_ms;
    std::int64_t updated_at_unix_ms{0};
    bool has_error{false};
};

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

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::string utf8_filename(const fs::path& path) {
    const auto encoded = path.filename().u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

bool is_session_directory_name(std::string_view name) noexcept {
    if (name.size() != 15 || name[8] != 'T') {
        return false;
    }
    for (std::size_t index = 0; index < name.size(); ++index) {
        if (index != 8 && (name[index] < '0' || name[index] > '9')) {
            return false;
        }
    }
    return true;
}

bool is_agent_log(const fs::path& path) {
    const auto name = utf8_filename(path);
    constexpr std::string_view prefix = "ai-agent_";
    constexpr std::string_view suffix = "_stdout.log";
    return name.size() > prefix.size() + suffix.size()
        && name.starts_with(prefix) && name.ends_with(suffix);
}

std::vector<LogCandidate> recent_log_files(const TraeSessionScanOptions& options) {
    struct SessionDirectory {
        fs::path path;
        std::string name;
    };

    std::vector<SessionDirectory> directories;
    for (const auto& root : options.logs_roots) {
        std::error_code root_error;
        const auto root_status = fs::symlink_status(root, root_error);
        if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
            continue;
        }

        std::error_code error;
        fs::directory_iterator iterator(
            root,
            fs::directory_options::skip_permission_denied,
            error);
        const fs::directory_iterator end;
        while (!error && iterator != end) {
            const auto entry = *iterator;
            std::error_code status_error;
            const auto status = entry.symlink_status(status_error);
            const auto name = utf8_filename(entry.path());
            if (!status_error && fs::is_directory(status) && !fs::is_symlink(status)
                && !has_hidden_name(entry.path()) && is_session_directory_name(name)) {
                directories.push_back({entry.path(), name});
            }
            iterator.increment(error);
        }
    }

    std::sort(directories.begin(), directories.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.name != rhs.name) {
            return lhs.name > rhs.name;
        }
        return lhs.path.native() < rhs.path.native();
    });
    constexpr std::size_t maximum_session_directories = 3;
    if (directories.size() > maximum_session_directories) {
        directories.resize(maximum_session_directories);
    }

    std::vector<LogCandidate> candidates;
    for (const auto& directory : directories) {
        const auto modular = directory.path / "Modular";
        std::error_code modular_error;
        const auto modular_status = fs::symlink_status(modular, modular_error);
        if (modular_error || !fs::is_directory(modular_status) || fs::is_symlink(modular_status)) {
            continue;
        }

        std::error_code error;
        fs::directory_iterator iterator(
            modular,
            fs::directory_options::skip_permission_denied,
            error);
        const fs::directory_iterator end;
        while (!error && iterator != end) {
            const auto entry = *iterator;
            std::error_code status_error;
            const auto status = entry.symlink_status(status_error);
            std::error_code time_error;
            const auto modified_at = entry.last_write_time(time_error);
            if (!status_error && !time_error && fs::is_regular_file(status)
                && !fs::is_symlink(status) && !has_hidden_name(entry.path())
                && is_agent_log(entry.path())) {
                candidates.push_back({entry.path(), modified_at});
            }
            iterator.increment(error);
        }
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

std::optional<std::string> extract_key_value(
    std::string_view line,
    std::string_view key) {
    const auto marker = std::string(key) + "=";
    const auto marker_position = line.find(marker);
    if (marker_position == std::string_view::npos) {
        return std::nullopt;
    }
    auto value = line.substr(marker_position + marker.size());
    if (!value.empty() && value.front() == '"') {
        value.remove_prefix(1);
        const auto quote = value.find('"');
        if (quote == std::string_view::npos) {
            return std::nullopt;
        }
        value = value.substr(0, quote);
    } else {
        const auto end = value.find_first_of(" \t\r\n");
        value = value.substr(0, end);
    }
    value = trim_ascii(value);
    if (value.empty() || value.size() > maximum_identifier_bytes) {
        return std::nullopt;
    }
    return std::string(value);
}

std::string percent_encode_component(std::string_view value) {
    constexpr char hexadecimal[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(value.size());
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        const bool unreserved = (byte >= 'a' && byte <= 'z')
            || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9')
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

void parse_line(
    std::string_view line,
    std::unordered_map<std::string, TaskState>& tasks) {
    line = trim_ascii(line);
    const auto separator = line.find_first_of(" \t");
    if (separator == std::string_view::npos) {
        return;
    }
    const auto timestamp = parse_rfc3339_unix_ms(line.substr(0, separator));
    if (!timestamp) {
        return;
    }

    const auto normalized = ascii_lower(line);
    const bool chat_activity = normalized.find("do_chat") != std::string::npos;
    const bool error = line.find(" ERROR ") != std::string_view::npos;
    if (!chat_activity && !error) {
        return;
    }
    const auto trae_task_id = extract_key_value(line, "task_id");
    if (!trae_task_id) {
        return;
    }
    const auto session_id = extract_key_value(line, "session_id");

    auto& state = tasks[*trae_task_id];
    const bool is_newest_event = *timestamp >= state.updated_at_unix_ms;
    if (!state.started_at_unix_ms || *timestamp < *state.started_at_unix_ms) {
        state.started_at_unix_ms = *timestamp;
    }
    state.updated_at_unix_ms = std::max(state.updated_at_unix_ms, *timestamp);
    state.has_error = state.has_error || error;
    if (session_id && (state.session_id.empty() || is_newest_event)) {
        state.session_id = *session_id;
    }
}

}  // namespace

TraeSessionScanner::TraeSessionScanner(TraeSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_log_files = std::max<std::size_t>(1, options_.max_log_files);
    options_.tail_bytes = std::max<std::size_t>(1, options_.tail_bytes);
}

std::vector<AIProgressTask> TraeSessionScanner::active_tasks() const {
    std::unordered_map<std::string, TaskState> states_by_task_id;
    for (const auto& candidate : recent_log_files(options_)) {
        const auto contents = read_complete_tail(candidate.path, options_.tail_bytes);
        if (!contents) {
            continue;
        }
        std::size_t start = 0;
        while (start < contents->size()) {
            const auto end = contents->find('\n', start);
            const auto line_end = end == std::string::npos ? contents->size() : end;
            parse_line(std::string_view(*contents).substr(start, line_end - start), states_by_task_id);
            if (end == std::string::npos) {
                break;
            }
            start = end + 1;
        }
    }

    std::vector<AIProgressTask> tasks;
    tasks.reserve(states_by_task_id.size());
    for (const auto& [trae_task_id, state] : states_by_task_id) {
        if (state.updated_at_unix_ms == 0) {
            continue;
        }
        const auto session_uri = state.session_id.empty()
            ? std::optional<std::string>{}
            : std::optional<std::string>{
                "solo-cn://solo-deeplink.ai/teleport_session?sid="
                + percent_encode_component(state.session_id)};
        tasks.push_back({
            .id = task_id(trae_task_id),
            .provider = AIProvider::trae,
            .title = "TRAE",
            .detail = std::nullopt,
            .progress = std::nullopt,
            .status = state.has_error ? AIProgressStatus::error : AIProgressStatus::running,
            .updated_at_unix_ms = state.updated_at_unix_ms,
            .session_uri = session_uri,
            .effort = std::nullopt,
            .started_at_unix_ms = state.started_at_unix_ms,
        });
    }
    std::sort(tasks.begin(), tasks.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.updated_at_unix_ms != rhs.updated_at_unix_ms) {
            return lhs.updated_at_unix_ms > rhs.updated_at_unix_ms;
        }
        return lhs.id < rhs.id;
    });
    return tasks;
}

std::string TraeSessionScanner::task_id(std::string_view trae_task_id) {
    return "trae-task-" + std::string(trae_task_id);
}

}  // namespace zisla::core
