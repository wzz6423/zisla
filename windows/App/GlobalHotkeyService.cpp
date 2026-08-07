#include "pch.h"
#include "GlobalHotkeyService.h"

#include <string>
#include <vector>

namespace winrt::Zisla {
namespace {

struct Win32HotkeyBinding {
    UINT modifiers{0};
    UINT virtual_key{0};
};

std::optional<Win32HotkeyBinding> win32_binding_for(
    zisla::core::VoiceHotkeyPreset preset) noexcept {
    constexpr UINT modifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;

    switch (preset) {
    case zisla::core::VoiceHotkeyPreset::control_alt_v:
        return Win32HotkeyBinding{modifiers, static_cast<UINT>('V')};
    case zisla::core::VoiceHotkeyPreset::control_alt_space:
        return Win32HotkeyBinding{modifiers, VK_SPACE};
    case zisla::core::VoiceHotkeyPreset::control_alt_r:
        return Win32HotkeyBinding{modifiers, static_cast<UINT>('R')};
    }
    return std::nullopt;
}

}

GlobalHotkeyService::~GlobalHotkeyService() {
    unregister_raw_input();
    unregister_hotkey();
}

bool GlobalHotkeyService::register_hotkey(
    HWND target,
    zisla::core::VoiceHotkeyAction action,
    zisla::core::VoiceHotkeyPreset preset) noexcept {
    unregister_raw_input();
    unregister_hotkey();

    if (!target) {
        registration_status_ = GlobalHotkeyRegistrationStatus::failed_error;
        return false;
    }

    const auto binding = win32_binding_for(preset);
    if (!binding) {
        registration_status_ = GlobalHotkeyRegistrationStatus::failed_error;
        return false;
    }

    if (!RegisterHotKey(
            target,
            hotkey_id,
            binding->modifiers,
            binding->virtual_key)) {
        const DWORD error = GetLastError();
        registration_status_ = (error == ERROR_HOTKEY_ALREADY_REGISTERED)
            ? GlobalHotkeyRegistrationStatus::failed_conflict
            : GlobalHotkeyRegistrationStatus::failed_error;
        return false;
    }

    target_window_ = target;
    current_action_ = action;
    current_virtual_key_ = binding->virtual_key;

    if (action == zisla::core::VoiceHotkeyAction::push_to_talk
        && !register_raw_input(target)) {
        (void)UnregisterHotKey(target, hotkey_id);
        target_window_ = nullptr;
        current_virtual_key_ = 0;
        registration_status_ = GlobalHotkeyRegistrationStatus::failed_error;
        return false;
    }

    registration_status_ = GlobalHotkeyRegistrationStatus::registered;
    return true;
}

void GlobalHotkeyService::unregister_hotkey() noexcept {
    if (target_window_ && registration_status_ == GlobalHotkeyRegistrationStatus::registered) {
        (void)UnregisterHotKey(target_window_, hotkey_id);
    }
    target_window_ = nullptr;
    current_virtual_key_ = 0;
    registration_status_ = GlobalHotkeyRegistrationStatus::not_registered;
}

bool GlobalHotkeyService::register_raw_input(HWND target) noexcept {
    if (!target || current_virtual_key_ == 0) {
        return false;
    }

    RAWINPUTDEVICE device{};
    device.usUsagePage = 0x01;
    device.usUsage = 0x06;
    device.dwFlags = RIDEV_INPUTSINK;
    device.hwndTarget = target;

    if (!RegisterRawInputDevices(&device, 1, sizeof(device))) {
        return false;
    }

    raw_input_registered_ = true;
    return true;
}

void GlobalHotkeyService::unregister_raw_input() noexcept {
    if (!raw_input_registered_) {
        return;
    }

    RAWINPUTDEVICE device{};
    device.usUsagePage = 0x01;
    device.usUsage = 0x06;
    device.dwFlags = RIDEV_REMOVE;
    device.hwndTarget = nullptr;

    (void)RegisterRawInputDevices(&device, 1, sizeof(device));
    raw_input_registered_ = false;
}

bool GlobalHotkeyService::handle_hotkey(int id) const noexcept {
    return id == hotkey_id
        && registration_status_ == GlobalHotkeyRegistrationStatus::registered;
}

std::optional<bool> GlobalHotkeyService::handle_raw_input(LPARAM lparam) const noexcept {
    if (!raw_input_registered_ || current_virtual_key_ == 0
        || current_action_ != zisla::core::VoiceHotkeyAction::push_to_talk) {
        return std::nullopt;
    }

    UINT size = 0;
    if (GetRawInputData(
            reinterpret_cast<HRAWINPUT>(lparam),
            RID_INPUT,
            nullptr,
            &size,
            sizeof(RAWINPUTHEADER)) != 0) {
        return std::nullopt;
    }

    if (size == 0 || size > 1024) {
        return std::nullopt;
    }

    std::vector<BYTE> buffer(size);
    if (GetRawInputData(
            reinterpret_cast<HRAWINPUT>(lparam),
            RID_INPUT,
            buffer.data(),
            &size,
            sizeof(RAWINPUTHEADER)) != size) {
        return std::nullopt;
    }

    const auto* raw = reinterpret_cast<const RAWINPUT*>(buffer.data());
    if (raw->header.dwType != RIM_TYPEKEYBOARD) {
        return std::nullopt;
    }

    const auto& keyboard = raw->data.keyboard;
    if (keyboard.VKey != current_virtual_key_) {
        return std::nullopt;
    }

    const bool key_up = (keyboard.Flags & RI_KEY_BREAK) != 0;
    return key_up;
}

GlobalHotkeyRegistrationStatus GlobalHotkeyService::status() const noexcept {
    return registration_status_;
}

std::string GlobalHotkeyService::status_message() const {
    switch (registration_status_) {
    case GlobalHotkeyRegistrationStatus::not_registered:
        return "未注册";
    case GlobalHotkeyRegistrationStatus::registered:
        return "已注册";
    case GlobalHotkeyRegistrationStatus::failed_conflict:
        return "快捷键冲突";
    case GlobalHotkeyRegistrationStatus::failed_error:
        return "注册失败";
    }
    return {};
}

zisla::core::VoiceHotkeyAction GlobalHotkeyService::action() const noexcept {
    return current_action_;
}

std::uint32_t GlobalHotkeyService::virtual_key() const noexcept {
    return current_virtual_key_;
}

}
