#include "zisla/core/Pomodoro.hpp"

#include <cstdint>
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

void startTransitionsIdleToRunningWithDeadline() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 1'000'000;

    engine.start(now);

    const auto snapshot = engine.snapshot(now);
    expect(snapshot.phase == PomodoroPhase::running,
        "start should move an idle timer to running");
    expect(snapshot.mode == PomodoroMode::focus,
        "the default timer mode should be focus");
    expect(snapshot.remaining_seconds == 25 * 60,
        "the default focus duration should be 25 minutes");
}

void pauseFreezesRemainingTime() {
    PomodoroEngine engine;
    constexpr std::int64_t start = 2'000'000;
    engine.start(start);

    engine.pause(start + 90'000);

    expect(engine.phase() == PomodoroPhase::paused,
        "pause should move a running timer to paused");
    expect(engine.snapshot(start + 300'000).remaining_seconds == 23 * 60 + 30,
        "a paused timer should not continue advancing");
}

void completionSwitchesToTheNextIdleMode() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 3'000'000;
    engine.start_with_remaining_seconds(1, now);

    expect(engine.complete_if_needed(now + 1'001),
        "a reached deadline should complete the current interval");
    expect(engine.mode() == PomodoroMode::rest,
        "a completed focus interval should switch to rest");
    expect(engine.phase() == PomodoroPhase::idle,
        "a completed interval should return to idle");
    expect(engine.snapshot(now + 1'001).remaining_seconds == 5 * 60,
        "the next rest interval should use its configured duration");

    engine.start_with_remaining_seconds(1, now + 2'000);
    expect(engine.complete_if_needed(now + 3'001),
        "a reached rest deadline should complete");
    expect(engine.mode() == PomodoroMode::focus,
        "a completed rest interval should switch back to focus");
}

void resetKeepsModeAndRestoresDuration() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 4'000'000;
    engine.start_with_remaining_seconds(1, now);
    (void)engine.complete_if_needed(now + 1'001);
    engine.start(now + 2'000);
    engine.pause(now + 5'000);

    engine.reset();

    expect(engine.mode() == PomodoroMode::rest,
        "reset should retain the current mode");
    expect(engine.phase() == PomodoroPhase::idle,
        "reset should return to idle");
    expect(engine.snapshot(now + 100'000).remaining_seconds == 5 * 60,
        "reset should restore the current mode duration");
}

void displayRoundsUpPartialSeconds() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 5'000'000;
    engine.start_with_remaining_seconds(62, now);

    expect(engine.snapshot(now + 1).remaining_seconds == 62,
        "sub-second elapsed time should not decrement the displayed second early");
    expect(engine.snapshot(now + 1'001).remaining_seconds == 61,
        "the display should decrement after a full second elapses");
}

void clockFormattingMatchesTheMacProductContract() {
    expect(PomodoroEngine::format_clock(61) == "01:01",
        "durations below one hour should use MM:SS");
    expect(PomodoroEngine::format_clock(3'723) == "01:02:03",
        "long durations should include hours");
    expect(PomodoroEngine::format_clock(29 * 60 + 28, true) == "00:29:28",
        "the expanded status should always include an hour component");
    expect(PomodoroEngine::format_clock(-1) == "00:00",
        "negative durations should format as zero");
}

void changingCurrentDurationResetsOnlyTheCurrentMode() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 6'000'000;
    engine.start(now);

    engine.set_duration_seconds(PomodoroMode::rest, 90);
    expect(engine.phase() == PomodoroPhase::running,
        "changing an inactive mode should not interrupt the active interval");

    engine.set_duration_seconds(PomodoroMode::focus, 600);
    expect(engine.phase() == PomodoroPhase::idle,
        "changing the active mode duration should reset the interval");
    expect(engine.snapshot(now).remaining_seconds == 600,
        "the reset interval should use the new duration");
}

void invalidDurationsAreClampedToOneSecond() {
    PomodoroEngine engine{0, -5};

    expect(engine.duration_seconds(PomodoroMode::focus) == 1,
        "focus duration should never be zero");
    expect(engine.duration_seconds(PomodoroMode::rest) == 1,
        "rest duration should never be negative");
}

void startAndPauseAreIdempotentOutsideTheirTransitions() {
    PomodoroEngine engine;
    constexpr std::int64_t now = 7'000'000;
    engine.pause(now);
    expect(engine.phase() == PomodoroPhase::idle,
        "pausing an idle timer should have no effect");

    engine.start(now);
    engine.start(now + 10'000);
    expect(engine.snapshot(now + 10'000).remaining_seconds == 24 * 60 + 50,
        "starting an already running timer should not reset its deadline");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"start creates running focus interval", startTransitionsIdleToRunningWithDeadline},
        {"pause freezes remaining", pauseFreezesRemainingTime},
        {"completion switches mode", completionSwitchesToTheNextIdleMode},
        {"reset restores current mode", resetKeepsModeAndRestoresDuration},
        {"display rounds partial seconds", displayRoundsUpPartialSeconds},
        {"clock formatting matches product", clockFormattingMatchesTheMacProductContract},
        {"duration changes reset current mode", changingCurrentDurationResetsOnlyTheCurrentMode},
        {"invalid durations clamp", invalidDurationsAreClampedToOneSecond},
        {"state transitions are idempotent", startAndPauseAreIdempotentOutsideTheirTransitions},
    };

    std::size_t failed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failed;
            std::cerr << "FAIL: " << name << " - " << error.what() << '\n';
        }
    }

    if (failed != 0) {
        std::cerr << failed << " test(s) failed\n";
        return 1;
    }
    return 0;
}
