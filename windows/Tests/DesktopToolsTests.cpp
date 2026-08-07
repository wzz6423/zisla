#include "zisla/core/DesktopTools.hpp"

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void actionsCannotOverlap() {
    DesktopToolsState state;
    expect(state.begin(DesktopToolAction::refresh_recycle_bin),
        "the first desktop action should start");
    expect(!state.begin(DesktopToolAction::empty_recycle_bin),
        "a destructive action must not overlap another action");
    expect(state.snapshot().busy
            && state.snapshot().active_action
                == DesktopToolAction::refresh_recycle_bin,
        "the original action should remain active");
}

void completionPublishesRecycleBinMetrics() {
    DesktopToolsState state;
    expect(state.begin(DesktopToolAction::empty_recycle_bin),
        "emptying the Recycle Bin should start");
    state.complete(
        {.item_count = 0, .size_bytes = 0, .available = true},
        "cleared");

    const auto& snapshot = state.snapshot();
    expect(!snapshot.busy
            && snapshot.active_action == DesktopToolAction::none,
        "completion should release the busy state");
    expect(snapshot.recycle_bin.available
            && snapshot.recycle_bin.item_count == 0,
        "completion should publish the refreshed Recycle Bin state");
    expect(snapshot.status == "cleared" && snapshot.error.empty(),
        "completion should expose only its success status");
}

void failurePreservesLastKnownMetrics() {
    DesktopToolsState state;
    expect(state.begin(DesktopToolAction::refresh_recycle_bin),
        "refresh should start");
    state.complete(
        {.item_count = 4, .size_bytes = 2'048, .available = true},
        {});
    expect(state.begin(DesktopToolAction::arrange_desktop),
        "desktop alignment should start after refresh");
    state.fail("Explorer unavailable");

    const auto& snapshot = state.snapshot();
    expect(snapshot.recycle_bin.item_count == 4
            && snapshot.recycle_bin.size_bytes == 2'048,
        "a failed unrelated action should preserve known metrics");
    expect(!snapshot.busy && snapshot.error == "Explorer unavailable",
        "failure should release the busy state and expose the error");
}

void revisionsAdvanceForEveryVisibleTransition() {
    DesktopToolsState state;
    expect(state.snapshot().revision == 0, "the initial revision should be zero");
    expect(state.begin(DesktopToolAction::open_store_updates),
        "opening Store updates should start");
    expect(state.snapshot().revision == 1,
        "begin should create a visible transition");
    state.fail("Store unavailable");
    expect(state.snapshot().revision == 2,
        "failure should create a second visible transition");
}

void completionRecordsTheActionThatFinished() {
    DesktopToolsState state;
    expect(state.begin(DesktopToolAction::release_system_memory),
        "releasing system memory should start");
    state.complete({.available = true}, "released");

    expect(state.snapshot().last_action
            == DesktopToolAction::release_system_memory,
        "the completed action should remain available to the UI");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"actions cannot overlap", actionsCannotOverlap},
        {"completion publishes metrics", completionPublishesRecycleBinMetrics},
        {"failure preserves metrics", failurePreservesLastKnownMetrics},
        {"revisions advance", revisionsAdvanceForEveryVisibleTransition},
        {"completion records action", completionRecordsTheActionThatFinished},
    };

    int failures = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failures;
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    return failures == 0 ? 0 : 1;
}
