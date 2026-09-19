#include "pch.h"
#include "CalendarService.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cwchar>
#include <iterator>
#include <limits>
#include <optional>
#include <stdexcept>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr std::uint64_t windows_epoch_100ns = 116'444'736'000'000'000ULL;

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

zisla::core::CalendarCivilDate current_local_date() noexcept {
    SYSTEMTIME local{};
    GetLocalTime(&local);
    return {
        .year = local.wYear,
        .month = local.wMonth,
        .day = local.wDay,
    };
}

std::uint8_t first_weekday() noexcept {
    std::array<wchar_t, 8> buffer{};
    const auto length = GetLocaleInfoEx(
        LOCALE_NAME_USER_DEFAULT,
        LOCALE_IFIRSTDAYOFWEEK,
        buffer.data(),
        static_cast<int>(buffer.size()));
    if (length <= 1) {
        return 1;
    }
    wchar_t* end = nullptr;
    const auto value = std::wcstol(buffer.data(), &end, 10);
    return end != buffer.data() && value >= 0 && value <= 6
        ? static_cast<std::uint8_t>(value + 1)
        : std::uint8_t{1};
}

DYNAMIC_TIME_ZONE_INFORMATION current_time_zone() {
    DYNAMIC_TIME_ZONE_INFORMATION zone{};
    if (GetDynamicTimeZoneInformation(&zone) == TIME_ZONE_ID_INVALID) {
        throw std::runtime_error("无法读取系统时区");
    }
    return zone;
}

std::int64_t file_time_to_unix_ms(FILETIME file_time) {
    ULARGE_INTEGER value{};
    value.LowPart = file_time.dwLowDateTime;
    value.HighPart = file_time.dwHighDateTime;
    if (value.QuadPart < windows_epoch_100ns) {
        throw std::runtime_error("日期早于支持范围");
    }
    const auto milliseconds = (value.QuadPart - windows_epoch_100ns) / 10'000ULL;
    if (milliseconds > static_cast<std::uint64_t>(
            std::numeric_limits<std::int64_t>::max())) {
        throw std::runtime_error("日期超出支持范围");
    }
    return static_cast<std::int64_t>(milliseconds);
}

FILETIME unix_ms_to_file_time(std::int64_t unix_ms) {
    if (unix_ms < 0
        || static_cast<std::uint64_t>(unix_ms)
            > (std::numeric_limits<std::uint64_t>::max() - windows_epoch_100ns)
                / 10'000ULL) {
        throw std::runtime_error("日期超出支持范围");
    }
    ULARGE_INTEGER value{};
    value.QuadPart = windows_epoch_100ns
        + static_cast<std::uint64_t>(unix_ms) * 10'000ULL;
    return {
        .dwLowDateTime = value.LowPart,
        .dwHighDateTime = value.HighPart,
    };
}

std::int64_t local_to_unix_ms(
    zisla::core::CalendarCivilDate date,
    int hour,
    int minute,
    int second = 0) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59
        || second < 0 || second > 59) {
        throw std::runtime_error("时间无效");
    }
    (void)zisla::core::CalendarEngine::civil_day(date);
    const SYSTEMTIME local{
        .wYear = static_cast<WORD>(date.year),
        .wMonth = static_cast<WORD>(date.month),
        .wDay = static_cast<WORD>(date.day),
        .wHour = static_cast<WORD>(hour),
        .wMinute = static_cast<WORD>(minute),
        .wSecond = static_cast<WORD>(second),
    };
    SYSTEMTIME utc{};
    const auto zone = current_time_zone();
    if (!TzSpecificLocalTimeToSystemTimeEx(&zone, &local, &utc)) {
        throw std::runtime_error("所选本地时间不存在或无法转换");
    }
    FILETIME file_time{};
    if (!SystemTimeToFileTime(&utc, &file_time)) {
        throw std::runtime_error("无法转换所选时间");
    }
    return file_time_to_unix_ms(file_time);
}

SYSTEMTIME unix_ms_to_local(std::int64_t unix_ms) {
    const auto file_time = unix_ms_to_file_time(unix_ms);
    SYSTEMTIME utc{};
    if (!FileTimeToSystemTime(&file_time, &utc)) {
        throw std::runtime_error("无法读取日程时间");
    }
    SYSTEMTIME local{};
    const auto zone = current_time_zone();
    if (!SystemTimeToTzSpecificLocalTimeEx(&zone, &utc, &local)) {
        throw std::runtime_error("无法转换日程时区");
    }
    return local;
}

