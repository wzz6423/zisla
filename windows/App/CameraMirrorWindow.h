#pragma once

#include "CameraMirrorContent.xaml.h"

#include <zisla/core/CameraMirror.hpp>

#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Windows.Media.Playback.h>

namespace winrt::Zisla {

class CameraMirrorWindow {
public:
    CameraMirrorWindow();
    ~CameraMirrorWindow();

    void show();
    void hide() noexcept;
    void setSnapshot(
        const zisla::core::CameraMirrorSnapshot& snapshot,
        const Windows::Media::Playback::MediaPlayer& player);
    void detachPreview() noexcept;
    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    void createWindow();

    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::CameraMirrorContent> content_;
    HWND hwnd_{nullptr};
    Microsoft::UI::Windowing::AppWindow app_window_{nullptr};
    Microsoft::UI::Windowing::AppWindow::Closing_revoker closing_revoker_{};
    bool visible_{false};
    bool destroying_{false};
};

}
