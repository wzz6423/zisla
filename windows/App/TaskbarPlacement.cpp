#include "pch.h"
#include "TaskbarPlacement.h"

#include "DisplayTopology.h"

#include <shellapi.h>

namespace winrt::Zisla {
namespace {

std::optional<zisla::core::PixelRect> shell_taskbar_bounds() noexcept {
    APPBARDATA appbar{};
    appbar.cbSize = sizeof(appbar);
    if (SHAppBarMessage(ABM_GETTASKBARPOS, &appbar) == 0) {
        return std::nullopt;
    }
    return zisla::core::PixelRect{
        appbar.rc.left,
        appbar.rc.top,
        appbar.rc.right - appbar.rc.left,
        appbar.rc.bottom - appbar.rc.top,
    };
}

zisla::core::TaskbarEdge edge_from_appbar() noexcept {
    APPBARDATA appbar{};
    appbar.cbSize = sizeof(appbar);
    if (SHAppBarMessage(ABM_GETTASKBARPOS, &appbar) != 0) {
        switch (appbar.uEdge) {
        case ABE_TOP:
            return zisla::core::TaskbarEdge::top;
        case ABE_LEFT:
            return zisla::core::TaskbarEdge::left;
        case ABE_RIGHT:
            return zisla::core::TaskbarEdge::right;
        case ABE_BOTTOM:
        default:
            return zisla::core::TaskbarEdge::bottom;
        }
    }
    return zisla::core::TaskbarEdge::bottom;
}

bool intersects(
    const zisla::core::PixelRect& first,
    const zisla::core::PixelRect& second) noexcept {
    return first.width > 0 && first.height > 0
        && second.width > 0 && second.height > 0
        && first.x < second.right() && first.right() > second.x
        && first.y < second.bottom() && first.bottom() > second.y;
}

}

std::optional<TaskbarSnapshot> TaskbarPlacement::current() noexcept {
    try {
        const auto bounds = shell_taskbar_bounds();
        if (!bounds) {
            return std::nullopt;
        }
        const RECT rect{
            bounds->x,
            bounds->y,
            bounds->right(),
            bounds->bottom(),
        };
        const auto monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
        const auto screen = DisplayTopology::screenForMonitor(monitor);
        if (!monitor || screen.bounds.width <= 0 || screen.bounds.height <= 0) {
            return std::nullopt;
        }

        return TaskbarSnapshot{
            .monitor = monitor,
            .bounds = *bounds,
            .screen = screen,
            .edge = edge_from_appbar(),
        };
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<TaskbarSnapshot> TaskbarPlacement::forTrayIcon(
    std::optional<zisla::core::PixelRect> tray_icon) noexcept {
    if (!tray_icon) {
        return current();
    }

    try {
        const RECT tray_rect{
            tray_icon->x,
            tray_icon->y,
            tray_icon->right(),
            tray_icon->bottom(),
        };
        const auto tray_monitor = MonitorFromRect(&tray_rect, MONITOR_DEFAULTTONEAREST);
        const auto tray_screen = DisplayTopology::screenForMonitor(tray_monitor);
        if (!tray_monitor || tray_screen.bounds.width <= 0 || tray_screen.bounds.height <= 0) {
            return current();
        }

        if (const auto primary = current(); primary && primary->valid()
            && primary->monitor == tray_monitor
            && intersects(primary->bounds, *tray_icon)) {
            return primary;
        }

        // Windows only documents the primary taskbar rectangle. Keep secondary placement
        // anchored to the public notification icon rather than probing private Shell windows.
        const auto inferred = zisla::core::taskbarGeometryForTrayIcon(
            tray_screen,
            *tray_icon);
        if (!inferred || !inferred->valid()) {
            return current();
        }
        return TaskbarSnapshot{
            .monitor = tray_monitor,
            .bounds = inferred->bounds,
            .screen = tray_screen,
            .edge = inferred->edge,
        };
    } catch (...) {
        return current();
    }
}

}
