#include "zisla/core/AIModels.hpp"
#include "zisla/core/FeatureSettings.hpp"
#include "zisla/core/OverlayPlacementEngine.hpp"
#include "zisla/core/PresentationEngine.hpp"
#include "zisla/core/detail/BoundedRecent.hpp"

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void hoverRevealsNonActivatingPreviewAtRequestedAnchor() {
    PresentationEngine engine;

    const auto effects = engine.dispatch(
        PresentationAction::hoverEntered(OverlayAnchor::top_edge));

    expect(engine.state() == PresentationState{
        .visibility = OverlayVisibility::peek,
        .anchor = OverlayAnchor::top_edge,
        .pointer_inside = true,
        .pinned = false,
    }, "hover should reveal a top-edge preview");
    expect(effects.size() == 1, "initial hover should only show the preview");
    expect(effects[0] == PresentationEffect{
        PresentationEffectKind::show_peek,
        OverlayAnchor::top_edge,
    }, "hover should show a non-activating preview");
}

void trayHoverUsesTheTrayAnchorAndDismissDelay() {
    PresentationEngine engine;

    const auto enter_effects = engine.dispatch(
        PresentationAction::hoverEntered(OverlayAnchor::tray));

    expect(engine.state().visibility == OverlayVisibility::peek
            && engine.state().anchor == OverlayAnchor::tray,
        "tray hover should reveal a preview anchored to the notification icon");
    expect(enter_effects.size() == 1
            && enter_effects[0] == PresentationEffect{
                PresentationEffectKind::show_peek,
                OverlayAnchor::tray,
            },
        "tray hover should request the shared non-activating preview");

    const auto exit_effects = engine.dispatch(PresentationAction::hoverExited());
    expect(exit_effects.size() == 1
            && exit_effects[0].kind == PresentationEffectKind::schedule_dismiss
            && exit_effects[0].anchor == OverlayAnchor::tray,
        "leaving the tray icon should reuse the delayed dismissal path");
}

void trayInteractionPromotesTheOverlayWithoutPinningIt() {
    PresentationEngine engine;

    const auto effects = engine.dispatch(
        PresentationAction::interactionRequested(OverlayAnchor::tray));

    expect(engine.state() == PresentationState{
        .visibility = OverlayVisibility::interactive,
        .anchor = OverlayAnchor::tray,
        .pointer_inside = false,
        .pinned = false,
    }, "tray click should show an interactive overlay");
    expect(effects.size() == 1, "initial interaction should only show the overlay");
    expect(effects[0] == PresentationEffect{
        PresentationEffectKind::show_interactive,
        OverlayAnchor::tray,
    }, "tray click should request the interactive host mode");

    expect(engine.dispatch(PresentationAction::hoverExited()).empty(),
        "interactive overlays should not dismiss when the pointer leaves");
    expect(engine.state().visibility == OverlayVisibility::interactive,
        "tray interaction should stay visible until light-dismissed");

    const auto dismiss_effects = engine.dispatch(
        PresentationAction::lightDismissRequested());
    expect(dismiss_effects.size() == 1
            && dismiss_effects[0].kind == PresentationEffectKind::hide,
        "an outside interaction should light-dismiss an unpinned overlay");
    expect(engine.state().visibility == OverlayVisibility::hidden,
        "light dismissal should return the overlay to hidden");
}

void pointerExitHidesOnlyAfterTheDismissDelay() {
    PresentationEngine engine;
    (void)engine.dispatch(PresentationAction::hoverEntered(OverlayAnchor::top_edge));

    const auto exit_effects = engine.dispatch(PresentationAction::hoverExited());
    expect(engine.state().visibility == OverlayVisibility::peek,
        "pointer exit should not hide immediately");
    expect(exit_effects.size() == 1, "pointer exit should schedule one dismiss");
    expect(exit_effects[0].kind == PresentationEffectKind::schedule_dismiss,
        "pointer exit should schedule dismissal");
    expect(exit_effects[0].dismiss_generation != 0,
        "scheduled dismissal should carry a generation");

    const auto elapsed_effects = engine.dispatch(
        PresentationAction::dismissDelayElapsed(
            exit_effects[0].dismiss_generation));
    expect(engine.state().visibility == OverlayVisibility::hidden,
        "elapsed delay should hide an unpinned overlay");
    expect(elapsed_effects.size() == 1, "elapsed delay should emit one effect");
    expect(elapsed_effects[0].kind == PresentationEffectKind::hide,
        "elapsed delay should hide the host window");
}

