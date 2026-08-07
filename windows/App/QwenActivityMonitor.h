#pragma once

#include <zisla/core/AIModels.hpp>

#include <windows.h>

#include <atomic>
#include <filesystem>
#include <memory>
#include <optional>
#include <thread>
#include <vector>

namespace winrt::Zisla {

class QwenActivityMonitor {
public:
    using ActivityList = std::vector<zisla::core::AIProgressTask>;

    explicit QwenActivityMonitor(std::filesystem::path projects_directory);
    ~QwenActivityMonitor();

    QwenActivityMonitor(const QwenActivityMonitor&) = delete;
    QwenActivityMonitor& operator=(const QwenActivityMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const ActivityList> snapshot() const noexcept;

    [[nodiscard]] static std::optional<std::filesystem::path>
        defaultProjectsDirectory() noexcept;

private:
    void run() noexcept;
    [[nodiscard]] bool watchDirectory(
        HANDLE directory,
        ULONGLONG& last_refresh_tick) noexcept;
    void scanAndPublish() noexcept;
    [[nodiscard]] bool waitForStop(DWORD timeout_ms) const noexcept;

    std::filesystem::path projects_directory_;
    std::atomic<std::shared_ptr<const ActivityList>> snapshot_;
    std::thread thread_;
    std::atomic_bool running_{false};
    HANDLE stop_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
