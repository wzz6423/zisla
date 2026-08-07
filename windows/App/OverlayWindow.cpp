#include "pch.h"
#include "OverlayWindow.h"
#include "AppHost.h"
#include "BackdropPolicy.h"

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

namespace winrt::Zisla {

OverlayWindow::OverlayWindow() {
    createWindow();
}

OverlayWindow::~OverlayWindow() {
    visible_ = false;
    if (activated_registered_ && window_) {
        try {
            window_.Activated(activated_token_);
        } catch (...) {
        }
        activated_registered_ = false;
    }
    try {
        if (content_) {
            content_->setVisible(false);
        }
    } catch (...) {
    }
    if (window_) {
        window_.Close();
    }
}

void OverlayWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    content_ = make_self<implementation::OverlayContent>();
    window_.Content(*content_);
    applyAcrylicBackdrop(window_);
    content_->setOpaqueSurface(!shouldUseTranslucentBackdrop());

    activated_token_ = window_.Activated([this](
        auto&&,
        Microsoft::UI::Xaml::WindowActivatedEventArgs const& args) {
        if (visible_ && interactive_ && !activation_guard_
            && args.WindowActivationState()
                == Microsoft::UI::Xaml::WindowActivationState::Deactivated) {
            AppHost::instance().dispatchPresentationAction(
                zisla::core::PresentationAction::lightDismissRequested());
        }
    });
    activated_registered_ = true;
    pointer_entered_revoker_ = content_->PointerEntered(auto_revoke, [](
        auto&&,
        Microsoft::UI::Xaml::Input::PointerRoutedEventArgs const&) {
        AppHost::instance().dispatchPresentationAction(
            zisla::core::PresentationAction::hoverEntered(
                AppHost::instance().currentAnchor()));
    });
    pointer_exited_revoker_ = content_->PointerExited(auto_revoke, [](
        auto&&,
        Microsoft::UI::Xaml::Input::PointerRoutedEventArgs const&) {
        AppHost::instance().dispatchPresentationAction(
            zisla::core::PresentationAction::hoverExited());
    });
    tapped_revoker_ = content_->Tapped(auto_revoke, [](
        auto&&,
        Microsoft::UI::Xaml::Input::TappedRoutedEventArgs const&) {
        AppHost::instance().promoteOverlay();
    });

    const auto native = window_.as<IWindowNative>();
    check_hresult(native->get_WindowHandle(&hwnd_));
    applyWindowStyle(false);

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(
        hwnd_,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        sizeof(corner));
    const COLORREF border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd_, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void OverlayWindow::applyWindowStyle(bool interactive) {
    const auto style = GetWindowLongPtrW(hwnd_, GWL_STYLE);
    const auto new_style = (style & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_THICKFRAME)) | WS_POPUP;
    SetWindowLongPtrW(hwnd_, GWL_STYLE, new_style);

    const auto extended_style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    const auto new_extended_style = interactive
        ? (extended_style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW) & ~WS_EX_NOACTIVATE
        : (extended_style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    SetWindowLongPtrW(hwnd_, GWL_EXSTYLE, new_extended_style);
    SetWindowPos(
        hwnd_,
        nullptr,
        0,
        0,
        0,
        0,
        SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
            | SWP_NOACTIVATE);
}

void OverlayWindow::show(
    const zisla::core::PixelRect& bounds,
    zisla::core::OverlaySurfaceKind surface,
    bool pinned) {
    refreshBackdrop();
    const bool interactive = surface == zisla::core::OverlaySurfaceKind::interactive;
    if (interactive_ != interactive) {
        applyWindowStyle(interactive);
        interactive_ = interactive;
    }
    content_->setInteractive(interactive);
    content_->setPinned(pinned);
    content_->setVisible(true);

    visible_ = true;
    const auto flags = SWP_SHOWWINDOW | (interactive ? 0 : SWP_NOACTIVATE);
    check_bool(SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        flags));

    if (interactive) {
        activation_guard_ = true;
        window_.Activate();
        SetForegroundWindow(hwnd_);
        activation_guard_ = false;
    }
}

void OverlayWindow::updateBounds(
    const zisla::core::PixelRect& bounds) noexcept {
    if (!visible_ || !hwnd_ || bounds.width <= 0 || bounds.height <= 0) {
        return;
    }

    RECT current{};
    if (GetWindowRect(hwnd_, &current)
        && current.left == bounds.x
        && current.top == bounds.y
        && current.right - current.left == bounds.width
        && current.bottom - current.top == bounds.height) {
        return;
    }

    SetWindowPos(
        hwnd_,
        nullptr,
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        SWP_NOACTIVATE | SWP_NOZORDER);
}

