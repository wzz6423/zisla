#pragma once

#include "TeleprompterContent.xaml.h"

#include <zisla/core/Teleprompter.hpp>

#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

class TeleprompterWindow {
public:
    TeleprompterWindow();
    ~TeleprompterWindow();

    void show();
    void hide() noexcept;
    void setSnapshot(const zisla::core::TeleprompterSnapshot& snapshot);
    [[nodiscard]] double scrollableHeight() const noexcept;
    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    void createWindow();

    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::TeleprompterContent> content_;
    HWND hwnd_{nullptr};
    bool visible_{false};
};

}
