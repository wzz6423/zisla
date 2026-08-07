#include "pch.h"
#include "CameraMirrorWindow.h"
#include "AppHost.h"
#include "DisplayTopology.h"

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>

#include <algorithm>

namespace winrt::Zisla {

CameraMirrorWindow::CameraMirrorWindow() {
    createWindow();
}

CameraMirrorWindow::~CameraMirrorWindow() {
    destroying_ = true;
    visible_ = false;
    detachPreview();
    if (closing_registered_ && app_window_) {
        try {
            app_window_.Closing(closing_token_);
        } catch (...) {
        }
        closing_registered_ = false;
    }
    if (window_) {
        try {
            window_.Close();
        } catch (...) {
        }
    }
}

void CameraMirrorWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    window_.Title(L"Zisla 摄像头镜子");
    content_ = make_self<implementation::CameraMirrorContent>();
    window_.Content(*content_);

    const auto native = window_.as<IWindowNative>();
    check_hresult(native->get_WindowHandle(&hwnd_));
    const auto style = GetWindowLongPtrW(hwnd_, GWL_STYLE);
    SetWindowLongPtrW(
        hwnd_,
        GWL_STYLE,
        (style & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
            | WS_MAXIMIZEBOX | WS_THICKFRAME)) | WS_POPUP);
    const auto extended_style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    SetWindowLongPtrW(
        hwnd_,
        GWL_EXSTYLE,
        extended_style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW);
    SetWindowPos(
        hwnd_,
        nullptr,
        0,
        0,
        0,
        0,
        SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
            | SWP_NOACTIVATE);

    app_window_ = window_.AppWindow();
    closing_token_ = app_window_.Closing([this](
        auto&&,
        Microsoft::UI::Windowing::AppWindowClosingEventArgs const& args) {
        if (!destroying_) {
            args.Cancel(true);
            AppHost::instance().closeCameraMirror();
        }
    });
    closing_registered_ = true;

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(
        hwnd_,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        sizeof(corner));
    const COLORREF border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd_, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void CameraMirrorWindow::show() {
    POINT cursor{};
    (void)GetCursorPos(&cursor);
    const auto screen = DisplayTopology::screenForPoint(cursor);
    const auto dpi = screen.dpi == 0 ? UINT{96} : screen.dpi;
    const int side = std::min({
        screen.work_area.width,
        screen.work_area.height,
        MulDiv(640, dpi, 96),
    });
    if (side <= 0) {
        return;
    }
    const int x = screen.work_area.x + (screen.work_area.width - side) / 2;
    const int y = screen.work_area.y + (screen.work_area.height - side) / 2;
    check_bool(SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        x,
        y,
        side,
        side,
        SWP_SHOWWINDOW));
    visible_ = true;
    window_.Activate();
    (void)SetForegroundWindow(hwnd_);
}

void CameraMirrorWindow::hide() noexcept {
    visible_ = false;
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void CameraMirrorWindow::setSnapshot(
    const zisla::core::CameraMirrorSnapshot& snapshot,
    const Windows::Media::Playback::MediaPlayer& player) {
    content_->setSnapshot(snapshot, player);
}

void CameraMirrorWindow::detachPreview() noexcept {
    if (content_) {
        content_->detachPreview();
    }
}

HWND CameraMirrorWindow::hwnd() const noexcept {
    return hwnd_;
}

bool CameraMirrorWindow::visible() const noexcept {
    return visible_;
}

}
