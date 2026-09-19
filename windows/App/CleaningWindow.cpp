#include "pch.h"
#include "CleaningWindow.h"

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>

namespace winrt::Zisla {

CleaningWindow::CleaningWindow(zisla::core::CleaningMode mode)
    : mode_(mode) {
    createWindow();
}

CleaningWindow::~CleaningWindow() {
    if (window_) {
        try {
            window_.Close();
        } catch (...) {
        }
    }
}

void CleaningWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    window_.Title(mode_ == zisla::core::CleaningMode::keyboard
        ? L"Zisla 键盘清洁"
        : L"Zisla 屏幕清洁");
    content_ = make_self<implementation::CleaningContent>();
    content_->setMode(mode_);
    window_.Content(*content_);

    const auto native = window_.as<IWindowNative>();
    check_hresult(native->get_WindowHandle(&hwnd_));
    applyWindowStyle(false);

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_DONOTROUND;
    DwmSetWindowAttribute(
        hwnd_,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        sizeof(corner));
    const COLORREF border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd_, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void CleaningWindow::applyWindowStyle(bool activate) {
    const auto style = GetWindowLongPtrW(hwnd_, GWL_STYLE);
    SetWindowLongPtrW(
        hwnd_,
        GWL_STYLE,
        (style & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
            | WS_MAXIMIZEBOX | WS_THICKFRAME)) | WS_POPUP);
    const auto extended_style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    const auto base_style = extended_style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW;
    SetWindowLongPtrW(
        hwnd_,
        GWL_EXSTYLE,
        activate ? base_style & ~WS_EX_NOACTIVATE : base_style | WS_EX_NOACTIVATE);
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

void CleaningWindow::show(
    const zisla::core::PixelRect& bounds,
    bool activate) {
    applyWindowStyle(activate);
    check_bool(SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        SWP_SHOWWINDOW | (activate ? 0 : SWP_NOACTIVATE)));
    if (activate) {
        window_.Activate();
        (void)SetForegroundWindow(hwnd_);
        (void)content_->Focus(Microsoft::UI::Xaml::FocusState::Programmatic);
    }
}

HWND CleaningWindow::hwnd() const noexcept {
    return hwnd_;
}

}