void pinnedOverlayIgnoresPointerExitAndStaleDismissal() {
    PresentationEngine engine;
    (void)engine.dispatch(PresentationAction::interactionRequested(OverlayAnchor::tray));
    (void)engine.dispatch(PresentationAction::pinChanged(true));

    expect(engine.state().pinned, "pin action should persist interactive mode");
    expect(engine.dispatch(PresentationAction::hoverExited()).empty(),
        "pointer exit should not schedule dismissal while pinned");
    expect(engine.dispatch(PresentationAction::dismissDelayElapsed(1)).empty(),
        "a stale timer should not hide a pinned overlay");
    expect(engine.state().visibility == OverlayVisibility::interactive,
        "pinned overlay should remain interactive");
    expect(engine.dispatch(PresentationAction::lightDismissRequested()).empty(),
        "outside interactions should not hide a pinned overlay");

    const auto unpin_effects = engine.dispatch(PresentationAction::pinChanged(false));
    expect(unpin_effects.empty(), "unpinning should leave the interactive overlay open");
    expect(engine.state().visibility == OverlayVisibility::interactive,
        "an unpinned overlay should wait for an explicit light dismissal");

    const auto dismiss_effects = engine.dispatch(
        PresentationAction::lightDismissRequested());
    expect(dismiss_effects.size() == 1
            && dismiss_effects[0].kind == PresentationEffectKind::hide,
        "an unpinned overlay should become light-dismissible again");
}

void hiddenOverlayIgnoresExitAndStaleDismissal() {
    PresentationEngine engine;

    expect(engine.dispatch(PresentationAction::hoverExited()).empty(),
        "hidden overlay should ignore pointer exit");
    expect(engine.dispatch(PresentationAction::dismissDelayElapsed(1)).empty(),
        "hidden overlay should ignore a stale dismiss timer");
    expect(engine.state().visibility == OverlayVisibility::hidden,
        "stale events should keep the overlay hidden");
}

void passiveHoverDoesNotReanchorAnInteractiveOverlay() {
    PresentationEngine engine;
    (void)engine.dispatch(
        PresentationAction::interactionRequested(OverlayAnchor::tray));

    const auto effects = engine.dispatch(
        PresentationAction::hoverEntered(OverlayAnchor::top_edge));

    expect(engine.state().visibility == OverlayVisibility::interactive,
        "hover should not demote an interactive overlay to preview mode");
    expect(engine.state().anchor == OverlayAnchor::tray,
        "passive hover should not move an interactive overlay away from its explicit anchor");
    expect(effects.empty(),
        "interactive hover should not re-show or move an already visible window");
}

void pinningFromHiddenShowsAnInteractiveOverlay() {
    PresentationEngine engine;

    const auto effects = engine.dispatch(PresentationAction::pinChanged(true));

    expect(engine.state().visibility == OverlayVisibility::interactive,
        "pinning should never leave the overlay hidden");
    expect(engine.state().pinned, "pinning should update persistent state");
    expect(effects.size() == 1, "pinning from hidden should show the overlay");
    expect(effects[0] == PresentationEffect{
        PresentationEffectKind::show_interactive,
        OverlayAnchor::top_edge,
    }, "pinning from hidden should use the current anchor");
}

void staleDismissGenerationCannotHideANewerSession() {
    PresentationEngine engine;
    (void)engine.dispatch(PresentationAction::hoverEntered(OverlayAnchor::top_edge));
    const auto first_exit = engine.dispatch(PresentationAction::hoverExited());
    const auto first_generation = first_exit[0].dismiss_generation;

    (void)engine.dispatch(PresentationAction::hoverEntered(OverlayAnchor::top_edge));
    const auto second_exit = engine.dispatch(PresentationAction::hoverExited());
    const auto second_generation = second_exit[0].dismiss_generation;

    expect(first_generation != second_generation,
        "each scheduled dismissal should receive a new generation");
    expect(engine.dispatch(
        PresentationAction::dismissDelayElapsed(first_generation)).empty(),
        "an older timer should be rejected after a new session schedules dismissal");
    expect(engine.state().visibility == OverlayVisibility::peek,
        "a stale timer should keep the newer preview visible");

    const auto fresh_effects = engine.dispatch(
        PresentationAction::dismissDelayElapsed(second_generation));
    expect(fresh_effects.size() == 1
            && fresh_effects[0].kind == PresentationEffectKind::hide,
        "the current timer should still dismiss the preview");
}

