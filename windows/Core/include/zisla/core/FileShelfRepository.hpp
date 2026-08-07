#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace zisla::core {

struct FileShelfItem {
    std::filesystem::path path;
    std::int64_t added_at_unix_ms{0};

    friend bool operator==(const FileShelfItem&, const FileShelfItem&) = default;
};

class FileShelfRepositoryError : public std::runtime_error {
public:
    explicit FileShelfRepositoryError(std::string message);
};

class FileShelfRepository {
public:
    explicit FileShelfRepository(
        std::filesystem::path directory,
        std::size_t capacity = 99);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] std::size_t capacity() const noexcept;

    [[nodiscard]] std::vector<FileShelfItem> load() const;
    [[nodiscard]] std::size_t add(
        std::span<const std::filesystem::path> paths,
        std::int64_t added_at_unix_ms) const;
    [[nodiscard]] bool remove(const std::filesystem::path& path) const;
    void clear() const;

private:
    std::filesystem::path directory_;
    std::size_t capacity_;
};

}  // namespace zisla::core
