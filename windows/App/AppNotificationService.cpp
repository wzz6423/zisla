#include "pch.h"
#include "AppNotificationService.h"

#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

#include <algorithm>
#include <chrono>
#include <limits>
#include <string_view>
#include <vector>

namespace winrt::Zisla {
namespace {

using Microsoft::Windows::AppNotifications::AppNotificationManager;
using Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs;
using Microsoft::Windows::AppNotifications::AppNotificationSetting;
using namespace Microsoft::Windows::AppNotifications::Builder;
using Windows::Data::Xml::Dom::XmlDocument;
using Windows::UI::Notifications::ScheduledToastNotification;
using Windows::UI::Notifications::ToastNotificationManager;

constexpr wchar_t alarm_group[] = L"zisla.alarm";
constexpr std::size_t occurrences_per_repeating_alarm = 32;
constexpr std::size_t maximum_scheduled_alarm_notifications =
    zisla::core::AlarmBook::maximum_alarms * occurrences_per_repeating_alarm;
constexpr std::uint64_t filetime_unix_epoch_ticks = 116'444'736'000'000'000ULL;
constexpr std::uint64_t filetime_ticks_per_millisecond = 10'000ULL;
constexpr std::uint64_t filetime_ticks_per_day = 864'000'000'000ULL;

struct ScheduledAlarm {
    const zisla::core::AlarmItem* alarm{nullptr};
    std::int64_t fire_unix_ms{0};
};

std::int64_t now_unix_ms() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::optional<std::int64_t> utc_system_time_to_unix_ms(
    const SYSTEMTIME& utc) noexcept {
    FILETIME file_time{};
    if (!SystemTimeToFileTime(&utc, &file_time)) {
        return std::nullopt;
    }
    ULARGE_INTEGER ticks{};
    ticks.LowPart = file_time.dwLowDateTime;
    ticks.HighPart = file_time.dwHighDateTime;
    if (ticks.QuadPart < filetime_unix_epoch_ticks) {
        return std::nullopt;
    }
    const auto milliseconds =
        (ticks.QuadPart - filetime_unix_epoch_ticks)
        / filetime_ticks_per_millisecond;
    if (milliseconds
        > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) {
        return std::nullopt;
    }
    return static_cast<std::int64_t>(milliseconds);
}

std::optional<std::int64_t> local_occurrence_to_unix_ms(
    SYSTEMTIME local_now,
    int day_offset,
    int hour,
    int minute) noexcept {
    local_now.wHour = 0;
    local_now.wMinute = 0;
    local_now.wSecond = 0;
    local_now.wMilliseconds = 0;

    FILETIME local_file_time{};
    if (!SystemTimeToFileTime(&local_now, &local_file_time)) {
        return std::nullopt;
    }
    ULARGE_INTEGER ticks{};
    ticks.LowPart = local_file_time.dwLowDateTime;
    ticks.HighPart = local_file_time.dwHighDateTime;
    const auto day_ticks = static_cast<std::uint64_t>(std::max(0, day_offset))
        * filetime_ticks_per_day;
    if (ticks.QuadPart > std::numeric_limits<std::uint64_t>::max() - day_ticks) {
        return std::nullopt;
    }
    ticks.QuadPart += day_ticks;
    local_file_time.dwLowDateTime = ticks.LowPart;
    local_file_time.dwHighDateTime = ticks.HighPart;

    SYSTEMTIME local_target{};
    if (!FileTimeToSystemTime(&local_file_time, &local_target)) {
        return std::nullopt;
    }
    local_target.wHour = static_cast<WORD>(std::clamp(hour, 0, 23));
    local_target.wMinute = static_cast<WORD>(std::clamp(minute, 0, 59));

    SYSTEMTIME utc_target{};
    if (!TzSpecificLocalTimeToSystemTimeEx(
            nullptr, &local_target, &utc_target)) {
        return std::nullopt;
    }
    return utc_system_time_to_unix_ms(utc_target);
}

zisla::core::AlarmLocalClock local_clock(std::int64_t unix_ms) noexcept {
    SYSTEMTIME local{};
    GetLocalTime(&local);
    return {
        .weekday = static_cast<std::uint8_t>(local.wDayOfWeek + 1),
        .hour = local.wHour,
        .minute = local.wMinute,
        .second = local.wSecond,
        .now_unix_ms = unix_ms,
    };
}

std::vector<ScheduledAlarm> schedule_candidates(
    std::span<const zisla::core::AlarmItem> alarms) {
    const auto current_unix_ms = now_unix_ms();
    const auto current_clock = local_clock(current_unix_ms);
    SYSTEMTIME local_now{};
    GetLocalTime(&local_now);

    std::vector<ScheduledAlarm> candidates;
    candidates.reserve(std::min(
        maximum_scheduled_alarm_notifications,
        alarms.size() * occurrences_per_repeating_alarm));
    for (const auto& alarm : alarms) {
        if (!alarm.enabled) {
            continue;
        }
        if (!alarm.repeating()) {
            if (alarm.one_shot_fire_unix_ms > current_unix_ms) {
                candidates.push_back({&alarm, alarm.one_shot_fire_unix_ms});
            }
            continue;
        }

        for (const auto& occurrence
             : zisla::core::AlarmBook::upcoming_repeating_occurrences(
                 alarm,
                 current_clock,
                 occurrences_per_repeating_alarm)) {
            const auto fire_time = local_occurrence_to_unix_ms(
                local_now,
                occurrence.day_offset,
                occurrence.hour,
                occurrence.minute);
            if (fire_time && *fire_time > current_unix_ms) {
                candidates.push_back({&alarm, *fire_time});
            }
        }
    }

    std::sort(candidates.begin(), candidates.end(), [](const auto& lhs, const auto& rhs) {
        return lhs.fire_unix_ms < rhs.fire_unix_ms;
    });
    if (candidates.size() > maximum_scheduled_alarm_notifications) {
        candidates.resize(maximum_scheduled_alarm_notifications);
    }
    return candidates;
}

Windows::Foundation::DateTime notification_time(std::int64_t unix_ms) {
    return winrt::clock::from_sys(std::chrono::system_clock::time_point{
        std::chrono::milliseconds{unix_ms},
    });
}

std::wstring alarm_detail(const zisla::core::AlarmItem& alarm) {
    auto detail = to_hstring(zisla::core::AlarmBook::format_time(alarm));
    std::wstring result{detail.c_str(), detail.size()};
    result += L" · ";
    const auto repeat = to_hstring(
        zisla::core::AlarmBook::format_repeat(alarm.weekday_mask));
    result.append(repeat.c_str(), repeat.size());
    return result;
}

AppNotificationAction notification_action(
    const AppNotificationActivatedEventArgs& args) noexcept {
    try {
        const auto arguments = args.Arguments();
        if (!arguments || !arguments.HasKey(L"action")) {
            return AppNotificationAction::open;
        }
        const auto action = arguments.Lookup(L"action");
        if (action == L"alarms") {
            return AppNotificationAction::alarms;
        }
        if (action == L"pomodoro") {
            return AppNotificationAction::pomodoro;
        }
    } catch (...) {
    }
    return AppNotificationAction::open;
}

}  // namespace

AppNotificationService::~AppNotificationService() {
    stop();
}

bool AppNotificationService::start(
    HWND target,
    UINT activated_message,
    UINT alarms_changed_message) noexcept {
    if (registered_) {
        return true;
    }
    if (!target || activated_message == 0 || alarms_changed_message == 0) {
        set_error("Notification activation requires a target window");
        return false;
    }

    try {
        manager_ = AppNotificationManager::Default();
        notification_invoked_token_ = manager_.NotificationInvoked(
            [target, activated_message](
                AppNotificationManager const&,
                AppNotificationActivatedEventArgs const& args) noexcept {
                (void)PostMessageW(
                    target,
                    activated_message,
                    static_cast<WPARAM>(notification_action(args)),
                    0);
            });
        notification_invoked_registered_ = true;
        manager_.Register();
        registered_ = true;
        bool worker_started = false;
        {
            std::lock_guard lock(mutex_);
            target_ = target;
            alarms_changed_message_ = alarms_changed_message;
            running_ = true;
            try {
                thread_ = std::thread([this] { run(); });
                worker_started = true;
            } catch (...) {
                running_ = false;
                target_ = nullptr;
                alarms_changed_message_ = 0;
            }
        }
        if (!worker_started) {
            set_error("Unable to start the alarm notification worker");
            stop();
            return false;
        }
        if (manager_.Setting() != AppNotificationSetting::Enabled) {
            set_error("Windows app notifications are disabled");
            return true;
        }
        set_error({});
        return true;
    } catch (const hresult_error& error) {
        set_error(to_string(error.message()));
    } catch (...) {
        set_error("Unable to register Windows app notifications");
    }
    stop();
    return false;
}

void AppNotificationService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    {
        std::lock_guard lock(mutex_);
        pending_alarms_.reset();
        target_ = nullptr;
        alarms_changed_message_ = 0;
    }
    try {
        if (notification_invoked_registered_ && manager_) {
            manager_.NotificationInvoked(notification_invoked_token_);
            notification_invoked_registered_ = false;
        }
    } catch (...) {
    }
    if (registered_ && manager_) {
        try {
            manager_.Unregister();
        } catch (...) {
        }
    }
    registered_ = false;
    manager_ = nullptr;
}

