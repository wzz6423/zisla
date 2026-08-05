#pragma once

#include <zisla/core/DesktopTools.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>

namespace winrt::Zisla {

class DesktopToolsService {
public:
    DesktopToolsService();
    ~DesktopToolsService();

    DesktopToolsService(const DesktopToolsService&) = delete;
    DesktopToolsService& operator=(const DesktopToolsService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void refreshRecycleBin();
    void arrangeDesktop();
    void emptyRecycleBin();
    void openStoreUpdates();
    void trimOwnWorkingSet();

    [[nodiscard]] std::shared_ptr<const zisla::core::DesktopToolsSnapshot>
        snapshot() const noexcept;

private:
    void enqueue(zisla::core::DesktopToolAction action);
    void run() noexcept;
    void execute(zisla::core::DesktopToolAction action);
    void publish() noexcept;
    void notify() const noexcept;

    zisla::core::DesktopToolsState state_;
    std::atomic<std::shared_ptr<const zisla::core::DesktopToolsSnapshot>> snapshot_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<zisla::core::DesktopToolAction> commands_;
    std::thread thread_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
