#pragma once

#include <zisla/core/NowPlaying.hpp>

#include <windows.h>

#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace winrt::Zisla {

enum class MediaSessionCommandKind {
    toggle_play_pause,
    previous,
    next,
    seek,
};

struct MediaSessionCommand {
    MediaSessionCommandKind kind{MediaSessionCommandKind::toggle_play_pause};
    std::string session_id;
    double position_seconds{0};
};

class MediaSessionMonitor {
public:
    MediaSessionMonitor();
    ~MediaSessionMonitor();

    MediaSessionMonitor(const MediaSessionMonitor&) = delete;
    MediaSessionMonitor& operator=(const MediaSessionMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const zisla::core::NowPlayingSnapshot>
        snapshot() const noexcept;
    [[nodiscard]] bool request(MediaSessionCommand command) noexcept;

private:
    struct WorkerState;

    void run() noexcept;
    void wake() noexcept;
    void notifyChanged() const noexcept;
    [[nodiscard]] std::deque<MediaSessionCommand> takeCommands() noexcept;
    void publish(std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) noexcept;

    std::atomic<std::shared_ptr<const zisla::core::NowPlayingSnapshot>> snapshot_;
    std::mutex command_mutex_;
    std::deque<MediaSessionCommand> commands_;
    std::thread thread_;
    std::atomic_bool running_{false};
    std::atomic_bool sessions_dirty_{true};
    std::atomic_bool metadata_dirty_{true};
    HANDLE stop_event_{nullptr};
    HANDLE wake_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
