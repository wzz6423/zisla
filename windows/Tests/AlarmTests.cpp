#include "zisla/core/Alarm.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-alarm-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

AlarmItem alarm(
    std::string id,
    int hour,
    int minute,
    AlarmWeekdayMask weekdays = 0,
    std::int64_t one_shot_fire_unix_ms = 0) {
    return {
        .id = std::move(id),
        .hour = hour,
        .minute = minute,
        .weekday_mask = weekdays,
        .one_shot_fire_unix_ms = one_shot_fire_unix_ms,
    };
}

void normalizationMatchesTheMacProductContract() {
    auto value = alarm("normalized", 30, -5, 0xff, 123);
    value = AlarmBook::normalized(std::move(value));

    expect(value.hour == 23 && value.minute == 0,
        "time values should clamp to a valid 24-hour clock");
    expect(value.weekday_mask == 0x7f,
        "invalid weekday bits should be removed");
    expect(value.repeating() && value.one_shot_fire_unix_ms == 0,
        "repeating alarms should not retain a one-shot timestamp");
    expect(AlarmBook::format_time(alarm("clock", 7, 5)) == "07:05",
        "alarm time should use two digits");
    expect(AlarmBook::format_repeat(0) == "仅一次"
            && AlarmBook::format_repeat(0x7f) == "每天"
            && AlarmBook::format_repeat(0x3e) == "工作日"
            && AlarmBook::format_repeat(0x41) == "周末"
            && AlarmBook::format_repeat(static_cast<AlarmWeekdayMask>(
                alarm_weekday_bit(2) | alarm_weekday_bit(4))) == "周一 周三",
        "repeat text should match the macOS product wording");
}

void repeatingOccurrencesPickTheNearestSelectedDays() {
    const AlarmLocalClock sunday_noon{
        .weekday = 1,
        .hour = 12,
        .minute = 0,
        .second = 30,
        .now_unix_ms = 1'000,
    };
    const auto weekdays = static_cast<AlarmWeekdayMask>(
        alarm_weekday_bit(1) | alarm_weekday_bit(2));
    const auto values = AlarmBook::upcoming_repeating_occurrences(
        alarm("weekly", 7, 0, weekdays), sunday_noon, 4);

    expect(values == std::vector<AlarmOccurrence>{
            {1, 7, 0},
            {7, 7, 0},
            {8, 7, 0},
            {14, 7, 0},
        },
        "a passed Sunday alarm should advance to Monday then repeat weekly");

    const auto later_today = AlarmBook::upcoming_repeating_occurrences(
        alarm("today", 18, 30, alarm_weekday_bit(1)), sunday_noon, 1);
    expect(later_today == std::vector<AlarmOccurrence>{{0, 18, 30}},
        "a selected time later today should stay on the same day");
}

