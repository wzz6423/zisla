#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct QuickNote {
    std::int64_t id{0};
    std::string title;
    std::string markdown;
    std::int64_t created_at_unix_ms{0};
    std::int64_t modified_at_unix_ms{0};

    friend bool operator==(const QuickNote&, const QuickNote&) = default;
};

[[nodiscard]] std::string quick_note_title(std::string_view markdown);
[[nodiscard]] bool quick_note_matches(
    const QuickNote& note,
    std::string_view query);

class QuickNoteRepositoryError : public std::runtime_error {
public:
    explicit QuickNoteRepositoryError(std::string message);
};

class QuickNoteRepository {
public:
    static constexpr std::size_t default_max_markdown_bytes =
        1U * 1024U * 1024U;

    explicit QuickNoteRepository(
        std::filesystem::path directory,
        std::size_t max_markdown_bytes = default_max_markdown_bytes);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] std::size_t max_markdown_bytes() const noexcept;

    [[nodiscard]] std::vector<QuickNote> load() const;
    [[nodiscard]] std::optional<QuickNote> find(std::int64_t id) const;
    [[nodiscard]] std::vector<QuickNote> search(std::string_view query) const;
    [[nodiscard]] std::optional<std::int64_t> create(
        std::string markdown,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool update(
        std::int64_t id,
        std::string markdown,
        std::int64_t now_unix_ms) const;
    [[nodiscard]] bool remove(std::int64_t id) const;
    [[nodiscard]] bool ensure_welcome_note(
        std::string markdown,
        std::int64_t now_unix_ms) const;

private:
    [[nodiscard]] bool valid_markdown(std::string_view markdown) const noexcept;

    std::filesystem::path directory_;
    std::size_t max_markdown_bytes_;
};

}  // namespace zisla::core