void explicitDismissClearsPinnedState() {
    PresentationEngine engine;
    (void)engine.dispatch(
        PresentationAction::interactionRequested(OverlayAnchor::tray));
    (void)engine.dispatch(PresentationAction::pinChanged(true));

    const auto effects = engine.dispatch(PresentationAction::dismissRequested());

    expect(engine.state().visibility == OverlayVisibility::hidden,
        "explicit dismissal should hide a pinned overlay");
    expect(!engine.state().pinned,
        "explicit dismissal should clear pinning instead of leaving hidden pinned state");
    expect(effects.size() == 1
            && effects[0].kind == PresentationEffectKind::hide,
        "explicit dismissal should hide without emitting a redundant timer cancellation");
}

void hostFailureReturnsTheEngineToHiddenState() {
    PresentationEngine engine;
    (void)engine.dispatch(PresentationAction::hoverEntered(OverlayAnchor::top_edge));
    const auto exit_effects = engine.dispatch(PresentationAction::hoverExited());

    const auto failure_effects = engine.dispatch(PresentationAction::hostFailed());

    expect(engine.state().visibility == OverlayVisibility::hidden
            && !engine.state().pointer_inside
            && !engine.state().pinned,
        "host failure should clear visibility, pointer, and pin state");
    expect(failure_effects.size() == 2,
        "host failure should cancel a pending timer and request best-effort hiding");
    expect(failure_effects[0].kind == PresentationEffectKind::cancel_scheduled_dismiss,
        "host failure should cancel the current dismiss generation");
    expect(failure_effects[1].kind == PresentationEffectKind::hide,
        "host failure should request best-effort host cleanup");
    expect(engine.dispatch(PresentationAction::dismissDelayElapsed(
        exit_effects[0].dismiss_generation)).empty(),
        "a timer issued before host failure should be stale");
}

void everyInteractionHoldRejectsLightDismissalUntilReleased() {
    constexpr PresentationHold holds[] = {
        PresentationHold::keyboard_focus,
        PresentationHold::drag,
        PresentationHold::transient_ui,
    };

    for (const auto hold : holds) {
        PresentationEngine engine;
        (void)engine.dispatch(
            PresentationAction::interactionRequested(OverlayAnchor::tray));
        (void)engine.dispatch(PresentationAction::holdChanged(hold, true));

        expect(engine.dispatch(PresentationAction::lightDismissRequested()).empty(),
            "an active interaction hold should suppress light dismissal");
        expect(engine.state().visibility == OverlayVisibility::interactive,
            "an active interaction hold should keep the overlay interactive");

        const auto release_effects = engine.dispatch(
            PresentationAction::holdChanged(hold, false));
        expect(release_effects.empty(),
            "releasing an interaction hold should not auto-dismiss interactive UI");

        const auto dismiss_effects = engine.dispatch(
            PresentationAction::lightDismissRequested());
        expect(dismiss_effects.size() == 1
                && dismiss_effects[0].kind == PresentationEffectKind::hide,
            "light dismissal should work after the interaction hold releases");
    }
}

void lightDismissalWaitsForAllInteractionHoldsToRelease() {
    PresentationEngine engine;
    (void)engine.dispatch(
        PresentationAction::interactionRequested(OverlayAnchor::tray));
    (void)engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::keyboard_focus, true));
    (void)engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::drag, true));

    expect(engine.dispatch(PresentationAction::lightDismissRequested()).empty(),
        "light dismissal should be ignored while interaction holds remain");

    expect(engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::keyboard_focus, false)).empty(),
        "releasing one hold should not dismiss interactive UI");
    expect(engine.dispatch(PresentationAction::lightDismissRequested()).empty(),
        "the remaining hold should continue rejecting light dismissal");

    const auto release_effects = engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::drag, false));
    expect(release_effects.empty(),
        "releasing the final hold should leave interactive UI visible");

    const auto dismiss_effects = engine.dispatch(
        PresentationAction::lightDismissRequested());
    expect(dismiss_effects.size() == 1
            && dismiss_effects[0].kind == PresentationEffectKind::hide,
        "light dismissal should resume after every hold releases");
}

