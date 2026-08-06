#pragma once

#include <zisla/core/Alarm.hpp>
#include <zisla/core/Pomodoro.hpp>

#include <windows.h>
#include <winrt/Microsoft.Windows.AppNotifications.h>

#include <cstdint>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace winrt::Zisla {

enum class AppNotificationAction : std::uint8_t {
    open,
    alarms,
    pomodoro,
};

class AppNotificationService {
public:
    AppNotificationService() = default;
    ~AppNotificationService();

    AppNotificationService(const AppNotificationService&) = delete;
    AppNotificationService& operator=(const AppNotificationService&) = delete;

    [[nodiscard]] bool start(
        HWND target,
        UINT activated_message,
        UINT alarms_changed_message) noexcept;
    void stop() noexcept;
    [[nodiscard]] bool reschedule_alarms(
        std::span<const zisla::core::AlarmItem> alarms) noexcept;
    [[nodiscard]] bool show_pomodoro_completion(
        zisla::core::PomodoroMode completed_mode,
        std::string_view next_duration) noexcept;

    [[nodiscard]] bool registered() const noexcept;
    [[nodiscard]] std::string last_error() const noexcept;
    [[nodiscard]] static std::optional<std::int64_t>
    next_one_shot_fire_unix_ms(int hour, int minute) noexcept;

private:
    void clear_alarm_schedule();
    void set_error(std::string message) noexcept;
    void run() noexcept;
    [[nodiscard]] std::string reschedule_alarm_notifications(
        std::span<const zisla::core::AlarmItem> alarms) noexcept;
    void publish_alarm_error(std::string error) noexcept;

    Microsoft::Windows::AppNotifications::AppNotificationManager manager_{nullptr};
    Microsoft::Windows::AppNotifications::AppNotificationManager::NotificationInvoked_revoker
        notification_invoked_revoker_{};
    bool registered_{false};
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::optional<std::vector<zisla::core::AlarmItem>> pending_alarms_;
    std::thread thread_;
    bool running_{false};
    HWND target_{nullptr};
    UINT alarms_changed_message_{0};
    std::string last_error_;
};

}  // namespace winrt::Zisla
