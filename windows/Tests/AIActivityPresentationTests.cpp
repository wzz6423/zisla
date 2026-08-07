#include "zisla/core/AIActivityPresentation.hpp"

#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

AIProgressTask task(
    std::string id,
    AIProgressStatus status,
    std::int64_t updated_at_unix_ms) {
    return {
        .id = std::move(id),
        .status = status,
        .updated_at_unix_ms = updated_at_unix_ms,
    };
}

void activeTasksUseOperationalPriorityBeforeRecency() {
    const std::vector<AIProgressTask> input = {
        task("success", AIProgressStatus::succeeded, 9'000),
        task("running", AIProgressStatus::running, 9'900),
        task("queued", AIProgressStatus::queued, 9'100),
        task("blocked", AIProgressStatus::blocked, 9'200),
        task("error", AIProgressStatus::error, 9'000),
    };

    const auto result = AIActivityPresenter::active_tasks(input);

    expect(result.size() == 4, "inactive history should not be shown in the compact view");
    expect(result[0].id == "error", "errors should be shown first");
    expect(result[1].id == "blocked", "blocked tasks should follow errors");
    expect(result[2].id == "queued", "queued tasks should follow blocked tasks");
    expect(result[3].id == "running", "running tasks should follow queued tasks");
}

void equalPriorityUsesNewestActivityThenStableID() {
    const std::vector<AIProgressTask> input = {
        task("zeta", AIProgressStatus::running, 2'000),
        task("alpha", AIProgressStatus::running, 2'000),
        task("newest", AIProgressStatus::running, 3'000),
    };

    const auto result = AIActivityPresenter::active_tasks(input);

    expect(result.size() == 3, "all active tasks should remain visible");
    expect(result[0].id == "newest", "newest activity should win within a status");
    expect(result[1].id == "alpha" && result[2].id == "zeta",
        "equal timestamps should use a stable ID order");
}

void noActiveTasksProduceAnEmptyPresentation() {
    const std::vector<AIProgressTask> input = {
        task("done", AIProgressStatus::succeeded, 1'000),
        task("failed", AIProgressStatus::failed, 2'000),
    };

    expect(AIActivityPresenter::active_tasks(input).empty(),
        "completed and failed history should not create a compact status");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"operational priority", activeTasksUseOperationalPriorityBeforeRecency},
        {"recency and stable ID", equalPriorityUsesNewestActivityThenStableID},
        {"empty active presentation", noActiveTasksProduceAnEmptyPresentation},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }

    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
