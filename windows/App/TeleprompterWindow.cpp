#include "pch.h"
#include "TeleprompterWindow.h"
#include "DisplayTopology.h"

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>

#include <algorithm>

namespace winrt::Zisla {

TeleprompterWindow::TeleprompterWindow() {
    createWindow();
}

TeleprompterWindow::~TeleprompterWindow() {
    visible_ = false;
    if (window_) {
        try {
            window_.Close();
        } catch (...) {
        }
    }
}

void TeleprompterWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    window_.Title(L"Zisla 提词器");
    content_ = make_self<implementation::TeleprompterContent>();
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

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(
        hwnd_,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        sizeof(corner));
    const COLORREF border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd_, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void TeleprompterWindow::show() {
    POINT cursor{};
    (void)GetCursorPos(&cursor);
    const auto screen = DisplayTopology::screenForPoint(cursor);
    const auto dpi = screen.dpi == 0 ? UINT{96} : screen.dpi;
    const int width = std::min(screen.work_area.width, MulDiv(720, dpi, 96));
    const int height = std::min(screen.work_area.height, MulDiv(520, dpi, 96));
    if (width <= 0 || height <= 0) {
        return;
    }
    const int x = screen.work_area.x + (screen.work_area.width - width) / 2;
    const int y = screen.work_area.y + (screen.work_area.height - height) / 2;
    check_bool(SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        x,
        y,
        width,
        height,
        SWP_SHOWWINDOW));
    visible_ = true;
    window_.Activate();
    (void)SetForegroundWindow(hwnd_);
}

void TeleprompterWindow::hide() noexcept {
    visible_ = false;
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void TeleprompterWindow::setSnapshot(
    const zisla::core::TeleprompterSnapshot& snapshot) {
    content_->setSnapshot(snapshot);
}

double TeleprompterWindow::scrollableHeight() const noexcept {
    return content_ ? content_->scrollableHeight() : 0.0;
}

HWND TeleprompterWindow::hwnd() const noexcept {
    return hwnd_;
}

bool TeleprompterWindow::visible() const noexcept {
    return visible_;
}

}
