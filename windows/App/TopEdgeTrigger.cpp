#include "pch.h"
#include "TopEdgeTrigger.h"
#include "DisplayTopology.h"

namespace winrt::Zisla {
namespace {

bool mouse_button_down() noexcept {
    constexpr int buttons[]{
        VK_LBUTTON,
        VK_RBUTTON,
        VK_MBUTTON,
        VK_XBUTTON1,
        VK_XBUTTON2,
    };
    for (const auto button : buttons) {
        if ((GetAsyncKeyState(button) & 0x8000) != 0) {
            return true;
        }
    }
    return false;
}

}

TopEdgeTrigger::~TopEdgeTrigger() {
    stop();
}

bool TopEdgeTrigger::start(
    HWND target,
    UINT entered_message,
    UINT exited_message) {
    if (!target || entered_message == 0 || exited_message == 0) {
        return false;
    }

    stop();
    target_ = target;
    entered_message_ = entered_message;
    exited_message_ = exited_message;
    refresh();
    running_ = !trigger_areas_.empty();
    if (!running_) {
        stop();
    }
    return running_;
}

void TopEdgeTrigger::stop() noexcept {
    running_ = false;
    target_ = nullptr;
    entered_message_ = 0;
    exited_message_ = 0;
    trigger_areas_.clear();
    pointer_inside_ = false;
    active_monitor_ = nullptr;
}

bool TopEdgeTrigger::running() const noexcept {
    return running_;
}

void TopEdgeTrigger::refresh() noexcept {
    struct MonitorBounds {
        HMONITOR monitor{nullptr};
        RECT bounds{};
    };

    try {
        struct EnumerationContext {
            std::vector<MonitorBounds> monitors;
            bool failed{false};
        } context;

        const BOOL enumerated = EnumDisplayMonitors(
            nullptr,
            nullptr,
            [](HMONITOR monitor, HDC, LPRECT bounds, LPARAM value) noexcept {
                auto& context = *reinterpret_cast<EnumerationContext*>(value);
                try {
                    context.monitors.push_back({monitor, *bounds});
                    return TRUE;
                } catch (...) {
                    context.failed = true;
                    return FALSE;
                }
            },
            reinterpret_cast<LPARAM>(&context));

        TriggerAreas areas;
        if (enumerated && !context.failed) {
            areas.reserve(context.monitors.size());
            for (const auto& monitor : context.monitors) {
                const POINT center{
                    monitor.bounds.left
                        + (monitor.bounds.right - monitor.bounds.left) / 2,
                    monitor.bounds.top
                        + (monitor.bounds.bottom - monitor.bounds.top) / 2,
                };
                const auto screen = DisplayTopology::screenForPoint(center);
                areas.push_back({
                    monitor.monitor,
                    placement_engine_.topEdgeTrigger(screen),
                });
            }
        }
        trigger_areas_ = std::move(areas);
    } catch (...) {
        trigger_areas_.clear();
    }
}

void TopEdgeTrigger::poll() noexcept {
    if (!running_) {
        return;
    }

    POINT point{};
    if (GetCursorPos(&point)) {
        handleMouseMove(point, !mouse_button_down());
    }
}

void TopEdgeTrigger::handleMouseMove(POINT point, bool eligible) noexcept {
    HMONITOR monitor = nullptr;
    if (eligible) {
        for (const auto& area : trigger_areas_) {
            if (point.x >= area.bounds.x && point.x < area.bounds.right()
                && point.y >= area.bounds.y && point.y < area.bounds.bottom()) {
                monitor = area.monitor;
                break;
            }
        }
    }

    if (monitor && (!pointer_inside_ || monitor != active_monitor_)) {
        pointer_inside_ = true;
        active_monitor_ = monitor;
        if (!PostMessageW(
            target_,
            entered_message_,
            reinterpret_cast<WPARAM>(monitor),
            0)) {
            pointer_inside_ = false;
            active_monitor_ = nullptr;
        }
    } else if (!monitor && pointer_inside_) {
        pointer_inside_ = false;
        active_monitor_ = nullptr;
        (void)PostMessageW(target_, exited_message_, 0, 0);
    }
}

}
