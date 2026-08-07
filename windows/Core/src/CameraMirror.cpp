#include "zisla/core/CameraMirror.hpp"

#include <limits>

namespace zisla::core {

const CameraMirrorSnapshot& CameraMirrorSession::snapshot() const noexcept {
    return snapshot_;
}

std::uint64_t CameraMirrorSession::begin_start() noexcept {
    const auto generation = next_generation();
    snapshot_ = {
        .phase = CameraMirrorPhase::preparing,
        .failure = std::nullopt,
    };
    return generation;
}

bool CameraMirrorSession::mark_running(std::uint64_t generation) noexcept {
    if (!accepts(generation)
        || snapshot_.phase != CameraMirrorPhase::preparing) {
        return false;
    }
    snapshot_ = {
        .phase = CameraMirrorPhase::running,
        .failure = std::nullopt,
    };
    return true;
}

bool CameraMirrorSession::mark_failed(
    std::uint64_t generation,
    CameraMirrorFailure failure) noexcept {
    if (!accepts(generation)) {
        return false;
    }
    snapshot_ = {
        .phase = CameraMirrorPhase::failed,
        .failure = failure,
    };
    return true;
}

void CameraMirrorSession::stop() noexcept {
    (void)next_generation();
    snapshot_ = {};
}

bool CameraMirrorSession::accepts(std::uint64_t generation) const noexcept {
    return generation != 0 && generation == generation_
        && (snapshot_.phase == CameraMirrorPhase::preparing
            || snapshot_.phase == CameraMirrorPhase::running);
}

std::uint64_t CameraMirrorSession::next_generation() noexcept {
    generation_ = generation_ == std::numeric_limits<std::uint64_t>::max()
        ? 1
        : generation_ + 1;
    return generation_;
}

}  // namespace zisla::core
