#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace zisla::core {

enum class OverlayVisibility {
    hidden,
    peek,
    interactive,
};

enum class OverlayAnchor {
    top_edge,
    tray,
    taskbar,
};

enum class PresentationHold : std::uint8_t {
    keyboard_focus,
    drag,
    transient_ui,
};

enum class PresentationActionKind {
    hover_entered,
    hover_exited,
    interaction_requested,
    pin_changed,
    hold_changed,
    light_dismiss_requested,
    dismiss_requested,
    host_failed,
    dismiss_delay_elapsed,
};

struct PresentationAction {
    PresentationActionKind kind{PresentationActionKind::hover_entered};
    OverlayAnchor anchor{OverlayAnchor::top_edge};
    bool value{false};
    PresentationHold hold{PresentationHold::keyboard_focus};
    std::uint64_t dismiss_generation{0};

    [[nodiscard]] static PresentationAction hoverEntered(OverlayAnchor anchor);
    [[nodiscard]] static PresentationAction hoverExited();
    [[nodiscard]] static PresentationAction interactionRequested(OverlayAnchor anchor);
    [[nodiscard]] static PresentationAction pinChanged(bool pinned);
    [[nodiscard]] static PresentationAction holdChanged(PresentationHold hold, bool held);
    [[nodiscard]] static PresentationAction lightDismissRequested();
    [[nodiscard]] static PresentationAction dismissRequested();
    [[nodiscard]] static PresentationAction hostFailed();
    [[nodiscard]] static PresentationAction dismissDelayElapsed(
        std::uint64_t generation);
};

enum class PresentationEffectKind {
    cancel_scheduled_dismiss,
    schedule_dismiss,
    show_peek,
    show_interactive,
    hide,
};

struct PresentationEffect {
    PresentationEffectKind kind{PresentationEffectKind::hide};
    OverlayAnchor anchor{OverlayAnchor::top_edge};
    std::uint64_t dismiss_generation{0};

    friend bool operator==(const PresentationEffect&, const PresentationEffect&) = default;
};

class EffectBatch {
public:
    static constexpr std::size_t capacity = 2;

    [[nodiscard]] std::size_t size() const noexcept;
    [[nodiscard]] bool empty() const noexcept;
    [[nodiscard]] const PresentationEffect& operator[](std::size_t index) const;

private:
    friend class PresentationEngine;

    void push(PresentationEffect effect);

    std::array<PresentationEffect, capacity> effects_{};
    std::size_t size_{0};
};

struct PresentationState {
    OverlayVisibility visibility{OverlayVisibility::hidden};
    OverlayAnchor anchor{OverlayAnchor::top_edge};
    bool pointer_inside{false};
    bool pinned{false};

    friend bool operator==(const PresentationState&, const PresentationState&) = default;
};

/// Mutable presentation state is confined to the Windows shell UI sequence.
/// Trigger threads must post actions instead of calling dispatch concurrently.
class PresentationEngine {
public:
    [[nodiscard]] const PresentationState& state() const noexcept;
    [[nodiscard]] EffectBatch dispatch(PresentationAction action);

private:
    [[nodiscard]] bool hasInteractionHold() const noexcept;
    [[nodiscard]] bool isHeldOpen() const noexcept;
    void cancelScheduledDismiss(EffectBatch& effects);
    void scheduleDismiss(EffectBatch& effects);

    static constexpr std::size_t hold_count = 3;

    PresentationState state_{};
    // Holds describe interactions inside the visible host and end whenever it hides.
    std::array<bool, hold_count> holds_{};
    std::uint64_t dismiss_generation_{0};
    bool dismiss_scheduled_{false};
};

}  // namespace zisla::core
