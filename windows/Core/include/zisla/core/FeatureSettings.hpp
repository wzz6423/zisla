#pragma once

#include <zisla/core/VoiceHotkey.hpp>

#include <string>

namespace zisla::core {

enum class PetSide {
    left,
    right,
};

/// Privacy-sensitive features default to off; core modules default to on.
struct FeatureSettings {
    bool media_enabled{true};
    bool media_show_lyrics_and_info{true};
    bool file_shelf_enabled{true};
    bool clipboard_history_enabled{false};
    bool clipboard_detection_enabled{false};
    bool ai_progress_enabled{true};
    bool ai_agent_enabled{true};
    bool downloader_enabled{true};
    bool video_download_status_enabled{true};
    bool browser_download_status_enabled{true};
    bool calendar_enabled{true};
    bool weather_enabled{true};
    bool mail_enabled{false};
    bool quick_notes_enabled{true};
    bool pdf_tools_enabled{true};
    bool toolbox_enabled{true};
    bool toolbox_reminder_enabled{false};
    bool focus_countdown_status_enabled{true};
    bool system_monitor_enabled{true};
    bool side_notices_enabled{true};
    bool notifications_muted{false};
    bool top_edge_enabled{true};
    bool pet_enabled{true};
    std::string pet_id{"dog"};
    PetSide pet_side{PetSide::right};
    bool voice_input_enabled{false};
    VoiceHotkeyAction voice_hotkey_action{VoiceHotkeyAction::toggle};
    VoiceHotkeyPreset voice_hotkey_preset{VoiceHotkeyPreset::control_alt_v};
    bool update_checks_enabled{true};
    bool automatic_updates_enabled{true};

    friend bool operator==(const FeatureSettings&, const FeatureSettings&) = default;
};

}  // namespace zisla::core
