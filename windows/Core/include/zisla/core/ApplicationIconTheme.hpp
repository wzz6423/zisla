#pragma once

namespace zisla::core {

enum class ApplicationIconTheme {
    day,
    night,
};

[[nodiscard]] constexpr ApplicationIconTheme application_icon_theme(
    bool system_uses_light_theme) noexcept {
    return system_uses_light_theme
        ? ApplicationIconTheme::day
        : ApplicationIconTheme::night;
}

}  // namespace zisla::core
