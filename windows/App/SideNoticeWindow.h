#pragma once

#include "SideNoticeContent.xaml.h"

#include <zisla/core/OverlayPlacementEngine.hpp>
#include <zisla/core/SideNoticeQueue.hpp>

#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

class SideNoticeWindow {
public:
    explicit SideNoticeWindow(zisla::core::NoticeSide side);
    ~SideNoticeWindow();

    void show(
        const zisla::core::PixelRect& bounds,
        const zisla::core::SideNoticeViewState& state);
    void hide() noexcept;
    void refreshBackdrop() noexcept;

    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    void createWindow();

    zisla::core::NoticeSide side_;
    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::SideNoticeContent> content_;
    HWND hwnd_{nullptr};
    bool visible_{false};
};

}
