#include "zisla/core/OverlayPlacementEngine.hpp"
#include "zisla/core/FeatureSettings.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace zisla::core {

std::int32_t PixelRect::right() const noexcept {
    return x + width;
}

std::int32_t PixelRect::bottom() const noexcept {
    return y + height;
}

std::int32_t PixelRect::centerX() const noexcept {
    return x + width / 2;
}

std::int32_t PixelRect::centerY() const noexcept {
    return y + height / 2;
}

OverlayPlacementEngine::OverlayPlacementEngine(
    OverlayPlacementConfiguration configuration)
    : configuration_(configuration) {}

namespace {

std::int32_t pixelsFromDip(float value, std::uint32_t dpi) noexcept {
    if (!std::isfinite(value) || value <= 0) {
        return 0;
    }

    const auto effective_dpi = dpi == 0 ? std::uint32_t{96} : dpi;
    const auto scaled = std::round(
        static_cast<double>(value) * static_cast<double>(effective_dpi) / 96.0);
    return static_cast<std::int32_t>(std::min(
        scaled,
        static_cast<double>(std::numeric_limits<std::int32_t>::max())));
}

PixelRect fitCard(PixelRect work_area, PixelSize requested) noexcept {
    const auto available_width = std::max(std::int32_t{0}, work_area.width);
    const auto available_height = std::max(std::int32_t{0}, work_area.height);
    return {
        work_area.x,
        work_area.y,
        std::min(requested.width, available_width),
        std::min(requested.height, available_height),
    };
}

bool intersects(const PixelRect& first, const PixelRect& second) noexcept {
    return first.width > 0 && first.height > 0
        && second.width > 0 && second.height > 0
        && first.x < second.right() && first.right() > second.x
        && first.y < second.bottom() && first.bottom() > second.y;
}

}  // namespace

std::optional<TaskbarGeometry> taskbarGeometryForTrayIcon(
    const ScreenSnapshot& screen,
    const PixelRect& tray_icon) noexcept {
    const auto& bounds = screen.bounds;
    if (bounds.width <= 0 || bounds.height <= 0 || !intersects(bounds, tray_icon)) {
        return std::nullopt;
    }

    const auto top_distance = std::max(0, tray_icon.y - bounds.y);
    const auto bottom_distance = std::max(0, bounds.bottom() - tray_icon.bottom());
    const auto left_distance = std::max(0, tray_icon.x - bounds.x);
    const auto right_distance = std::max(0, bounds.right() - tray_icon.right());

    auto edge = TaskbarEdge::top;
    auto edge_distance = top_distance;
    const auto choose_nearer_edge = [&edge, &edge_distance](
                                        TaskbarEdge candidate,
                                        std::int32_t distance) noexcept {
        if (distance < edge_distance) {
            edge = candidate;
            edge_distance = distance;
        }
    };
    choose_nearer_edge(TaskbarEdge::bottom, bottom_distance);
    choose_nearer_edge(TaskbarEdge::left, left_distance);
    choose_nearer_edge(TaskbarEdge::right, right_distance);

    const auto& work_area = screen.work_area;
    const auto top_inset = std::clamp(work_area.y - bounds.y, 0, bounds.height);
    const auto bottom_inset = std::clamp(
        bounds.bottom() - work_area.bottom(),
        0,
        bounds.height);
    const auto left_inset = std::clamp(work_area.x - bounds.x, 0, bounds.width);
    const auto right_inset = std::clamp(
        bounds.right() - work_area.right(),
        0,
        bounds.width);

    const auto fallback_thickness = [&]() noexcept {
        switch (edge) {
        case TaskbarEdge::top:
            return std::clamp(tray_icon.bottom() - bounds.y, 1, bounds.height);
        case TaskbarEdge::bottom:
            return std::clamp(bounds.bottom() - tray_icon.y, 1, bounds.height);
        case TaskbarEdge::left:
            return std::clamp(tray_icon.right() - bounds.x, 1, bounds.width);
        case TaskbarEdge::right:
            return std::clamp(bounds.right() - tray_icon.x, 1, bounds.width);
        }
        return 0;
    };

    const auto thickness = [&]() noexcept {
        switch (edge) {
        case TaskbarEdge::top:
            return top_inset;
        case TaskbarEdge::bottom:
            return bottom_inset;
        case TaskbarEdge::left:
            return left_inset;
        case TaskbarEdge::right:
            return right_inset;
        }
        return 0;
    }();
    const auto effective_thickness = thickness > 0
        ? thickness
        : fallback_thickness();

    switch (edge) {
    case TaskbarEdge::top:
        return TaskbarGeometry{{bounds.x, bounds.y, bounds.width, effective_thickness}, edge};
    case TaskbarEdge::bottom:
        return TaskbarGeometry{{
            bounds.x,
            bounds.bottom() - effective_thickness,
            bounds.width,
            effective_thickness,
        }, edge};
    case TaskbarEdge::left:
        return TaskbarGeometry{{bounds.x, bounds.y, effective_thickness, bounds.height}, edge};
    case TaskbarEdge::right:
        return TaskbarGeometry{{
            bounds.right() - effective_thickness,
            bounds.y,
            effective_thickness,
            bounds.height,
        }, edge};
    }
    return std::nullopt;
}

