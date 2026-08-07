#include "zisla/core/Teleprompter.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace zisla::core {

TeleprompterEngine::TeleprompterEngine(
    std::string script,
    double scroll_speed)
    : script_(std::move(script)),
      scroll_speed_(normalized_speed(scroll_speed)) {}

const std::string& TeleprompterEngine::script() const noexcept {
    return script_;
}

double TeleprompterEngine::scroll_speed() const noexcept {
    return scroll_speed_;
}

double TeleprompterEngine::scroll_offset() const noexcept {
    return scroll_offset_;
}

bool TeleprompterEngine::auto_scrolling() const noexcept {
    return auto_scrolling_;
}

TeleprompterSnapshot TeleprompterEngine::snapshot() const {
    return {
        .script = script_,
        .scroll_speed = scroll_speed_,
        .scroll_offset = scroll_offset_,
        .auto_scrolling = auto_scrolling_,
    };
}

void TeleprompterEngine::set_script(std::string script) {
    if (script_ == script) {
        return;
    }
    script_ = std::move(script);
    reset();
}

void TeleprompterEngine::set_scroll_speed(double scroll_speed) noexcept {
    scroll_speed_ = normalized_speed(scroll_speed);
}

bool TeleprompterEngine::toggle_auto_scroll() noexcept {
    if (script_.empty()) {
        auto_scrolling_ = false;
        return false;
    }
    auto_scrolling_ = !auto_scrolling_;
    return auto_scrolling_;
}

void TeleprompterEngine::pause() noexcept {
    auto_scrolling_ = false;
}

void TeleprompterEngine::reset() noexcept {
    scroll_offset_ = 0.0;
    auto_scrolling_ = false;
}

void TeleprompterEngine::advance(
    double elapsed_seconds,
    double maximum_offset) noexcept {
    if (!auto_scrolling_ || !std::isfinite(elapsed_seconds)
        || elapsed_seconds <= 0.0) {
        return;
    }

    const auto maximum = std::isfinite(maximum_offset)
        ? std::max(0.0, maximum_offset)
        : 0.0;
    if (maximum <= 0.0) {
        scroll_offset_ = 0.0;
        auto_scrolling_ = false;
        return;
    }

    scroll_offset_ = std::min(
        maximum,
        scroll_offset_ + scroll_speed_ * elapsed_seconds);
    if (scroll_offset_ >= maximum) {
        auto_scrolling_ = false;
    }
}

double TeleprompterEngine::normalized_speed(double value) noexcept {
    if (!std::isfinite(value)) {
        return default_scroll_speed;
    }
    return std::clamp(value, minimum_scroll_speed, maximum_scroll_speed);
}

}  // namespace zisla::core
