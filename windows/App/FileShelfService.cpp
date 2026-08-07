#include "pch.h"
#include "FileShelfService.h"

#include <chrono>
#include <utility>

namespace winrt::Zisla {
namespace {

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

}

FileShelfService::FileShelfService(std::filesystem::path state_directory)
    : repository_(std::move(state_directory)),
      snapshot_(std::make_shared<const ItemList>()) {}

FileShelfService::~FileShelfService() {
    stop();
}

bool FileShelfService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    commands_.push_back({CommandKind::reload, {}});
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void FileShelfService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

void FileShelfService::add(std::vector<std::filesystem::path> paths) {
    if (!paths.empty()) {
        enqueue({CommandKind::add, std::move(paths)});
    }
}

void FileShelfService::remove(std::filesystem::path path) {
    if (!path.empty()) {
        std::vector<std::filesystem::path> paths;
        paths.push_back(std::move(path));
        enqueue({CommandKind::remove, std::move(paths)});
    }
}

void FileShelfService::clear() {
    enqueue({CommandKind::clear, {}});
}

std::shared_ptr<const FileShelfService::ItemList>
FileShelfService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::size_t FileShelfService::capacity() const noexcept {
    return repository_.capacity();
}

void FileShelfService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void FileShelfService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        try {
            execute(command);
            publish();
        } catch (...) {
        }
    }
}

void FileShelfService::execute(const Command& command) {
    switch (command.kind) {
    case CommandKind::reload:
        break;
    case CommandKind::add:
        (void)repository_.add(command.paths, now_unix_milliseconds());
        break;
    case CommandKind::remove:
        if (!command.paths.empty()) {
            (void)repository_.remove(command.paths.front());
        }
        break;
    case CommandKind::clear:
        repository_.clear();
        break;
    }
}

void FileShelfService::publish() {
    auto next = std::make_shared<const ItemList>(repository_.load());
    snapshot_.store(std::move(next), std::memory_order_release);

    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
