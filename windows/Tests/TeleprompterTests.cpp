#include "zisla/core/Teleprompter.hpp"

#include <cmath>
#include <exception>
#include <functional>
#include <iostream>
#include <limits>
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

void expectNear(double actual, double expected, std::string_view message) {
    expect(std::abs(actual - expected) < 0.0001, message);
}

void defaultsMatchTheMacProductContract() {
    TeleprompterEngine engine;

    expect(engine.script().empty(), "the initial script should be empty");
    expectNear(engine.scroll_speed(), 45.0,
        "the default speed should be 45 pixels per second");
    expectNear(engine.scroll_offset(), 0.0,
        "the initial scroll offset should be zero");
    expect(!engine.auto_scrolling(),
        "automatic scrolling should start paused");
}

void emptyScriptCannotStartScrolling() {
    TeleprompterEngine engine;

    expect(!engine.toggle_auto_scroll(),
        "an empty script should not start automatic scrolling");
    expect(!engine.auto_scrolling(),
        "the empty script should remain paused");
}

void elapsedTimeAdvancesAtTheConfiguredSpeed() {
    TeleprompterEngine engine{"hello", 60.0};
    (void)engine.toggle_auto_scroll();

    engine.advance(0.5, 100.0);

    expectNear(engine.scroll_offset(), 30.0,
        "half a second at 60 pixels per second should advance 30 pixels");
    expect(engine.auto_scrolling(),
        "scrolling should continue before the end");
}

void reachingTheEndStopsAtTheMaximumOffset() {
    TeleprompterEngine engine{"hello", 100.0};
    (void)engine.toggle_auto_scroll();

    engine.advance(2.0, 75.0);

    expectNear(engine.scroll_offset(), 75.0,
        "the offset should clamp to the scrollable height");
    expect(!engine.auto_scrolling(),
        "reaching the end should pause automatic scrolling");
}

void resetReturnsToTheBeginningAndPauses() {
    TeleprompterEngine engine{"hello"};
    (void)engine.toggle_auto_scroll();
    engine.advance(1.0, 500.0);

    engine.reset();

    expectNear(engine.scroll_offset(), 0.0,
        "reset should return to the top");
    expect(!engine.auto_scrolling(),
        "reset should pause automatic scrolling");
}

void changingTheScriptResetsOnlyWhenContentChanges() {
    TeleprompterEngine engine{"first"};
    (void)engine.toggle_auto_scroll();
    engine.advance(1.0, 500.0);

    engine.set_script("first");
    expect(engine.auto_scrolling(),
        "setting identical content should preserve the running state");

    engine.set_script("second");
    expectNear(engine.scroll_offset(), 0.0,
        "new content should return to the beginning");
    expect(!engine.auto_scrolling(),
        "new content should pause automatic scrolling");
}

void speedIsClampedAndInvalidValuesUseTheDefault() {
    TeleprompterEngine engine{"hello", 1.0};
    expectNear(engine.scroll_speed(), 15.0,
        "speeds below the slider range should clamp to 15");

    engine.set_scroll_speed(500.0);
    expectNear(engine.scroll_speed(), 150.0,
        "speeds above the slider range should clamp to 150");

    engine.set_scroll_speed(std::numeric_limits<double>::quiet_NaN());
    expectNear(engine.scroll_speed(), 45.0,
        "non-finite speeds should use the product default");
}

void invalidTicksDoNotChangeTheScrollPosition() {
    TeleprompterEngine engine{"hello"};
    (void)engine.toggle_auto_scroll();

    engine.advance(-1.0, 100.0);
    engine.advance(std::numeric_limits<double>::infinity(), 100.0);

    expectNear(engine.scroll_offset(), 0.0,
        "invalid elapsed times should be ignored");
    expect(engine.auto_scrolling(),
        "an ignored tick should not pause a valid session");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"defaults match product", defaultsMatchTheMacProductContract},
        {"empty script cannot scroll", emptyScriptCannotStartScrolling},
        {"elapsed time advances", elapsedTimeAdvancesAtTheConfiguredSpeed},
        {"end clamps and stops", reachingTheEndStopsAtTheMaximumOffset},
        {"reset returns to top", resetReturnsToTheBeginningAndPauses},
        {"script changes reset", changingTheScriptResetsOnlyWhenContentChanges},
        {"speed normalization", speedIsClampedAndInvalidValuesUseTheDefault},
        {"invalid ticks are ignored", invalidTicksDoNotChangeTheScrollPosition},
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
