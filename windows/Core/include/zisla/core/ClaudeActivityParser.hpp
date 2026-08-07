#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct ClaudeTranscriptSnapshot {
    std::string_view jsonl;
    std::int64_t modified_at_unix_ms{0};
    std::string_view fallback_session_id;
};

/// Parses `.claude/projects/**/*.jsonl` without retaining message text.
class ClaudeActivityParser {
public:
    [[nodiscard]] static std::vector<AIProgressTask> active_tasks(
        std::span<const ClaudeTranscriptSnapshot> transcripts);

    [[nodiscard]] static std::string task_id(std::string_view session_id);
};

}  // namespace zisla::core
