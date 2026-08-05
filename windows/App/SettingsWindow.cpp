#include "pch.h"
#include "SettingsWindow.h"
#include "AppHost.h"
#include "BackdropPolicy.h"
#include "DisplayTopology.h"

#include <microsoft.ui.interop.h>
#include <microsoft.ui.xaml.window.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

#include <algorithm>

namespace winrt::Zisla {

SettingsWindow::SettingsWindow() {
    createWindow();
}

SettingsWindow::~SettingsWindow() {
    destroying_ = true;
    if (window_) {
        try {
            window_.Close();
        } catch (...) {
        }
    }
}

void SettingsWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    window_.Title(L"Zisla 设置");
    content_ = make_self<implementation::SettingsContent>();
    window_.Content(*content_);
    applyMicaBackdrop(window_);

    activated_revoker_ = window_.Activated(auto_revoke, [this](
        auto&&,
        Microsoft::UI::Xaml::WindowActivatedEventArgs const& args) {
        if (args.WindowActivationState()
            != Microsoft::UI::Xaml::WindowActivationState::Deactivated) {
            content_->refreshStartupTask();
        }
    });

    const auto native = window_.as<IWindowNative>();
    check_hresult(native->get_WindowHandle(&hwnd_));

    const auto window_id = Microsoft::UI::GetWindowIdFromWindow(hwnd_);
    app_window_ = Microsoft::UI::Windowing::AppWindow::GetFromWindowId(window_id);

    closing_revoker_ = app_window_.Closing(auto_revoke, [this](
        auto&&,
        Microsoft::UI::Windowing::AppWindowClosingEventArgs const& args) {
        if (!destroying_) {
            args.Cancel(true);
            hide();
        }
    });
}

void SettingsWindow::show() {
    refreshBackdrop();
    POINT cursor{};
    (void)GetCursorPos(&cursor);
    const auto screen = DisplayTopology::screenForPoint(cursor);
    const auto dpi = screen.dpi == 0 ? UINT{96} : screen.dpi;
    const int width = std::min(screen.work_area.width, MulDiv(780, dpi, 96));
    const int height = std::min(screen.work_area.height, MulDiv(620, dpi, 96));
    const int x = screen.work_area.x + (screen.work_area.width - width) / 2;
    const int y = screen.work_area.y + (screen.work_area.height - height) / 2;
    check_bool(SetWindowPos(
        hwnd_,
        nullptr,
        x,
        y,
        width,
        height,
        SWP_NOZORDER | SWP_NOACTIVATE));
    window_.Activate();
}

void SettingsWindow::hide() noexcept {
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
    AppHost::instance().settingsWindowHidden();
}

void SettingsWindow::refreshBackdrop() noexcept {
    applyMicaBackdrop(window_);
}

void SettingsWindow::setMail(
    std::shared_ptr<const MailServiceSnapshot> snapshot) {
    if (content_) {
        content_->setMailSnapshot(std::move(snapshot));
    }
}

void SettingsWindow::setUpdate(
    std::shared_ptr<const UpdateServiceSnapshot> snapshot) {
    if (content_) {
        content_->setUpdateSnapshot(std::move(snapshot));
    }
}

HWND SettingsWindow::hwnd() const noexcept {
    return hwnd_;
}

}