void OverlayWindow::hide() noexcept {
    visible_ = false;
    try {
        if (content_) {
            content_->setVisible(false);
        }
    } catch (...) {
    }
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void OverlayWindow::refreshBackdrop() noexcept {
    applyAcrylicBackdrop(window_);
    if (content_) {
        content_->setOpaqueSurface(!shouldUseTranslucentBackdrop());
    }
}

void OverlayWindow::setAIActivities(
    std::span<const zisla::core::AIProgressTask> tasks) {
    content_->setAIActivities(tasks);
    relayoutIfVisible();
}

void OverlayWindow::setNowPlaying(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    content_->setNowPlaying(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setShelfItems(
    std::span<const zisla::core::FileShelfItem> items,
    std::size_t capacity) {
    content_->setShelfItems(items, capacity);
    relayoutIfVisible();
}

void OverlayWindow::setClipboardItems(
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> items,
    std::size_t capacity) {
    content_->setClipboardItems(std::move(items), capacity);
    relayoutIfVisible();
}

void OverlayWindow::setQuickNotes(
    std::shared_ptr<const QuickNotesServiceSnapshot> snapshot) {
    content_->setQuickNotes(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setPDFProcessing(
    std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot) {
    content_->setPDFProcessing(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setAIAgentSkills(
    std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot) {
    content_->setAIAgentSkills(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setAIAgentWorkspace(
    std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot) {
    content_->setAIAgentWorkspace(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setCalendar(
    std::shared_ptr<const CalendarServiceSnapshot> snapshot) {
    content_->setCalendar(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setMail(
    std::shared_ptr<const MailServiceSnapshot> snapshot) {
    content_->setMail(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setDetectedClipboardLink(std::string link) {
    content_->setDetectedClipboardLink(std::move(link));
    relayoutIfVisible();
}

void OverlayWindow::setDownload(
    std::shared_ptr<const zisla::core::DownloadSnapshot> snapshot,
    std::filesystem::path output_directory) {
    content_->setDownload(std::move(snapshot), std::move(output_directory));
    relayoutIfVisible();
}

void OverlayWindow::setBrowserDownloads(
    std::shared_ptr<const BrowserDownloadServiceSnapshot> snapshot) {
    content_->setBrowserDownloads(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setPomodoro(zisla::core::PomodoroSnapshot snapshot) {
    content_->setPomodoro(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setAlarms(
    std::span<const zisla::core::AlarmItem> alarms,
    std::optional<zisla::core::NextAlarm> next_alarm,
    std::string error) {
    content_->setAlarms(alarms, std::move(next_alarm), std::move(error));
    relayoutIfVisible();
}

void OverlayWindow::setPowerRequests(zisla::core::PowerRequestSnapshot snapshot) {
    content_->setPowerRequests(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setCleaning(zisla::core::CleaningMode mode) {
    content_->setCleaning(mode);
    relayoutIfVisible();
}

void OverlayWindow::setVoiceInput(
    zisla::core::VoiceInputSnapshot snapshot,
    bool enabled) {
    content_->setVoiceInput(std::move(snapshot), enabled);
    relayoutIfVisible();
}

void OverlayWindow::setWeather(
    std::shared_ptr<const WeatherServiceSnapshot> snapshot,
    std::span<const zisla::core::WeatherLocation> locations,
    bool enabled,
    bool loading,
    std::string status_override) {
    content_->setWeather(
        std::move(snapshot),
        locations,
        enabled,
        loading,
        std::move(status_override));
    relayoutIfVisible();
}

void OverlayWindow::setSystemMonitor(
    std::shared_ptr<const SystemMonitorServiceSnapshot> snapshot) {
    content_->setSystemMonitor(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setDesktopTools(
    std::shared_ptr<const zisla::core::DesktopToolsSnapshot> snapshot) {
    content_->setDesktopTools(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::setDiskCleanup(
    std::shared_ptr<const DiskCleanupServiceSnapshot> snapshot) {
    content_->setDiskCleanup(std::move(snapshot));
    relayoutIfVisible();
}

void OverlayWindow::showAlarmEditor() {
    content_->showAlarmEditor();
    relayoutIfVisible();
}

void OverlayWindow::showPomodoro() {
    content_->showPomodoro();
    relayoutIfVisible();
}

HWND OverlayWindow::hwnd() const noexcept {
    return hwnd_;
}

bool OverlayWindow::visible() const noexcept {
    return visible_;
}

zisla::core::DipSize OverlayWindow::preferredInteractiveCardSize() const noexcept {
    return content_
        ? content_->preferredInteractiveCardSize()
        : zisla::core::DipSize{660.0F, 420.0F};
}

void OverlayWindow::relayoutIfVisible() noexcept {
    if (visible_ && interactive_) {
        AppHost::instance().requestOverlayRelayout();
    }
}

}
