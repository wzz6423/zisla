#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class ClipboardContentKind {
    text,
    image,
    file,
};

struct ClipboardHistoryContent {
    ClipboardContentKind kind{ClipboardContentKind::text};
    std::string text;
    std::vector<std::uint8_t> image;
    std::filesystem::path file_path;
    std::string file_display_name;

    [[nodiscard]] static ClipboardHistoryContent make_text(std::string value);
    [[nodiscard]] static ClipboardHistoryContent make_image(
        std::vector<std::uint8_t> value);
    [[nodiscard]] static ClipboardHistoryContent make_file(
        std::filesystem::path path,
        std::string display_name = {});

    friend bool operator==(const ClipboardHistoryContent&, const ClipboardHistoryContent&)
        = default;
};

struct ClipboardHistoryItem {
    std::int64_t id{0};
    ClipboardHistoryContent content;
    std::int64_t last_copied_at_unix_ms{0};
    bool pinned{false};

    friend bool operator==(const ClipboardHistoryItem&, const ClipboardHistoryItem&) = default;
};

enum class ClipboardHistoryFilter {
    all,
    pinned,
    history,
};

[[nodiscard]] bool clipboard_history_matches(
    const ClipboardHistoryItem& item,
    ClipboardHistoryFilter filter,
    std::string_view query);

class ClipboardHistoryRepositoryError : public std::runtime_error {
public:
    explicit ClipboardHistoryRepositoryError(std::string message);
};

class ClipboardHistoryRepository {
public:
    explicit ClipboardHistoryRepository(
        std::filesystem::path directory,
        std::size_t capacity = 999,
        std::size_t max_image_bytes = 10U * 1024U * 1024U);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] std::size_t capacity() const noexcept;
    [[nodiscard]] std::size_t max_image_bytes() const noexcept;

    [[nodiscard]] std::vector<ClipboardHistoryItem> load() const;
    [[nodiscard]] bool record(
        ClipboardHistoryContent content,
        std::int64_t copied_at_unix_ms,
        bool pinned = false) const;
    [[nodiscard]] bool set_pinned(
        std::int64_t id,
        bool pinned,
        std::int64_t copied_at_unix_ms) const;
    [[nodiscard]] bool remove(std::int64_t id) const;
    void clear_history() const;
    void clear_all() const;

private:
    std::filesystem::path directory_;
    std::size_t capacity_;
    std::size_t max_image_bytes_;
};

[[nodiscard]] std::vector<ClipboardHistoryItem> filter_clipboard_history(
    std::span<const ClipboardHistoryItem> items,
    ClipboardHistoryFilter filter,
    std::string_view query);

}  // namespace zisla::core
