#pragma once

#include <zisla/core/SystemMonitor.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace winrt::Zisla {

struct SystemMonitorServiceSnapshot {
    zisla::core::SystemMonitorSnapshot metrics;
    zisla::core::SystemMetricHistory history;
    bool active{false};
    bool loading{false};
    std::string error;
};

class SystemMonitorService {
public:
    SystemMonitorService();
    ~SystemMonitorService();

    SystemMonitorService(const SystemMonitorService&) = delete;
    SystemMonitorService& operator=(const SystemMonitorService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;
    void set_active(bool active) noexcept;
    void refresh() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] bool active() const noexcept;
    [[nodiscard]] std::shared_ptr<const SystemMonitorServiceSnapshot>
        snapshot() const noexcept;

private:
    void run() noexcept;
    void publish(SystemMonitorServiceSnapshot snapshot) noexcept;
    void publish_error(std::string error) noexcept;
    void notify_changed() const noexcept;

    std::atomic<std::shared_ptr<const SystemMonitorServiceSnapshot>> snapshot_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::thread thread_;
    bool running_{false};
    bool active_{false};
    bool refresh_requested_{false};
    bool reset_baselines_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
