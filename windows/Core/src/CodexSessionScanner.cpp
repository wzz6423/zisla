#include "zisla/core/CodexSessionScanner.hpp"
#include "zisla/core/detail/BoundedRecent.hpp"

#include "zisla/core/CodexActivityParser.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

constexpr std::size_t maximum_session_index_bytes = 4 * 1'024 * 1'024;

struct RolloutCandidate {
    fs::path path;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct OwnedRolloutSnapshot {
    std::string jsonl;
    std::int64_t modified_at_unix_ms{0};
};

bool has_numeric_name(const fs::path& path, std::size_t length) noexcept {
    const auto name = path.filename().native();
    if (name.size() != length) {
        return false;
    }
    return std::all_of(name.begin(), name.end(), [](fs::path::value_type value) {
        return value >= static_cast<fs::path::value_type>('0')
            && value <= static_cast<fs::path::value_type>('9');
    });
}

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::vector<fs::path> numeric_directories(
    const fs::path& root,
    std::size_t component_length,
    std::size_t limit) {
    std::vector<fs::path> result;
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
        if (!status_error
            && fs::is_directory(status)
            && !fs::is_symlink(status)
            && has_numeric_name(entry.path(), component_length)) {
            result.push_back(entry.path());
        }
        iterator.increment(error);
    }

    std::sort(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
        return lhs.filename().native() > rhs.filename().native();
    });
    if (result.size() > limit) {
        result.resize(limit);
    }
    return result;
}

std::vector<fs::path> rollout_search_directories(const fs::path& sessions_directory) {
    const auto years = numeric_directories(sessions_directory, 4, 2);
    if (years.empty()) {
        return {sessions_directory};
    }

    std::vector<fs::path> days;
    for (const auto& year : years) {
        const auto months = numeric_directories(year, 2, 2);
        for (const auto& month : months) {
            auto month_days = numeric_directories(month, 2, 4);
            days.insert(
                days.end(),
                std::make_move_iterator(month_days.begin()),
                std::make_move_iterator(month_days.end()));
        }
    }
    return days.empty() ? std::vector<fs::path>{sessions_directory} : days;
}

bool is_rollout_file(const fs::directory_entry& entry) {
    const auto filename = entry.path().filename().native();
    const auto prefix = fs::path{"rollout-"}.native();
    if (!filename.starts_with(prefix)
        || entry.path().extension() != fs::path{".jsonl"}) {
        return false;
    }

    std::error_code error;
    const auto status = entry.symlink_status(error);
    return !error && fs::is_regular_file(status) && !fs::is_symlink(status);
}

std::int64_t unix_milliseconds(fs::file_time_type time) noexcept {
    const auto system_time = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
        time - fs::file_time_type::clock::now() + std::chrono::system_clock::now());
    const auto count = std::chrono::duration_cast<std::chrono::milliseconds>(
        system_time.time_since_epoch()).count();
    if constexpr (sizeof(count) > sizeof(std::int64_t)) {
        return count > std::numeric_limits<std::int64_t>::max()
            ? std::numeric_limits<std::int64_t>::max()
            : count < std::numeric_limits<std::int64_t>::min()
            ? std::numeric_limits<std::int64_t>::min()
            : static_cast<std::int64_t>(count);
    }
    return static_cast<std::int64_t>(count);
}

std::vector<RolloutCandidate> recent_rollouts(
    const CodexSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(options.sessions_directory, root_error);
    if (root_error
        || !fs::is_directory(root_status)
        || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<RolloutCandidate> candidates;
    candidates.reserve(options.max_rollout_files);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.path.native() < rhs.path.native();
    };
    for (const auto& directory : rollout_search_directories(options.sessions_directory)) {
        std::error_code error;
        fs::recursive_directory_iterator iterator(
            directory,
            fs::directory_options::skip_permission_denied,
            error);
        const fs::recursive_directory_iterator end;
        while (!error && iterator != end) {
            const auto entry = *iterator;
            if (entry.is_directory(error) && has_hidden_name(entry.path())) {
                iterator.disable_recursion_pending();
            }
            if (!error && is_rollout_file(entry)) {
                std::error_code time_error;
                const auto modified_at = entry.last_write_time(time_error);
                if (!time_error) {
                    detail::retain_newest(
                        candidates,
                        RolloutCandidate{
                            entry.path(),
                            modified_at,
                            unix_milliseconds(modified_at),
                        },
                        options.max_rollout_files,
                        newer);
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

fs::path session_index_path(const CodexSessionScanOptions& options) {
    return options.session_index_path.empty()
        ? options.sessions_directory.parent_path() / "session_index.jsonl"
        : options.session_index_path;
}

}  // namespace

CodexSessionScanner::CodexSessionScanner(CodexSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_rollout_files = std::max<std::size_t>(1, options_.max_rollout_files);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
}

std::vector<AIProgressTask> CodexSessionScanner::active_tasks() const {
    const auto candidates = recent_rollouts(options_);
    std::vector<OwnedRolloutSnapshot> owned;
    owned.reserve(candidates.size());
    for (const auto& candidate : candidates) {
        if (auto contents = read_complete_tail(
                candidate.path,
                options_.initial_tail_bytes)) {
            owned.push_back({std::move(*contents), candidate.modified_at_unix_ms});
        }
    }

    std::vector<CodexRolloutSnapshot> snapshots;
    snapshots.reserve(owned.size());
    for (const auto& snapshot : owned) {
        snapshots.push_back({snapshot.jsonl, snapshot.modified_at_unix_ms});
    }

    const auto index = read_complete_tail(
        session_index_path(options_),
        maximum_session_index_bytes).value_or(std::string{});
    return CodexActivityParser::active_tasks(snapshots, index);
}

}  // namespace zisla::core
