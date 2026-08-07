#include "zisla/core/CompactStatusSelector.hpp"

#include <algorithm>

namespace zisla::core {

std::array<CompactStatusPriority, CompactStatusSelector::priority_count>
CompactStatusSelector::normalized(
    std::span<const CompactStatusPriority> priorities) noexcept {
    std::array<CompactStatusPriority, priority_count> result{};
    std::array<bool, priority_count> seen{};
    std::size_t write_position = 0;

    for (const auto priority : priorities) {
        const auto index = static_cast<std::size_t>(priority);
        if (index < priority_count && !seen[index]) {
            seen[index] = true;
            result[write_position++] = priority;
        }
    }

    for (const auto priority : default_order()) {
        const auto index = static_cast<std::size_t>(priority);
        if (!seen[index]) {
            result[write_position++] = priority;
        }
    }

    return result;
}

std::optional<CompactStatusPriority> CompactStatusSelector::select(
    std::span<const CompactStatusPriority> priorities,
    std::span<const CompactStatusPriority> available) noexcept {
    for (const auto priority : normalized(priorities)) {
        if (std::find(available.begin(), available.end(), priority) != available.end()) {
            return priority;
        }
    }
    return std::nullopt;
}

}  // namespace zisla::core
