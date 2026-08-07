#include "pch.h"
#include "TaskbarPlacement.h"

#include "DisplayTopology.h"

#include <shellapi.h>
#include <UIAutomation.h>
#include <wrl/client.h>

#pragma comment(lib, "uiautomationcore.lib")

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

std::optional<zisla::core::PixelRect> shell_child_bounds(
    const TaskbarSnapshot& taskbar,
    const wchar_t* class_name) noexcept {
    const auto shell_taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!shell_taskbar) {
        return std::nullopt;
    }
    const auto child = FindWindowExW(shell_taskbar, nullptr, class_name, nullptr);
    if (!child) {
        return std::nullopt;
    }
    RECT bounds{};
    if (!GetWindowRect(child, &bounds)) {
        return std::nullopt;
    }
    const auto result = zisla::core::PixelRect{
        bounds.left,
        bounds.top,
        bounds.right - bounds.left,
        bounds.bottom - bounds.top,
    };
    return intersects(result, taskbar.bounds) ? std::optional{result} : std::nullopt;
}

std::optional<zisla::core::PixelRect> automation_element_bounds(
    const TaskbarSnapshot& taskbar,
    const wchar_t* automation_id,
    bool prefer_trailing) noexcept {
    using ::Microsoft::WRL::ComPtr;

    try {
        ComPtr<IUIAutomation> automation;
        if (FAILED(CoCreateInstance(
                CLSID_CUIAutomation,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&automation)))) {
            return std::nullopt;
        }

        ComPtr<IUIAutomationElement> root;
        if (FAILED(automation->GetRootElement(&root)) || !root) {
            return std::nullopt;
        }

        VARIANT value{};
        value.vt = VT_BSTR;
        value.bstrVal = SysAllocString(automation_id);
        if (!value.bstrVal) {
            return std::nullopt;
        }

        ComPtr<IUIAutomationCondition> condition;
        const auto condition_result = automation->CreatePropertyCondition(
            UIA_AutomationIdPropertyId,
            value,
            &condition);
        VariantClear(&value);
        if (FAILED(condition_result) || !condition) {
            return std::nullopt;
        }

        ComPtr<IUIAutomationElementArray> elements;
        if (FAILED(root->FindAll(TreeScope_Subtree, condition.Get(), &elements))
            || !elements) {
            return std::nullopt;
        }

        int length = 0;
        if (FAILED(elements->get_Length(&length))) {
            return std::nullopt;
        }
        std::optional<zisla::core::PixelRect> result;
        const bool horizontal = taskbar.edge == zisla::core::TaskbarEdge::top
            || taskbar.edge == zisla::core::TaskbarEdge::bottom;
        for (int index = 0; index < length; ++index) {
            ComPtr<IUIAutomationElement> element;
            if (FAILED(elements->GetElement(index, &element)) || !element) {
                continue;
            }
            RECT bounds{};
            if (FAILED(element->get_CurrentBoundingRectangle(&bounds))) {
                continue;
            }
            const auto candidate = zisla::core::PixelRect{
                bounds.left,
                bounds.top,
                bounds.right - bounds.left,
                bounds.bottom - bounds.top,
            };
            if (!intersects(candidate, taskbar.bounds)) {
                continue;
            }
            if (!result || !prefer_trailing) {
                result = candidate;
                if (!prefer_trailing) {
                    break;
                }
                continue;
            }
            const auto candidate_coordinate = horizontal ? candidate.x : candidate.y;
            const auto result_coordinate = horizontal ? result->x : result->y;
            if (candidate_coordinate > result_coordinate) {
                result = candidate;
            }
        }
        return result;
    } catch (...) {
    }
    return std::nullopt;
}

std::optional<zisla::core::PixelRect> start_button_bounds(
    const TaskbarSnapshot& taskbar) noexcept {
    if (const auto start = shell_child_bounds(taskbar, L"Start")) {
        return start;
    }
    return automation_element_bounds(taskbar, L"StartButton", false);
}

std::optional<zisla::core::PixelRect> system_tray_bounds(
    const TaskbarSnapshot& taskbar) noexcept {
    const auto element = shell_child_bounds(taskbar, L"TrayNotifyWnd").value_or(
        automation_element_bounds(
        taskbar,
        L"SystemTrayFrame",
        true).value_or(zisla::core::PixelRect{}));
    const bool horizontal = taskbar.edge == zisla::core::TaskbarEdge::top
        || taskbar.edge == zisla::core::TaskbarEdge::bottom;
    const auto axis_start = horizontal ? taskbar.bounds.x : taskbar.bounds.y;
    const auto axis_end = horizontal ? taskbar.bounds.right() : taskbar.bounds.bottom();
    const auto system_start = element.width > 0 && element.height > 0
        ? (horizontal ? element.x : element.y)
        : axis_end - std::min(
            axis_end - axis_start,
            std::max(
                MulDiv(240, static_cast<int>(taskbar.screen.dpi), 96),
                (axis_end - axis_start) / 2));
    if (system_start < axis_start || system_start >= axis_end) {
        return std::nullopt;
    }
    return horizontal
        ? std::optional{zisla::core::PixelRect{
            system_start,
            taskbar.bounds.y,
            axis_end - system_start,
            taskbar.bounds.height}}
        : std::optional{zisla::core::PixelRect{
            taskbar.bounds.x,
            system_start,
            taskbar.bounds.width,
            axis_end - system_start}};
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

        auto snapshot = TaskbarSnapshot{
            .monitor = monitor,
            .bounds = *bounds,
            .screen = screen,
            .edge = edge_from_appbar(),
        };
        snapshot.start_button = start_button_bounds(snapshot);
        snapshot.system_tray = system_tray_bounds(snapshot);
        return snapshot;
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
        auto snapshot = TaskbarSnapshot{
            .monitor = tray_monitor,
            .bounds = inferred->bounds,
            .screen = tray_screen,
            .edge = inferred->edge,
        };
        snapshot.start_button = start_button_bounds(snapshot);
        snapshot.system_tray = system_tray_bounds(snapshot);
        return snapshot;
    } catch (...) {
        return current();
    }
}

std::optional<zisla::core::PixelRect> TaskbarPlacement::startButtonBounds(
    const TaskbarSnapshot& taskbar) noexcept {
    if (!taskbar.valid()) {
        return std::nullopt;
    }
    return start_button_bounds(taskbar);
}

}
