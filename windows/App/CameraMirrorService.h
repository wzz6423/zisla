#pragma once

#include <zisla/core/CameraMirror.hpp>

#include <windows.h>
#include <winrt/Windows.Media.Capture.h>
#include <winrt/Windows.Media.Playback.h>

#include <cstdint>
#include <memory>

namespace winrt::Zisla {

class CameraMirrorService : public std::enable_shared_from_this<CameraMirrorService> {
public:
    CameraMirrorService(HWND target, UINT changed_message, UINT failed_message);
    ~CameraMirrorService();

    CameraMirrorService(const CameraMirrorService&) = delete;
    CameraMirrorService& operator=(const CameraMirrorService&) = delete;

    void start();
    void stop() noexcept;
    void handle_runtime_failure(std::uint64_t generation) noexcept;

    [[nodiscard]] const zisla::core::CameraMirrorSnapshot& snapshot() const noexcept;
    [[nodiscard]] Windows::Media::Playback::MediaPlayer media_player() const noexcept;

private:
    winrt::fire_and_forget start_async(std::uint64_t generation);
    void finish_failure(
        std::uint64_t generation,
        zisla::core::CameraMirrorFailure failure) noexcept;
    void release_resources() noexcept;
    void notify_changed() const noexcept;

    HWND target_{nullptr};
    UINT changed_message_{0};
    UINT failed_message_{0};
    zisla::core::CameraMirrorSession session_;
    Windows::Media::Capture::MediaCapture media_capture_{nullptr};
    Windows::Media::Playback::MediaPlayer media_player_{nullptr};
    Windows::Media::Capture::MediaCapture::Failed_revoker capture_failed_revoker_{};
    Windows::Media::Playback::MediaPlayer::MediaFailed_revoker media_failed_revoker_{};
};

}