void nextAlarmComparesOneShotAndRepeatingSchedules() {
    AlarmBook book({
        alarm("one-shot", 13, 0, 0, 90'000),
        alarm("weekly", 12, 5, alarm_weekday_bit(1)),
    });
    const auto next = book.next_alarm({
        .weekday = 1,
        .hour = 12,
        .minute = 0,
        .second = 0,
        .now_unix_ms = 0,
    });

    expect(next.has_value() && next->alarm.id == "one-shot"
            && next->fire_unix_ms == 90'000,
        "the nearest absolute one-shot alarm should beat a later repeat");
}

void oneShotAlarmsDisableAfterTheirStoredFireTime() {
    AlarmBook book({alarm("once", 8, 0, 0, 10'000)});

    expect(!book.reconcile(9'999),
        "a future one-shot alarm should remain enabled");
    expect(book.reconcile(10'000),
        "a due one-shot alarm should change state");
    expect(!book.alarms().front().enabled,
        "a fired one-shot alarm should remain in the list but be disabled");
    expect(!book.reconcile(11'000),
        "reconciling an already disabled alarm should be idempotent");
}

void oneShotDeliveryGraceUsesASaturatingDeadline() {
    AlarmBook book({alarm("once", 8, 0, 0, 10'000)});

    expect(!book.reconcile(14'999, 5'000),
        "a one-shot alarm should remain enabled during its delivery window");
    expect(book.reconcile(15'000, 5'000),
        "a one-shot alarm should disable when its delivery window ends");
    expect(AlarmBook::delivery_deadline(
            std::numeric_limits<std::int64_t>::max() - 10,
            20) == std::numeric_limits<std::int64_t>::max(),
        "delivery deadline calculation should saturate at int64 max");
}

void bookCrudSortsAndRejectsInvalidIdentity() {
    AlarmBook book;
    expect(book.add(alarm("later", 18, 0, 0, 100'000)),
        "a valid alarm should be added");
    expect(book.add(alarm("earlier", 7, 30, 0, 50'000)),
        "a second valid alarm should be added");
    expect(!book.add(alarm("later", 9, 0, 0, 60'000)),
        "duplicate ids should be rejected");
    expect(!book.add(alarm("", 9, 0, 0, 60'000)),
        "empty ids should be rejected");
    expect(book.alarms().front().id == "earlier",
        "alarms should sort by time");

    auto changed = *book.find("later");
    changed.hour = 6;
    changed.label = "Morning";
    expect(book.update(changed), "an existing alarm should update");
    expect(book.alarms().front().id == "later"
            && book.alarms().front().label == "Morning",
        "updating time should restore sorted order");
    expect(book.remove("earlier") && !book.remove("missing"),
        "remove should report whether an alarm existed");
}

void repositoryPersistsAtomicReplacementAcrossInstances() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    const std::vector initial{
        alarm("work", 9, 15, static_cast<AlarmWeekdayMask>(
            alarm_weekday_bit(2) | alarm_weekday_bit(4))),
        alarm("once", 18, 30, 0, 123'456),
    };
    {
        const AlarmRepository repository(state);
        repository.replace(initial);
    }

    const AlarmRepository reopened(state);
    auto loaded = reopened.load();
    expect(loaded == AlarmBook(initial).alarms(),
        "a reopened repository should restore normalized alarms");

    loaded.erase(loaded.begin());
    loaded.front().enabled = false;
    reopened.replace(loaded);
    const auto replaced = AlarmRepository(state).load();
    expect(replaced.size() == 1 && replaced.front().id == "once"
            && !replaced.front().enabled,
        "replacement should atomically persist updates and removals");
}

void capacityKeepsTheFirstSixtyFourNormalizedAlarms() {
    std::vector<AlarmItem> values;
    for (std::size_t index = 0; index < AlarmBook::maximum_alarms + 3; ++index) {
        values.push_back(alarm(
            "alarm-" + std::to_string(index),
            static_cast<int>(index % 24),
            static_cast<int>(index % 60),
            alarm_weekday_bit(2)));
    }

    expect(AlarmBook(std::move(values)).alarms().size()
            == AlarmBook::maximum_alarms,
        "the alarm book should enforce its scheduling capacity");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"normalization matches product", normalizationMatchesTheMacProductContract},
        {"repeating occurrences pick nearest days", repeatingOccurrencesPickTheNearestSelectedDays},
        {"next alarm compares schedules", nextAlarmComparesOneShotAndRepeatingSchedules},
        {"one-shot alarms disable after firing", oneShotAlarmsDisableAfterTheirStoredFireTime},
        {"one-shot delivery grace saturates", oneShotDeliveryGraceUsesASaturatingDeadline},
        {"book CRUD sorts and validates", bookCrudSortsAndRejectsInvalidIdentity},
        {"repository persists replacement", repositoryPersistsAtomicReplacementAcrossInstances},
        {"capacity is enforced", capacityKeepsTheFirstSixtyFourNormalizedAlarms},
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