zisla::core::CalendarEventSnapshot snapshot_for(
    const zisla::core::CalendarLocalItem& item) {
    const auto source = "local:" + std::to_string(item.id);
    return {
        .id = source,
        .title = item.title,
        .start_unix_ms = item.start_unix_ms,
        .end_unix_ms = item.end_unix_ms,
        .is_all_day = item.is_all_day,
        .calendar_title = "Zisla",
        .kind = item.kind,
        .is_completed = item.is_completed,
        .source_identifier = source,
    };
}

}

CalendarService::CalendarService(std::filesystem::path state_directory)
    : repository_(std::move(state_directory)),
      snapshot_(std::make_shared<const CalendarServiceSnapshot>()),
      reference_date_(current_local_date()) {}

CalendarService::~CalendarService() {
    stop();
}

bool CalendarService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    commands_.push_back({CommandKind::show_current_week});
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void CalendarService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

void CalendarService::reload() {
    enqueue({CommandKind::reload});
}

void CalendarService::showCurrentWeek() {
    enqueue({CommandKind::show_current_week});
}

void CalendarService::setReferenceDate(zisla::core::CalendarCivilDate date) {
    enqueue({
        .kind = CommandKind::set_reference_date,
        .start = {.date = date},
    });
}

void CalendarService::createEvent(
    std::string title,
    CalendarLocalDateTime start,
    CalendarLocalDateTime end,
    bool all_day) {
    enqueue({
        .kind = CommandKind::create_event,
        .title = std::move(title),
        .start = start,
        .end = end,
        .value = all_day,
    });
}

void CalendarService::createReminder(
    std::string title,
    CalendarLocalDateTime due,
    bool all_day) {
    enqueue({
        .kind = CommandKind::create_reminder,
        .title = std::move(title),
        .start = due,
        .value = all_day,
    });
}

void CalendarService::setReminderCompleted(
    std::int64_t id,
    bool completed) {
    if (id > 0) {
        enqueue({
            .kind = CommandKind::set_reminder_completed,
            .id = id,
            .value = completed,
        });
    }
}

void CalendarService::remove(std::int64_t id) {
    if (id > 0) {
        enqueue({
            .kind = CommandKind::remove,
            .id = id,
        });
    }
}

std::int64_t CalendarService::unixMilliseconds(CalendarLocalDateTime value) {
    return local_to_unix_ms(
        value.date,
        value.hour,
        value.minute);
}

CalendarLocalDateTime CalendarService::localDateTime(std::int64_t unix_ms) {
    const auto local = unix_ms_to_local(unix_ms);
    return {
        .date = {
            .year = local.wYear,
            .month = local.wMonth,
            .day = local.wDay,
        },
        .hour = local.wHour,
        .minute = local.wMinute,
    };
}

std::shared_ptr<const CalendarServiceSnapshot>
CalendarService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void CalendarService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        if (command.kind == CommandKind::set_reference_date
            || command.kind == CommandKind::show_current_week) {
            std::erase_if(commands_, [](const auto& pending) {
                return pending.kind == CommandKind::set_reference_date
                    || pending.kind == CommandKind::show_current_week
                    || pending.kind == CommandKind::reload;
            });
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void CalendarService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        try {
            execute(std::move(command));
            publish();
        } catch (const std::exception& error) {
            publishError(error.what());
        } catch (...) {
            publishError("日历存储发生未知错误");
        }
    }
}

