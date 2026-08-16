#include "zisla/core/SideNoticeQueue.hpp"

#include <array>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

IslandNotice notice(
    std::string id,
    NoticeSide side = NoticeSide::right,
    std::string title = "Notice") {
    return {
        .id = std::move(id),
        .title = std::move(title),
        .side = side,
    };
}

void ordinaryCapacityDoesNotCountCollapsedStatuses() {
    SideNoticeQueue queue;
    for (int index = 0; index < 5; ++index) {
        queue.enqueue(
            notice("ai-active-codex-" + std::to_string(index)),
            1'000,
            std::nullopt);
    }
    for (int index = 0; index < 4; ++index) {
        queue.enqueue(
            notice("ordinary-" + std::to_string(index)),
            1'000,
            std::nullopt);
    }

    const auto state = queue.view_state(NoticeSide::right);
    expect(state.compact_notice
            && state.compact_notice->id == "ai-active-codex-0"
            && state.compact_count == 5,
        "collapsed AI activity should retain every active item behind one presentation");
    expect(state.ordinary_notices.size() == 3
            && state.ordinary_notices[0].id == "ordinary-1"
            && state.ordinary_notices[2].id == "ordinary-3",
        "ordinary capacity should evict only the oldest ordinary notice");
}

void duplicateIDsReplaceAcrossSides() {
    SideNoticeQueue queue;
    queue.enqueue(notice("same", NoticeSide::left, "Old"), 1'000, std::nullopt);
    queue.enqueue(notice("same", NoticeSide::right, "New"), 2'000, std::nullopt);

    expect(queue.notices(NoticeSide::left).empty(),
        "replacing an id should remove its old side entry");
    const auto right = queue.notices(NoticeSide::right);
    expect(right.size() == 1 && right[0].title == "New",
        "replacing an id should append the new notice on its requested side");
}

void pairedBatchAppearsOnBothSidesTogether() {
    SideNoticeQueue queue;
    const std::array pair{
        notice("message-pair-left", NoticeSide::left, "Alice"),
        notice("message-pair-right", NoticeSide::right, "Hello"),
    };

    queue.enqueue_all(pair, 3'000);

    expect(queue.notices(NoticeSide::left) == std::vector{pair[0]}
            && queue.notices(NoticeSide::right) == std::vector{pair[1]},
        "one queue update should publish both halves of a paired message");
}

void temporaryExpiryPausesWhileHoveredAndRestartsForThreeSeconds() {
    SideNoticeQueue queue;
    queue.enqueue(notice("temporary"), 1'000);
    expect(queue.next_expiration_ms() == 7'000,
        "temporary notices should default to six seconds");
    expect(queue.remove_expired(6'999) == 0,
        "temporary notices should remain before their deadline");

    expect(queue.set_hovered("temporary", true, 2'000),
        "hover should find the visible notice");
    expect(!queue.next_expiration_ms(),
        "hover should pause a temporary notice expiry");
    expect(queue.remove_expired(20'000) == 0,
        "a hovered notice should not expire even after its old deadline");

    expect(queue.set_hovered("temporary", false, 20'000),
        "pointer exit should find the visible notice");
    expect(queue.next_expiration_ms() == 23'000,
        "leaving a notice should start a fresh three-second deadline");
    expect(queue.remove_expired(22'999) == 0
            && queue.remove_expired(23'000) == 1
            && queue.empty(),
        "the restarted deadline should expire exactly once");
}

void persistentNoticeRequiresExplicitRemoval() {
    SideNoticeQueue queue;
    queue.enqueue(notice("persistent", NoticeSide::left), 1'000, std::nullopt);

    expect(queue.set_hovered("persistent", false, 2'000),
        "persistent notice hover updates should still report the id");
    expect(!queue.next_expiration_ms() && queue.remove_expired(100'000) == 0,
        "hover changes must not make a persistent notice temporary");
    expect(queue.remove("persistent") && queue.empty(),
        "persistent notices should support explicit dismissal");
}

void updateOnlyRefreshesVisibleContentWithoutRestartingExpiry() {
    SideNoticeQueue queue;
    queue.enqueue(notice("visible", NoticeSide::right, "Old"), 1'000);

    expect(queue.update_if_present(
            notice("visible", NoticeSide::right, "Updated")),
        "a visible notice should accept a content update");
    expect(queue.notices(NoticeSide::right)[0].title == "Updated"
            && queue.next_expiration_ms() == 7'000,
        "content updates should preserve the original expiry deadline");
    expect(!queue.update_if_present(notice("missing")),
        "updating a missing notice should not insert it");
}

void compactStatusUsesConfiguredPriority() {
    SideNoticeQueue queue;
    queue.enqueue(notice("media-active-right"), 1'000, std::nullopt);
    queue.enqueue(notice("ai-active-codex"), 1'000, std::nullopt);
    queue.enqueue(notice("focus-transition"), 1'000, std::nullopt);

    expect(queue.view_state(NoticeSide::right).compact_notice->id
            == "focus-transition",
        "default compact priority should select transient state first");
    const std::array priorities{
        CompactStatusPriority::media,
        CompactStatusPriority::ai_activity,
    };
    expect(queue.view_state(NoticeSide::right, priorities).compact_notice->id
            == "media-active-right",
        "custom compact priority should select the first available category");
}

void hoveringACompactRowPausesItsWholeGroup() {
    SideNoticeQueue queue;
    queue.enqueue(notice("ai-active-codex-1"), 1'000);
    queue.enqueue(notice("ai-active-codex-2"), 1'000);

    expect(queue.set_hovered("ai-active-codex-1", true, 2'000),
        "the visible compact row should be hoverable");
    expect(!queue.next_expiration_ms(),
        "hovering one compact row should pause every represented item");
    expect(queue.set_hovered("ai-active-codex-1", false, 20'000),
        "the visible compact row should resume its group");
    expect(queue.next_expiration_ms() == 23'000
            && queue.remove_expired(23'000) == 2,
        "leaving a compact row should apply one three-second deadline to the group");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"ordinary capacity excludes collapsed statuses", ordinaryCapacityDoesNotCountCollapsedStatuses},
        {"duplicate ids replace across sides", duplicateIDsReplaceAcrossSides},
        {"paired batch publishes both sides", pairedBatchAppearsOnBothSidesTogether},
        {"temporary expiry pauses on hover", temporaryExpiryPausesWhileHoveredAndRestartsForThreeSeconds},
        {"persistent notices require removal", persistentNoticeRequiresExplicitRemoval},
        {"updates preserve expiry", updateOnlyRefreshesVisibleContentWithoutRestartingExpiry},
        {"compact status honors priority", compactStatusUsesConfiguredPriority},
        {"compact hover pauses its group", hoveringACompactRowPausesItsWholeGroup},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }

    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
