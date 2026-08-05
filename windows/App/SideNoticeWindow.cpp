#include "pch.h"
#include "SideNoticeWindow.h"
#include "BackdropPolicy.h"

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

namespace winrt::Zisla {

SideNoticeWindow::SideNoticeWindow(zisla::core::NoticeSide side)
    : side_(side) {
    createWindow();
}

SideNoticeWindow::~SideNoticeWindow() {
    visible_ = false;
    if (window_) {
        try {
            window_.Close();
        } catch (...) {
        }
    }
}

void SideNoticeWindow::createWindow() {
    window_ = Microsoft::UI::Xaml::Window();
    content_ = make_self<implementation::SideNoticeContent>();
    window_.Content(*content_);
    applyAcrylicBackdrop(window_);
    content_->setOpaqueSurface(!shouldUseTranslucentBackdrop());

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
        extended_style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
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

void SideNoticeWindow::show(
    const zisla::core::PixelRect& bounds,
    const zisla::core::SideNoticeViewState& state) {
    if (bounds.width <= 0 || bounds.height <= 0) {
        hide();
        return;
    }
    refreshBackdrop();
    content_->setState(side_, state);
    visible_ = true;
    check_bool(SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        SWP_SHOWWINDOW | SWP_NOACTIVATE));
}

void SideNoticeWindow::hide() noexcept {
    visible_ = false;
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void SideNoticeWindow::refreshBackdrop() noexcept {
    applyAcrylicBackdrop(window_);
    if (content_) {
        content_->setOpaqueSurface(!shouldUseTranslucentBackdrop());
    }
}

HWND SideNoticeWindow::hwnd() const noexcept {
    return hwnd_;
}

bool SideNoticeWindow::visible() const noexcept {
    return visible_;
}

}
