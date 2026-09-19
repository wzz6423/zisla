#pragma once

#include <zisla/core/AIModels.hpp>

#include <windows.h>

#include <atomic>
#include <filesystem>
#include <functional>
#include <memory>
#include <thread>
#include <vector>

namespace winrt::Zisla {

class FileActivityMonitor {
public:
    using ActivityList = std::vector<zisla::core::AIProgressTask>;
    using Scanner = std::function<ActivityList()>;

    FileActivityMonitor(
        std::vector<std::filesystem::path> watch_roots,
        Scanner scanner);
    ~FileActivityMonitor();

    FileActivityMonitor(const FileActivityMonitor&) = delete;
    FileActivityMonitor& operator=(const FileActivityMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const ActivityList> snapshot() const noexcept;

private:
    void run() noexcept;
    [[nodiscard]] bool watchDirectories(ULONGLONG& last_refresh_tick);
    void scanAndPublish() noexcept;
    [[nodiscard]] bool waitForStop(DWORD timeout_ms) const noexcept;

    std::vector<std::filesystem::path> watch_roots_;
    Scanner scanner_;
    std::atomic<std::shared_ptr<const ActivityList>> snapshot_;
    std::thread thread_;
    std::atomic_bool running_{false};
    HANDLE stop_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
