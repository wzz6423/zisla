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

class HarnessActivityMonitor {
public:
    using ActivityList = std::vector<zisla::core::AIProgressTask>;

    explicit HarnessActivityMonitor(std::filesystem::path data_directory);
    ~HarnessActivityMonitor();

    HarnessActivityMonitor(const HarnessActivityMonitor&) = delete;
    HarnessActivityMonitor& operator=(const HarnessActivityMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const ActivityList> snapshot() const noexcept;

    [[nodiscard]] static std::optional<std::filesystem::path>
        defaultDataDirectory() noexcept;

private:
    void run() noexcept;
    [[nodiscard]] bool watchDirectory(
        HANDLE directory,
        ULONGLONG& last_refresh_tick) noexcept;
    void scanAndPublish() noexcept;
    [[nodiscard]] bool waitForStop(DWORD timeout_ms) const noexcept;

    std::filesystem::path data_directory_;
    std::atomic<std::shared_ptr<const ActivityList>> snapshot_;
    std::thread thread_;
    std::atomic_bool running_{false};
    HANDLE stop_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
