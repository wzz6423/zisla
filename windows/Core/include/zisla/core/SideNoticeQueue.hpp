#pragma once

#include "zisla/core/AIModels.hpp"
#include "zisla/core/CompactStatusSelector.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>
#include <vector>

namespace zisla::core {

struct SideNoticeQueueConfiguration {
    std::size_t capacity_per_side{3};
    std::int64_t default_expiry_ms{6'000};
    std::int64_t post_hover_expiry_ms{3'000};
};

struct SideNoticeViewState {
    std::optional<IslandNotice> compact_notice;
    std::size_t compact_count{0};
    std::vector<IslandNotice> ordinary_notices;

    friend bool operator==(const SideNoticeViewState&, const SideNoticeViewState&) = default;
};

class SideNoticeQueue {
public:
    explicit SideNoticeQueue(SideNoticeQueueConfiguration configuration = {});

    void enqueue(IslandNotice notice, std::int64_t now_ms);
    void enqueue(
        IslandNotice notice,
        std::int64_t now_ms,
        std::optional<std::int64_t> expires_after_ms);
    void enqueue_all(
        std::span<const IslandNotice> notices,
        std::int64_t now_ms);
    void enqueue_all(
        std::span<const IslandNotice> notices,
        std::int64_t now_ms,
        std::optional<std::int64_t> expires_after_ms);

    [[nodiscard]] bool update_if_present(const IslandNotice& notice);
    [[nodiscard]] bool set_hovered(
        std::string_view id,
        bool hovered,
        std::int64_t now_ms);
    [[nodiscard]] bool remove(std::string_view id);
    [[nodiscard]] std::size_t remove_expired(std::int64_t now_ms);
    void clear() noexcept;

    [[nodiscard]] std::vector<IslandNotice> notices(NoticeSide side) const;
    [[nodiscard]] SideNoticeViewState view_state(NoticeSide side) const;
    [[nodiscard]] SideNoticeViewState view_state(
        NoticeSide side,
        std::span<const CompactStatusPriority> priorities) const;
    [[nodiscard]] std::optional<std::int64_t> next_expiration_ms() const noexcept;
    [[nodiscard]] bool empty() const noexcept;

    [[nodiscard]] static bool is_compact_collapsed_notice(
        const IslandNotice& notice) noexcept;

private:
    struct Entry {
        IslandNotice notice;
        bool persistent{false};
        std::optional<std::int64_t> expires_at_ms;
    };

    using Entries = std::vector<Entry>;

    [[nodiscard]] Entries& entries(NoticeSide side) noexcept;
    [[nodiscard]] const Entries& entries(NoticeSide side) const noexcept;
    [[nodiscard]] Entry* find(std::string_view id) noexcept;
    void trim_ordinary_overflow(NoticeSide side);

    SideNoticeQueueConfiguration configuration_;
    Entries left_;
    Entries right_;
};

}  // namespace zisla::core
