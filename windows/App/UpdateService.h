#pragma once

#include "WinHttpRequest.h"

#include <zisla/core/Update.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

namespace winrt::Zisla {

enum class UpdateServicePhase {
    idle,
    checking,
    up_to_date,
    available,
    failed,
};

struct UpdateServiceSnapshot {
    UpdateServicePhase phase{UpdateServicePhase::idle};
    zisla::core::UpdateChannel channel{zisla::core::UpdateChannel::release};
    std::optional<zisla::core::AvailableUpdate> update;
    std::string message;
};

class UpdateService {
public:
    explicit UpdateService(std::string current_version);
    ~UpdateService();

    UpdateService(const UpdateService&) = delete;
    UpdateService& operator=(const UpdateService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;
    void check(zisla::core::UpdateChannel channel);

    [[nodiscard]] std::shared_ptr<const UpdateServiceSnapshot>
        snapshot() const noexcept;

private:
    struct Command {
        zisla::core::UpdateChannel channel{zisla::core::UpdateChannel::release};
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    void publish(UpdateServiceSnapshot snapshot) noexcept;
    void publish_error(
        zisla::core::UpdateChannel channel,
        std::string message) noexcept;
    void notify() noexcept;

    std::string current_version_;
    std::atomic<std::shared_ptr<const UpdateServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    WinHttpCancellation cancellation_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
