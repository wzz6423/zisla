#include "pch.h"
#include "QuickNotesService.h"

#include <chrono>
#include <stdexcept>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr std::string_view welcome_markdown = R"(# 朋友，看这里。

从现在开始，你可以在随记中记录信息了。

记忆力并不是智慧，但没有记忆力还成什么智慧呢？

-- 哈柏

读书感悟、生活体验、团队计划，都可以随手写在这里。内容会自动保存在这台电脑上。

愿你能愉快而轻松地使用这个小工具。
)";

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

}

QuickNotesService::QuickNotesService(std::filesystem::path state_directory)
    : repository_(std::move(state_directory)),
      snapshot_(std::make_shared<const QuickNotesServiceSnapshot>()) {}

QuickNotesService::~QuickNotesService() {
    stop();
}

bool QuickNotesService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    commands_.push_back({CommandKind::reload});
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

void QuickNotesService::stop() noexcept {
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

void QuickNotesService::reload() {
    enqueue({CommandKind::reload});
}

void QuickNotesService::create(std::string markdown) {
    enqueue({
        .kind = CommandKind::create,
        .markdown = std::move(markdown),
    });
}

void QuickNotesService::update(std::int64_t id, std::string markdown) {
    if (id > 0) {
        enqueue({
            .kind = CommandKind::update,
            .id = id,
            .markdown = std::move(markdown),
        });
    }
}

void QuickNotesService::remove(std::int64_t id) {
    if (id > 0) {
        enqueue({
            .kind = CommandKind::remove,
            .id = id,
        });
    }
}

std::shared_ptr<const QuickNotesServiceSnapshot>
QuickNotesService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::size_t QuickNotesService::max_markdown_bytes() const noexcept {
    return repository_.max_markdown_bytes();
}

void QuickNotesService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void QuickNotesService::run() noexcept {
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
            const auto preferred_selection_id = execute(std::move(command));
            publish(preferred_selection_id);
        } catch (const std::exception& error) {
            publish_error(error.what());
        } catch (...) {
            publish_error("随记存储发生未知错误");
        }
    }
}

std::optional<std::int64_t> QuickNotesService::execute(Command command) {
    if (!welcome_checked_) {
        (void)repository_.ensure_welcome_note(
            std::string(welcome_markdown),
            now_unix_milliseconds());
        welcome_checked_ = true;
    }

    switch (command.kind) {
    case CommandKind::reload:
        return std::nullopt;
    case CommandKind::create: {
        const auto id = repository_.create(
            std::move(command.markdown),
            now_unix_milliseconds());
        if (!id) {
            throw std::runtime_error("随记内容不能超过 1 MiB");
        }
        return id;
    }
    case CommandKind::update:
        if (command.markdown.size() > repository_.max_markdown_bytes()) {
            throw std::runtime_error("随记内容不能超过 1 MiB");
        }
        (void)repository_.update(
            command.id,
            std::move(command.markdown),
            now_unix_milliseconds());
        return std::nullopt;
    case CommandKind::remove:
        (void)repository_.remove(command.id);
        return std::nullopt;
    }
    return std::nullopt;
}

void QuickNotesService::publish(
    std::optional<std::int64_t> preferred_selection_id) {
    auto next = std::make_shared<const QuickNotesServiceSnapshot>(
        QuickNotesServiceSnapshot{
            .notes = repository_.load(),
            .preferred_selection_id = preferred_selection_id,
            .loading = false,
        });
    snapshot_.store(std::move(next), std::memory_order_release);
    notify();
}

void QuickNotesService::publish_error(std::string error) noexcept {
    try {
        const auto current = snapshot();
        auto next = std::make_shared<const QuickNotesServiceSnapshot>(
            QuickNotesServiceSnapshot{
                .notes = current ? current->notes : std::vector<zisla::core::QuickNote>{},
                .error = std::move(error),
                .loading = false,
            });
        snapshot_.store(std::move(next), std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void QuickNotesService::notify() noexcept {
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
