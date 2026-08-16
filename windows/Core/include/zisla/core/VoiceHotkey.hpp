#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace zisla::core {

enum class VoiceHotkeyAction {
    toggle,
    push_to_talk,
};

enum class VoiceHotkeyPreset {
    control_alt_v,
    control_alt_space,
    control_alt_r,
};

enum class VoiceHotkeyEvent {
    pressed,
    released,
};

enum class VoiceHotkeyCommand {
    none,
    toggle_voice_input,
    start_voice_input,
    stop_voice_input,
};

[[nodiscard]] constexpr VoiceHotkeyPreset default_voice_hotkey_preset() noexcept {
    return VoiceHotkeyPreset::control_alt_v;
}

[[nodiscard]] std::string_view voice_hotkey_action_token(
    VoiceHotkeyAction action) noexcept;

[[nodiscard]] std::string voice_hotkey_action_display_name(
    VoiceHotkeyAction action);

[[nodiscard]] std::optional<VoiceHotkeyAction> voice_hotkey_action_from_token(
    std::string_view token) noexcept;

[[nodiscard]] std::string_view voice_hotkey_preset_token(
    VoiceHotkeyPreset preset) noexcept;

[[nodiscard]] std::string voice_hotkey_preset_display_name(
    VoiceHotkeyPreset preset);

[[nodiscard]] std::optional<VoiceHotkeyPreset> voice_hotkey_preset_from_token(
    std::string_view token) noexcept;

[[nodiscard]] VoiceHotkeyCommand voice_hotkey_command(
    VoiceHotkeyAction action,
    VoiceHotkeyEvent event) noexcept;

}  // namespace zisla::core
