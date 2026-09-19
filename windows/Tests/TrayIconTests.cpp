#include <zisla/core/ApplicationIconTheme.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

using namespace zisla::core;

namespace {

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void lightSystemThemeUsesDayIcon() {
    expect(application_icon_theme(true) == ApplicationIconTheme::day,
        "light system theme should use the day icon");
}

void darkSystemThemeUsesNightIcon() {
    expect(application_icon_theme(false) == ApplicationIconTheme::night,
        "dark system theme should use the night icon");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"light system theme uses day icon", lightSystemThemeUsesDayIcon},
        {"dark system theme uses night icon", darkSystemThemeUsesNightIcon},
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
