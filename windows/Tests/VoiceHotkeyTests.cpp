#include <zisla/core/VoiceHotkey.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

using namespace zisla::core;

namespace {

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void tokensAndDisplayNamesRoundTrip() {
    expect(voice_hotkey_action_token(VoiceHotkeyAction::toggle) == "toggle",
        "toggle action should have a stable token");
    expect(voice_hotkey_action_token(VoiceHotkeyAction::push_to_talk) == "push-to-talk",
        "push-to-talk action should have a stable token");
    expect(voice_hotkey_action_display_name(VoiceHotkeyAction::toggle) == "切换",
        "toggle action should have a localized display name");
    expect(voice_hotkey_action_display_name(VoiceHotkeyAction::push_to_talk) == "按住说话",
        "push-to-talk action should have a localized display name");
    expect(voice_hotkey_action_from_token("toggle") == VoiceHotkeyAction::toggle,
        "toggle action token should round trip");
    expect(voice_hotkey_action_from_token("push-to-talk")
            == VoiceHotkeyAction::push_to_talk,
        "push-to-talk action token should round trip");
    expect(!voice_hotkey_action_from_token("invalid").has_value(),
        "unknown action token should be rejected");

    expect(voice_hotkey_preset_token(VoiceHotkeyPreset::control_alt_v) == "control-alt-v",
        "V preset should have a stable token");
    expect(voice_hotkey_preset_token(VoiceHotkeyPreset::control_alt_space)
            == "control-alt-space",
        "Space preset should have a stable token");
    expect(voice_hotkey_preset_token(VoiceHotkeyPreset::control_alt_r) == "control-alt-r",
        "R preset should have a stable token");
    expect(voice_hotkey_preset_display_name(VoiceHotkeyPreset::control_alt_v) == "Ctrl+Alt+V",
        "V preset should have a display name");
    expect(voice_hotkey_preset_display_name(VoiceHotkeyPreset::control_alt_space)
            == "Ctrl+Alt+Space",
        "Space preset should have a display name");
    expect(voice_hotkey_preset_display_name(VoiceHotkeyPreset::control_alt_r) == "Ctrl+Alt+R",
        "R preset should have a display name");
    expect(voice_hotkey_preset_from_token("control-alt-v")
            == VoiceHotkeyPreset::control_alt_v,
        "V preset token should round trip");
    expect(voice_hotkey_preset_from_token("control-alt-space")
            == VoiceHotkeyPreset::control_alt_space,
        "Space preset token should round trip");
    expect(voice_hotkey_preset_from_token("control-alt-r")
            == VoiceHotkeyPreset::control_alt_r,
        "R preset token should round trip");
    expect(!voice_hotkey_preset_from_token("invalid").has_value(),
        "unknown preset token should be rejected");
    expect(default_voice_hotkey_preset() == VoiceHotkeyPreset::control_alt_v,
        "default preset should avoid the Windows system menu shortcut");
}

void toggleCommandsOnlyOnKeyPress() {
    expect(voice_hotkey_command(
               VoiceHotkeyAction::toggle,
               VoiceHotkeyEvent::pressed)
            == VoiceHotkeyCommand::toggle_voice_input,
        "toggle hotkey press should toggle dictation");
    expect(voice_hotkey_command(
               VoiceHotkeyAction::toggle,
               VoiceHotkeyEvent::released)
            == VoiceHotkeyCommand::none,
        "toggle hotkey release should not change dictation");
}

void pushToTalkStartsAndStopsWithTheKey() {
    expect(voice_hotkey_command(
               VoiceHotkeyAction::push_to_talk,
               VoiceHotkeyEvent::pressed)
            == VoiceHotkeyCommand::start_voice_input,
        "push-to-talk press should start dictation");
    expect(voice_hotkey_command(
               VoiceHotkeyAction::push_to_talk,
               VoiceHotkeyEvent::released)
            == VoiceHotkeyCommand::stop_voice_input,
        "push-to-talk release should stop dictation");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"tokens and display names round trip", tokensAndDisplayNamesRoundTrip},
        {"toggle commands only on key press", toggleCommandsOnlyOnKeyPress},
        {"push-to-talk starts and stops with the key", pushToTalkStartsAndStopsWithTheKey},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }

    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
