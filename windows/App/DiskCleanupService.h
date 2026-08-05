#pragma once

#include <zisla/core/DiskCleanup.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct DiskCleanupServiceSnapshot {
    std::vector<zisla::core::DiskCleanupCandidate> candidates;
    bool scanning{false};
    bool cleaning{false};
    std::uint64_t freed_bytes{0};
    std::uint64_t revision{0};
    std::string status;
    std::string error;
};

class DiskCleanupService {
public:
    DiskCleanupService();
    ~DiskCleanupService();

    DiskCleanupService(const DiskCleanupService&) = delete;
    DiskCleanupService& operator=(const DiskCleanupService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;
    void scan();
    void clean(std::vector<std::filesystem::path> paths);

    [[nodiscard]] std::shared_ptr<const DiskCleanupServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        scan,
        clean,
    };

    struct Command {
        CommandKind kind{CommandKind::scan};
        std::vector<std::filesystem::path> paths;
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    void publish() noexcept;
    void notify() const noexcept;

    DiskCleanupServiceSnapshot state_;
    std::atomic<std::shared_ptr<const DiskCleanupServiceSnapshot>> snapshot_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
