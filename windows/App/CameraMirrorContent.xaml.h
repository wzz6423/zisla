#pragma once

#include "CameraMirrorContent.g.h"

#include <zisla/core/CameraMirror.hpp>

#include <winrt/Windows.Media.Playback.h>

namespace winrt::Zisla::implementation {

struct CameraMirrorContent : CameraMirrorContentT<CameraMirrorContent> {
    CameraMirrorContent();

    void setSnapshot(
        const zisla::core::CameraMirrorSnapshot& snapshot,
        const Windows::Media::Playback::MediaPlayer& player);
    void detachPreview() noexcept;

    void RetryButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget CameraSettingsButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void CloseButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    Windows::Media::Playback::MediaPlayer player_{nullptr};
};

}

namespace winrt::Zisla::factory_implementation {

struct CameraMirrorContent : CameraMirrorContentT<
    CameraMirrorContent,
    implementation::CameraMirrorContent> {};

}