void CalendarService::execute(Command command) {
    switch (command.kind) {
    case CommandKind::reload:
        return;
    case CommandKind::show_current_week:
        reference_date_ = current_local_date();
        return;
    case CommandKind::set_reference_date:
        (void)zisla::core::CalendarEngine::civil_day(command.start.date);
        reference_date_ = command.start.date;
        return;
    case CommandKind::create_event: {
        std::int64_t start = 0;
        std::int64_t end = 0;
        if (command.value) {
            start = local_to_unix_ms(command.start.date, 0, 0);
            end = local_to_unix_ms(
                zisla::core::CalendarEngine::add_days(command.end.date, 1),
                0,
                0);
        } else {
            start = local_to_unix_ms(
                command.start.date,
                command.start.hour,
                command.start.minute);
            end = local_to_unix_ms(
                command.end.date,
                command.end.hour,
                command.end.minute);
        }
        (void)repository_.create_event(
            {
                .title = std::move(command.title),
                .start_unix_ms = start,
                .end_unix_ms = end,
                .is_all_day = command.value,
            },
            now_unix_milliseconds());
        reference_date_ = command.start.date;
        return;
    }
    case CommandKind::create_reminder: {
        const auto due = local_to_unix_ms(
            command.start.date,
            command.value ? 0 : command.start.hour,
            command.value ? 0 : command.start.minute);
        (void)repository_.create_reminder(
            {
                .title = std::move(command.title),
                .due_unix_ms = due,
                .is_all_day = command.value,
            },
            std::nullopt,
            now_unix_milliseconds());
        reference_date_ = command.start.date;
        return;
    }
    case CommandKind::set_reminder_completed:
        (void)repository_.set_reminder_completed(
            command.id,
            command.value,
            now_unix_milliseconds());
        return;
    case CommandKind::remove:
        (void)repository_.remove(command.id);
        return;
    }
}

void CalendarService::publish() {
    const auto week_start_day = first_weekday();
    const auto week_start = zisla::core::CalendarEngine::days_of_week(
        reference_date_,
        week_start_day);
    if (week_start.size() != zisla::core::CalendarEngine::week_day_count) {
        throw std::runtime_error("无法计算当前周");
    }

    std::vector<zisla::core::CalendarDayInterval> intervals;
    intervals.reserve(week_start.size());
    for (const auto& day : week_start) {
        intervals.push_back({
            .start_unix_ms = local_to_unix_ms(day.date, 0, 0),
            .end_unix_ms = local_to_unix_ms(
                zisla::core::CalendarEngine::add_days(day.date, 1),
                0,
                0),
            .day_ordinal = day.day_ordinal,
            .weekday = day.weekday,
        });
    }

    const auto stored = repository_.load_for_range(
        intervals.front().start_unix_ms,
        intervals.back().end_unix_ms);
    std::vector<zisla::core::CalendarEventSnapshot> items;
    for (const auto& item : stored) {
        auto source = snapshot_for(item);
        if (!item.recurrence) {
            items.push_back(std::move(source));
            continue;
        }

        const auto source_local = unix_ms_to_local(item.start_unix_ms);
        std::vector<zisla::core::CalendarProjectionDay> projection_days;
        projection_days.reserve(intervals.size());
        for (std::size_t index = 0; index < intervals.size(); ++index) {
            const auto occurrence = item.is_all_day
                ? intervals[index].start_unix_ms
                : local_to_unix_ms(
                    week_start[index].date,
                    source_local.wHour,
                    source_local.wMinute,
                    source_local.wSecond);
            projection_days.push_back({
                .interval = intervals[index],
                .occurrence_unix_ms = occurrence,
            });
        }
        auto occurrences = zisla::core::CalendarEngine::project_reminder_occurrences(
            source,
            *item.recurrence,
            projection_days);
        items.insert(
            items.end(),
            std::make_move_iterator(occurrences.begin()),
            std::make_move_iterator(occurrences.end()));
    }

    auto next = std::make_shared<const CalendarServiceSnapshot>(
        CalendarServiceSnapshot{
            .reference_date = reference_date_,
            .first_weekday = week_start_day,
            .week_days = week_start,
            .day_intervals = std::move(intervals),
            .items = zisla::core::CalendarEngine::prepared_agenda_items(items),
            .loading = false,
        });
    snapshot_.store(std::move(next), std::memory_order_release);
    notify();
}

void CalendarService::publishError(std::string error) noexcept {
    try {
        const auto current = snapshot();
        auto next = std::make_shared<const CalendarServiceSnapshot>(
            CalendarServiceSnapshot{
                .reference_date = current ? current->reference_date : reference_date_,
                .first_weekday = current ? current->first_weekday : first_weekday(),
                .week_days = current
                    ? current->week_days
                    : std::vector<zisla::core::CalendarWeekday>{},
                .day_intervals = current
                    ? current->day_intervals
                    : std::vector<zisla::core::CalendarDayInterval>{},
                .items = current
                    ? current->items
                    : std::vector<zisla::core::CalendarEventSnapshot>{},
                .error = std::move(error),
                .loading = false,
            });
        snapshot_.store(std::move(next), std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void CalendarService::notify() noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
