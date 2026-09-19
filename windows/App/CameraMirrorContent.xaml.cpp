#include "pch.h"
#include "CameraMirrorContent.xaml.h"
#include "AppHost.h"

#include <winrt/Windows.System.h>

#if __has_include("CameraMirrorContent.g.cpp")
#include "CameraMirrorContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {

CameraMirrorContent::CameraMirrorContent() {
    InitializeComponent();
}

void CameraMirrorContent::setSnapshot(
    const zisla::core::CameraMirrorSnapshot& snapshot,
    const Windows::Media::Playback::MediaPlayer& player) {
    using Microsoft::UI::Xaml::Visibility;
    using zisla::core::CameraMirrorFailure;
    using zisla::core::CameraMirrorPhase;

    const bool running = snapshot.phase == CameraMirrorPhase::running && player;
    const bool failed = snapshot.phase == CameraMirrorPhase::failed;
    PreparingView().Visibility(!running && !failed
        ? Visibility::Visible
        : Visibility::Collapsed);
    FailureView().Visibility(failed
        ? Visibility::Visible
        : Visibility::Collapsed);
    Preview().Visibility(running
        ? Visibility::Visible
        : Visibility::Collapsed);

    if (running) {
        if (get_abi(player_) != get_abi(player)) {
            detachPreview();
            player_ = player;
            Preview().SetMediaPlayer(player_);
        }
    } else {
        detachPreview();
    }

    if (!failed) {
        return;
    }

    const auto reason = snapshot.failure.value_or(CameraMirrorFailure::configuration);
    switch (reason) {
    case CameraMirrorFailure::denied:
        FailureIcon().Glyph(L"\uE8B8");
        FailureTitle().Text(L"未获得摄像头权限");
        FailureDetail().Text(L"请在 Windows 隐私设置中允许 Zisla 使用摄像头");
        CameraSettingsButton().Visibility(Visibility::Visible);
        break;
    case CameraMirrorFailure::restricted:
        FailureIcon().Glyph(L"\uE72E");
        FailureTitle().Text(L"摄像头访问受限");
        FailureDetail().Text(L"当前系统策略禁止访问摄像头");
        CameraSettingsButton().Visibility(Visibility::Visible);
        break;
    case CameraMirrorFailure::unavailable:
        FailureIcon().Glyph(L"\uE8B8");
        FailureTitle().Text(L"未检测到摄像头");
        FailureDetail().Text(L"没有可用的视频输入设备");
        CameraSettingsButton().Visibility(Visibility::Collapsed);
        break;
    case CameraMirrorFailure::configuration:
        FailureIcon().Glyph(L"\uE814");
        FailureTitle().Text(L"无法开启摄像头");
        FailureDetail().Text(L"请稍后重试或检查摄像头是否被其他应用占用");
        CameraSettingsButton().Visibility(Visibility::Collapsed);
        break;
    }
}

void CameraMirrorContent::detachPreview() noexcept {
    if (!player_) {
        return;
    }
    try {
        Preview().SetMediaPlayer(nullptr);
    } catch (...) {
    }
    player_ = nullptr;
}

void CameraMirrorContent::RetryButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().retryCameraMirror();
}

winrt::fire_and_forget CameraMirrorContent::CameraSettingsButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    try {
        (void)co_await Windows::System::Launcher::LaunchUriAsync(
            Windows::Foundation::Uri{L"ms-settings:privacy-webcam"});
    } catch (...) {
    }
}

void CameraMirrorContent::CloseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().closeCameraMirror();
}

}
