#include "pch.h"
#include "CameraMirrorService.h"

#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Media.Capture.Frames.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Devices.h>
#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>

#include <stdexcept>
#include <utility>

namespace winrt::Zisla {
namespace {

using zisla::core::CameraMirrorFailure;
using Windows::Media::Capture::Frames::MediaFrameSource;

std::optional<CameraMirrorFailure> access_failure(
    Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus status)
    noexcept {
    using AccessStatus =
        Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;
    switch (status) {
    case AccessStatus::DeniedBySystem:
        return CameraMirrorFailure::restricted;
    case AccessStatus::DeniedByUser:
        return CameraMirrorFailure::denied;
    case AccessStatus::NotDeclaredByApp:
        return CameraMirrorFailure::configuration;
    case AccessStatus::Allowed:
    case AccessStatus::UserPromptRequired:
        return std::nullopt;
    }
    return CameraMirrorFailure::configuration;
}

CameraMirrorFailure failure_for_error(hresult code) noexcept {
    // Keep the documented Media Foundation error local instead of importing broad MF headers.
    constexpr HRESULT unsupported_capture_device =
        static_cast<HRESULT>(-1072844856);
    if (code == E_ACCESSDENIED) {
        return CameraMirrorFailure::denied;
    }
    if (code == unsupported_capture_device) {
        return CameraMirrorFailure::unavailable;
    }
    return CameraMirrorFailure::configuration;
}

MediaFrameSource preview_source(
    const Windows::Media::Capture::MediaCapture& capture) {
    using Windows::Media::Capture::Frames::MediaFrameSourceKind;
    using Windows::Media::Capture::MediaStreamType;

    MediaFrameSource record{nullptr};
    for (const auto& entry : capture.FrameSources()) {
        const auto source = entry.Value();
        const auto info = source.Info();
        if (info.SourceKind() != MediaFrameSourceKind::Color) {
            continue;
        }
        if (info.MediaStreamType() == MediaStreamType::VideoPreview) {
            return source;
        }
        if (!record && info.MediaStreamType() == MediaStreamType::VideoRecord) {
            record = source;
        }
    }
    return record;
}

}

CameraMirrorService::CameraMirrorService(
    HWND target,
    UINT changed_message,
    UINT failed_message)
    : target_(target),
      changed_message_(changed_message),
      failed_message_(failed_message) {
    if (!target_ || changed_message_ == 0 || failed_message_ == 0) {
        throw std::invalid_argument("camera mirror messages require a target");
    }
}

CameraMirrorService::~CameraMirrorService() {
    session_.stop();
    release_resources();
}

void CameraMirrorService::start() {
    release_resources();
    const auto generation = session_.begin_start();
    notify_changed();
    start_async(generation);
}

void CameraMirrorService::stop() noexcept {
    session_.stop();
    release_resources();
    notify_changed();
}

void CameraMirrorService::handle_runtime_failure(
    std::uint64_t generation) noexcept {
    if (!session_.mark_failed(
            generation,
            CameraMirrorFailure::configuration)) {
        return;
    }
    release_resources();
    notify_changed();
}

const zisla::core::CameraMirrorSnapshot& CameraMirrorService::snapshot() const noexcept {
    return session_.snapshot();
}

Windows::Media::Playback::MediaPlayer CameraMirrorService::media_player() const noexcept {
    return media_player_;
}

winrt::fire_and_forget CameraMirrorService::start_async(
    std::uint64_t generation) {
    const auto lifetime = shared_from_this();
    (void)lifetime;

    try {
        using namespace Windows::Security::Authorization::AppCapabilityAccess;

        const auto capability = AppCapability::Create(L"Webcam");
        auto access = capability.CheckAccess();
        if (access == AppCapabilityAccessStatus::UserPromptRequired) {
            access = co_await capability.RequestAccessAsync();
        }
        if (!session_.accepts(generation)) {
            co_return;
        }
        if (const auto failure = access_failure(access)) {
            finish_failure(generation, *failure);
            co_return;
        }

        const auto devices = co_await Windows::Devices::Enumeration::DeviceInformation::FindAllAsync(
            Windows::Media::Devices::MediaDevice::GetVideoCaptureSelector());
        if (!session_.accepts(generation)) {
            co_return;
        }
        if (devices.Size() == 0) {
            finish_failure(generation, CameraMirrorFailure::unavailable);
            co_return;
        }

        Windows::Media::Capture::MediaCapture capture;
        auto capture_failed = capture.Failed(auto_revoke, [
            target = target_,
            message = failed_message_,
            generation](auto&&, auto&&) noexcept {
                (void)PostMessageW(
                    target,
                    message,
                    static_cast<WPARAM>(generation),
                    0);
            });

        Windows::Media::Capture::MediaCaptureInitializationSettings settings;
        settings.VideoDeviceId(devices.GetAt(0).Id());
        settings.StreamingCaptureMode(
            Windows::Media::Capture::StreamingCaptureMode::Video);
        co_await capture.InitializeAsync(settings);
        if (!session_.accepts(generation)) {
            capture.Close();
            co_return;
        }

        media_capture_ = capture;
        capture_failed_revoker_ = std::move(capture_failed);
        const auto source = preview_source(media_capture_);
        if (!source) {
            finish_failure(generation, CameraMirrorFailure::configuration);
            co_return;
        }

        Windows::Media::Playback::MediaPlayer player;
        player.RealTimePlayback(true);
        player.AutoPlay(false);
        player.Source(
            Windows::Media::Core::MediaSource::CreateFromMediaFrameSource(source));
        auto media_failed = player.MediaFailed(auto_revoke, [
            target = target_,
            message = failed_message_,
            generation](auto&&, auto&&) noexcept {
                (void)PostMessageW(
                    target,
                    message,
                    static_cast<WPARAM>(generation),
                    0);
            });

        media_player_ = std::move(player);
        media_failed_revoker_ = std::move(media_failed);
        if (!session_.mark_running(generation)) {
            release_resources();
            co_return;
        }
        media_player_.Play();
        notify_changed();
    } catch (const hresult_error& error) {
        finish_failure(generation, failure_for_error(error.code()));
    } catch (...) {
        finish_failure(generation, CameraMirrorFailure::configuration);
    }
}

void CameraMirrorService::finish_failure(
    std::uint64_t generation,
    CameraMirrorFailure failure) noexcept {
    if (!session_.mark_failed(generation, failure)) {
        return;
    }
    release_resources();
    notify_changed();
}

void CameraMirrorService::release_resources() noexcept {
    try {
        capture_failed_revoker_.revoke();
    } catch (...) {
    }
    try {
        media_failed_revoker_.revoke();
    } catch (...) {
    }
    if (media_player_) {
        try {
            media_player_.Pause();
        } catch (...) {
        }
        try {
            media_player_.Source(nullptr);
        } catch (...) {
        }
        try {
            media_player_.Close();
        } catch (...) {
        }
        media_player_ = nullptr;
    }
    if (media_capture_) {
        try {
            media_capture_.Close();
        } catch (...) {
        }
        media_capture_ = nullptr;
    }
}

void CameraMirrorService::notify_changed() const noexcept {
    (void)PostMessageW(target_, changed_message_, 0, 0);
}

}
