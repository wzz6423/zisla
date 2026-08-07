#include "zisla/core/AIActivityPresentation.hpp"

#include <algorithm>

namespace zisla::core {
namespace {

int status_priority(AIProgressStatus status) noexcept {
    switch (status) {
    case AIProgressStatus::error:
        return 0;
    case AIProgressStatus::blocked:
        return 1;
    case AIProgressStatus::queued:
        return 2;
    case AIProgressStatus::running:
        return 3;
    case AIProgressStatus::succeeded:
    case AIProgressStatus::failed:
        return 4;
    }
    return 4;
}

}  // namespace

std::vector<AIProgressTask> AIActivityPresenter::active_tasks(
    std::span<const AIProgressTask> tasks) {
    std::vector<AIProgressTask> result;
    result.reserve(tasks.size());
    for (const auto& task : tasks) {
        if (is_active(task.status)) {
            result.push_back(task);
        }
    }

    std::sort(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
        const auto lhs_priority = status_priority(lhs.status);
        const auto rhs_priority = status_priority(rhs.status);
        if (lhs_priority != rhs_priority) {
            return lhs_priority < rhs_priority;
        }
        if (lhs.updated_at_unix_ms != rhs.updated_at_unix_ms) {
            return lhs.updated_at_unix_ms > rhs.updated_at_unix_ms;
        }
        return lhs.id < rhs.id;
    });
    return result;
}

}  // namespace zisla::core
