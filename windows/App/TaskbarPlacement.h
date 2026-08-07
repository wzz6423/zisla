#pragma once

#include <zisla/core/OverlayPlacementEngine.hpp>

#include <windows.h>

#include <optional>

namespace winrt::Zisla {

struct TaskbarSnapshot {
    HMONITOR monitor{nullptr};
    zisla::core::PixelRect bounds{};
    zisla::core::ScreenSnapshot screen{};
    zisla::core::TaskbarEdge edge{zisla::core::TaskbarEdge::bottom};
    std::optional<zisla::core::PixelRect> start_button;
    // Covers the complete trailing system area, including clock and notification controls.
    std::optional<zisla::core::PixelRect> system_tray;

    [[nodiscard]] bool valid() const noexcept {
        return monitor != nullptr && bounds.width > 0 && bounds.height > 0
            && screen.bounds.width > 0 && screen.bounds.height > 0;
    }
};

class TaskbarPlacement {
public:
    [[nodiscard]] static std::optional<TaskbarSnapshot> current() noexcept;
    [[nodiscard]] static std::optional<TaskbarSnapshot> forTrayIcon(
        std::optional<zisla::core::PixelRect> tray_icon) noexcept;
    [[nodiscard]] static std::optional<zisla::core::PixelRect> startButtonBounds(
        const TaskbarSnapshot& taskbar) noexcept;
};

}