void unpinKeepsInteractiveOverlayOpenAfterHoldsRelease() {
    PresentationEngine engine;
    (void)engine.dispatch(
        PresentationAction::interactionRequested(OverlayAnchor::tray));
    (void)engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::keyboard_focus, true));
    (void)engine.dispatch(PresentationAction::pinChanged(true));

    expect(engine.dispatch(PresentationAction::pinChanged(false)).empty(),
        "unpinning should not dismiss while keyboard focus is held");

    const auto release_effects = engine.dispatch(PresentationAction::holdChanged(
        PresentationHold::keyboard_focus, false));
    expect(release_effects.empty(),
        "releasing focus after unpinning should keep interactive UI visible");
    expect(engine.state().visibility == OverlayVisibility::interactive,
        "unpinning should restore light-dismiss behavior without auto-hiding");
}

void topEdgeGeometryUsesEachScreensPhysicalCoordinates() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {-2560, 0, 2560, 1440},
        .work_area = {-2560, 0, 2560, 1400},
    };

    expect(engine.topEdgeTrigger(screen) == PixelRect{-1440, 0, 320, 6},
        "top trigger should be centered on a negative-coordinate screen");
    expect(engine.topEdgeCard(screen, OverlaySurfaceKind::peek)
            == PixelRect{-1490, 8, 420, 96},
        "top preview should expand downward from that screen");
}

void trayGeometryExpandsInwardFromHorizontalTaskbars() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot bottom_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };
    expect(engine.trayCard(
            bottom_taskbar,
            {1840, 1040, 24, 24},
            OverlaySurfaceKind::interactive)
            == PixelRect{1440, 612, 480, 420},
        "bottom taskbar card should expand upward and clamp to the right edge");

    const ScreenSnapshot top_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 48, 1920, 1032},
    };
    expect(engine.trayCard(
            top_taskbar,
            {100, 0, 24, 24},
            OverlaySurfaceKind::interactive)
            == PixelRect{0, 56, 480, 420},
        "top taskbar card should expand downward and stay inside the work area");
}

void trayGeometryExpandsInwardFromVerticalTaskbars() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot left_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {48, 0, 1872, 1080},
    };
    expect(engine.trayCard(
            left_taskbar,
            {0, 500, 24, 24},
            OverlaySurfaceKind::interactive)
            == PixelRect{56, 302, 480, 420},
        "left taskbar card should expand right into the work area");

    const ScreenSnapshot right_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1872, 1080},
    };
    expect(engine.trayCard(
            right_taskbar,
            {1872, 500, 24, 24},
            OverlaySurfaceKind::interactive)
            == PixelRect{1384, 302, 480, 420},
        "right taskbar card should expand left into the work area");
}

