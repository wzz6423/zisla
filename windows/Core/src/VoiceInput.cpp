#include "zisla/core/VoiceInput.hpp"

#include <limits>
#include <utility>

namespace zisla::core {

const VoiceInputSnapshot& VoiceInputSession::snapshot() const noexcept {
    return snapshot_;
}

std::uint64_t VoiceInputSession::begin() noexcept {
    const auto generation = next_generation();
    snapshot_ = {
        .phase = VoiceInputPhase::requesting_speech_permission,
        .failure = std::nullopt,
    };
    return generation;
}

bool VoiceInputSession::mark_speech_permission_granted(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::requesting_speech_permission) {
        return false;
    }
    snapshot_.phase = VoiceInputPhase::requesting_microphone_permission;
    return true;
}

bool VoiceInputSession::mark_speech_permission_denied(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::requesting_speech_permission) {
        return false;
    }
    snapshot_ = {
        .phase = VoiceInputPhase::failed,
        .failure = VoiceInputFailure::speech_permission_denied,
    };
    return true;
}

bool VoiceInputSession::mark_microphone_permission_granted(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::requesting_microphone_permission) {
        return false;
    }
    snapshot_.phase = VoiceInputPhase::starting;
    return true;
}

bool VoiceInputSession::mark_microphone_permission_denied(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::requesting_microphone_permission) {
        return false;
    }
    snapshot_ = {
        .phase = VoiceInputPhase::failed,
        .failure = VoiceInputFailure::microphone_permission_denied,
    };
    return true;
}

bool VoiceInputSession::mark_listening(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::starting) {
        return false;
    }
    snapshot_.phase = VoiceInputPhase::listening;
    return true;
}

bool VoiceInputSession::mark_failed(
    std::uint64_t generation,
    VoiceInputFailure failure) noexcept {
    if (!accepts(generation)) {
        return false;
    }
    // finalizing 阶段的错误走回退，不暴露失败
    if (snapshot_.phase == VoiceInputPhase::finalizing) {
        return finish_finalization(generation);
    }
    snapshot_ = {
        .phase = VoiceInputPhase::failed,
        .failure = failure,
        .partial_text = snapshot_.partial_text,
        .final_text = snapshot_.final_text,
    };
    return true;
}

bool VoiceInputSession::update_partial_text(
    std::uint64_t generation,
    std::string text) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::listening) {
        return false;
    }
    snapshot_.partial_text = std::move(text);
    return true;
}

bool VoiceInputSession::mark_finalizing(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::listening) {
        return false;
    }
    snapshot_.phase = VoiceInputPhase::finalizing;
    return true;
}

bool VoiceInputSession::update_final_text(
    std::uint64_t generation,
    std::string text) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::finalizing) {
        return false;
    }
    snapshot_.final_text = std::move(text);
    snapshot_.phase = VoiceInputPhase::idle;
    return true;
}

bool VoiceInputSession::finish_finalization(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != VoiceInputPhase::finalizing) {
        return false;
    }
    // 最终文本优先，否则用部分文本回退
    if (snapshot_.final_text.empty() && !snapshot_.partial_text.empty()) {
        snapshot_.final_text = snapshot_.partial_text;
    }
    snapshot_.phase = VoiceInputPhase::idle;
    return true;
}

void VoiceInputSession::cancel() noexcept {
    (void)next_generation();
    snapshot_ = {};
}

bool VoiceInputSession::accepts(std::uint64_t generation) const noexcept {
    return generation != 0 && generation == generation_
        && snapshot_.phase != VoiceInputPhase::idle
        && snapshot_.phase != VoiceInputPhase::failed;
}

std::uint64_t VoiceInputSession::next_generation() noexcept {
    generation_ = generation_ == std::numeric_limits<std::uint64_t>::max()
        ? 1
        : generation_ + 1;
    return generation_;
}

}  // namespace zisla::core
