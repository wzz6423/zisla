#pragma once

#include "OverlayContent.g.h"
#include "DiskCleanupService.h"
#include "BrowserDownloadService.h"
#include "WeatherService.h"
#include "QuickNotesService.h"
#include "PDFProcessingService.hpp"
#include "AIAgentSkillsService.h"
#include "AIAgentWorkspaceService.h"
#include "SystemMonitorService.h"
#include "CalendarService.h"
#include "MailService.h"

#include <zisla/core/Alarm.hpp>
#include <zisla/core/AIModels.hpp>
#include <zisla/core/CleaningSession.hpp>
#include <zisla/core/ClipboardHistory.hpp>
#include <zisla/core/DesktopTools.hpp>
#include <zisla/core/Download.hpp>
#include <zisla/core/FileShelfRepository.hpp>
#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>
#include <zisla/core/Pomodoro.hpp>
#include <zisla/core/PowerRequests.hpp>
#include <zisla/core/VoiceInput.hpp>
#include <zisla/core/Weather.hpp>

#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace winrt::Zisla::implementation {

struct OverlayContent : OverlayContentT<OverlayContent> {
    OverlayContent();

    void setInteractive(bool interactive);
    void setVisible(bool visible);
    void setPinned(bool pinned);
    void setOpaqueSurface(bool opaque);
    [[nodiscard]] zisla::core::DipSize preferredInteractiveCardSize() const noexcept;
    void setAIActivities(std::span<const zisla::core::AIProgressTask> tasks);
    void setNowPlaying(std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot);
    void setShelfItems(
        std::span<const zisla::core::FileShelfItem> items,
        std::size_t capacity);
    void setClipboardItems(
        std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> items,
        std::size_t capacity);
    void setQuickNotes(std::shared_ptr<const QuickNotesServiceSnapshot> snapshot);
    void setPDFProcessing(
        std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot);
    void setAIAgentSkills(
        std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot);
    void setAIAgentWorkspace(
        std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot);
    void setCalendar(std::shared_ptr<const CalendarServiceSnapshot> snapshot);
    void setMail(std::shared_ptr<const MailServiceSnapshot> snapshot);
    void setDetectedClipboardLink(std::string link);
    void setDownload(
        std::shared_ptr<const zisla::core::DownloadSnapshot> snapshot,
        std::filesystem::path output_directory);
    void setBrowserDownloads(
        std::shared_ptr<const BrowserDownloadServiceSnapshot> snapshot);
    void setPomodoro(zisla::core::PomodoroSnapshot snapshot);
    void setAlarms(
        std::span<const zisla::core::AlarmItem> alarms,
        std::optional<zisla::core::NextAlarm> next_alarm,
        std::string error);
    void setPowerRequests(zisla::core::PowerRequestSnapshot snapshot);
    void setCleaning(zisla::core::CleaningMode mode);
    void setVoiceInput(
        zisla::core::VoiceInputSnapshot snapshot,
        bool enabled);
    void setWeather(
        std::shared_ptr<const WeatherServiceSnapshot> snapshot,
        std::span<const zisla::core::WeatherLocation> locations,
        bool enabled,
        bool loading,
        std::string status_override);
    void setSystemMonitor(
        std::shared_ptr<const SystemMonitorServiceSnapshot> snapshot);
    void setDesktopTools(
        std::shared_ptr<const zisla::core::DesktopToolsSnapshot> snapshot);
    void setDiskCleanup(
        std::shared_ptr<const DiskCleanupServiceSnapshot> snapshot);
    void showAlarmEditor();
    void showPomodoro();

