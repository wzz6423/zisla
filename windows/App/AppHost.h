#pragma once

#include "TopEdgeTrigger.h"
#include "TrayIcon.h"
#include "TaskbarPlacement.h"
#include "GlobalHotkeyService.h"
#include "PDFProcessingService.hpp"
#include "MailService.h"
#include "UpdateService.h"

#include <zisla/core/Alarm.hpp>
#include <zisla/core/AIAgentRouting.hpp>
#include <zisla/core/AIAgentSkills.hpp>
#include <zisla/core/CameraMirror.hpp>
#include <zisla/core/Calendar.hpp>
#include <zisla/core/FeatureSettings.hpp>
#include <zisla/core/CleaningSession.hpp>
#include <zisla/core/ClipboardHistory.hpp>
#include <zisla/core/Download.hpp>
#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>
#include <zisla/core/Pet.hpp>
#include <zisla/core/Pomodoro.hpp>
#include <zisla/core/PowerRequests.hpp>
#include <zisla/core/PresentationEngine.hpp>
#include <zisla/core/SideNoticeQueue.hpp>
#include <zisla/core/Teleprompter.hpp>
#include <zisla/core/VoiceInput.hpp>
#include <zisla/core/Weather.hpp>

#include <windows.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Storage.h>

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace winrt::Zisla {

class OverlayWindow;
class SettingsWindow;
class CodexActivityMonitor;
class ClaudeActivityMonitor;
class GeminiActivityMonitor;
class GrokActivityMonitor;
class HarnessActivityMonitor;
class KimiActivityMonitor;
class QwenActivityMonitor;
class TraeActivityMonitor;
class WorkBuddyActivityMonitor;
class FileActivityMonitor;
class AIStateMonitor;
class MediaSessionMonitor;
class SideNoticeWindow;
class FileShelfService;
class ClipboardHistoryService;
class QuickNotesService;
class CalendarService;
struct CalendarServiceSnapshot;
class PowerRequestService;
class CleaningWindow;
class TeleprompterWindow;
class CameraMirrorWindow;
class CameraMirrorService;
class AppNotificationService;
class WeatherService;
class SystemMonitorService;
class DesktopToolsService;
class DiskCleanupService;
class DownloadService;
class BrowserDownloadService;
struct BrowserDownloadServiceSnapshot;
class TaskbarWidgetWindow;
class PetWindow;
class VoiceInputService;
class AIAgentSkillsService;
struct AIAgentSkillsServiceSnapshot;
enum class AIAgentSkillDestination;
class AIAgentWorkspaceService;
struct AIAgentWorkspaceServiceSnapshot;

class AppHost {
public:
    static AppHost& instance();
    static void loadSettings();
    static void saveSettings();

    void start();
    void shutdown() noexcept;
    void requestExternalActivation() noexcept;

    void dispatchPresentationAction(zisla::core::PresentationAction action);
    void promoteOverlay();
    void dismissOverlay();
    void togglePin();
    void showSettings();
    void openTaskbarWidget();
    void setTaskbarWidgetEnabled(bool enabled);
    void setPetEnabled(bool enabled);
    void setPetId(std::string id);
    void setPetSide(zisla::core::PetSide side);
    void setTopEdgeEnabled(bool enabled);
    void setSideNoticesEnabled(bool enabled);
    void setClipboardHistoryEnabled(bool enabled);
    void setClipboardDetectionEnabled(bool enabled);
    void setVoiceInputEnabled(bool enabled);
    void setVoiceHotkeyAction(zisla::core::VoiceHotkeyAction action);
    void setVoiceHotkeyPreset(zisla::core::VoiceHotkeyPreset preset);
    void toggleVoiceInput();
    void setNotificationsMuted(bool muted);
    void setWeatherEnabled(bool enabled);
    void setBrowserDownloadStatusEnabled(bool enabled);
    void setSystemMonitorActive(bool active) noexcept;
    void refreshDesktopTools();
    void arrangeDesktop();
    void emptyRecycleBin();
    void openStoreUpdates();
    void checkForUpdates(zisla::core::UpdateChannel channel);
    void openAvailableUpdate();
    void configureMail(MailConnectionSettings settings);
    void beginMailAuthorization();
    void refreshMail();
    void markMailRead(std::string message_id);
    void moveMailToJunk(std::string message_id);
    void deleteMail(std::string message_id);
    void sendMail(
        std::vector<zisla::core::MailRecipient> recipients,
        std::string subject,
        std::string body);
    void replyMail(std::string message_id, std::string body);
    void trimOwnWorkingSet();
    void scanDiskCleanup();
    void cleanDiskCleanup(std::vector<std::filesystem::path> paths);
    void refreshWeather();
    void searchWeatherLocation(std::string query);
    void removeWeatherLocation(std::string id);
    void setSideNoticeHovered(std::string_view id, bool hovered);
    void dismissSideNotice(std::string_view id);
    void settingsWindowHidden() noexcept;
    void toggleMediaPlayback();
    void playPreviousMedia();
    void playNextMedia();
    void seekMedia(double position_seconds);
    void togglePomodoro();
    void resetPomodoro();
    void setPomodoroDuration(
        zisla::core::PomodoroMode mode,
        std::int64_t seconds);
    [[nodiscard]] bool addAlarm(
        int hour,
        int minute,
        std::string label,
        zisla::core::AlarmWeekdayMask weekday_mask);
    [[nodiscard]] bool updateAlarm(
        std::string id,
        int hour,
        int minute,
        std::string label,
        zisla::core::AlarmWeekdayMask weekday_mask);
    void setAlarmEnabled(std::string id, bool enabled);
    void removeAlarm(std::string id);
    void openSystemClock();
    void setKeepDisplayAwake(bool enabled);
    void setPreventIdleSystemSleep(bool enabled);
    void startScreenCleaning();
    void startKeyboardCleaning();
    void requestEndCleaning() noexcept;
    void showTeleprompter();
    void closeTeleprompter() noexcept;
    void toggleTeleprompterScrolling();
    void resetTeleprompter();
    void setTeleprompterSpeed(double speed);
    void setTeleprompterScript(std::string script);
    void showCameraMirror();
    void closeCameraMirror() noexcept;
    void retryCameraMirror();
    void addShelfPaths(std::vector<std::filesystem::path> paths);
    void removeShelfPath(std::filesystem::path path);
    void clearShelf();
    void copyShelfPath(std::filesystem::path path);
    void copyAllShelfPaths();
    void shareAllShelfPaths();
    void openShelfPath(const std::filesystem::path& path);
    void revealShelfPath(const std::filesystem::path& path);
    void addPinnedClipboardContent(zisla::core::ClipboardHistoryContent content);
    void setClipboardItemPinned(std::int64_t id, bool pinned);
    void removeClipboardItem(std::int64_t id);
    void clearClipboardHistory();
    void clearAllClipboardItems();
    void copyClipboardItem(std::int64_t id);
    void copyTextToClipboard(std::string text);
    [[nodiscard]] bool startDownload(
        std::string url,
        zisla::core::DownloadMode mode,
        std::filesystem::path output_directory);
    void cancelDownload();
    void revealDownloadedFile();
    void reloadQuickNotes();
    void createQuickNote(std::string markdown);
    void updateQuickNote(std::int64_t id, std::string markdown);
    void removeQuickNote(std::int64_t id);
    [[nodiscard]] std::uint64_t submitPDFProcessing(
        zisla::pdf::PDFProcessingRequest request);
    void reloadAIAgentWorkspace();
    void createAIAgentThread();
    void removeAIAgentThread(std::string thread_id);
    void submitAIAgentMessage(
        std::string thread_id,
        std::string content,
        std::optional<zisla::core::AgentCLIKind> cli_kind,
        std::optional<std::string> channel_id);
    void cancelAIAgentRequest() noexcept;
    void configureAIAgentConnection(
        std::optional<std::string> channel_id,
        zisla::core::AgentChannelProtocol protocol,
        std::string name,
        std::string base_url,
        std::string model,
        std::string endpoint_priority,
        std::string api_key,
        std::optional<zisla::core::AgentBalanceProbe> balance_probe);
    void removeAIAgentConnection(std::string channel_id);
    void refreshAIAgentAccountBalance(std::string account_id);
    void refreshAIAgentChannelModels(std::string channel_id);
    void reloadAIAgentSkills();
    void setAIAgentSkillEnabled(std::filesystem::path path, bool enabled);
    void setAIAgentSkillsSynchronizationMode(
        zisla::core::AgentSkillSynchronizationMode mode);
    void setAIAgentSkillsDestinationEnabled(
        AIAgentSkillDestination destination,
        bool enabled);
    void synchronizeAIAgentSkills();
    void openAIAgentSkillsLibrary();
    void showCurrentCalendarWeek();
    void setCalendarReferenceDate(zisla::core::CalendarCivilDate date);
    void createCalendarEvent(
        std::string title,
        zisla::core::CalendarCivilDate start_date,
        int start_hour,
        int start_minute,
        zisla::core::CalendarCivilDate end_date,
        int end_hour,
        int end_minute,
        bool all_day);
    void createCalendarReminder(
        std::string title,
        zisla::core::CalendarCivilDate due_date,
        int due_hour,
        int due_minute,
        bool all_day);
    void setCalendarReminderCompleted(std::int64_t id, bool completed);
    void removeCalendarItem(std::int64_t id);
    void ignoreCurrentClipboardSequence() noexcept;
    void exitApplication();

    [[nodiscard]] zisla::core::OverlayAnchor currentAnchor() const noexcept;
    [[nodiscard]] bool isTopEdgeEnabled() const noexcept;
    [[nodiscard]] bool areSideNoticesEnabled() const noexcept;
    [[nodiscard]] bool isClipboardHistoryEnabled() const noexcept;
    [[nodiscard]] bool isClipboardDetectionEnabled() const noexcept;
    [[nodiscard]] bool isVoiceInputEnabled() const noexcept;
    [[nodiscard]] zisla::core::VoiceHotkeyAction voiceHotkeyAction() const noexcept;
    [[nodiscard]] zisla::core::VoiceHotkeyPreset voiceHotkeyPreset() const noexcept;
    [[nodiscard]] std::string voiceHotkeyStatus() const;
    [[nodiscard]] bool areNotificationsMuted() const noexcept;
    [[nodiscard]] bool isWeatherEnabled() const noexcept;
    [[nodiscard]] bool isBrowserDownloadStatusEnabled() const noexcept;
    [[nodiscard]] bool isTaskbarWidgetEnabled() const noexcept;
    [[nodiscard]] bool isPetEnabled() const noexcept;
    [[nodiscard]] const std::string& petId() const noexcept;
    [[nodiscard]] zisla::core::PetSide petSide() const noexcept;
    [[nodiscard]] const MailConnectionSettings& mailConnectionSettings() const noexcept;
    [[nodiscard]] zisla::core::UpdateChannel updateChannel() const noexcept;
    [[nodiscard]] std::shared_ptr<const MailServiceSnapshot> mailSnapshot() const noexcept;
    [[nodiscard]] std::shared_ptr<const UpdateServiceSnapshot> updateSnapshot() const noexcept;
    [[nodiscard]] std::vector<zisla::core::PetManifest> availablePets() const;
    [[nodiscard]] std::size_t clipboardImageLimit() const noexcept;
    [[nodiscard]] HWND overlayWindowHandle() const noexcept;

private:
    AppHost() = default;
    ~AppHost();

    AppHost(const AppHost&) = delete;
    AppHost& operator=(const AppHost&) = delete;

    static constexpr UINT tray_message = WM_APP + 1;
    static constexpr UINT top_edge_entered_message = WM_APP + 2;
    static constexpr UINT top_edge_exited_message = WM_APP + 3;
    static constexpr UINT activate_message = WM_APP + 4;
    static constexpr UINT ai_activity_changed_message = WM_APP + 5;
    static constexpr UINT media_session_changed_message = WM_APP + 6;
    static constexpr UINT file_shelf_changed_message = WM_APP + 7;
    static constexpr UINT clipboard_history_changed_message = WM_APP + 8;
    static constexpr UINT clipboard_link_detected_message = WM_APP + 9;
    static constexpr UINT cleaning_exit_message = WM_APP + 10;
    static constexpr UINT camera_mirror_changed_message = WM_APP + 11;
    static constexpr UINT camera_mirror_failed_message = WM_APP + 12;
    static constexpr UINT notification_activated_message = WM_APP + 13;
    static constexpr UINT weather_changed_message = WM_APP + 14;
    static constexpr UINT quick_notes_changed_message = WM_APP + 15;
    static constexpr UINT system_monitor_changed_message = WM_APP + 16;
    static constexpr UINT desktop_tools_changed_message = WM_APP + 17;
    static constexpr UINT disk_cleanup_changed_message = WM_APP + 18;
    static constexpr UINT download_changed_message = WM_APP + 19;
    static constexpr UINT browser_download_changed_message = WM_APP + 20;
    static constexpr UINT calendar_changed_message = WM_APP + 21;
    static constexpr UINT voice_input_changed_message = WM_APP + 22;
    static constexpr UINT pdf_processing_changed_message = WM_APP + 23;
    static constexpr UINT ai_agent_skills_changed_message = WM_APP + 24;
    static constexpr UINT ai_agent_workspace_changed_message = WM_APP + 25;
    static constexpr UINT mail_changed_message = WM_APP + 26;
    static constexpr UINT update_changed_message = WM_APP + 27;
    static constexpr UINT_PTR dismiss_timer_id = 1;
    static constexpr UINT_PTR side_notice_timer_id = 2;
    static constexpr UINT_PTR pomodoro_timer_id = 3;
    static constexpr UINT_PTR teleprompter_timer_id = 4;
    static constexpr UINT_PTR alarm_timer_id = 5;
    static constexpr UINT_PTR voice_finalization_timer_id = 6;
    static constexpr UINT_PTR top_edge_timer_id = 7;
    static constexpr UINT dismiss_delay_ms = 450;
    static constexpr UINT pomodoro_timer_interval_ms = 250;
    static constexpr UINT teleprompter_timer_interval_ms = 16;
    static constexpr UINT top_edge_poll_interval_ms = 40;

    static LRESULT CALLBACK windowProcedure(
        HWND hwnd,
        UINT message,
        WPARAM wparam,
        LPARAM lparam);
    LRESULT handleMessage(UINT message, WPARAM wparam, LPARAM lparam);

    void createMessageWindow();
    void destroyMessageWindow() noexcept;
    void showTrayContextMenu();
    void handleTrayEvent(UINT event);
    void applyEffects(const zisla::core::EffectBatch& effects);
    [[nodiscard]] bool showOverlay(zisla::core::OverlayAnchor anchor);
    void hideOverlay() noexcept;
    void scheduleDismiss(std::uint64_t generation);
    void cancelScheduledDismiss() noexcept;
    void refreshAIActivities() noexcept;
    void refreshNowPlaying() noexcept;
    void refreshFileShelf() noexcept;
    void refreshClipboardHistory() noexcept;
    void refreshQuickNotes() noexcept;
    void refreshPDFProcessing() noexcept;
    void refreshAIAgentWorkspace() noexcept;
    void refreshAIAgentSkills() noexcept;
    void refreshCalendar() noexcept;
    void refreshMailView() noexcept;
    void refreshUpdate() noexcept;
    void refreshSystemMonitor() noexcept;
    void refreshDesktopToolsView() noexcept;
    void refreshDiskCleanup() noexcept;
    void refreshDownload() noexcept;
    void refreshBrowserDownloads() noexcept;
    void refreshTaskbarWidget() noexcept;
    void refreshBackdrops() noexcept;
    void refreshPet() noexcept;
    [[nodiscard]] bool loadSelectedPet() noexcept;
    void refreshDownloadNotice(
        const std::shared_ptr<const zisla::core::DownloadSnapshot>& snapshot);
    void refreshBrowserDownloadNotice(
        const std::shared_ptr<const BrowserDownloadServiceSnapshot>& snapshot);
    void refreshPomodoro() noexcept;
    void refreshAlarms() noexcept;
    void refreshPowerRequests() noexcept;
    void refreshCleaning() noexcept;
    void refreshTeleprompter() noexcept;
    void refreshCameraMirror() noexcept;
    void refreshVoiceInput() noexcept;
    void refreshVoiceHotkey() noexcept;
    void applyVoiceHotkeyCommand(zisla::core::VoiceHotkeyCommand command) noexcept;
    void startVoiceInput() noexcept;
    void stopVoiceInput() noexcept;
    void cancelVoiceFinalization() noexcept;
    void startWeatherService() noexcept;
    void handleWeatherChanged() noexcept;
    void refreshWeatherView() noexcept;
    winrt::fire_and_forget refreshWeatherAsync(bool request_current_location);
    [[nodiscard]] bool weatherIsStale() const noexcept;
    void handlePomodoroTimer() noexcept;
    void stopPomodoroTimer() noexcept;
    void loadAlarms() noexcept;
    [[nodiscard]] bool commitAlarms(zisla::core::AlarmBook alarms) noexcept;
    void reconcileAndRescheduleAlarms() noexcept;
    void scheduleAlarmTimer() noexcept;
    void stopAlarmTimer() noexcept;
    void handleTeleprompterTimer() noexcept;
    void stopTeleprompterTimer() noexcept;
    void consumeClipboardLink() noexcept;
    void updateClipboardListener() noexcept;
    winrt::fire_and_forget copyClipboardItemAsync(
        std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
        std::int64_t id);
    [[nodiscard]] bool ensureShareManager();
    winrt::fire_and_forget shareShelfPathsAsync(
        std::vector<std::filesystem::path> paths);
    void consumeExternalNotices(std::int64_t now_unix_ms);
    void refreshAIActivityNotices(
        std::span<const zisla::core::AIProgressTask> activities,
        std::int64_t now_unix_ms);
    void refreshMediaNotice(
        std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot);
    void updateSideNoticeWindows() noexcept;
    void hideSideNoticeWindows() noexcept;
    void scheduleSideNoticeExpiration() noexcept;
    void cancelSideNoticeExpiration() noexcept;
    void anchorSideNoticesToPointer() noexcept;
    void startCleaning(zisla::core::CleaningMode mode) noexcept;
    void endCleaning() noexcept;
    void rebuildCleaningWindows() noexcept;
    [[nodiscard]] bool replaceCleaningWindows(zisla::core::CleaningMode mode);
    void holdPowerRequestsForCleaning() noexcept;
    void restorePowerRequestsAfterCleaning() noexcept;

    HWND message_window_{nullptr};
    std::atomic<HWND> activation_window_{nullptr};
    std::atomic_bool external_activation_pending_{false};
    UINT taskbar_created_message_{0};
    std::uint64_t scheduled_dismiss_generation_{0};
    bool started_{false};
    bool top_edge_enabled_{true};
    bool taskbar_widget_enabled_{true};
    bool media_notice_presented_{false};
    bool clipboard_listener_registered_{false};
    std::int64_t launch_unix_ms_{0};
    std::int64_t teleprompter_last_tick_ms_{0};
    HMONITOR side_notice_monitor_{nullptr};

    TrayIcon tray_icon_;
    TopEdgeTrigger top_edge_trigger_;
    TaskbarPlacement taskbar_placement_;
    zisla::core::PresentationEngine presentation_engine_;
    zisla::core::OverlayPlacementEngine placement_engine_;
    zisla::core::FeatureSettings settings_;
    std::optional<zisla::core::PetActivity> pet_activity_;
    zisla::core::PomodoroEngine pomodoro_engine_;
    zisla::core::AlarmBook alarm_book_;
    zisla::core::CleaningSession cleaning_session_;
    zisla::core::TeleprompterEngine teleprompter_engine_;
    zisla::core::SideNoticeQueue side_notice_queue_;
    zisla::core::VoiceInputPhase voice_input_phase_{
        zisla::core::VoiceInputPhase::idle};

    std::unordered_map<std::string, zisla::core::AIProgressStatus>
        ai_task_statuses_;
    std::unordered_set<std::string> active_ai_notice_ids_;
    std::unordered_set<std::string> shown_ai_notice_ids_;

    std::unique_ptr<OverlayWindow> overlay_window_;
    std::unique_ptr<SettingsWindow> settings_window_;
    std::unique_ptr<CodexActivityMonitor> codex_activity_monitor_;
    std::unique_ptr<ClaudeActivityMonitor> claude_activity_monitor_;
    std::unique_ptr<GeminiActivityMonitor> gemini_activity_monitor_;
    std::unique_ptr<GrokActivityMonitor> grok_activity_monitor_;
    std::unique_ptr<HarnessActivityMonitor> harness_activity_monitor_;
    std::unique_ptr<KimiActivityMonitor> kimi_activity_monitor_;
    std::unique_ptr<QwenActivityMonitor> qwen_activity_monitor_;
    std::unique_ptr<TraeActivityMonitor> trae_activity_monitor_;
    std::unique_ptr<WorkBuddyActivityMonitor> workbuddy_activity_monitor_;
    std::unique_ptr<FileActivityMonitor> copilot_activity_monitor_;
    std::unique_ptr<FileActivityMonitor> qoder_activity_monitor_;
    std::unique_ptr<FileActivityMonitor> doubao_activity_monitor_;
    std::unique_ptr<FileActivityMonitor> opencode_activity_monitor_;
    std::unique_ptr<AIStateMonitor> ai_state_monitor_;
    std::unique_ptr<MediaSessionMonitor> media_session_monitor_;
    std::unique_ptr<FileShelfService> file_shelf_service_;
    std::unique_ptr<ClipboardHistoryService> clipboard_history_service_;
    std::unique_ptr<QuickNotesService> quick_notes_service_;
    std::unique_ptr<zisla::pdf::PDFProcessingService> pdf_processing_service_;
    std::unique_ptr<AIAgentWorkspaceService> ai_agent_workspace_service_;
    std::unique_ptr<AIAgentSkillsService> ai_agent_skills_service_;
    std::unique_ptr<CalendarService> calendar_service_;
    std::unique_ptr<MailService> mail_service_;
    std::unique_ptr<UpdateService> update_service_;
    std::unique_ptr<PowerRequestService> power_request_service_;
    std::unique_ptr<AppNotificationService> notification_service_;
    std::unique_ptr<WeatherService> weather_service_;
    std::unique_ptr<SystemMonitorService> system_monitor_service_;
    std::unique_ptr<DesktopToolsService> desktop_tools_service_;
    std::unique_ptr<DiskCleanupService> disk_cleanup_service_;
    std::unique_ptr<DownloadService> download_service_;
    std::unique_ptr<BrowserDownloadService> browser_download_service_;
    std::unique_ptr<TaskbarWidgetWindow> taskbar_widget_window_;
    std::unique_ptr<PetWindow> pet_window_;
    std::vector<zisla::core::PetLibraryEntry> pet_entries_;
    std::unique_ptr<zisla::core::WeatherLocationRepository>
        weather_location_repository_;
    std::vector<zisla::core::WeatherLocation> weather_locations_;
    std::string weather_storage_error_;
    std::string weather_status_override_;
    std::filesystem::path download_output_directory_;
    std::string download_startup_error_;
    MailConnectionSettings mail_connection_settings_;
    zisla::core::UpdateChannel update_channel_{zisla::core::UpdateChannel::release};
    std::uint64_t download_terminal_notice_revision_{0};
    std::unordered_set<std::string> browser_completed_notice_ids_;
    std::uint64_t weather_location_generation_{0};
    std::uint64_t handled_weather_search_generation_{0};
    bool weather_location_pending_{false};
    std::unique_ptr<zisla::core::AlarmRepository> alarm_repository_;
    std::string alarm_storage_error_;
    std::string alarm_notification_error_;
    std::unique_ptr<zisla::core::PowerRequestController> power_request_controller_;
    std::optional<zisla::core::PowerRequestSnapshot> cleaning_power_state_;
    std::vector<std::unique_ptr<CleaningWindow>> cleaning_windows_;
    std::unique_ptr<TeleprompterWindow> teleprompter_window_;
    std::unique_ptr<CameraMirrorWindow> camera_mirror_window_;
    std::shared_ptr<CameraMirrorService> camera_mirror_service_;
    std::shared_ptr<VoiceInputService> voice_input_service_;
    std::unique_ptr<GlobalHotkeyService> voice_hotkey_service_;
    std::unique_ptr<SideNoticeWindow> left_notice_window_;
    std::unique_ptr<SideNoticeWindow> right_notice_window_;
    Windows::ApplicationModel::DataTransfer::DataTransferManager
        share_manager_{nullptr};
    Windows::ApplicationModel::DataTransfer::DataTransferManager::DataRequested_revoker
        share_requested_revoker_{};
    Windows::Foundation::Collections::IVector<Windows::Storage::IStorageItem>
        pending_share_items_{nullptr};
};

}