void taskbarCompanionAndCardFollowTaskbarEdge() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };
    const PixelRect taskbar{0, 1040, 1920, 40};
    const auto widget = engine.taskbarWidget(
        screen,
        taskbar,
        TaskbarEdge::bottom,
        TaskbarWidgetPosition::trailing,
        PixelRect{1840, 1040, 24, 24});
    expect(widget == PixelRect{1796, 1042, 36, 36},
        "bottom taskbar companion should sit inside the taskbar beside its notification icon");
    expect(engine.taskbarCard(
                screen,
                taskbar,
                widget,
                TaskbarEdge::bottom,
                OverlaySurfaceKind::peek)
            == PixelRect{1500, 938, 420, 96},
        "bottom taskbar companion should expand upward from the taskbar companion");

    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::leading,
                PixelRect{1840, 1040, 24, 24})
            == PixelRect{8, 1042, 36, 36},
        "leading position should use the left side of a horizontal taskbar");
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::before_start,
                PixelRect{1840, 1040, 24, 24},
                PixelRect{900, 1040, 40, 40})
            == PixelRect{856, 1042, 36, 36},
        "before-start position should sit left of the Start button");
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::before_start,
                PixelRect{1840, 1040, 24, 24},
                PixelRect{900, 1040, 40, 40},
                DipSize{176, 36})
            == PixelRect{716, 1042, 176, 36},
        "before-start position should keep a media widget left of the Start button");
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::trailing)
            == PixelRect{1876, 1042, 36, 36},
        "missing notification icon geometry should use the trailing taskbar fallback");
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::trailing,
                PixelRect{100, 900, 24, 24})
            == PixelRect{1876, 1042, 36, 36},
            "an unrelated icon rectangle should not move the taskbar companion");

    const PixelRect system_tray{1680, 1040, 240, 40};
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::trailing,
                system_tray)
            == PixelRect{1636, 1042, 36, 36},
        "trailing position should sit left of the complete system tray");
    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::trailing,
                system_tray,
                std::nullopt,
                DipSize{240, 36})
            == PixelRect{1432, 1042, 240, 36},
        "wide taskbar status should remain left of the complete system tray");

    const ScreenSnapshot top_screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 40, 1920, 1040},
    };
    const PixelRect top_taskbar{0, 0, 1920, 40};
    const auto top_widget = engine.taskbarWidget(
        top_screen,
        top_taskbar,
        TaskbarEdge::top,
        TaskbarWidgetPosition::trailing);
    expect(top_widget == PixelRect{1876, 2, 36, 36},
        "top taskbar companion should stay inside the taskbar near its trailing edge");
    expect(engine.taskbarCard(
                top_screen,
                top_taskbar,
                top_widget,
                TaskbarEdge::top,
                OverlaySurfaceKind::peek)
            == PixelRect{1500, 46, 420, 96},
        "top taskbar companion should expand downward from the taskbar companion");

    const ScreenSnapshot left_screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {48, 0, 1872, 1080},
    };
    const PixelRect left_taskbar{0, 0, 48, 1080};
    expect(engine.taskbarWidget(
                left_screen,
                left_taskbar,
                TaskbarEdge::left,
                TaskbarWidgetPosition::leading)
            == PixelRect{6, 8, 36, 36},
        "leading position should use the top of a vertical taskbar");
    expect(engine.taskbarWidget(
                left_screen,
                left_taskbar,
                TaskbarEdge::left,
                TaskbarWidgetPosition::before_start,
                std::nullopt,
                PixelRect{0, 600, 48, 40})
            == PixelRect{6, 556, 36, 36},
        "before-start position should use the space above a vertical Start button");
    expect(engine.taskbarWidget(
                left_screen,
                left_taskbar,
                TaskbarEdge::left,
                TaskbarWidgetPosition::trailing,
                PixelRect{0, 1000, 48, 40})
            == PixelRect{6, 956, 36, 36},
        "trailing position should use the bottom of a vertical taskbar before its tray");

    expect(engine.taskbarWidget(
                left_screen,
                left_taskbar,
                TaskbarEdge::left,
                TaskbarWidgetPosition::trailing,
                PixelRect{0, 1000, 48, 40},
                std::nullopt,
                DipSize{36, 240})
            == PixelRect{6, 752, 36, 240},
        "a vertical taskbar status should extend along the taskbar without leaving it");

    const ScreenSnapshot right_screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1872, 1080},
    };
    const PixelRect right_taskbar{1872, 0, 48, 1080};
    expect(engine.taskbarWidget(
                right_screen,
                right_taskbar,
                TaskbarEdge::right,
                TaskbarWidgetPosition::before_start,
                std::nullopt,
                PixelRect{1872, 600, 48, 40})
            == PixelRect{1878, 556, 36, 36},
        "before-start position should remain inside a right-side vertical taskbar");

    expect(engine.taskbarWidget(
                screen,
                taskbar,
                TaskbarEdge::bottom,
                TaskbarWidgetPosition::leading,
                std::nullopt,
                std::nullopt,
                DipSize{240, 36})
            == PixelRect{8, 1042, 240, 36},
        "a horizontal taskbar status should extend along the taskbar without leaving it");
}