PixelSize OverlayPlacementEngine::cardSize(
    OverlaySurfaceKind surface,
    std::uint32_t dpi) const noexcept {
    const auto size = surface == OverlaySurfaceKind::peek
        ? configuration_.peek_card_size
        : configuration_.interactive_card_size;
    return {
        pixelsFromDip(size.width, dpi),
        pixelsFromDip(size.height, dpi),
    };
}

PixelRect OverlayPlacementEngine::topEdgeTrigger(
    const ScreenSnapshot& screen) const {
    const auto& bounds = screen.bounds;
    const auto trigger_width = std::clamp(
        pixelsFromDip(configuration_.top_trigger_size.width, screen.dpi),
        std::int32_t{0},
        std::max(std::int32_t{0}, bounds.width));
    const auto trigger_height = std::clamp(
        pixelsFromDip(configuration_.top_trigger_size.height, screen.dpi),
        std::int32_t{0},
        std::max(std::int32_t{0}, bounds.height));
    return {
        bounds.centerX() - trigger_width / 2,
        bounds.y,
        trigger_width,
        trigger_height,
    };
}

PixelRect OverlayPlacementEngine::topEdgeCard(
    const ScreenSnapshot& screen,
    OverlaySurfaceKind surface) const {
    const auto& wa = screen.work_area;
    auto card = fitCard(wa, cardSize(surface, screen.dpi));
    const auto gap = pixelsFromDip(configuration_.edge_gap, screen.dpi);

    card.x = wa.centerX() - card.width / 2;
    card.y = wa.y + gap;

    card.x = std::clamp(card.x, wa.x, wa.x + std::max(0, wa.width - card.width));
    card.y = std::clamp(card.y, wa.y, wa.y + std::max(0, wa.height - card.height));

    return card;
}

PixelRect OverlayPlacementEngine::trayCard(
    const ScreenSnapshot& screen,
    const PixelRect& tray_icon,
    OverlaySurfaceKind surface) const {
    const auto& wa = screen.work_area;
    auto card = fitCard(wa, cardSize(surface, screen.dpi));
    const auto gap = pixelsFromDip(configuration_.edge_gap, screen.dpi);

    const auto icon_center_x = tray_icon.centerX();
    const auto icon_center_y = tray_icon.centerY();
    if (icon_center_y <= wa.y) {
        card.x = icon_center_x - card.width / 2;
        card.y = wa.y + gap;
    } else if (icon_center_x <= wa.x) {
        card.x = wa.x + gap;
        card.y = icon_center_y - card.height / 2;
    } else if (icon_center_x >= wa.right()) {
        card.x = wa.right() - card.width - gap;
        card.y = icon_center_y - card.height / 2;
    } else {
        card.x = icon_center_x - card.width / 2;
        card.y = wa.bottom() - card.height - gap;
    }

    card.x = std::clamp(card.x, wa.x, wa.x + std::max(0, wa.width - card.width));
    card.y = std::clamp(card.y, wa.y, wa.y + std::max(0, wa.height - card.height));

    return card;
}

PixelSize OverlayPlacementEngine::taskbarWidgetSize(
    std::uint32_t dpi) const noexcept {
    return {
        pixelsFromDip(configuration_.taskbar_widget_size.width, dpi),
        pixelsFromDip(configuration_.taskbar_widget_size.height, dpi),
    };
}

PixelRect OverlayPlacementEngine::taskbarWidget(
    const ScreenSnapshot& screen,
    const PixelRect& taskbar,
    TaskbarEdge edge,
    std::optional<PixelRect> tray_icon) const {
    const auto size = taskbarWidgetSize(screen.dpi);
    if (taskbar.width <= 0 || taskbar.height <= 0
        || size.width <= 0 || size.height <= 0
        || size.width > screen.work_area.width
        || size.height > screen.work_area.height) {
        return {};
    }

    const auto gap = pixelsFromDip(configuration_.edge_gap, screen.dpi);
    PixelRect result{
        screen.work_area.x,
        screen.work_area.y,
        size.width,
        size.height,
    };

    if (edge == TaskbarEdge::top || edge == TaskbarEdge::bottom) {
        result.x = tray_icon && intersects(*tray_icon, taskbar)
            ? tray_icon->x - result.width - gap
            : screen.work_area.right() - result.width - gap;
        result.y = edge == TaskbarEdge::bottom
            ? taskbar.y - result.height - gap
            : taskbar.bottom() + gap;
    } else {
        result.y = tray_icon && intersects(*tray_icon, taskbar)
            ? tray_icon->y - result.height - gap
            : screen.work_area.bottom() - result.height - gap;
        result.x = edge == TaskbarEdge::left
            ? taskbar.right() + gap
            : taskbar.x - result.width - gap;
    }

    const auto& work_area = screen.work_area;
    result.x = std::clamp(
        result.x,
        work_area.x,
        work_area.right() - result.width);
    result.y = std::clamp(
        result.y,
        work_area.y,
        work_area.bottom() - result.height);
    return result;
}

