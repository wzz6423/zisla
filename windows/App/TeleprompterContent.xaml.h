#pragma once

#include "TeleprompterContent.g.h"

#include <zisla/core/Teleprompter.hpp>

namespace winrt::Zisla::implementation {

struct TeleprompterContent : TeleprompterContentT<TeleprompterContent> {
    TeleprompterContent();

    void setSnapshot(const zisla::core::TeleprompterSnapshot& snapshot);
    [[nodiscard]] double scrollableHeight() noexcept;

    void PlayPauseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ResetButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SpeedSlider_ValueChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args);
    winrt::fire_and_forget PasteButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void CloseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    std::string script_;
    bool updating_{false};
};

}

namespace winrt::Zisla::factory_implementation {

struct TeleprompterContent : TeleprompterContentT<
    TeleprompterContent,
    implementation::TeleprompterContent> {};

}
