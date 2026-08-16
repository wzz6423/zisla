#include "zisla/core/CameraMirror.hpp"

#include <exception>
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

void startsIdle() {
    CameraMirrorSession session;

    expect(session.snapshot() == CameraMirrorSnapshot{},
        "a camera session should start idle");
}

void beginStartEntersPreparing() {
    CameraMirrorSession session;

    const auto generation = session.begin_start();

    expect(generation != 0, "a start should issue a nonzero generation");
    expect(session.snapshot().phase == CameraMirrorPhase::preparing,
        "a start should enter the preparing phase");
    expect(!session.snapshot().failure,
        "a new start should clear an earlier failure");
}

void currentGenerationCanRun() {
    CameraMirrorSession session;
    const auto generation = session.begin_start();

    expect(session.mark_running(generation),
        "the current start should be allowed to run");
    expect(session.snapshot().phase == CameraMirrorPhase::running,
        "a successful start should enter the running phase");
}

void failuresRetainTheirReason() {
    CameraMirrorSession session;
    const auto generation = session.begin_start();

    expect(session.mark_failed(generation, CameraMirrorFailure::denied),
        "the current start should accept a failure");
    expect(session.snapshot().phase == CameraMirrorPhase::failed,
        "a failed start should enter the failed phase");
    expect(session.snapshot().failure == CameraMirrorFailure::denied,
        "the failure reason should remain available to the UI");
    expect(!session.mark_running(generation),
        "a later completion from the failed attempt must not restart the camera");
}

void newerStartsRejectStaleResults() {
    CameraMirrorSession session;
    const auto stale = session.begin_start();
    const auto current = session.begin_start();

    expect(!session.mark_running(stale),
        "an older asynchronous start must not publish running state");
    expect(session.mark_running(current),
        "the newest asynchronous start should still be accepted");
}

void stopInvalidatesPendingResults() {
    CameraMirrorSession session;
    const auto generation = session.begin_start();

    session.stop();

    expect(session.snapshot().phase == CameraMirrorPhase::idle,
        "stopping should return to idle");
    expect(!session.mark_failed(generation, CameraMirrorFailure::configuration),
        "a completion arriving after stop must be ignored");
}

void runningSessionsCanReportDeviceFailure() {
    CameraMirrorSession session;
    const auto generation = session.begin_start();
    (void)session.mark_running(generation);

    expect(session.mark_failed(generation, CameraMirrorFailure::configuration),
        "the active camera should be able to report a runtime failure");
    expect(session.snapshot().failure == CameraMirrorFailure::configuration,
        "the runtime failure should be published");
}

void retryClearsThePreviousFailure() {
    CameraMirrorSession session;
    const auto first = session.begin_start();
    (void)session.mark_failed(first, CameraMirrorFailure::unavailable);

    const auto retry = session.begin_start();

    expect(retry != first, "a retry should invalidate the previous attempt");
    expect(session.snapshot().phase == CameraMirrorPhase::preparing,
        "a retry should return to preparing");
    expect(!session.snapshot().failure,
        "a retry should clear the previous failure reason");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"starts idle", startsIdle},
        {"begin enters preparing", beginStartEntersPreparing},
        {"current generation runs", currentGenerationCanRun},
        {"failure reason is retained", failuresRetainTheirReason},
        {"stale results are rejected", newerStartsRejectStaleResults},
        {"stop invalidates pending results", stopInvalidatesPendingResults},
        {"runtime failures are accepted", runningSessionsCanReportDeviceFailure},
        {"retry clears failure", retryClearsThePreviousFailure},
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
