#pragma once

#include "zisla/core/AIModels.hpp"

#include <span>
#include <vector>

namespace zisla::core {

class AIActivityPresenter {
public:
    [[nodiscard]] static std::vector<AIProgressTask> active_tasks(
        std::span<const AIProgressTask> tasks);
};

}  // namespace zisla::core
