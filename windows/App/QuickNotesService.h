#pragma once

#include <zisla/core/QuickNotes.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct QuickNotesServiceSnapshot {
    std::vector<zisla::core::QuickNote> notes;
    std::optional<std::int64_t> preferred_selection_id;
    std::string error;
    bool loading{true};
};

class QuickNotesService {
public:
    explicit QuickNotesService(std::filesystem::path state_directory);
    ~QuickNotesService();

    QuickNotesService(const QuickNotesService&) = delete;
    QuickNotesService& operator=(const QuickNotesService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void reload();
    void create(std::string markdown);
    void update(std::int64_t id, std::string markdown);
    void remove(std::int64_t id);

    [[nodiscard]] std::shared_ptr<const QuickNotesServiceSnapshot>
        snapshot() const noexcept;
    [[nodiscard]] std::size_t max_markdown_bytes() const noexcept;

private:
    enum class CommandKind {
        reload,
        create,
        update,
        remove,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        std::int64_t id{0};
        std::string markdown;
    };

    void enqueue(Command command);
    void run() noexcept;
    [[nodiscard]] std::optional<std::int64_t> execute(Command command);
    void publish(std::optional<std::int64_t> preferred_selection_id);
    void publish_error(std::string error) noexcept;
    void notify() noexcept;

    zisla::core::QuickNoteRepository repository_;
    std::atomic<std::shared_ptr<const QuickNotesServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    bool running_{false};
    bool welcome_checked_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
