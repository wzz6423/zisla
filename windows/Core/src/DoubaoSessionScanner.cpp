#include "zisla/core/DoubaoSessionScanner.hpp"
#include "zisla/core/detail/BoundedRecent.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

struct FileCandidate {
    fs::path path;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

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

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::vector<FileCandidate> recent_files(const DoubaoSessionScanOptions& options) {
    std::vector<FileCandidate> candidates;
    candidates.reserve(options.max_files);
    const auto newer = [](const auto& lhs, const auto& rhs) {
        if (lhs.modified_at != rhs.modified_at) {
            return lhs.modified_at > rhs.modified_at;
        }
        return lhs.path.native() < rhs.path.native();
    };
    for (const auto& root : options.data_roots) {
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
                && !fs::is_symlink(status) && !has_hidden_name(entry.path())) {
                std::error_code time_error;
                const auto modified_at = entry.last_write_time(time_error);
                const auto normalized = entry.path().lexically_normal();
                const bool already_seen = std::any_of(
                    candidates.begin(), candidates.end(), [&normalized](const auto& candidate) {
                        return candidate.path.lexically_normal() == normalized;
                    });
                if (!time_error && !already_seen) {
                    detail::retain_newest(
                        candidates,
                        FileCandidate{
                            .path = entry.path(),
                            .modified_at = modified_at,
                            .modified_at_unix_ms = unix_milliseconds(modified_at),
                        },
                        options.max_files,
                        newer);
                }
            }
            iterator.increment(error);
        }
    }
    std::sort(candidates.begin(), candidates.end(), newer);
    return candidates;
}

}  // namespace

DoubaoSessionScanner::DoubaoSessionScanner(DoubaoSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_files = std::max<std::size_t>(1, options_.max_files);
    options_.recency_threshold_ms = std::max<std::int64_t>(
        0,
        options_.recency_threshold_ms);
}

std::vector<AIProgressTask> DoubaoSessionScanner::active_tasks() const {
    if (!options_.application_running) {
        return {};
    }
    const auto now_unix_ms = options_.now_unix_ms == 0
        ? current_unix_milliseconds()
        : options_.now_unix_ms;
    const auto cutoff = recency_cutoff(
        now_unix_ms,
        options_.recency_threshold_ms);
    const auto candidates = recent_files(options_);
    if (candidates.empty() || candidates.front().modified_at_unix_ms <= cutoff) {
        return {};
    }
    return {AIProgressTask{
        .id = "doubao-active",
        .provider = AIProvider::doubao,
        .title = "\xE8\xB1\x86\xE5\x8C\x85",
        .detail = std::nullopt,
        .progress = std::nullopt,
        .status = AIProgressStatus::running,
        .updated_at_unix_ms = candidates.front().modified_at_unix_ms,
        .session_uri = std::nullopt,
        .effort = std::nullopt,
        .started_at_unix_ms = std::nullopt,
    }};
}

}  // namespace zisla::core