void taskbarGeometryFollowsTheTrayIconMonitor() {
    const ScreenSnapshot secondary_bottom_taskbar{
        .bounds = {-1920, 0, 1920, 1080},
        .work_area = {-1920, 0, 1920, 1040},
        .dpi = 144,
    };
    const PixelRect secondary_tray{-96, 1044, 24, 28};
    const auto bottom = taskbarGeometryForTrayIcon(
        secondary_bottom_taskbar,
        secondary_tray);
    expect(bottom.has_value() && bottom->valid(),
        "a tray icon on a secondary monitor should produce a taskbar anchor");
    expect(bottom->edge == TaskbarEdge::bottom
            && bottom->bounds == PixelRect{-1920, 1040, 1920, 40},
        "a secondary bottom taskbar should use that monitor's work-area inset");

    const ScreenSnapshot top_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 48, 1920, 1032},
    };
    const auto top = taskbarGeometryForTrayIcon(top_taskbar, {96, 8, 24, 24});
    expect(top.has_value() && top->edge == TaskbarEdge::top
            && top->bounds == PixelRect{0, 0, 1920, 48},
        "a top-edge tray icon should preserve the top taskbar geometry");

    const ScreenSnapshot left_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {48, 0, 1872, 1080},
    };
    const auto left = taskbarGeometryForTrayIcon(left_taskbar, {8, 500, 24, 24});
    expect(left.has_value() && left->edge == TaskbarEdge::left
            && left->bounds == PixelRect{0, 0, 48, 1080},
        "a left-edge tray icon should preserve the vertical taskbar geometry");

    const ScreenSnapshot auto_hidden_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1080},
    };
    const auto auto_hidden = taskbarGeometryForTrayIcon(
        auto_hidden_taskbar,
        {1800, 1048, 24, 24});
    expect(auto_hidden.has_value() && auto_hidden->edge == TaskbarEdge::bottom
            && auto_hidden->bounds == PixelRect{0, 1048, 1920, 32},
        "an auto-hidden taskbar should fall back to the visible tray-icon edge");

    expect(!taskbarGeometryForTrayIcon(
                secondary_bottom_taskbar,
                {20, 20, 24, 24}).has_value(),
        "an icon outside the screen should not produce a taskbar anchor");
}

void taskbarPetUsesConfiguredSideAndFallsBackWhenNeeded() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };
    const PixelRect taskbar{0, 1040, 1920, 40};
    const PixelRect widget{56, 1042, 36, 36};

    expect(engine.taskbarPet(
                screen,
                taskbar,
                widget,
                TaskbarEdge::bottom,
                PetSide::right)
            == PixelRect{96, 1042, 30, 36},
        "right-side pet should sit after the taskbar companion inside the taskbar");
    expect(engine.taskbarPet(
                screen,
                taskbar,
                widget,
                TaskbarEdge::bottom,
                PetSide::left)
            == PixelRect{22, 1042, 30, 36},
        "left-side pet should sit before the taskbar companion inside the taskbar");

    const PixelRect right_edge_widget{1884, 1042, 36, 36};
    expect(engine.taskbarPet(
                screen,
                taskbar,
                right_edge_widget,
                TaskbarEdge::bottom,
                PetSide::right)
            == PixelRect{1850, 1042, 30, 36},
        "pet should fall back to the opposite side at the taskbar edge");

    const PixelRect system_tray{1680, 1040, 240, 40};
    const PixelRect tray_adjacent_widget{1636, 1042, 36, 36};
    expect(engine.taskbarPet(
                screen,
                taskbar,
                tray_adjacent_widget,
                TaskbarEdge::bottom,
                PetSide::right,
                system_tray)
            == PixelRect{1602, 1042, 30, 36},
        "pet should switch sides instead of covering the system tray");
}

void placementScalesDipMetricsForEachDisplayDpi() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 2560, 1440},
        .work_area = {0, 0, 2560, 1400},
        .dpi = 144,
    };

    expect(engine.topEdgeTrigger(screen) == PixelRect{1040, 0, 480, 9},
        "top trigger DIP metrics should scale at 150 percent DPI");
    expect(engine.topEdgeCard(screen, OverlaySurfaceKind::peek)
            == PixelRect{965, 12, 630, 144},
        "preview size and edge gap should scale at 150 percent DPI");
    expect(engine.cardSize(OverlaySurfaceKind::interactive, screen.dpi)
            == PixelSize{720, 630},
        "interactive card size should scale independently from preview size");
}

