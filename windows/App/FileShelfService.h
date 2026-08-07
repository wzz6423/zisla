#pragma once

#include <zisla/core/FileShelfRepository.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace winrt::Zisla {

class FileShelfService {
public:
    using ItemList = std::vector<zisla::core::FileShelfItem>;

    explicit FileShelfService(std::filesystem::path state_directory);
    ~FileShelfService();

    FileShelfService(const FileShelfService&) = delete;
    FileShelfService& operator=(const FileShelfService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void add(std::vector<std::filesystem::path> paths);
    void remove(std::filesystem::path path);
    void clear();

    [[nodiscard]] std::shared_ptr<const ItemList> snapshot() const noexcept;
    [[nodiscard]] std::size_t capacity() const noexcept;

private:
    enum class CommandKind {
        reload,
        add,
        remove,
        clear,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        std::vector<std::filesystem::path> paths;
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(const Command& command);
    void publish();

    zisla::core::FileShelfRepository repository_;
    std::atomic<std::shared_ptr<const ItemList>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
