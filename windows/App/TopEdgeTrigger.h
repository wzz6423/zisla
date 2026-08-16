#pragma once

#include <zisla/core/OverlayPlacementEngine.hpp>

#include <windows.h>

#include <vector>

namespace winrt::Zisla {

class TopEdgeTrigger {
public:
    TopEdgeTrigger() = default;
    ~TopEdgeTrigger();

    TopEdgeTrigger(const TopEdgeTrigger&) = delete;
    TopEdgeTrigger& operator=(const TopEdgeTrigger&) = delete;

    [[nodiscard]] bool start(
        HWND target,
        UINT entered_message,
        UINT exited_message);
    void stop() noexcept;
    void refresh() noexcept;
    void poll() noexcept;
    [[nodiscard]] bool running() const noexcept;

private:
    struct TriggerArea {
        HMONITOR monitor{nullptr};
        zisla::core::PixelRect bounds{};
    };

    using TriggerAreas = std::vector<TriggerArea>;

    void handleMouseMove(POINT point, bool eligible) noexcept;

    HWND target_{nullptr};
    UINT entered_message_{0};
    UINT exited_message_{0};
    TriggerAreas trigger_areas_;
    bool running_{false};
    bool pointer_inside_{false};
    HMONITOR active_monitor_{nullptr};
    zisla::core::OverlayPlacementEngine placement_engine_;
};

}
