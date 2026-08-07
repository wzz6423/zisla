#pragma once

#include <zisla/core/OverlayPlacementEngine.hpp>

#include <windows.h>

#include <vector>

namespace winrt::Zisla {

class DisplayTopology {
public:
    [[nodiscard]] static zisla::core::ScreenSnapshot screenForPoint(POINT point) noexcept;
    [[nodiscard]] static zisla::core::ScreenSnapshot screenForRect(RECT rect) noexcept;
    [[nodiscard]] static zisla::core::ScreenSnapshot screenForMonitor(
        HMONITOR monitor) noexcept;
    [[nodiscard]] static HMONITOR monitorForPoint(POINT point) noexcept;
    [[nodiscard]] static std::vector<zisla::core::ScreenSnapshot> screens() noexcept;
    [[nodiscard]] static bool foregroundWindowCoversMonitor(
        HMONITOR monitor,
        HWND overlay_window,
        HWND settings_window) noexcept;

private:
    [[nodiscard]] static UINT dpiForMonitor(HMONITOR monitor) noexcept;
};

}
