#pragma once

#include "CleaningContent.xaml.h"

#include <zisla/core/CleaningSession.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>

#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

class CleaningWindow {
public:
    explicit CleaningWindow(zisla::core::CleaningMode mode);
    ~CleaningWindow();

    void show(const zisla::core::PixelRect& bounds, bool activate);
    [[nodiscard]] HWND hwnd() const noexcept;

private:
    void createWindow();
    void applyWindowStyle(bool activate);

    zisla::core::CleaningMode mode_;
    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::CleaningContent> content_;
    HWND hwnd_{nullptr};
};

}