bool AppNotificationService::reschedule_alarms(
    std::span<const zisla::core::AlarmItem> alarms) noexcept {
    try {
        {
            std::lock_guard lock(mutex_);
            if (!running_) {
                return false;
            }
            pending_alarms_.emplace(alarms.begin(), alarms.end());
        }
        condition_.notify_one();
        return true;
    } catch (...) {
        set_error("Unable to queue alarm notifications");
    }
    return false;
}

bool AppNotificationService::show_pomodoro_completion(
    zisla::core::PomodoroMode completed_mode,
    std::string_view next_duration) noexcept {
    if (!registered_ || !manager_) {
        return false;
    }
    try {
        std::wstring detail = completed_mode == zisla::core::PomodoroMode::focus
            ? L"下一阶段：休息 "
            : L"下一阶段：专注 ";
        const auto duration = to_hstring(next_duration);
        detail.append(duration.c_str(), duration.size());
        const auto notification = AppNotificationBuilder()
            .AddArgument(L"action", L"pomodoro")
            .AddText(completed_mode == zisla::core::PomodoroMode::focus
                ? L"专注完成"
                : L"休息结束")
            .AddText(hstring{detail})
            .BuildNotification();
        manager_.Show(notification);
        return true;
    } catch (const hresult_error& error) {
        set_error(to_string(error.message()));
    } catch (...) {
        set_error("Unable to show the Pomodoro notification");
    }
    return false;
}

