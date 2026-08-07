#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class CalendarItemKind {
    event,
    reminder,
};

struct CalendarEventSnapshot {
    std::string id;
    std::string title;
    std::int64_t start_unix_ms{0};
    std::int64_t end_unix_ms{0};
    bool is_all_day{false};
    std::string calendar_title;
    CalendarItemKind kind{CalendarItemKind::event};
    bool is_completed{false};
    std::optional<std::string> source_identifier;
    bool is_projected_occurrence{false};

    friend bool operator==(
        const CalendarEventSnapshot&,
        const CalendarEventSnapshot&) = default;
};

struct CalendarEventDraft {
    std::string title;
    std::int64_t start_unix_ms{0};
    std::int64_t end_unix_ms{0};
    bool is_all_day{false};

    friend bool operator==(const CalendarEventDraft&, const CalendarEventDraft&) = default;
};

struct CalendarReminderDraft {
    std::string title;
    std::int64_t due_unix_ms{0};
    bool is_all_day{false};

    friend bool operator==(
        const CalendarReminderDraft&,
        const CalendarReminderDraft&) = default;
};

enum class CalendarMutationErrorCode {
    empty_title,
    invalid_date,
    invalid_date_range,
    invalid_recurrence,
    missing_source_identifier,
    action_not_supported,
    calendar_unavailable,
    item_not_found,
};

class CalendarMutationError : public std::runtime_error {
public:
    CalendarMutationError(
        CalendarMutationErrorCode code,
        std::string message);

    [[nodiscard]] CalendarMutationErrorCode code() const noexcept;

private:
    CalendarMutationErrorCode code_;
};

struct CalendarCivilDate {
    int year{2026};
    unsigned month{1};
    unsigned day{1};

    friend bool operator==(const CalendarCivilDate&, const CalendarCivilDate&) = default;
};

struct CalendarWeekday {
    CalendarCivilDate date;
    std::uint8_t weekday{1};
    std::int64_t day_ordinal{0};

    friend bool operator==(const CalendarWeekday&, const CalendarWeekday&) = default;
};

struct CalendarDayInterval {
    std::int64_t start_unix_ms{0};
    std::int64_t end_unix_ms{0};
    std::int64_t day_ordinal{0};
    std::uint8_t weekday{1};

    friend bool operator==(
        const CalendarDayInterval&,
        const CalendarDayInterval&) = default;
};

using CalendarWeekdayMask = std::uint8_t;

[[nodiscard]] constexpr CalendarWeekdayMask calendar_weekday_bit(
    std::uint8_t weekday) noexcept {
    return weekday >= 1 && weekday <= 7
        ? static_cast<CalendarWeekdayMask>(1U << (weekday - 1U))
        : CalendarWeekdayMask{0};
}

enum class CalendarRecurrenceFrequency {
    daily,
    weekly,
};

struct CalendarRecurrenceRule {
    CalendarRecurrenceFrequency frequency{CalendarRecurrenceFrequency::daily};
    unsigned interval{1};
    CalendarWeekdayMask weekday_mask{0};
    std::int64_t source_day_ordinal{0};
    std::uint8_t source_weekday{1};
    std::uint8_t first_weekday{1};
    std::optional<std::int64_t> until_unix_ms;

    friend bool operator==(
        const CalendarRecurrenceRule&,
        const CalendarRecurrenceRule&) = default;
};

struct CalendarProjectionDay {
    CalendarDayInterval interval;
    std::int64_t occurrence_unix_ms{0};

    friend bool operator==(
        const CalendarProjectionDay&,
        const CalendarProjectionDay&) = default;
};

struct CalendarLocalItem {
    std::int64_t id{0};
    CalendarItemKind kind{CalendarItemKind::event};
    std::string title;
    std::int64_t start_unix_ms{0};
    std::int64_t end_unix_ms{0};
    bool is_all_day{false};
    bool is_completed{false};
    std::optional<CalendarRecurrenceRule> recurrence;
    std::int64_t created_at_unix_ms{0};
    std::int64_t modified_at_unix_ms{0};

    friend bool operator==(const CalendarLocalItem&, const CalendarLocalItem&) = default;
};

class CalendarEngine {
public:
    static constexpr int week_day_count = 7;
    static constexpr std::size_t maximum_projected_occurrences = 512;

    [[nodiscard]] static std::string normalized_title(std::string_view title);
    [[nodiscard]] static CalendarEventDraft validated(CalendarEventDraft draft);
    [[nodiscard]] static CalendarReminderDraft validated(CalendarReminderDraft draft);
    [[nodiscard]] static CalendarRecurrenceRule validated(CalendarRecurrenceRule rule);

    [[nodiscard]] static CalendarWeekday civil_day(CalendarCivilDate date);
    [[nodiscard]] static CalendarCivilDate add_days(
        CalendarCivilDate date,
        int offset);

    [[nodiscard]] static std::vector<CalendarWeekday> days_of_week(
        CalendarCivilDate reference,
        std::uint8_t first_weekday = 1);

    [[nodiscard]] static std::vector<CalendarEventSnapshot> events_on_day(
        std::span<const CalendarEventSnapshot> events,
        CalendarDayInterval day);

    [[nodiscard]] static std::vector<CalendarEventSnapshot> prepared_agenda_items(
        std::span<const CalendarEventSnapshot> items);

    [[nodiscard]] static bool item_occurs_on_day(
        const CalendarEventSnapshot& item,
        CalendarDayInterval day) noexcept;

    [[nodiscard]] static std::vector<CalendarEventSnapshot>
        project_reminder_occurrences(
            const CalendarEventSnapshot& source,
            CalendarRecurrenceRule rule,
            std::span<const CalendarProjectionDay> days,
            std::size_t maximum_results = maximum_projected_occurrences);

private:
    [[nodiscard]] static bool sort_agenda_items(
        const CalendarEventSnapshot& lhs,
        const CalendarEventSnapshot& rhs);
};

class CalendarRepositoryError : public std::runtime_error {
public:
    explicit CalendarRepositoryError(std::string message);
};

class CalendarRepository {
public:
    explicit CalendarRepository(std::filesystem::path directory);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] std::optional<CalendarLocalItem> find(std::int64_t id) const;
    [[nodiscard]] std::vector<CalendarLocalItem> load_for_range(
        std::int64_t range_start_unix_ms,
        std::int64_t range_end_unix_ms) const;
    [[nodiscard]] std::int64_t create_event(
        CalendarEventDraft draft,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] std::int64_t create_reminder(
        CalendarReminderDraft draft,
        std::optional<CalendarRecurrenceRule> recurrence,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool update_event(
        std::int64_t id,
        CalendarEventDraft draft,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool update_reminder(
        std::int64_t id,
        CalendarReminderDraft draft,
        std::optional<CalendarRecurrenceRule> recurrence,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool set_reminder_completed(
        std::int64_t id,
        bool completed,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool remove(std::int64_t id) const;

private:
    std::filesystem::path directory_;
};

}  // namespace zisla::core
