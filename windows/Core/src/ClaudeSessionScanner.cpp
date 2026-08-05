#include "zisla/core/ClaudeSessionScanner.hpp"

#include "zisla/core/ClaudeActivityParser.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <limits>
#include <optional>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

struct TranscriptCandidate {
    fs::path path;
    fs::file_time_type modified_at;
    std::int64_t modified_at_unix_ms{0};
};

struct OwnedTranscriptSnapshot {
    std::string jsonl;
    std::int64_t modified_at_unix_ms{0};
    std::string fallback_session_id;
};

bool has_hidden_name(const fs::path& path) noexcept {
    const auto name = path.filename().native();
    return !name.empty() && name.front() == static_cast<fs::path::value_type>('.');
}

std::int64_t unix_milliseconds(fs::file_time_type time) noexcept {
    const auto system_time = std::chrono::file_clock::to_sys(time);
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

bool is_transcript_file(const fs::directory_entry& entry) {
    if (entry.path().extension() != fs::path{".jsonl"}) {
        return false;
    }
    std::error_code error;
    const auto status = entry.symlink_status(error);
    return !error && fs::is_regular_file(status) && !fs::is_symlink(status);
}

std::vector<TranscriptCandidate> recent_transcripts(
    const ClaudeSessionScanOptions& options) {
    std::error_code root_error;
    const auto root_status = fs::symlink_status(options.projects_directory, root_error);
    if (root_error || !fs::is_directory(root_status) || fs::is_symlink(root_status)) {
        return {};
    }

    std::vector<TranscriptCandidate> candidates;
    std::error_code error;
    fs::recursive_directory_iterator iterator(
        options.projects_directory,
        fs::directory_options::skip_permission_denied,
        error);
    const fs::recursive_directory_iterator end;
    while (!error && iterator != end) {
        const auto entry = *iterator;
        std::error_code directory_error;
        if (entry.is_directory(directory_error) && has_hidden_name(entry.path())) {
            iterator.disable_recursion_pending();
        }
        if (!directory_error && is_transcript_file(entry)) {
            std::error_code time_error;
            const auto modified_at = entry.last_write_time(time_error);
            if (!time_error) {
                candidates.push_back({
                    entry.path(),
                    modified_at,
                    unix_milliseconds(modified_at),
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
    if (candidates.size() > options.max_transcript_files) {
        candidates.resize(options.max_transcript_files);
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

}  // namespace

ClaudeSessionScanner::ClaudeSessionScanner(ClaudeSessionScanOptions options)
    : options_(std::move(options)) {
    options_.max_transcript_files = std::max<std::size_t>(
        1,
        options_.max_transcript_files);
    options_.initial_tail_bytes = std::max<std::size_t>(1, options_.initial_tail_bytes);
}

std::vector<AIProgressTask> ClaudeSessionScanner::active_tasks() const {
    const auto candidates = recent_transcripts(options_);
    std::vector<OwnedTranscriptSnapshot> owned;
    owned.reserve(candidates.size());
    for (const auto& candidate : candidates) {
        if (auto contents = read_complete_tail(
                candidate.path,
                options_.initial_tail_bytes)) {
            owned.push_back({
                std::move(*contents),
                candidate.modified_at_unix_ms,
                candidate.path.stem().string(),
            });
        }
    }

    std::vector<ClaudeTranscriptSnapshot> snapshots;
    snapshots.reserve(owned.size());
    for (const auto& snapshot : owned) {
        snapshots.push_back({
            snapshot.jsonl,
            snapshot.modified_at_unix_ms,
            snapshot.fallback_session_id,
        });
    }
    return ClaudeActivityParser::active_tasks(snapshots);
}

}  // namespace zisla::core
