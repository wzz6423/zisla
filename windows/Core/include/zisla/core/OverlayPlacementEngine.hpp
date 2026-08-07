#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace zisla::core {

enum class PetSide;

struct PixelSize {
    std::int32_t width{0};
    std::int32_t height{0};

    friend bool operator==(const PixelSize&, const PixelSize&) = default;
};

struct DipSize {
    float width{0};
    float height{0};

    friend bool operator==(const DipSize&, const DipSize&) = default;
};

struct PixelRect {
    std::int32_t x{0};
    std::int32_t y{0};
    std::int32_t width{0};
    std::int32_t height{0};

    [[nodiscard]] std::int32_t right() const noexcept;
    [[nodiscard]] std::int32_t bottom() const noexcept;
    [[nodiscard]] std::int32_t centerX() const noexcept;
    [[nodiscard]] std::int32_t centerY() const noexcept;

    friend bool operator==(const PixelRect&, const PixelRect&) = default;
};

struct ScreenSnapshot {
    PixelRect bounds{};
    PixelRect work_area{};
    std::uint32_t dpi{96};
};

enum class OverlaySurfaceKind {
    peek,
    interactive,
};

enum class TaskbarEdge {
    top,
    bottom,
    left,
    right,
};

enum class TaskbarWidgetPosition {
    leading,
    before_start,
    trailing,
};

struct TaskbarGeometry {
    PixelRect bounds{};
    TaskbarEdge edge{TaskbarEdge::bottom};

    [[nodiscard]] bool valid() const noexcept {
        return bounds.width > 0 && bounds.height > 0;
    }
};

/// Derives a taskbar anchor from a public notification-area icon rectangle.
/// This is used when Windows does not expose a secondary taskbar rectangle.
[[nodiscard]] std::optional<TaskbarGeometry> taskbarGeometryForTrayIcon(
    const ScreenSnapshot& screen,
    const PixelRect& tray_icon) noexcept;

struct OverlayPlacementConfiguration {
    DipSize peek_card_size{420, 96};
    DipSize interactive_card_size{480, 420};
    DipSize top_trigger_size{320, 6};
    DipSize taskbar_widget_size{36, 36};
    DipSize pet_window_size{30, 36};
    float side_notice_width{252};
    float side_notice_row_height{54};
    float side_notice_row_spacing{6};
    float edge_gap{8};
    float pet_gap{4};
};

class OverlayPlacementEngine {
public:
    explicit OverlayPlacementEngine(
        OverlayPlacementConfiguration configuration = {});

    [[nodiscard]] PixelSize cardSize(
        OverlaySurfaceKind surface,
        std::uint32_t dpi,
        std::optional<DipSize> preferred_size = std::nullopt) const noexcept;
    [[nodiscard]] PixelRect topEdgeTrigger(const ScreenSnapshot& screen) const;
    [[nodiscard]] PixelRect topEdgeCard(
        const ScreenSnapshot& screen,
        OverlaySurfaceKind surface,
        std::optional<DipSize> preferred_size = std::nullopt) const;
    [[nodiscard]] PixelRect trayCard(
        const ScreenSnapshot& screen,
        const PixelRect& tray_icon,
        OverlaySurfaceKind surface,
        std::optional<DipSize> preferred_size = std::nullopt) const;
    [[nodiscard]] PixelSize taskbarWidgetSize(
        std::uint32_t dpi,
        std::optional<DipSize> preferred_size = std::nullopt) const noexcept;
    [[nodiscard]] PixelRect taskbarWidget(
        const ScreenSnapshot& screen,
        const PixelRect& taskbar,
        TaskbarEdge edge,
        TaskbarWidgetPosition position,
        std::optional<PixelRect> trailing_reserved_area = std::nullopt,
        std::optional<PixelRect> start_button = std::nullopt,
        std::optional<DipSize> preferred_size = std::nullopt) const;
    [[nodiscard]] PixelRect taskbarCard(
        const ScreenSnapshot& screen,
        const PixelRect& taskbar,
        const PixelRect& widget,
        TaskbarEdge edge,
        OverlaySurfaceKind surface,
        std::optional<DipSize> preferred_size = std::nullopt) const;
    [[nodiscard]] PixelRect taskbarPet(
        const ScreenSnapshot& screen,
        const PixelRect& taskbar,
        const PixelRect& widget,
        TaskbarEdge edge,
        PetSide side,
        std::optional<PixelRect> trailing_reserved_area = std::nullopt) const;
    [[nodiscard]] PixelRect sideNoticePanel(
        const ScreenSnapshot& screen,
        NoticeSide side,
        std::size_t row_count) const;
    [[nodiscard]] PixelRect trayNoticePanel(
        const ScreenSnapshot& screen,
        const PixelRect& tray_icon,
        std::size_t row_count) const;

private:
    OverlayPlacementConfiguration configuration_;
};

}  // namespace zisla::core
