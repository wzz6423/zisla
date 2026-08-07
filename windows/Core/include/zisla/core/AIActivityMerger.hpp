#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstdint>
#include <span>
#include <vector>

namespace zisla::core {

struct AIActivityMergeOptions {
    std::int64_t now_unix_ms{0};
    std::uint64_t active_task_ttl_ms{30ULL * 60ULL * 1'000ULL};
};

class AIActivityMerger {
public:
    [[nodiscard]] static std::vector<AIProgressTask> merge(
        std::span<const AIProgressTask> persisted,
        std::span<const AIProgressTask> detected,
        AIActivityMergeOptions options);
};

}  // namespace zisla::core
