#include "pch.h"
#include "BackdropPolicy.h"

#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.UI.ViewManagement.h>

namespace winrt::Zisla {

bool shouldUseTranslucentBackdrop() noexcept {
    try {
        Windows::UI::ViewManagement::UISettings settings;
        Windows::UI::ViewManagement::AccessibilitySettings accessibility;
        return settings.AdvancedEffectsEnabled() && !accessibility.HighContrast();
    } catch (...) {
        return false;
    }
}

void applyAcrylicBackdrop(Microsoft::UI::Xaml::Window const& window) noexcept {
    try {
        if (shouldUseTranslucentBackdrop()) {
            window.SystemBackdrop(
                Microsoft::UI::Xaml::Media::DesktopAcrylicBackdrop());
        } else {
            window.SystemBackdrop(nullptr);
        }
    } catch (...) {
        try {
            window.SystemBackdrop(nullptr);
        } catch (...) {
        }
    }
}

void applyMicaBackdrop(Microsoft::UI::Xaml::Window const& window) noexcept {
    try {
        if (shouldUseTranslucentBackdrop()) {
            window.SystemBackdrop(
                Microsoft::UI::Xaml::Media::MicaBackdrop());
        } else {
            window.SystemBackdrop(nullptr);
        }
    } catch (...) {
        try {
            window.SystemBackdrop(nullptr);
        } catch (...) {
        }
    }
}

}
