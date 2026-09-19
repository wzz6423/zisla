#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct CodexRolloutSnapshot {
    std::string_view jsonl;
    std::int64_t modified_at_unix_ms{0};
};

class CodexActivityParser {
public:
    [[nodiscard]] static std::vector<AIProgressTask> active_tasks(
        std::span<const CodexRolloutSnapshot> rollouts,
        std::string_view session_index_jsonl = {});
    [[nodiscard]] static std::string task_id(std::string_view turn_id);
};

}  // namespace zisla::core