void preferredCardSizesFollowTheirAnchorAndWorkArea() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };
    const DipSize preferred{860, 540};

    expect(engine.trayCard(
            screen,
            {1840, 1040, 24, 24},
            OverlaySurfaceKind::interactive,
            preferred)
            == PixelRect{1060, 492, 860, 540},
        "a preferred size should keep tray cards inward and inside the work area");

    const ScreenSnapshot small_screen{
        .bounds = {0, 0, 480, 320},
        .work_area = {0, 0, 480, 320},
    };
    expect(engine.topEdgeCard(
            small_screen,
            OverlaySurfaceKind::interactive,
            preferred)
            == PixelRect{0, 0, 480, 320},
        "a preferred size should shrink to fit a constrained display");

    const ScreenSnapshot scaled_screen{
        .bounds = {0, 0, 2560, 1440},
        .work_area = {0, 0, 2560, 1400},
        .dpi = 144,
    };
    expect(engine.cardSize(
            OverlaySurfaceKind::interactive,
            scaled_screen.dpi,
            preferred)
            == PixelSize{1290, 810},
        "preferred card dimensions should follow the active display DPI");
}

void oversizedCardsFitWithinTheAvailableWorkArea() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot small_screen{
        .bounds = {0, 0, 300, 150},
        .work_area = {0, 0, 300, 150},
    };

    expect(engine.topEdgeCard(small_screen, OverlaySurfaceKind::interactive)
            == PixelRect{0, 0, 300, 150},
        "card should shrink instead of leaving a small work area");
}

void topTriggerStaysAtThePhysicalEdgeAboveATopTaskbar() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 48, 1920, 1032},
    };

    expect(engine.topEdgeTrigger(screen) == PixelRect{800, 0, 320, 6},
        "top trigger should use screen bounds rather than taskbar work area");
}

void sideNoticeGeometryFlanksTheTopPreview() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot screen{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };

    expect(engine.sideNoticePanel(screen, NoticeSide::left, 3)
            == PixelRect{490, 8, 252, 174},
        "left notices should end one gap before the centered preview");
    expect(engine.sideNoticePanel(screen, NoticeSide::right, 3)
            == PixelRect{1178, 8, 252, 174},
        "right notices should start one gap after the centered preview");
    expect(engine.sideNoticePanel(screen, NoticeSide::left, 0) == PixelRect{},
        "an empty notice side should not reserve a window");
}

void sideNoticeGeometryScalesAndStaysInsideTheWorkArea() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot scaled{
        .bounds = {0, 0, 2560, 1440},
        .work_area = {0, 72, 2560, 1368},
        .dpi = 144,
    };

    expect(engine.sideNoticePanel(scaled, NoticeSide::left, 2)
            == PixelRect{575, 84, 378, 171},
        "side notice dimensions and gaps should scale with display DPI");

    const ScreenSnapshot small{
        .bounds = {0, 0, 300, 180},
        .work_area = {0, 20, 300, 160},
    };
    const auto right = engine.sideNoticePanel(small, NoticeSide::right, 4);
    expect(right.x >= small.work_area.x
            && right.y >= small.work_area.y
            && right.right() <= small.work_area.right()
            && right.bottom() <= small.work_area.bottom(),
        "side notices should shrink and clamp inside a constrained work area");
}

void trayNoticeGeometryTracksTheTrayIcon() {
    const OverlayPlacementEngine engine;
    const ScreenSnapshot bottom_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {0, 0, 1920, 1040},
    };

    expect(engine.trayNoticePanel(bottom_taskbar, {1880, 1040, 40, 40}, 2)
            == PixelRect{1620, 926, 252, 114},
        "tray notices should use the left side when a bottom taskbar icon has no right space");

    const ScreenSnapshot left_taskbar{
        .bounds = {0, 0, 1920, 1080},
        .work_area = {48, 0, 1872, 1080},
    };
    expect(engine.trayNoticePanel(left_taskbar, {0, 500, 48, 40}, 3)
            == PixelRect{56, 433, 252, 174},
        "tray notices should prefer the right side of the tray icon");
}

