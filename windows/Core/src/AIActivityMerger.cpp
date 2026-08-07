#include "zisla/core/AIActivityMerger.hpp"

#include <algorithm>

namespace zisla::core {
namespace {

void upsert(std::vector<AIProgressTask>& tasks, const AIProgressTask& task) {
    const auto existing = std::find_if(
        tasks.begin(),
        tasks.end(),
        [&task](const AIProgressTask& candidate) {
            return candidate.id == task.id;
        });
    if (existing == tasks.end()) {
        tasks.push_back(task);
    } else {
        *existing = task;
    }
}

bool is_stale_active_task(
    const AIProgressTask& task,
    AIActivityMergeOptions options) noexcept {
    if (!is_active(task.status)
        || task.updated_at_unix_ms >= options.now_unix_ms) {
        return false;
    }
    const auto age = static_cast<std::uint64_t>(options.now_unix_ms)
        - static_cast<std::uint64_t>(task.updated_at_unix_ms);
    return age > options.active_task_ttl_ms;
}

}  // namespace

std::vector<AIProgressTask> AIActivityMerger::merge(
    std::span<const AIProgressTask> persisted,
    std::span<const AIProgressTask> detected,
    AIActivityMergeOptions options) {
    std::vector<AIProgressTask> result;
    result.reserve(persisted.size() + detected.size());
    for (const auto& task : persisted) {
        upsert(result, task);
    }
    for (const auto& task : detected) {
        upsert(result, task);
    }
    std::erase_if(result, [options](const AIProgressTask& task) {
        return is_stale_active_task(task, options);
    });
    return result;
}

}  // namespace zisla::core
