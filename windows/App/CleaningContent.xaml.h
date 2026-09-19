#pragma once

#include "CleaningContent.g.h"

#include <zisla/core/CleaningSession.hpp>

namespace winrt::Zisla::implementation {

struct CleaningContent : CleaningContentT<CleaningContent> {
    CleaningContent();

    void setMode(zisla::core::CleaningMode mode);
    void Root_Tapped(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Input::TappedRoutedEventArgs const&);
    void ExitButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void Root_KeyDown(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args);
    void Root_KeyUp(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args);

private:
    zisla::core::CleaningMode mode_{zisla::core::CleaningMode::screen};
};

}

namespace winrt::Zisla::factory_implementation {

struct CleaningContent : CleaningContentT<
    CleaningContent,
    implementation::CleaningContent> {};

}
