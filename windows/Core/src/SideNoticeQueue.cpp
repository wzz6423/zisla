#include "zisla/core/SideNoticeQueue.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace zisla::core {
namespace {

std::int64_t deadline(std::int64_t now_ms, std::int64_t duration_ms) noexcept {
    const auto duration = std::max<std::int64_t>(0, duration_ms);
    const auto maximum = std::numeric_limits<std::int64_t>::max();
    return now_ms > maximum - duration
        ? maximum
        : now_ms + duration;
}

std::optional<CompactStatusPriority> compact_priority(
    const IslandNotice& notice) noexcept {
    const auto& id = notice.id;
    if (id.starts_with("focus-transition")
        || notice.style == NoticeStyle::headphone) {
        return CompactStatusPriority::transient;
    }
    if (id.starts_with("video-download-")) {
        return CompactStatusPriority::video_download;
    }
    if (id.starts_with("browser-download-")) {
        return CompactStatusPriority::browser_download;
    }
    if (id.starts_with("focus-countdown-")) {
        return CompactStatusPriority::focus_countdown;
    }
    if (id.starts_with("toolbox-reminder-")) {
        return CompactStatusPriority::toolbox_reminder;
    }
    if (id.starts_with("ai-active-")) {
        return CompactStatusPriority::ai_activity;
    }
    if (id.starts_with("media-active-")) {
        return CompactStatusPriority::media;
    }
    if (id.starts_with("focus-mode-")) {
        return CompactStatusPriority::focus_mode;
    }
    return std::nullopt;
}

}  // namespace

SideNoticeQueue::SideNoticeQueue(SideNoticeQueueConfiguration configuration)
    : configuration_(configuration) {
    configuration_.capacity_per_side = std::max<std::size_t>(
        1,
        configuration_.capacity_per_side);
    configuration_.default_expiry_ms = std::max<std::int64_t>(
        0,
        configuration_.default_expiry_ms);
    configuration_.post_hover_expiry_ms = std::max<std::int64_t>(
        0,
        configuration_.post_hover_expiry_ms);
}

void SideNoticeQueue::enqueue(IslandNotice notice, std::int64_t now_ms) {
    enqueue(
        std::move(notice),
        now_ms,
        configuration_.default_expiry_ms);
}

void SideNoticeQueue::enqueue(
    IslandNotice notice,
    std::int64_t now_ms,
    std::optional<std::int64_t> expires_after_ms) {
    (void)remove(notice.id);
    const auto side = notice.side;
    Entry entry{
        .notice = std::move(notice),
        .persistent = !expires_after_ms,
    };
    if (expires_after_ms) {
        entry.expires_at_ms = deadline(now_ms, *expires_after_ms);
    }
    entries(side).push_back(std::move(entry));
    trim_ordinary_overflow(side);
}

void SideNoticeQueue::enqueue_all(
    std::span<const IslandNotice> notices,
    std::int64_t now_ms) {
    enqueue_all(notices, now_ms, configuration_.default_expiry_ms);
}

void SideNoticeQueue::enqueue_all(
    std::span<const IslandNotice> notices,
    std::int64_t now_ms,
    std::optional<std::int64_t> expires_after_ms) {
    for (const auto& notice : notices) {
        enqueue(notice, now_ms, expires_after_ms);
    }
}

bool SideNoticeQueue::update_if_present(const IslandNotice& notice) {
    const auto update = [this, &notice](
                            Entries& values,
                            Entries& destination,
                            NoticeSide side) {
        const auto existing = std::find_if(
            values.begin(),
            values.end(),
            [&notice](const Entry& entry) {
                return entry.notice.id == notice.id;
            });
        if (existing == values.end()) {
            return false;
        }
        if (notice.side == side) {
            existing->notice = notice;
            return true;
        }
        auto moved = std::move(*existing);
        values.erase(existing);
        moved.notice = notice;
        destination.push_back(std::move(moved));
        trim_ordinary_overflow(notice.side);
        return true;
    };

    return update(left_, right_, NoticeSide::left)
        || update(right_, left_, NoticeSide::right);
}

bool SideNoticeQueue::set_hovered(
    std::string_view id,
    bool hovered,
    std::int64_t now_ms) {
    auto* entry = find(id);
    if (!entry) {
        return false;
    }
    const auto update = [this, hovered, now_ms](Entry& candidate) {
        if (!candidate.persistent) {
            candidate.expires_at_ms = hovered
                ? std::nullopt
                : std::optional<std::int64_t>{deadline(
                    now_ms,
                    configuration_.post_hover_expiry_ms)};
        }
    };
    const auto priority = compact_priority(entry->notice);
    if (!priority) {
        update(*entry);
        return true;
    }
    for (auto& candidate : entries(entry->notice.side)) {
        if (compact_priority(candidate.notice) == priority) {
            update(candidate);
        }
    }
    return true;
}

