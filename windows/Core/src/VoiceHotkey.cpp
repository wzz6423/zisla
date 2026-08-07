#include <zisla/core/VoiceHotkey.hpp>

#include <array>
#include <string_view>

namespace zisla::core {
namespace {

constexpr std::array action_tokens{
    std::string_view{"toggle"},
    std::string_view{"push-to-talk"},
};

constexpr std::array preset_tokens{
    std::string_view{"control-alt-v"},
    std::string_view{"control-alt-space"},
    std::string_view{"control-alt-r"},
};

}

std::string_view voice_hotkey_action_token(VoiceHotkeyAction action) noexcept {
    const auto index = static_cast<std::size_t>(action);
    return index < action_tokens.size()
        ? action_tokens[index]
        : std::string_view{};
}

std::string voice_hotkey_action_display_name(VoiceHotkeyAction action) {
    switch (action) {
    case VoiceHotkeyAction::toggle:
        return "切换";
    case VoiceHotkeyAction::push_to_talk:
        return "按住说话";
    }
    return {};
}

std::optional<VoiceHotkeyAction> voice_hotkey_action_from_token(
    std::string_view token) noexcept {
    for (std::size_t i = 0; i < action_tokens.size(); ++i) {
        if (action_tokens[i] == token) {
            return static_cast<VoiceHotkeyAction>(i);
        }
    }
    return std::nullopt;
}

std::string_view voice_hotkey_preset_token(VoiceHotkeyPreset preset) noexcept {
    const auto index = static_cast<std::size_t>(preset);
    return index < preset_tokens.size()
        ? preset_tokens[index]
        : std::string_view{};
}

std::string voice_hotkey_preset_display_name(VoiceHotkeyPreset preset) {
    switch (preset) {
    case VoiceHotkeyPreset::control_alt_v:
        return "Ctrl+Alt+V";
    case VoiceHotkeyPreset::control_alt_space:
        return "Ctrl+Alt+Space";
    case VoiceHotkeyPreset::control_alt_r:
        return "Ctrl+Alt+R";
    }
    return {};
}

std::optional<VoiceHotkeyPreset> voice_hotkey_preset_from_token(
    std::string_view token) noexcept {
    for (std::size_t i = 0; i < preset_tokens.size(); ++i) {
        if (preset_tokens[i] == token) {
            return static_cast<VoiceHotkeyPreset>(i);
        }
    }
    return std::nullopt;
}

VoiceHotkeyCommand voice_hotkey_command(
    VoiceHotkeyAction action,
    VoiceHotkeyEvent event) noexcept {
    switch (action) {
    case VoiceHotkeyAction::toggle:
        return event == VoiceHotkeyEvent::pressed
            ? VoiceHotkeyCommand::toggle_voice_input
            : VoiceHotkeyCommand::none;
    case VoiceHotkeyAction::push_to_talk:
        return event == VoiceHotkeyEvent::pressed
            ? VoiceHotkeyCommand::start_voice_input
            : VoiceHotkeyCommand::stop_voice_input;
    }
    return VoiceHotkeyCommand::none;
}

}  // namespace zisla::core
