#pragma once

#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

[[nodiscard]] bool shouldUseTranslucentBackdrop() noexcept;
void applyAcrylicBackdrop(Microsoft::UI::Xaml::Window const& window) noexcept;
void applyMicaBackdrop(Microsoft::UI::Xaml::Window const& window) noexcept;

}
