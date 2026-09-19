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

class ClaudeActivityMonitor {
public:
    using ActivityList = std::vector<zisla::core::AIProgressTask>;

    explicit ClaudeActivityMonitor(std::filesystem::path projects_root);
    ~ClaudeActivityMonitor();

    ClaudeActivityMonitor(const ClaudeActivityMonitor&) = delete;
    ClaudeActivityMonitor& operator=(const ClaudeActivityMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const ActivityList> snapshot() const noexcept;

    [[nodiscard]] static std::optional<std::filesystem::path>
        defaultProjectsRoot() noexcept;

private:
    void run() noexcept;
    [[nodiscard]] bool watchDirectory(
        HANDLE directory,
        ULONGLONG& last_refresh_tick) noexcept;
    void scanAndPublish() noexcept;
    [[nodiscard]] bool waitForStop(DWORD timeout_ms) const noexcept;

    std::filesystem::path projects_root_;
    std::atomic<std::shared_ptr<const ActivityList>> snapshot_;
    std::thread thread_;
    std::atomic_bool running_{false};
    HANDLE stop_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
