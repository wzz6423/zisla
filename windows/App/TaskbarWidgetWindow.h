#pragma once

#include "TaskbarWidgetContent.xaml.h"

#include <zisla/core/OverlayPlacementEngine.hpp>

#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

class TaskbarWidgetWindow {
public:
    TaskbarWidgetWindow();
    ~TaskbarWidgetWindow();

    void show(const zisla::core::PixelRect& bounds);
    void hide() noexcept;
    void refreshBackdrop() noexcept;

    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    void createWindow();

    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::TaskbarWidgetContent> content_;
    HWND hwnd_{nullptr};
    bool visible_{false};
};

}
