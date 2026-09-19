#include "pch.h"
#include "DisplayTopology.h"

#include <dwmapi.h>
#include <shellscalingapi.h>

#include <algorithm>

namespace winrt::Zisla {
namespace {

BOOL CALLBACK collectScreen(
    HMONITOR monitor,
    HDC,
    LPRECT,
    LPARAM value) noexcept {
    auto& screens = *reinterpret_cast<
        std::vector<zisla::core::ScreenSnapshot>*>(value);
    try {
        screens.push_back(DisplayTopology::screenForMonitor(monitor));
        return TRUE;
    } catch (...) {
        return FALSE;
    }
}

}

HMONITOR DisplayTopology::monitorForPoint(POINT point) noexcept {
    return MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
}

std::vector<zisla::core::ScreenSnapshot> DisplayTopology::screens() noexcept {
    std::vector<zisla::core::ScreenSnapshot> result;
    try {
        result.reserve(static_cast<std::size_t>(std::max(1, GetSystemMetrics(SM_CMONITORS))));
    } catch (...) {
        return result;
    }

    (void)EnumDisplayMonitors(
        nullptr,
        nullptr,
        collectScreen,
        reinterpret_cast<LPARAM>(&result));
    return result;
}

UINT DisplayTopology::dpiForMonitor(HMONITOR monitor) noexcept {
    UINT dpi_x = USER_DEFAULT_SCREEN_DPI;
    UINT dpi_y = USER_DEFAULT_SCREEN_DPI;
    if (monitor
        && SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
        return dpi_x;
    }
    return USER_DEFAULT_SCREEN_DPI;
}

zisla::core::ScreenSnapshot DisplayTopology::screenForMonitor(
    HMONITOR monitor) noexcept {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!monitor || !GetMonitorInfoW(monitor, &info)) {
        return {};
    }

    return {
        .bounds = {
            info.rcMonitor.left,
            info.rcMonitor.top,
            info.rcMonitor.right - info.rcMonitor.left,
            info.rcMonitor.bottom - info.rcMonitor.top,
        },
        .work_area = {
            info.rcWork.left,
            info.rcWork.top,
            info.rcWork.right - info.rcWork.left,
            info.rcWork.bottom - info.rcWork.top,
        },
        .dpi = dpiForMonitor(monitor),
    };
}

zisla::core::ScreenSnapshot DisplayTopology::screenForPoint(POINT point) noexcept {
    return screenForMonitor(monitorForPoint(point));
}

zisla::core::ScreenSnapshot DisplayTopology::screenForRect(RECT rect) noexcept {
    const POINT center{
        rect.left + (rect.right - rect.left) / 2,
        rect.top + (rect.bottom - rect.top) / 2,
    };
    return screenForPoint(center);
}

bool DisplayTopology::foregroundWindowCoversMonitor(
    HMONITOR monitor,
    HWND overlay_window,
    HWND settings_window) noexcept {
    const auto foreground = GetForegroundWindow();
    if (!monitor || !foreground || foreground == overlay_window
        || foreground == settings_window || !IsWindowVisible(foreground)
        || IsIconic(foreground)) {
        return false;
    }

    wchar_t class_name[64]{};
    GetClassNameW(foreground, class_name, static_cast<int>(_countof(class_name)));
    if (wcscmp(class_name, L"Progman") == 0
        || wcscmp(class_name, L"WorkerW") == 0
        || wcscmp(class_name, L"Shell_TrayWnd") == 0
        || wcscmp(class_name, L"Shell_SecondaryTrayWnd") == 0) {
        return false;
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) {
        return false;
    }

    RECT frame{};
    if (FAILED(DwmGetWindowAttribute(
            foreground,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &frame,
            sizeof(frame)))) {
        if (!GetWindowRect(foreground, &frame)) {
            return false;
        }
    }

    constexpr LONG tolerance = 2;
    return frame.left <= info.rcMonitor.left + tolerance
        && frame.top <= info.rcMonitor.top + tolerance
        && frame.right >= info.rcMonitor.right - tolerance
        && frame.bottom >= info.rcMonitor.bottom - tolerance;
}

}
