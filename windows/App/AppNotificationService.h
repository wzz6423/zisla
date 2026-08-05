#pragma once

#include <zisla/core/Alarm.hpp>
#include <zisla/core/Pomodoro.hpp>

#include <windows.h>
#include <winrt/Microsoft.Windows.AppNotifications.h>

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>

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

    [[nodiscard]] bool start(HWND target, UINT activated_message) noexcept;
    void stop() noexcept;
    [[nodiscard]] bool reschedule_alarms(
        std::span<const zisla::core::AlarmItem> alarms) noexcept;
    [[nodiscard]] bool show_pomodoro_completion(
        zisla::core::PomodoroMode completed_mode,
        std::string_view next_duration) noexcept;

    [[nodiscard]] bool registered() const noexcept;
    [[nodiscard]] const std::string& last_error() const noexcept;
    [[nodiscard]] static std::optional<std::int64_t>
    next_one_shot_fire_unix_ms(int hour, int minute) noexcept;

private:
    void clear_alarm_schedule();
    void set_error(std::string message) noexcept;

    Microsoft::Windows::AppNotifications::AppNotificationManager manager_{nullptr};
    Microsoft::Windows::AppNotifications::AppNotificationManager::NotificationInvoked_revoker
        notification_invoked_revoker_{};
    bool registered_{false};
    std::string last_error_;
};

}  // namespace winrt::Zisla
