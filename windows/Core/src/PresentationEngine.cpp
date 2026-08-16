#include "zisla/core/PresentationEngine.hpp"

#include <algorithm>
#include <stdexcept>

namespace zisla::core {

PresentationAction PresentationAction::hoverEntered(OverlayAnchor anchor) {
    return {PresentationActionKind::hover_entered, anchor};
}

PresentationAction PresentationAction::hoverExited() {
    return {PresentationActionKind::hover_exited};
}

PresentationAction PresentationAction::interactionRequested(OverlayAnchor anchor) {
    return {PresentationActionKind::interaction_requested, anchor};
}

PresentationAction PresentationAction::pinChanged(bool pinned) {
    return {PresentationActionKind::pin_changed, OverlayAnchor::top_edge, pinned};
}

PresentationAction PresentationAction::holdChanged(PresentationHold hold, bool held) {
    return {
        PresentationActionKind::hold_changed,
        OverlayAnchor::top_edge,
        held,
        hold,
    };
}

PresentationAction PresentationAction::lightDismissRequested() {
    return {PresentationActionKind::light_dismiss_requested};
}

PresentationAction PresentationAction::dismissRequested() {
    return {PresentationActionKind::dismiss_requested};
}

PresentationAction PresentationAction::hostFailed() {
    return {PresentationActionKind::host_failed};
}

PresentationAction PresentationAction::dismissDelayElapsed(
    std::uint64_t generation) {
    return {
        PresentationActionKind::dismiss_delay_elapsed,
        OverlayAnchor::top_edge,
        false,
        PresentationHold::keyboard_focus,
        generation,
    };
}

std::size_t EffectBatch::size() const noexcept {
    return size_;
}

bool EffectBatch::empty() const noexcept {
    return size_ == 0;
}

const PresentationEffect& EffectBatch::operator[](std::size_t index) const {
    return effects_.at(index);
}

void EffectBatch::push(PresentationEffect effect) {
    if (size_ >= capacity) {
        throw std::logic_error("presentation effect batch capacity exceeded");
    }
    effects_[size_++] = effect;
}

const PresentationState& PresentationEngine::state() const noexcept {
    return state_;
}

bool PresentationEngine::hasInteractionHold() const noexcept {
    return std::any_of(holds_.begin(), holds_.end(), [](bool held) { return held; });
}

bool PresentationEngine::isHeldOpen() const noexcept {
    return state_.pointer_inside || hasInteractionHold();
}

void PresentationEngine::cancelScheduledDismiss(EffectBatch& effects) {
    if (!dismiss_scheduled_) {
        return;
    }
    ++dismiss_generation_;
    dismiss_scheduled_ = false;
    effects.push({
        PresentationEffectKind::cancel_scheduled_dismiss,
        state_.anchor,
    });
}

void PresentationEngine::scheduleDismiss(EffectBatch& effects) {
    ++dismiss_generation_;
    dismiss_scheduled_ = true;
    effects.push({
        PresentationEffectKind::schedule_dismiss,
        state_.anchor,
        dismiss_generation_,
    });
}

EffectBatch PresentationEngine::dispatch(PresentationAction action) {
    EffectBatch effects;

    switch (action.kind) {
    case PresentationActionKind::hover_entered:
        cancelScheduledDismiss(effects);
        state_.pointer_inside = true;
        if (state_.visibility == OverlayVisibility::interactive) {
            break;
        }
        state_.anchor = action.anchor;
        state_.visibility = OverlayVisibility::peek;
        effects.push({PresentationEffectKind::show_peek, action.anchor});
        break;

    case PresentationActionKind::hover_exited:
        if (state_.visibility == OverlayVisibility::hidden) {
            break;
        }
        state_.pointer_inside = false;
        if (state_.visibility == OverlayVisibility::peek
            && !state_.pinned && !isHeldOpen()) {
            scheduleDismiss(effects);
        }
        break;

    case PresentationActionKind::interaction_requested:
        cancelScheduledDismiss(effects);
        effects.push({PresentationEffectKind::show_interactive, action.anchor});
        holds_.fill(false);
        state_.visibility = OverlayVisibility::interactive;
        state_.anchor = action.anchor;
        state_.pointer_inside = false;
        break;

    case PresentationActionKind::pin_changed:
        state_.pinned = action.value;
        if (action.value) {
            state_.visibility = OverlayVisibility::interactive;
            cancelScheduledDismiss(effects);
            effects.push({PresentationEffectKind::show_interactive, state_.anchor});
        }
        break;

    case PresentationActionKind::hold_changed: {
        const auto index = static_cast<std::size_t>(action.hold);
        if (index >= holds_.size()) {
            break;
        }
        if (state_.visibility == OverlayVisibility::hidden) {
            holds_[index] = false;
            break;
        }
        holds_[index] = action.value;
        if (action.value) {
            cancelScheduledDismiss(effects);
        } else if (state_.visibility == OverlayVisibility::peek
            && !state_.pinned && !isHeldOpen()) {
            scheduleDismiss(effects);
        }
        break;
    }

    case PresentationActionKind::light_dismiss_requested:
        if (state_.visibility == OverlayVisibility::hidden
            || state_.pinned || hasInteractionHold()) {
            break;
        }
        cancelScheduledDismiss(effects);
        effects.push({PresentationEffectKind::hide, state_.anchor});
        state_.visibility = OverlayVisibility::hidden;
        state_.pointer_inside = false;
        holds_.fill(false);
        break;

    case PresentationActionKind::dismiss_requested:
        if (state_.visibility == OverlayVisibility::hidden) {
            break;
        }
        cancelScheduledDismiss(effects);
        effects.push({PresentationEffectKind::hide, state_.anchor});
        state_.visibility = OverlayVisibility::hidden;
        state_.pointer_inside = false;
        state_.pinned = false;
        holds_.fill(false);
        break;

    case PresentationActionKind::host_failed:
        if (state_.visibility == OverlayVisibility::hidden) {
            break;
        }
        cancelScheduledDismiss(effects);
        effects.push({PresentationEffectKind::hide, state_.anchor});
        state_.visibility = OverlayVisibility::hidden;
        state_.pointer_inside = false;
        state_.pinned = false;
        holds_.fill(false);
        break;

    case PresentationActionKind::dismiss_delay_elapsed:
        if (!dismiss_scheduled_
            || action.dismiss_generation != dismiss_generation_) {
            break;
        }
        dismiss_scheduled_ = false;
        if (state_.visibility != OverlayVisibility::hidden
            && !state_.pinned && !isHeldOpen()) {
            effects.push({PresentationEffectKind::hide, state_.anchor});
            state_.visibility = OverlayVisibility::hidden;
            holds_.fill(false);
        }
        break;
    }

    return effects;
}

}  // namespace zisla::core