bool SideNoticeQueue::remove(std::string_view id) {
    bool removed = false;
    for (auto* values : {&left_, &right_}) {
        const auto original_size = values->size();
        std::erase_if(*values, [id](const Entry& entry) {
            return entry.notice.id == id;
        });
        removed = removed || values->size() != original_size;
    }
    return removed;
}

std::size_t SideNoticeQueue::remove_expired(std::int64_t now_ms) {
    std::size_t removed = 0;
    for (auto* values : {&left_, &right_}) {
        const auto original_size = values->size();
        std::erase_if(*values, [now_ms](const Entry& entry) {
            return entry.expires_at_ms && *entry.expires_at_ms <= now_ms;
        });
        removed += original_size - values->size();
    }
    return removed;
}

void SideNoticeQueue::clear() noexcept {
    left_.clear();
    right_.clear();
}

std::vector<IslandNotice> SideNoticeQueue::notices(NoticeSide side) const {
    std::vector<IslandNotice> result;
    const auto& values = entries(side);
    result.reserve(values.size());
    for (const auto& entry : values) {
        result.push_back(entry.notice);
    }
    return result;
}

SideNoticeViewState SideNoticeQueue::view_state(NoticeSide side) const {
    const auto priorities = CompactStatusSelector::default_order();
    return view_state(side, priorities);
}

SideNoticeViewState SideNoticeQueue::view_state(
    NoticeSide side,
    std::span<const CompactStatusPriority> priorities) const {
    SideNoticeViewState state;
    std::vector<CompactStatusPriority> available;
    for (const auto& entry : entries(side)) {
        if (const auto priority = compact_priority(entry.notice)) {
            available.push_back(*priority);
        } else {
            state.ordinary_notices.push_back(entry.notice);
        }
    }

    const auto selected = CompactStatusSelector::select(priorities, available);
    if (!selected) {
        return state;
    }
    for (const auto& entry : entries(side)) {
        if (compact_priority(entry.notice) != selected) {
            continue;
        }
        if (!state.compact_notice) {
            state.compact_notice = entry.notice;
        }
        ++state.compact_count;
    }
    return state;
}

std::optional<std::int64_t> SideNoticeQueue::next_expiration_ms() const noexcept {
    std::optional<std::int64_t> result;
    for (const auto* values : {&left_, &right_}) {
        for (const auto& entry : *values) {
            if (entry.expires_at_ms
                && (!result || *entry.expires_at_ms < *result)) {
                result = entry.expires_at_ms;
            }
        }
    }
    return result;
}

bool SideNoticeQueue::empty() const noexcept {
    return left_.empty() && right_.empty();
}

bool SideNoticeQueue::is_compact_collapsed_notice(
    const IslandNotice& notice) noexcept {
    return compact_priority(notice).has_value();
}

SideNoticeQueue::Entries& SideNoticeQueue::entries(NoticeSide side) noexcept {
    return side == NoticeSide::left ? left_ : right_;
}

const SideNoticeQueue::Entries& SideNoticeQueue::entries(
    NoticeSide side) const noexcept {
    return side == NoticeSide::left ? left_ : right_;
}

SideNoticeQueue::Entry* SideNoticeQueue::find(std::string_view id) noexcept {
    for (auto* values : {&left_, &right_}) {
        const auto entry = std::find_if(
            values->begin(),
            values->end(),
            [id](const Entry& candidate) {
                return candidate.notice.id == id;
            });
        if (entry != values->end()) {
            return &*entry;
        }
    }
    return nullptr;
}

void SideNoticeQueue::trim_ordinary_overflow(NoticeSide side) {
    auto& values = entries(side);
    auto ordinary_count = static_cast<std::size_t>(std::count_if(
        values.begin(),
        values.end(),
        [](const Entry& entry) {
            return !is_compact_collapsed_notice(entry.notice);
        }));
    while (ordinary_count > configuration_.capacity_per_side) {
        const auto oldest = std::find_if(
            values.begin(),
            values.end(),
            [](const Entry& entry) {
                return !is_compact_collapsed_notice(entry.notice);
            });
        if (oldest == values.end()) {
            break;
        }
        values.erase(oldest);
        --ordinary_count;
    }
}

}  // namespace zisla::core