PixelRect OverlayPlacementEngine::taskbarCard(
    const ScreenSnapshot& screen,
    const PixelRect& taskbar,
    const PixelRect& widget,
    TaskbarEdge edge,
    OverlaySurfaceKind surface) const {
    if (taskbar.width <= 0 || taskbar.height <= 0
        || widget.width <= 0 || widget.height <= 0) {
        return {};
    }

    auto card = fitCard(screen.work_area, cardSize(surface, screen.dpi));
    const auto gap = pixelsFromDip(configuration_.edge_gap, screen.dpi);
    if (edge == TaskbarEdge::bottom) {
        card.x = widget.centerX() - card.width / 2;
        card.y = widget.y - card.height - gap;
    } else if (edge == TaskbarEdge::top) {
        card.x = widget.centerX() - card.width / 2;
        card.y = widget.bottom() + gap;
    } else if (edge == TaskbarEdge::left) {
        card.x = widget.right() + gap;
        card.y = widget.centerY() - card.height / 2;
    } else {
        card.x = widget.x - card.width - gap;
        card.y = widget.centerY() - card.height / 2;
    }

    card.x = std::clamp(
        card.x,
        screen.work_area.x,
        screen.work_area.x + std::max(0, screen.work_area.width - card.width));
    card.y = std::clamp(
        card.y,
        screen.work_area.y,
        screen.work_area.y + std::max(0, screen.work_area.height - card.height));
    return card;
}

PixelRect OverlayPlacementEngine::taskbarPet(
    const ScreenSnapshot& screen,
    const PixelRect& widget,
    TaskbarEdge edge,
    PetSide side) const {
    const auto requested = PixelSize{
        pixelsFromDip(configuration_.pet_window_size.width, screen.dpi),
        pixelsFromDip(configuration_.pet_window_size.height, screen.dpi),
    };
    if (widget.width <= 0 || widget.height <= 0
        || requested.width <= 0 || requested.height <= 0
        || requested.width > screen.work_area.width
        || requested.height > screen.work_area.height) {
        return {};
    }

    const auto gap = pixelsFromDip(configuration_.pet_gap, screen.dpi);
    const auto fits = [&screen](const PixelRect& candidate) noexcept {
        return candidate.x >= screen.work_area.x
            && candidate.y >= screen.work_area.y
            && candidate.right() <= screen.work_area.right()
            && candidate.bottom() <= screen.work_area.bottom();
    };

    PixelRect before{};
    PixelRect after{};
    if (edge == TaskbarEdge::top || edge == TaskbarEdge::bottom) {
        const auto y = widget.centerY() - requested.height / 2;
        before = {
            widget.x - gap - requested.width,
            y,
            requested.width,
            requested.height,
        };
        after = {
            widget.right() + gap,
            y,
            requested.width,
            requested.height,
        };
    } else {
        const auto x = widget.centerX() - requested.width / 2;
        before = {
            x,
            widget.y - gap - requested.height,
            requested.width,
            requested.height,
        };
        after = {
            x,
            widget.bottom() + gap,
            requested.width,
            requested.height,
        };
    }

    const auto& preferred = side == PetSide::left ? before : after;
    const auto& fallback = side == PetSide::left ? after : before;
    if (fits(preferred)) {
        return preferred;
    }
    return fits(fallback) ? fallback : PixelRect{};
}

PixelRect OverlayPlacementEngine::sideNoticePanel(
    const ScreenSnapshot& screen,
    NoticeSide side,
    std::size_t row_count) const {
    if (row_count == 0) {
        return {};
    }

    const auto row_height = pixelsFromDip(
        configuration_.side_notice_row_height,
        screen.dpi);
    const auto row_spacing = pixelsFromDip(
        configuration_.side_notice_row_spacing,
        screen.dpi);
    const auto requested_height = std::min(
        static_cast<long double>(std::numeric_limits<std::int32_t>::max()),
        static_cast<long double>(row_height) * row_count
            + static_cast<long double>(row_spacing) * (row_count - 1));
    auto panel = fitCard(
        screen.work_area,
        {
            pixelsFromDip(configuration_.side_notice_width, screen.dpi),
            static_cast<std::int32_t>(requested_height),
        });
    const auto gap = pixelsFromDip(configuration_.edge_gap, screen.dpi);
    const auto preview = cardSize(OverlaySurfaceKind::peek, screen.dpi);

    panel.x = side == NoticeSide::left
        ? screen.bounds.centerX() - preview.width / 2 - gap - panel.width
        : screen.bounds.centerX() + preview.width / 2 + gap;
    panel.y = screen.work_area.y + gap;
    panel.x = std::clamp(
        panel.x,
        screen.work_area.x,
        screen.work_area.x + std::max(0, screen.work_area.width - panel.width));
    panel.y = std::clamp(
        panel.y,
        screen.work_area.y,
        screen.work_area.y + std::max(0, screen.work_area.height - panel.height));
    return panel;
}

}  // namespace zisla::core
