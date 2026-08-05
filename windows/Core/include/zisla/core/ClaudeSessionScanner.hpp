#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <vector>

namespace zisla::core {

struct ClaudeSessionScanOptions {
    std::filesystem::path projects_directory;
    std::size_t max_transcript_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
};

/// Scans `.claude/projects/**/*.jsonl` for Claude Code (VS Code) active sessions.
class ClaudeSessionScanner {
public:
    explicit ClaudeSessionScanner(ClaudeSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;

private:
    ClaudeSessionScanOptions options_;
};

}  // namespace zisla::core
