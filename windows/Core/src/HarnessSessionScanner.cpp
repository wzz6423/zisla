#include "zisla/core/HarnessSessionScanner.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <string>
#include <string_view>
#include <system_error>
#include <unordered_map>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

struct FileCandidate {
    fs::path path;
    std::string file_name;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

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

std::int64_t current_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

bool is_supported_data_file(const fs::path& path) {
    const auto extension = path.extension().u8string();
    const auto normalized = ascii_lower({
        reinterpret_cast<const char*>(extension.data()),
        extension.size(),
    });
    return normalized == ".log" || normalized == ".json" || normalized == ".jsonl";
}

std::vector<FileCandidate> recent_files(const HarnessSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(options.data_directory, root_error);
    if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<FileCandidate> candidates;
    std::error_code error;
    fs::recursive_directory_iterator iterator(
        options.data_directory,
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
            && fs::is_regular_file(status) && !fs::is_symlink(status)
            && is_supported_data_file(entry.path())) {
            std::error_code time_error;
            const auto modified_at = entry.last_write_time(time_error);
            const auto file_name = utf8_filename(entry.path());
            if (!time_error && !file_name.empty()) {
                candidates.push_back({
                    .path = entry.path(),
                    .file_name = file_name,
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
        return lhs.path.native() < rhs.path.native();
    });
    if (candidates.size() > options.max_files) {
        candidates.resize(options.max_files);
    }
    return candidates;
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

HarnessSessionScanner::HarnessSessionScanner(HarnessSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_files = std::max<std::size_t>(1, options_.max_files);
    options_.recency_threshold_ms = std::max<std::int64_t>(
        0,
        options_.recency_threshold_ms);
}

std::vector<AIProgressTask> HarnessSessionScanner::active_tasks() const {
    const auto now_unix_ms = options_.now_unix_ms == 0
        ? current_unix_milliseconds()
        : options_.now_unix_ms;
    const auto cutoff = recency_cutoff(now_unix_ms, options_.recency_threshold_ms);

    std::unordered_map<std::string, AIProgressTask> tasks_by_id;
    for (const auto& candidate : recent_files(options_)) {
        if (candidate.modified_at_unix_ms <= cutoff) {
            continue;
        }
        AIProgressTask task{
            .id = task_id(candidate.file_name),
            .provider = AIProvider::harness,
            .title = "harnext",
            .detail = std::nullopt,
            .progress = std::nullopt,
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = candidate.modified_at_unix_ms,
            .session_uri = std::nullopt,
            .effort = std::nullopt,
            .started_at_unix_ms = std::nullopt,
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

std::string HarnessSessionScanner::task_id(std::string_view file_name) {
    return "harness-file-" + std::string(file_name);
}

}  // namespace zisla::core
