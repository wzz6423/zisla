#pragma once

#include <zisla/core/AIStateRepository.hpp>

#include <windows.h>

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

namespace winrt::Zisla {

class AIStateMonitor {
public:
    using ActivityList = std::vector<zisla::core::AIProgressTask>;
    using NoticeList = std::vector<zisla::core::IslandNotice>;

    explicit AIStateMonitor(std::filesystem::path state_directory);
    ~AIStateMonitor();

    AIStateMonitor(const AIStateMonitor&) = delete;
    AIStateMonitor& operator=(const AIStateMonitor&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const ActivityList> snapshot() const noexcept;
    [[nodiscard]] NoticeList takeNotices();

    [[nodiscard]] static std::optional<std::filesystem::path>
        defaultStateDirectory() noexcept;

private:
    void run() noexcept;
    [[nodiscard]] bool watchDirectory(HANDLE directory) noexcept;
    void scanAndPublish(bool force) noexcept;
    [[nodiscard]] bool waitForStop(DWORD timeout_ms) const noexcept;

    std::filesystem::path state_directory_;
    std::atomic<std::shared_ptr<const ActivityList>> snapshot_;
    std::mutex pending_notices_mutex_;
    NoticeList pending_notices_;
    zisla::core::AIStateStorageChangeToken last_token_;
    std::thread thread_;
    std::atomic_bool running_{false};
    HANDLE stop_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
    bool token_initialized_{false};
};

}
