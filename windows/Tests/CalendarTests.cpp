#include "zisla/core/Calendar.hpp"

#include <algorithm>
#include <chrono>
#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

template <typename Function>
void expectMutationError(
    Function&& function,
    CalendarMutationErrorCode code,
    std::string_view message) {
    try {
        function();
    } catch (const CalendarMutationError& error) {
        expect(error.code() == code, message);
        return;
    }
    throw std::runtime_error(std::string(message));
}

CalendarDayInterval day(
    std::int64_t start,
    std::int64_t end,
    std::int64_t ordinal,
    std::uint8_t weekday) {
    return {
        .start_unix_ms = start,
        .end_unix_ms = end,
        .day_ordinal = ordinal,
        .weekday = weekday,
    };
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-calendar-" + std::to_string(suffix));
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

void normalizedTitleTrimsWhitespaceAndRejectsEmpty() {
    expect(CalendarEngine::normalized_title("  会议  ") == "会议",
        "标题应去除前后空白");
    expect(CalendarEngine::normalized_title("\t日程\n") == "日程",
        "标题应去除制表符和换行符");
    expectMutationError(
        [] { (void)CalendarEngine::normalized_title("   "); },
        CalendarMutationErrorCode::empty_title,
        "仅空白标题应被拒绝");
}

void mutationDraftsValidateTitleAndDateRange() {
    const auto event = CalendarEngine::validated(CalendarEventDraft{
        .title = "  周会 ",
        .start_unix_ms = 1'000,
        .end_unix_ms = 2'000,
    });
    expect(event.title == "周会", "事件标题应规范化");

    expectMutationError(
        [] {
            (void)CalendarEngine::validated(CalendarEventDraft{
                .title = "无效会议",
                .start_unix_ms = 2'000,
                .end_unix_ms = 2'000,
            });
        },
        CalendarMutationErrorCode::invalid_date_range,
        "结束时间不晚于开始时间时应被拒绝");

    const auto reminder = CalendarEngine::validated(CalendarReminderDraft{
        .title = "  提交周报 ",
        .due_unix_ms = 3'000,
        .is_all_day = true,
    });
    expect(reminder.title == "提交周报" && reminder.is_all_day,
        "待办应保留日期属性并规范化标题");
}

void daysOfWeekUsesCivilDatesWithoutTimezoneAssumptions() {
    const auto monday_first = CalendarEngine::days_of_week(
        {.year = 2026, .month = 8, .day = 5},
        1);
    expect(monday_first.size() == 7, "一周应包含七天");
    expect(monday_first.front().date == CalendarCivilDate{2026, 8, 3}
            && monday_first.front().weekday == 1,
        "2026-08-05 所在周应从周一 2026-08-03 开始");
    expect(monday_first.back().date == CalendarCivilDate{2026, 8, 9}
            && monday_first.back().weekday == 7,
        "该周应在周日 2026-08-09 结束");

    const auto sunday_first = CalendarEngine::days_of_week(
        {.year = 2026, .month = 8, .day = 5},
        7);
    expect(sunday_first.front().date == CalendarCivilDate{2026, 8, 2},
        "周日起始设置应返回 2026-08-02");

    expectMutationError(
        [] {
            (void)CalendarEngine::days_of_week(
                {.year = 2026, .month = 2, .day = 30});
        },
        CalendarMutationErrorCode::invalid_date,
        "无效公历日期应被拒绝");
}

void civilDateDayArithmeticCrossesCalendarBoundaries() {
    expect(CalendarEngine::add_days(
            {.year = 2026, .month = 8, .day = 1},
            -1) == CalendarCivilDate{2026, 7, 31},
        "向前移动一天应跨越月份边界");
    expect(CalendarEngine::add_days(
            {.year = 2024, .month = 2, .day = 28},
            1) == CalendarCivilDate{2024, 2, 29},
        "闰年日期运算应保留 2 月 29 日");
    expect(CalendarEngine::add_days(
            {.year = 2026, .month = 12, .day = 31},
            1) == CalendarCivilDate{2027, 1, 1},
        "向后移动一天应跨越年份边界");
}

void itemOccurrenceUsesExplicitDayBoundaries() {
    constexpr std::int64_t spring_day_start = 1'000'000;
    constexpr std::int64_t spring_day_end = spring_day_start + 23 * 3'600'000;
    const auto spring_day = day(spring_day_start, spring_day_end, 20'000, 7);

    CalendarEventSnapshot late_event{
        .id = "late",
        .title = "夏令时切换日",
        .start_unix_ms = spring_day_end - 1'800'000,
        .end_unix_ms = spring_day_end + 1'800'000,
    };
    expect(CalendarEngine::item_occurs_on_day(late_event, spring_day),
        "事件匹配应使用调用方提供的 23 小时日边界");

    CalendarEventSnapshot next_day{
        .id = "next",
        .title = "次日提醒",
        .start_unix_ms = spring_day_end,
        .end_unix_ms = spring_day_end,
        .kind = CalendarItemKind::reminder,
    };
    expect(!CalendarEngine::item_occurs_on_day(next_day, spring_day),
        "半开区间不应把次日零点归入前一天");
}

void agendaFilteringAndSortingMatchesMacBehavior() {
    const auto selected_day = day(10'000, 20'000, 100, 1);
    std::vector<CalendarEventSnapshot> items{
        {.id = "event-b", .title = "事件 B", .start_unix_ms = 15'000,
         .end_unix_ms = 16'000, .kind = CalendarItemKind::event},
        {.id = "outside", .title = "其他日期", .start_unix_ms = 21'000,
         .end_unix_ms = 22'000, .kind = CalendarItemKind::event},
        {.id = "reminder-a", .title = "提醒 A", .start_unix_ms = 15'000,
         .end_unix_ms = 15'000, .kind = CalendarItemKind::reminder},
        {.id = "event-a", .title = "事件 A", .start_unix_ms = 15'000,
         .end_unix_ms = 16'000, .kind = CalendarItemKind::event},
    };

    const auto filtered = CalendarEngine::events_on_day(items, selected_day);
    const auto sorted = CalendarEngine::prepared_agenda_items(filtered);
    expect(sorted.size() == 3, "应只保留所选日期的三个项目");
    expect(sorted[0].id == "reminder-a"
            && sorted[1].id == "event-a"
            && sorted[2].id == "event-b",
        "同一时间提醒优先，随后按 id 稳定排序");
}

void dailyReminderProjectionIncludesActualAndProjectedOccurrences() {
    CalendarEventSnapshot source{
        .id = "reminder:daily",
        .title = "每日复盘",
        .start_unix_ms = 10'500,
        .end_unix_ms = 10'500,
        .calendar_title = "Zisla",
        .kind = CalendarItemKind::reminder,
        .source_identifier = "daily",
    };
    const CalendarRecurrenceRule rule{
        .frequency = CalendarRecurrenceFrequency::daily,
        .interval = 2,
        .source_day_ordinal = 100,
    };
    const std::vector<CalendarProjectionDay> days{
        {.interval = day(10'000, 20'000, 100, 1), .occurrence_unix_ms = 10'500},
        {.interval = day(20'000, 30'000, 101, 2), .occurrence_unix_ms = 20'500},
        {.interval = day(30'000, 40'000, 102, 3), .occurrence_unix_ms = 30'500},
    };

    const auto result = CalendarEngine::project_reminder_occurrences(
        source, rule, days);
    expect(result.size() == 2, "每两天重复应返回实际发生和第二个投影");
    expect(result[0].start_unix_ms == 10'500
            && !result[0].is_projected_occurrence,
        "原始到期时间应保留为实际发生");
    expect(result[1].start_unix_ms == 30'500
            && result[1].is_projected_occurrence,
        "后续发生应标记为投影");
}

void weeklyReminderProjectionHonorsWeekAnchorAndWeekdays() {
    const auto source_week = CalendarEngine::days_of_week(
        {.year = 2026, .month = 8, .day = 5},
        1);
    const auto source_wednesday = source_week[2].day_ordinal;
    const auto source_monday = source_week[0].day_ordinal;
    CalendarEventSnapshot source{
        .id = "reminder:weekly",
        .title = "隔周例会",
        .start_unix_ms = 30'500,
        .end_unix_ms = 30'500,
        .kind = CalendarItemKind::reminder,
        .source_identifier = "weekly",
    };
    const CalendarRecurrenceRule rule{
        .frequency = CalendarRecurrenceFrequency::weekly,
        .interval = 2,
        .weekday_mask = static_cast<CalendarWeekdayMask>(
            calendar_weekday_bit(1) | calendar_weekday_bit(3)),
        .source_day_ordinal = source_wednesday,
        .source_weekday = 3,
        .first_weekday = 1,
    };
    const std::vector<CalendarProjectionDay> days{
        {.interval = day(30'000, 40'000, source_wednesday, 3), .occurrence_unix_ms = 30'500},
        {.interval = day(80'000, 90'000, source_monday + 7, 1), .occurrence_unix_ms = 80'500},
        {.interval = day(100'000, 110'000, source_monday + 9, 3), .occurrence_unix_ms = 100'500},
        {.interval = day(150'000, 160'000, source_monday + 14, 1), .occurrence_unix_ms = 150'500},
        {.interval = day(170'000, 180'000, source_monday + 16, 3), .occurrence_unix_ms = 170'500},
    };

    const auto result = CalendarEngine::project_reminder_occurrences(
        source, rule, days);
    expect(result.size() == 3, "隔周规则应跳过中间一周");
    expect(result[0].start_unix_ms == 30'500
            && result[1].start_unix_ms == 150'500
            && result[2].start_unix_ms == 170'500,
        "周规则应按周起点和工作日掩码选择发生日期");
}

void completedReminderDoesNotProjectFutureOccurrences() {
    CalendarEventSnapshot source{
        .id = "reminder:done",
        .title = "已完成",
        .start_unix_ms = 10'500,
        .end_unix_ms = 10'500,
        .kind = CalendarItemKind::reminder,
        .is_completed = true,
        .source_identifier = "done",
    };
    const CalendarRecurrenceRule rule{
        .frequency = CalendarRecurrenceFrequency::daily,
        .interval = 1,
        .source_day_ordinal = 100,
    };
    const std::vector<CalendarProjectionDay> days{
        {.interval = day(10'000, 20'000, 100, 1), .occurrence_unix_ms = 10'500},
        {.interval = day(20'000, 30'000, 101, 2), .occurrence_unix_ms = 20'500},
    };

    const auto result = CalendarEngine::project_reminder_occurrences(
        source, rule, days);
    expect(result.size() == 1
            && result[0].is_completed
            && !result[0].is_projected_occurrence,
        "完成待办只保留实际发生，不应投影未来实例");
}

void projectionRejectsInvalidRulesAndCapsResults() {
    CalendarEventSnapshot source{
        .id = "reminder:cap",
        .title = "限制",
        .start_unix_ms = 10'500,
        .end_unix_ms = 10'500,
        .kind = CalendarItemKind::reminder,
        .source_identifier = "cap",
    };
    const std::vector<CalendarProjectionDay> days{
        {.interval = day(10'000, 20'000, 100, 1), .occurrence_unix_ms = 10'500},
        {.interval = day(20'000, 30'000, 101, 2), .occurrence_unix_ms = 20'500},
        {.interval = day(30'000, 40'000, 102, 3), .occurrence_unix_ms = 30'500},
    };

    expectMutationError(
        [&] {
            (void)CalendarEngine::project_reminder_occurrences(
                source,
                CalendarRecurrenceRule{
                    .frequency = CalendarRecurrenceFrequency::daily,
                    .interval = 0,
                    .source_day_ordinal = 100,
                },
                days);
        },
        CalendarMutationErrorCode::invalid_recurrence,
        "零间隔重复规则应被拒绝");

    const auto capped = CalendarEngine::project_reminder_occurrences(
        source,
        CalendarRecurrenceRule{
            .frequency = CalendarRecurrenceFrequency::daily,
            .interval = 1,
            .source_day_ordinal = 100,
        },
        days,
        2);
    expect(capped.size() == 2, "投影结果应遵守调用方上限");
}

void repositoryPersistsCrudAndKindBoundaries() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    CalendarRepository repository(state);
    const auto event_id = repository.create_event(
        {
            .title = "  产品评审 ",
            .start_unix_ms = 10'000,
            .end_unix_ms = 12'000,
        },
        100);
    const auto reminder_id = repository.create_reminder(
        {
            .title = "  提交纪要 ",
            .due_unix_ms = 13'000,
        },
        std::nullopt,
        110);
    expect(event_id > 0 && reminder_id > event_id,
        "本地日程应分配稳定递增标识");

    const CalendarRepository reopened(state);
    const auto event = reopened.find(event_id);
    const auto reminder = reopened.find(reminder_id);
    expect(event && event->title == "产品评审"
            && event->kind == CalendarItemKind::event,
        "重开仓库后应恢复规范化事件");
    expect(reminder && reminder->title == "提交纪要"
            && reminder->kind == CalendarItemKind::reminder,
        "重开仓库后应恢复待办");

    expect(!reopened.set_reminder_completed(event_id, true, 120),
        "事件不能被误更新为已完成待办");
    expect(reopened.set_reminder_completed(reminder_id, true, 130),
        "待办应支持完成状态更新");
    expect(reopened.find(reminder_id)->is_completed,
        "完成状态应持久化");

    expect(!reopened.update_reminder(
            event_id,
            {.title = "错误类型", .due_unix_ms = 15'000},
            std::nullopt,
            140),
        "待办更新不能覆盖事件记录");
    expect(reopened.update_event(
            event_id,
            {.title = "产品终审", .start_unix_ms = 20'000, .end_unix_ms = 22'000},
            150),
        "事件应支持同类型更新");
    expect(reopened.find(event_id)->title == "产品终审",
        "事件更新应持久化");
    expect(reopened.remove(event_id) && !reopened.remove(event_id),
        "删除应准确报告记录是否存在");
}

void repositoryRangeQueryIncludesOverlapsAndActiveRecurrences() {
    TemporaryDirectory temporary;
    CalendarRepository repository(temporary.path() / "state");
    (void)repository.create_event(
        {.title = "跨范围事件", .start_unix_ms = 5'000, .end_unix_ms = 15'000},
        1);
    (void)repository.create_event(
        {.title = "范围外事件", .start_unix_ms = 30'000, .end_unix_ms = 40'000},
        2);
    (void)repository.create_reminder(
        {.title = "范围内待办", .due_unix_ms = 18'000},
        std::nullopt,
        3);
    const auto week = CalendarEngine::days_of_week(
        {.year = 2026, .month = 8, .day = 5},
        1);
    const auto recurring_id = repository.create_reminder(
        {.title = "较早开始的重复待办", .due_unix_ms = 1'000},
        CalendarRecurrenceRule{
            .frequency = CalendarRecurrenceFrequency::weekly,
            .interval = 1,
            .weekday_mask = calendar_weekday_bit(3),
            .source_day_ordinal = week[2].day_ordinal - 7,
            .source_weekday = 3,
            .first_weekday = 1,
        },
        4);

    const auto items = repository.load_for_range(10'000, 20'000);
    expect(items.size() == 3, "范围查询应包含重叠事件、点待办和有效重复待办");
    expect(std::any_of(items.begin(), items.end(), [](const auto& item) {
            return item.title == "跨范围事件";
        }),
        "跨越查询起点的事件应被返回");
    expect(std::any_of(items.begin(), items.end(), [recurring_id](const auto& item) {
            return item.id == recurring_id && item.recurrence.has_value();
        }),
        "首次到期早于范围的活动重复待办仍应被返回用于投影");
}

void repositoryPreservesRecurrenceAndRejectsInvalidEnd() {
    TemporaryDirectory temporary;
    CalendarRepository repository(temporary.path() / "state");
    const auto source_day = CalendarEngine::civil_day(
        {.year = 2026, .month = 8, .day = 3});
    const CalendarRecurrenceRule recurrence{
        .frequency = CalendarRecurrenceFrequency::daily,
        .interval = 2,
        .source_day_ordinal = source_day.day_ordinal,
        .source_weekday = source_day.weekday,
        .first_weekday = 1,
        .until_unix_ms = 50'000,
    };
    const auto id = repository.create_reminder(
        {.title = "两日一次", .due_unix_ms = 10'000, .is_all_day = true},
        recurrence,
        100);
    const auto restored = CalendarRepository(temporary.path() / "state").find(id);
    expect(restored && restored->recurrence == recurrence,
        "重复规则所有字段应跨实例恢复");

    expectMutationError(
        [&] {
            (void)repository.create_reminder(
                {.title = "无效结束", .due_unix_ms = 10'000},
                CalendarRecurrenceRule{
                    .frequency = CalendarRecurrenceFrequency::daily,
                    .interval = 1,
                    .source_day_ordinal = source_day.day_ordinal,
                    .source_weekday = source_day.weekday,
                    .until_unix_ms = 9'999,
                },
                200);
        },
        CalendarMutationErrorCode::invalid_recurrence,
        "重复结束时间早于首次到期时间时应被拒绝");
}

void runTests() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"normalizedTitleTrimsWhitespaceAndRejectsEmpty",
         normalizedTitleTrimsWhitespaceAndRejectsEmpty},
        {"mutationDraftsValidateTitleAndDateRange",
         mutationDraftsValidateTitleAndDateRange},
        {"daysOfWeekUsesCivilDatesWithoutTimezoneAssumptions",
         daysOfWeekUsesCivilDatesWithoutTimezoneAssumptions},
        {"civilDateDayArithmeticCrossesCalendarBoundaries",
         civilDateDayArithmeticCrossesCalendarBoundaries},
        {"itemOccurrenceUsesExplicitDayBoundaries",
         itemOccurrenceUsesExplicitDayBoundaries},
        {"agendaFilteringAndSortingMatchesMacBehavior",
         agendaFilteringAndSortingMatchesMacBehavior},
        {"dailyReminderProjectionIncludesActualAndProjectedOccurrences",
         dailyReminderProjectionIncludesActualAndProjectedOccurrences},
        {"weeklyReminderProjectionHonorsWeekAnchorAndWeekdays",
         weeklyReminderProjectionHonorsWeekAnchorAndWeekdays},
        {"completedReminderDoesNotProjectFutureOccurrences",
         completedReminderDoesNotProjectFutureOccurrences},
        {"projectionRejectsInvalidRulesAndCapsResults",
         projectionRejectsInvalidRulesAndCapsResults},
        {"repositoryPersistsCrudAndKindBoundaries",
         repositoryPersistsCrudAndKindBoundaries},
        {"repositoryRangeQueryIncludesOverlapsAndActiveRecurrences",
         repositoryRangeQueryIncludesOverlapsAndActiveRecurrences},
        {"repositoryPreservesRecurrenceAndRejectsInvalidEnd",
         repositoryPreservesRecurrenceAndRejectsInvalidEnd},
    };

    for (const auto& [name, test] : tests) {
        test();
        std::cout << "[通过] " << name << '\n';
    }
}

}  // namespace

int main() {
    try {
        runTests();
        std::cout << "\n所有日历测试通过\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "\n日历测试失败: " << error.what() << '\n';
        return 1;
    }
}