bool AppNotificationService::registered() const noexcept {
    return registered_;
}

std::string AppNotificationService::last_error() const noexcept {
    try {
        std::lock_guard lock(mutex_);
        return last_error_;
    } catch (...) {
        return "Unable to read the notification status";
    }
}

std::optional<std::int64_t>
AppNotificationService::next_one_shot_fire_unix_ms(
    int hour,
    int minute) noexcept {
    SYSTEMTIME local_now{};
    GetLocalTime(&local_now);
    const auto target_seconds = std::clamp(hour, 0, 23) * 3'600
        + std::clamp(minute, 0, 59) * 60;
    const auto current_seconds = local_now.wHour * 3'600
        + local_now.wMinute * 60 + local_now.wSecond;
    return local_occurrence_to_unix_ms(
        local_now,
        target_seconds <= current_seconds ? 1 : 0,
        hour,
        minute);
}

void AppNotificationService::clear_alarm_schedule() {
    auto notifier = ToastNotificationManager::CreateToastNotifier();
    const hstring group{alarm_group};
    for (const auto& scheduled : notifier.GetScheduledToastNotifications()) {
        if (scheduled.Group() == group) {
            notifier.RemoveFromSchedule(scheduled);
        }
    }
}

void AppNotificationService::set_error(std::string message) noexcept {
    try {
        std::lock_guard lock(mutex_);
        last_error_ = std::move(message);
    } catch (...) {
    }
}

void AppNotificationService::run() noexcept {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
        {
            std::lock_guard lock(mutex_);
            running_ = false;
            pending_alarms_.reset();
        }
        publish_alarm_error("Unable to initialize the alarm notification worker");
        return;
    }

    while (true) {
        std::vector<zisla::core::AlarmItem> alarms;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return pending_alarms_.has_value() || !running_;
            });
            if (!pending_alarms_ && !running_) {
                break;
            }
            alarms = std::move(*pending_alarms_);
            pending_alarms_.reset();
        }
        publish_alarm_error(reschedule_alarm_notifications(alarms));
    }
    winrt::uninit_apartment();
}

std::string AppNotificationService::reschedule_alarm_notifications(
    std::span<const zisla::core::AlarmItem> alarms) noexcept {
    try {
        clear_alarm_schedule();
        const bool has_enabled_alarm = std::any_of(
            alarms.begin(), alarms.end(), [](const auto& alarm) {
                return alarm.enabled;
            });
        if (!has_enabled_alarm) {
            return {};
        }
        const auto manager = AppNotificationManager::Default();
        if (!manager || manager.Setting() != AppNotificationSetting::Enabled) {
            return "Windows app notifications are unavailable";
        }

        auto notifier = ToastNotificationManager::CreateToastNotifier();
        std::size_t index = 0;
        for (const auto& candidate : schedule_candidates(alarms)) {
            const auto title = candidate.alarm->label.empty()
                ? hstring{L"闹钟"}
                : to_hstring(candidate.alarm->label);
            const auto notification = AppNotificationBuilder()
                .AddArgument(L"action", L"alarms")
                .AddArgument(L"alarmId", to_hstring(candidate.alarm->id))
                .AddText(title)
                .AddText(hstring{alarm_detail(*candidate.alarm)})
                .SetScenario(AppNotificationScenario::Alarm)
                .SetAudioEvent(
                    AppNotificationSoundEvent::Alarm,
                    AppNotificationAudioLooping::Loop)
                .BuildNotification();

            XmlDocument document;
            document.LoadXml(notification.Payload());
            ScheduledToastNotification scheduled(
                document,
                notification_time(candidate.fire_unix_ms));
            scheduled.Tag(hstring{L"a" + std::to_wstring(index++)});
            scheduled.Group(hstring{alarm_group});
            notifier.AddToSchedule(scheduled);
        }
        return {};
    } catch (const hresult_error& error) {
        try {
            clear_alarm_schedule();
        } catch (...) {
        }
        return to_string(error.message());
    } catch (...) {
        try {
            clear_alarm_schedule();
        } catch (...) {
        }
        return "Unable to schedule alarms";
    }
}

void AppNotificationService::publish_alarm_error(std::string error) noexcept {
    HWND target = nullptr;
    UINT message = 0;
    try {
        std::lock_guard lock(mutex_);
        last_error_ = std::move(error);
        target = target_;
        message = alarms_changed_message_;
    } catch (...) {
        return;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}  // namespace winrt::Zisla
