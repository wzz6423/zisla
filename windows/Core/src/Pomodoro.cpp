#include "zisla/core/Pomodoro.hpp"

#include <algorithm>
#include <iomanip>
#include <limits>
#include <sstream>

namespace zisla::core {

bool PomodoroSnapshot::active() const noexcept {
    return phase != PomodoroPhase::idle;
}

PomodoroEngine::PomodoroEngine(
    std::int64_t focus_duration_seconds,
    std::int64_t rest_duration_seconds) noexcept
    : focus_duration_seconds_(normalized_duration_seconds(focus_duration_seconds)),
      rest_duration_seconds_(normalized_duration_seconds(rest_duration_seconds)),
      remaining_when_paused_ms_(duration_milliseconds(focus_duration_seconds_)) {}

PomodoroMode PomodoroEngine::mode() const noexcept {
    return mode_;
}

PomodoroPhase PomodoroEngine::phase() const noexcept {
    return phase_;
}

std::int64_t PomodoroEngine::duration_seconds(PomodoroMode mode) const noexcept {
    return mode == PomodoroMode::focus
        ? focus_duration_seconds_
        : rest_duration_seconds_;
}

std::int64_t PomodoroEngine::remaining_milliseconds(
    std::int64_t now_unix_ms) const noexcept {
    if (phase_ == PomodoroPhase::idle) {
        return duration_milliseconds(duration_seconds(mode_));
    }
    if (phase_ == PomodoroPhase::paused || !deadline_unix_ms_) {
        return std::max<std::int64_t>(0, remaining_when_paused_ms_);
    }
    if (*deadline_unix_ms_ <= now_unix_ms) {
        return 0;
    }
    if (now_unix_ms < 0
        && *deadline_unix_ms_ > std::numeric_limits<std::int64_t>::max() + now_unix_ms) {
        return std::numeric_limits<std::int64_t>::max();
    }
    return *deadline_unix_ms_ - now_unix_ms;
}

PomodoroSnapshot PomodoroEngine::snapshot(std::int64_t now_unix_ms) const noexcept {
    const auto remaining_ms = remaining_milliseconds(now_unix_ms);
    const auto remaining_seconds = remaining_ms == 0
        ? std::int64_t{0}
        : std::int64_t{1} + (remaining_ms - 1) / 1'000;
    return {
        .mode = mode_,
        .phase = phase_,
        .remaining_seconds = remaining_seconds,
        .focus_duration_seconds = focus_duration_seconds_,
        .rest_duration_seconds = rest_duration_seconds_,
    };
}

void PomodoroEngine::set_duration_seconds(
    PomodoroMode mode,
    std::int64_t seconds) noexcept {
    const auto normalized = normalized_duration_seconds(seconds);
    if (mode == PomodoroMode::focus) {
        focus_duration_seconds_ = normalized;
    } else {
        rest_duration_seconds_ = normalized;
    }
    if (mode_ == mode) {
        reset();
    }
}

void PomodoroEngine::start(std::int64_t now_unix_ms) noexcept {
    if (phase_ == PomodoroPhase::running) {
        return;
    }
    if (phase_ == PomodoroPhase::idle) {
        remaining_when_paused_ms_ = duration_milliseconds(duration_seconds(mode_));
    }
    deadline_unix_ms_ = deadline_after(now_unix_ms, remaining_when_paused_ms_);
    phase_ = PomodoroPhase::running;
}

void PomodoroEngine::pause(std::int64_t now_unix_ms) noexcept {
    if (phase_ != PomodoroPhase::running) {
        return;
    }
    remaining_when_paused_ms_ = remaining_milliseconds(now_unix_ms);
    deadline_unix_ms_.reset();
    phase_ = PomodoroPhase::paused;
}

void PomodoroEngine::reset() noexcept {
    phase_ = PomodoroPhase::idle;
    deadline_unix_ms_.reset();
    remaining_when_paused_ms_ = duration_milliseconds(duration_seconds(mode_));
}

bool PomodoroEngine::complete_if_needed(std::int64_t now_unix_ms) noexcept {
    if (phase_ != PomodoroPhase::running
        || remaining_milliseconds(now_unix_ms) > 0) {
        return false;
    }
    mode_ = next_mode(mode_);
    reset();
    return true;
}

void PomodoroEngine::start_with_remaining_seconds(
    std::int64_t seconds,
    std::int64_t now_unix_ms) noexcept {
    remaining_when_paused_ms_ = duration_milliseconds(
        std::max<std::int64_t>(0, seconds));
    deadline_unix_ms_ = deadline_after(now_unix_ms, remaining_when_paused_ms_);
    phase_ = PomodoroPhase::running;
}

std::string PomodoroEngine::format_clock(
    std::int64_t remaining_seconds,
    bool always_include_hours) {
    const auto total = std::max<std::int64_t>(0, remaining_seconds);
    const auto hours = total / 3'600;
    const auto minutes = (total / 60) % 60;
    const auto seconds = total % 60;

    std::ostringstream result;
    result << std::setfill('0');
    if (always_include_hours || hours > 0) {
        result << std::setw(2) << hours << ':';
    }
    result << std::setw(2) << (hours > 0 ? minutes : total / 60)
           << ':' << std::setw(2) << seconds;
    return result.str();
}

std::int64_t PomodoroEngine::normalized_duration_seconds(
    std::int64_t seconds) noexcept {
    return std::max<std::int64_t>(1, seconds);
}

std::int64_t PomodoroEngine::duration_milliseconds(
    std::int64_t seconds) noexcept {
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    if (seconds > maximum / 1'000) {
        return maximum;
    }
    return std::max<std::int64_t>(0, seconds) * 1'000;
}

std::int64_t PomodoroEngine::deadline_after(
    std::int64_t now_unix_ms,
    std::int64_t duration_ms) noexcept {
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    if (duration_ms >= maximum || now_unix_ms > maximum - duration_ms) {
        return maximum;
    }
    return now_unix_ms + duration_ms;
}

PomodoroMode PomodoroEngine::next_mode(PomodoroMode mode) noexcept {
    return mode == PomodoroMode::focus
        ? PomodoroMode::rest
        : PomodoroMode::focus;
}

}  // namespace zisla::core
