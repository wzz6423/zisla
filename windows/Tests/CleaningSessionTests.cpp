#include "zisla/core/CleaningSession.hpp"

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
    CleaningSession session;

    expect(session.mode() == CleaningMode::idle,
        "a cleaning session should start idle");
    expect(!session.active(),
        "an idle cleaning session should not be active");
}

void screenModeBecomesActive() {
    CleaningSession session;

    expect(session.set_mode(CleaningMode::screen),
        "starting screen cleaning should report a transition");
    expect(session.mode() == CleaningMode::screen,
        "screen cleaning should become the only active mode");
    expect(session.active(),
        "screen cleaning should mark the session active");
}

void keyboardModeReplacesScreenMode() {
    CleaningSession session;
    (void)session.set_mode(CleaningMode::screen);

    expect(session.set_mode(CleaningMode::keyboard),
        "keyboard cleaning should replace screen cleaning");
    expect(session.mode() == CleaningMode::keyboard,
        "only keyboard cleaning should remain active");
}

void screenModeReplacesKeyboardMode() {
    CleaningSession session;
    (void)session.set_mode(CleaningMode::keyboard);

    expect(session.set_mode(CleaningMode::screen),
        "screen cleaning should replace keyboard cleaning");
    expect(session.mode() == CleaningMode::screen,
        "only screen cleaning should remain active");
}

void repeatedModeIsIdempotent() {
    CleaningSession session;
    (void)session.set_mode(CleaningMode::keyboard);

    expect(!session.set_mode(CleaningMode::keyboard),
        "starting the active mode again should not report a transition");
    expect(session.mode() == CleaningMode::keyboard,
        "an idempotent start should preserve the active mode");
}

void stopReturnsEveryModeToIdle() {
    CleaningSession session;
    (void)session.set_mode(CleaningMode::screen);
    session.stop();

    expect(session.mode() == CleaningMode::idle,
        "stop should end screen cleaning");
    session.stop();
    expect(!session.active(),
        "repeated stop should remain idle");

    (void)session.set_mode(CleaningMode::keyboard);
    session.stop();
    expect(session.mode() == CleaningMode::idle,
        "stop should end keyboard cleaning");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"session starts idle", startsIdle},
        {"screen mode becomes active", screenModeBecomesActive},
        {"keyboard replaces screen", keyboardModeReplacesScreenMode},
        {"screen replaces keyboard", screenModeReplacesKeyboardMode},
        {"repeated mode is idempotent", repeatedModeIsIdempotent},
        {"stop returns to idle", stopReturnsEveryModeToIdle},
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
