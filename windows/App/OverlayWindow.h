#pragma once

#include "OverlayContent.xaml.h"
#include "AIAgentSkillsService.h"
#include "AIAgentWorkspaceService.h"
#include "PDFProcessingService.hpp"
#include "WeatherService.h"
#include "QuickNotesService.h"
#include "SystemMonitorService.h"
#include "DiskCleanupService.h"
#include "BrowserDownloadService.h"
#include "CalendarService.h"
#include "MailService.h"

#include <zisla/core/Alarm.hpp>
#include <zisla/core/AIModels.hpp>
#include <zisla/core/CleaningSession.hpp>
#include <zisla/core/ClipboardHistory.hpp>
#include <zisla/core/DesktopTools.hpp>
#include <zisla/core/Download.hpp>
#include <zisla/core/FileShelfRepository.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>
#include <zisla/core/Pomodoro.hpp>
#include <zisla/core/PowerRequests.hpp>
#include <zisla/core/VoiceInput.hpp>
#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/Weather.hpp>

#include <winrt/Microsoft.UI.Xaml.h>

#include <filesystem>
#include <span>
#include <memory>
#include <optional>
#include <string>

namespace winrt::Zisla {

class OverlayWindow {
public:
    OverlayWindow();
    ~OverlayWindow();

    void show(
        const zisla::core::PixelRect& bounds,
        zisla::core::OverlaySurfaceKind surface,
        bool pinned);
    void hide() noexcept;
    void refreshBackdrop() noexcept;
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

    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    void createWindow();
    void applyWindowStyle(bool interactive);

    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::OverlayContent> content_;
    HWND hwnd_{nullptr};
    Microsoft::UI::Xaml::Window::Activated_revoker activated_revoker_{};
    Microsoft::UI::Xaml::UIElement::PointerEntered_revoker pointer_entered_revoker_{};
    Microsoft::UI::Xaml::UIElement::PointerExited_revoker pointer_exited_revoker_{};
    Microsoft::UI::Xaml::UIElement::Tapped_revoker tapped_revoker_{};
    bool visible_{false};
    bool interactive_{false};
    bool activation_guard_{false};
};

}
