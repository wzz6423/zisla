#pragma once

#include <zisla/core/Calendar.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct CalendarLocalDateTime {
    zisla::core::CalendarCivilDate date;
    int hour{0};
    int minute{0};
};

struct CalendarServiceSnapshot {
    zisla::core::CalendarCivilDate reference_date;
    std::uint8_t first_weekday{1};
    std::vector<zisla::core::CalendarWeekday> week_days;
    std::vector<zisla::core::CalendarDayInterval> day_intervals;
    std::vector<zisla::core::CalendarEventSnapshot> items;
    std::string error;
    bool loading{true};
};

class CalendarService {
public:
    explicit CalendarService(std::filesystem::path state_directory);
    ~CalendarService();

    CalendarService(const CalendarService&) = delete;
    CalendarService& operator=(const CalendarService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void reload();
    void showCurrentWeek();
    void setReferenceDate(zisla::core::CalendarCivilDate date);
    void createEvent(
        std::string title,
        CalendarLocalDateTime start,
        CalendarLocalDateTime end,
        bool all_day);
    void createReminder(
        std::string title,
        CalendarLocalDateTime due,
        bool all_day);
    void setReminderCompleted(std::int64_t id, bool completed);
    void remove(std::int64_t id);

    [[nodiscard]] static std::int64_t unixMilliseconds(
        CalendarLocalDateTime value);
    [[nodiscard]] static CalendarLocalDateTime localDateTime(
        std::int64_t unix_ms);

    [[nodiscard]] std::shared_ptr<const CalendarServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        reload,
        show_current_week,
        set_reference_date,
        create_event,
        create_reminder,
        set_reminder_completed,
        remove,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        std::int64_t id{0};
        std::string title;
        CalendarLocalDateTime start;
        CalendarLocalDateTime end;
        bool value{false};
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    void publish();
    void publishError(std::string error) noexcept;
    void notify() noexcept;

    zisla::core::CalendarRepository repository_;
    std::atomic<std::shared_ptr<const CalendarServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    zisla::core::CalendarCivilDate reference_date_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
