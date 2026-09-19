#pragma once

#include <array>
#include <cstddef>
#include <optional>
#include <span>

namespace zisla::core {

enum class CompactStatusPriority {
    transient,
    video_download,
    browser_download,
    focus_countdown,
    toolbox_reminder,
    ai_activity,
    media,
    focus_mode,
};

class CompactStatusSelector {
public:
    static constexpr std::size_t priority_count = 8;

    [[nodiscard]] static constexpr std::array<CompactStatusPriority, priority_count>
    default_order() noexcept {
        return {
            CompactStatusPriority::transient,
            CompactStatusPriority::video_download,
            CompactStatusPriority::browser_download,
            CompactStatusPriority::focus_countdown,
            CompactStatusPriority::toolbox_reminder,
            CompactStatusPriority::ai_activity,
            CompactStatusPriority::media,
            CompactStatusPriority::focus_mode,
        };
    }

    [[nodiscard]] static std::array<CompactStatusPriority, priority_count> normalized(
        std::span<const CompactStatusPriority> priorities) noexcept;
    [[nodiscard]] static std::optional<CompactStatusPriority> select(
        std::span<const CompactStatusPriority> priorities,
        std::span<const CompactStatusPriority> available) noexcept;
};

}  // namespace zisla::core
