#pragma once

#include <zisla/core/ClipboardHistory.hpp>
#include <zisla/core/ClipboardLinkDetector.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct DetectedClipboardLink {
    std::string url;
    std::string host;
};

class ClipboardHistoryService {
public:
    using ItemList = std::vector<zisla::core::ClipboardHistoryItem>;

    explicit ClipboardHistoryService(std::filesystem::path state_directory);
    ~ClipboardHistoryService();

    ClipboardHistoryService(const ClipboardHistoryService&) = delete;
    ClipboardHistoryService& operator=(const ClipboardHistoryService&) = delete;

    [[nodiscard]] bool start(
        HWND target,
        UINT history_changed_message,
        UINT link_detected_message);
    void stop() noexcept;
    void configure(bool history_enabled, bool link_detection_enabled) noexcept;

    void capture(std::uint32_t sequence);
    void ignore_sequence(std::uint32_t sequence) noexcept;
    void record_pinned(zisla::core::ClipboardHistoryContent content);
    void set_pinned(std::int64_t id, bool pinned);
    void remove(std::int64_t id);
    void clear_history();
    void clear_all();

    [[nodiscard]] std::shared_ptr<const ItemList> snapshot() const noexcept;
    [[nodiscard]] std::shared_ptr<const DetectedClipboardLink> detected_link() const noexcept;
    [[nodiscard]] std::size_t capacity() const noexcept;
    [[nodiscard]] std::size_t max_image_bytes() const noexcept;

private:
    enum class CommandKind {
        reload,
        capture,
        record_pinned,
        set_pinned,
        remove,
        clear_history,
        clear_all,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        zisla::core::ClipboardHistoryContent content;
        std::int64_t id{0};
        std::uint32_t sequence{0};
        bool pinned{false};
    };

    struct ClipboardReadResult {
        std::optional<zisla::core::ClipboardHistoryContent> content;
        std::optional<zisla::core::ClipboardUrlCandidate> link_candidate;
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    [[nodiscard]] ClipboardReadResult read_clipboard(std::uint32_t sequence) const;
    void publish_history();
    void publish_link(const zisla::core::ClipboardUrlCandidate& candidate);

    zisla::core::ClipboardHistoryRepository repository_;
    zisla::core::ClipboardLinkDetector link_detector_;
    std::atomic<std::shared_ptr<const ItemList>> snapshot_;
    std::atomic<std::shared_ptr<const DetectedClipboardLink>> detected_link_;
    std::atomic_bool history_enabled_{false};
    std::atomic_bool link_detection_enabled_{false};
    std::atomic<std::uint32_t> ignored_sequence_{0};
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    bool running_{false};
    HWND target_{nullptr};
    UINT history_changed_message_{0};
    UINT link_detected_message_{0};
};

}