    void PinButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void VoiceInputButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SettingsButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void CloseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DashboardAIButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DashboardFocusButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DashboardWeatherButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DashboardDownloadButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DashboardBrowserDownloadButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void WeatherRefreshButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void WeatherSearch_QuerySubmitted(
        Microsoft::UI::Xaml::Controls::AutoSuggestBox const&,
        Microsoft::UI::Xaml::Controls::AutoSuggestBoxQuerySubmittedEventArgs const& args);
    void MailRefreshButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailAuthorizeButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget MailOpenAuthorizationButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailSendButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailReplyButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailReplySendButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailReplyCancelButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailMarkReadButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailJunkButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailDeleteButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ShelfView_DragOver(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::DragEventArgs const& args);
    void ShelfView_DragLeave(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::DragEventArgs const&);
    winrt::fire_and_forget ShelfView_Drop(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::DragEventArgs const& args);
    winrt::fire_and_forget ShelfPasteButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ShelfCopyAllButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ShelfShareButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ShelfClearButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ModuleNavigation_SelectionChanged(
        Microsoft::UI::Xaml::Controls::NavigationView const&,
        Microsoft::UI::Xaml::Controls::NavigationViewSelectionChangedEventArgs const& args);
    void MediaPreviousButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MediaPlayPauseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MediaNextButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MediaProgress_ValueChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args);
    void ClipboardFilterButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ClipboardSearch_TextChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
    winrt::fire_and_forget ClipboardAddText_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget ClipboardAddImage_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget ClipboardAddFile_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ClipboardClearHistory_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget ClipboardClearAll_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NotesSearch_TextChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
    void NotesList_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void NotesEditor_TextChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
    void NotesMode_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void NotesNewButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NotesRefreshButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget NotesDeleteButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NotesCopyButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NotesTeleprompterButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AgendaPreviousWeekButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AgendaTodayButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AgendaNextWeekButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AgendaDayButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget AgendaNewEventButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget AgendaNewReminderButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AgendaReminderCheckBox_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget AgendaDeleteButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DownloadUrl_TextChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
    void DownloadStartButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DownloadCancelButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget DownloadFolderButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DownloadRevealButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void PomodoroStartPauseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void PomodoroResetButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void PomodoroApplyDurationButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AlarmSaveButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AlarmCancelButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AlarmWeekdayButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void AlarmOpenClockButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void PowerDisplayToggle_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void PowerSystemToggle_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ScreenCleaningButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void KeyboardCleaningButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void TeleprompterButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void CameraMirrorButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DesktopArrangeButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void StoreUpdatesButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget RecycleBinButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DiskCleanupScanButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget DiskCleanupCleanButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SystemMemoryReleaseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void updatePeek();
    void updateVoiceInputView();
    void updateAIView();
    void updateMediaView();
    void updateDashboardView();
    void updateShelfView();
    void updateClipboardView();
    void updateQuickNotesView();
    void updatePDFToolsView();
    void updateAIAgentSkillsView();
    void updateCalendarView();
    void updateMailView();
    void updateDownloadView();
    void updateToolboxView();
    void updateAlarmView();
    void updateWeatherView();
    void updateSystemMonitorView();
    void updateSystemMonitorActivity() noexcept;
    void updateDiskCleanupView();
    void updateDiskCleanupSelection();
    Microsoft::UI::Xaml::Controls::Grid makeAlarmRow(
        const zisla::core::AlarmItem& alarm);
    void beginAlarmEdit(std::string_view id);
    void resetAlarmEditor();
    [[nodiscard]] zisla::core::AlarmWeekdayMask selectedAlarmWeekdays();
    Microsoft::UI::Xaml::Controls::Grid makeShelfRow(
        const zisla::core::FileShelfItem& item);
    Microsoft::UI::Xaml::Controls::Grid makeClipboardRow(
        const zisla::core::ClipboardHistoryItem& item,
        std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
        std::uint64_t generation);
    Microsoft::UI::Xaml::Controls::Grid makeQuickNoteRow(
        const zisla::core::QuickNote& note);
    Microsoft::UI::Xaml::Controls::Grid makeCalendarRow(
        const zisla::core::CalendarEventSnapshot& item);
    Microsoft::UI::Xaml::Controls::Grid makeMailRow(
        const zisla::core::MailMessage& message);
    Microsoft::UI::Xaml::Controls::Grid makeWeatherRow(
        const zisla::core::WeatherSnapshot& weather);
    Microsoft::UI::Xaml::Controls::CheckBox makeDiskCleanupRow(
        const zisla::core::DiskCleanupCandidate& candidate,
        bool selected);
    [[nodiscard]] std::vector<std::filesystem::path>
        selectedDiskCleanupPaths();
    Windows::Foundation::IAsyncAction addStorageItemsAsync(
        Windows::ApplicationModel::DataTransfer::DataPackageView const& data);
    void selectNavigationModule(hstring const& tag);
    void clearArtwork();
    winrt::fire_and_forget loadArtwork(
        zisla::core::MediaArtwork artwork,
        std::uint64_t generation);
    winrt::fire_and_forget loadClipboardImage(
        Microsoft::UI::Xaml::Controls::Image image,
        std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
        std::int64_t id,
        std::uint64_t generation);
    Windows::Foundation::IAsyncAction showClipboardMessage(
        hstring title,
        hstring message);
    void loadQuickNoteEditor(bool force = false);
    void renderQuickNotePreview(std::string_view markdown);
    void flushQuickNoteSave();
    winrt::fire_and_forget showCalendarEditor(bool reminder);
    [[nodiscard]] std::vector<zisla::core::MailRecipient> mailRecipients();

    std::vector<zisla::core::AIProgressTask> ai_tasks_;
    zisla::core::MediaArtwork displayed_artwork_;
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> now_playing_;
    std::vector<zisla::core::FileShelfItem> shelf_items_;
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>>
        clipboard_items_{std::make_shared<
            const std::vector<zisla::core::ClipboardHistoryItem>>()};
    std::shared_ptr<const QuickNotesServiceSnapshot> quick_notes_snapshot_{
        std::make_shared<const QuickNotesServiceSnapshot>()};
    std::shared_ptr<const CalendarServiceSnapshot> calendar_snapshot_{
        std::make_shared<const CalendarServiceSnapshot>()};
    std::shared_ptr<const MailServiceSnapshot> mail_snapshot_{
        std::make_shared<const MailServiceSnapshot>()};
    std::string detected_clipboard_link_;
    std::shared_ptr<const zisla::core::DownloadSnapshot> download_snapshot_{
        std::make_shared<const zisla::core::DownloadSnapshot>()};
    std::shared_ptr<const BrowserDownloadServiceSnapshot>
        browser_download_snapshot_{
            std::make_shared<const BrowserDownloadServiceSnapshot>()};
    std::filesystem::path download_output_directory_;
    zisla::core::PomodoroSnapshot pomodoro_;
    std::vector<zisla::core::AlarmItem> alarms_;
    std::optional<zisla::core::NextAlarm> next_alarm_;
    std::string alarm_error_;
    std::string editing_alarm_id_;
    zisla::core::PowerRequestSnapshot power_requests_;
    zisla::core::CleaningMode cleaning_mode_{zisla::core::CleaningMode::idle};
    zisla::core::VoiceInputSnapshot voice_input_;
    std::shared_ptr<const WeatherServiceSnapshot> weather_snapshot_;
    std::shared_ptr<const SystemMonitorServiceSnapshot> system_monitor_snapshot_{
        std::make_shared<const SystemMonitorServiceSnapshot>()};
    // Keep disk volume controls alive between monitor snapshots so a refresh
    // updates their values instead of replaying the ProgressBar entrance animation.
    std::vector<std::wstring> system_disk_volume_keys_;
    std::shared_ptr<const zisla::core::DesktopToolsSnapshot> desktop_tools_snapshot_{
        std::make_shared<const zisla::core::DesktopToolsSnapshot>()};
    std::shared_ptr<const DiskCleanupServiceSnapshot> disk_cleanup_snapshot_{
        std::make_shared<const DiskCleanupServiceSnapshot>()};
    std::vector<zisla::core::WeatherLocation> weather_locations_;
    std::string weather_status_override_;
    hstring selected_module_{L"dashboard"};
    std::uint64_t artwork_generation_{0};
    std::uint64_t clipboard_generation_{0};
    std::optional<std::int64_t> selected_quick_note_id_;
    std::optional<std::int64_t> displayed_quick_note_id_;
    std::optional<std::int64_t> selected_calendar_day_ordinal_;
    std::string replying_to_mail_id_;
    hstring mail_verification_uri_;
    Microsoft::UI::Xaml::DispatcherTimer quick_note_save_timer_{nullptr};
    bool interactive_{false};
    bool visible_{false};
    bool updating_media_progress_{false};
    bool updating_quick_notes_{false};
    bool updating_quick_note_editor_{false};
    bool quick_note_dirty_{false};
    bool quick_note_preview_{false};
    bool force_quick_note_reload_{false};
    bool updating_download_url_{false};
    bool weather_enabled_{true};
    bool voice_input_enabled_{false};
    bool weather_loading_{false};
    std::size_t shelf_capacity_{99};
    std::size_t clipboard_capacity_{999};
    zisla::core::ClipboardHistoryFilter clipboard_filter_{
        zisla::core::ClipboardHistoryFilter::all};
};

}

namespace winrt::Zisla::factory_implementation {

struct OverlayContent : OverlayContentT<OverlayContent, implementation::OverlayContent> {};

}
