#pragma once

#include <zisla/core/Download.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

class BilibiliDownloadClient;
class MediaFoundationMuxer;

class DownloadService {
public:
    DownloadService(
        std::filesystem::path yt_dlp_executable,
        std::optional<std::filesystem::path> ffmpeg_executable,
        std::filesystem::path temporary_root);
    ~DownloadService();

    DownloadService(const DownloadService&) = delete;
    DownloadService& operator=(const DownloadService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;
    [[nodiscard]] bool start_download(zisla::core::DownloadRequest request);
    void cancel();

    [[nodiscard]] std::shared_ptr<const zisla::core::DownloadSnapshot>
        snapshot() const noexcept;

private:
    struct PipeResult {
        std::string diagnostic;
    };

    void run() noexcept;
    void execute(zisla::core::DownloadRequest request);
    void execute_bilibili(
        const zisla::core::DownloadRequest& request,
        const std::filesystem::path& task_directory);
    [[nodiscard]] PipeResult drain_pipe(HANDLE pipe);
    void accept_event(zisla::core::YTDLPEvent event);
    void update_bilibili_progress(double fraction, std::string speed) noexcept;
    void finish_direct(const zisla::core::DownloadRequest& request);
    void finish_native_packaging(
        const zisla::core::DownloadRequest& request,
        const std::filesystem::path& task_directory);
    void fail(std::string message) noexcept;
    void publish_locked() noexcept;
    void notify_changed() const noexcept;
    [[nodiscard]] bool cancellation_requested() const noexcept;

    std::filesystem::path yt_dlp_executable_;
    std::optional<std::filesystem::path> ffmpeg_executable_;
    std::filesystem::path temporary_root_;
    std::unique_ptr<BilibiliDownloadClient> bilibili_client_;
    std::unique_ptr<MediaFoundationMuxer> media_muxer_;
    zisla::core::DownloadState state_;
    std::atomic<std::shared_ptr<const zisla::core::DownloadSnapshot>> snapshot_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::optional<zisla::core::DownloadRequest> pending_request_;
    std::optional<std::filesystem::path> completed_file_;
    std::vector<zisla::core::DownloadedMediaComponent> components_;
    std::thread thread_;
    HANDLE active_job_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
    bool running_{false};
    bool cancel_requested_{false};
    bool task_in_progress_{false};
};

}