void boundedRecentCandidatesRetainOnlyTheNewestValues() {
    struct Candidate {
        int timestamp;
        int tie_breaker;
    };
    const auto newer = [](const Candidate& lhs, const Candidate& rhs) {
        return lhs.timestamp != rhs.timestamp
            ? lhs.timestamp > rhs.timestamp
            : lhs.tie_breaker < rhs.tie_breaker;
    };
    std::vector<Candidate> candidates;
    for (const auto candidate : {
             Candidate{10, 2},
             Candidate{30, 3},
             Candidate{20, 4},
             Candidate{30, 1},
             Candidate{5, 0},
         }) {
        detail::retain_newest(candidates, candidate, 3, newer);
    }
    std::sort(candidates.begin(), candidates.end(), newer);

    expect(candidates.size() == 3,
        "bounded recent candidates should never exceed their capacity");
    expect(candidates[0].timestamp == 30 && candidates[0].tie_breaker == 1,
        "the newest tie should retain the normal scanner ordering");
    expect(candidates[1].timestamp == 30 && candidates[1].tie_breaker == 3,
        "both newest tied values should be retained");
    expect(candidates[2].timestamp == 20,
        "older candidates should be replaced as newer values arrive");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"hover reveals preview", hoverRevealsNonActivatingPreviewAtRequestedAnchor},
        {"tray hover uses shared preview", trayHoverUsesTheTrayAnchorAndDismissDelay},
        {"tray click becomes interactive", trayInteractionPromotesTheOverlayWithoutPinningIt},
        {"pointer exit waits for delay", pointerExitHidesOnlyAfterTheDismissDelay},
        {"pin rejects stale dismissal", pinnedOverlayIgnoresPointerExitAndStaleDismissal},
        {"hidden ignores stale events", hiddenOverlayIgnoresExitAndStaleDismissal},
        {"passive hover preserves interactive anchor", passiveHoverDoesNotReanchorAnInteractiveOverlay},
        {"pinning reveals interaction", pinningFromHiddenShowsAnInteractiveOverlay},
        {"stale dismiss generation is rejected", staleDismissGenerationCannotHideANewerSession},
        {"explicit dismiss clears pin", explicitDismissClearsPinnedState},
        {"host failure resets presentation", hostFailureReturnsTheEngineToHiddenState},
        {"interaction holds prevent light dismissal", everyInteractionHoldRejectsLightDismissalUntilReleased},
        {"all interaction holds must release", lightDismissalWaitsForAllInteractionHoldsToRelease},
        {"unpin keeps interactive overlay open", unpinKeepsInteractiveOverlayOpenAfterHoldsRelease},
        {"top edge supports multiple screens", topEdgeGeometryUsesEachScreensPhysicalCoordinates},
        {"tray expands from horizontal taskbars", trayGeometryExpandsInwardFromHorizontalTaskbars},
        {"tray expands from vertical taskbars", trayGeometryExpandsInwardFromVerticalTaskbars},
        {"taskbar companion follows taskbar edge", taskbarCompanionAndCardFollowTaskbarEdge},
        {"taskbar geometry follows tray monitor", taskbarGeometryFollowsTheTrayIconMonitor},
        {"taskbar pet follows companion side", taskbarPetUsesConfiguredSideAndFallsBackWhenNeeded},
        {"placement scales for display DPI", placementScalesDipMetricsForEachDisplayDpi},
        {"preferred cards follow anchor and work area", preferredCardSizesFollowTheirAnchorAndWorkArea},
        {"oversized cards stay visible", oversizedCardsFitWithinTheAvailableWorkArea},
        {"top trigger uses physical edge", topTriggerStaysAtThePhysicalEdgeAboveATopTaskbar},
        {"side notices flank top preview", sideNoticeGeometryFlanksTheTopPreview},
        {"side notices scale and remain visible", sideNoticeGeometryScalesAndStaysInsideTheWorkArea},
        {"tray notices follow the tray icon", trayNoticeGeometryTracksTheTrayIcon},
        {"recent candidates stay bounded", boundedRecentCandidatesRetainOnlyTheNewestValues},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }

    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
