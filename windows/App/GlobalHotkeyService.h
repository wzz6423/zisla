#pragma once

#include <zisla/core/VoiceHotkey.hpp>

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>

namespace winrt::Zisla {

enum class GlobalHotkeyRegistrationStatus {
    not_registered,
    registered,
    failed_conflict,
    failed_error,
};

class GlobalHotkeyService {
public:
    GlobalHotkeyService() = default;
    ~GlobalHotkeyService();

    GlobalHotkeyService(const GlobalHotkeyService&) = delete;
    GlobalHotkeyService& operator=(const GlobalHotkeyService&) = delete;

    [[nodiscard]] bool register_hotkey(
        HWND target,
        zisla::core::VoiceHotkeyAction action,
        zisla::core::VoiceHotkeyPreset preset) noexcept;

    void unregister_hotkey() noexcept;

    [[nodiscard]] bool register_raw_input(HWND target) noexcept;
    void unregister_raw_input() noexcept;

    [[nodiscard]] bool handle_hotkey(int id) const noexcept;
    [[nodiscard]] std::optional<bool> handle_raw_input(
        LPARAM lparam) const noexcept;

    [[nodiscard]] GlobalHotkeyRegistrationStatus status() const noexcept;
    [[nodiscard]] std::string status_message() const;
    [[nodiscard]] zisla::core::VoiceHotkeyAction action() const noexcept;
    [[nodiscard]] std::uint32_t virtual_key() const noexcept;

private:
    static constexpr int hotkey_id = 1;

    HWND target_window_{nullptr};
    zisla::core::VoiceHotkeyAction current_action_{
        zisla::core::VoiceHotkeyAction::toggle};
    std::uint32_t current_virtual_key_{0};
    GlobalHotkeyRegistrationStatus registration_status_{
        GlobalHotkeyRegistrationStatus::not_registered};
    bool raw_input_registered_{false};
};

}
