#pragma once

#include <cstdint>
#include <filesystem>
#include <span>
#include <vector>

namespace zisla::core {

enum class DiskCleanupKind {
    application_cache,
    cache,
    log,
    crash_report,
    temporary_file,
    package_cache,
    developer_artifact,
    large_file,
};

struct DiskCleanupCandidate {
    std::filesystem::path path;
    DiskCleanupKind kind{DiskCleanupKind::cache};
    std::uint64_t size_bytes{0};

    friend bool operator==(
        const DiskCleanupCandidate&,
        const DiskCleanupCandidate&) = default;
};

class DiskCleanupPlanner {
public:
    [[nodiscard]] static bool isDescendantOfAllowedRoot(
        const std::filesystem::path& candidate,
        std::span<const std::filesystem::path> roots) noexcept;

    [[nodiscard]] static bool isAllowedCandidate(
        const DiskCleanupCandidate& candidate,
        std::span<const std::filesystem::path> roots) noexcept;

    [[nodiscard]] static std::vector<DiskCleanupCandidate> deduplicate(
        std::span<const DiskCleanupCandidate> candidates);
};

}  // namespace zisla::core
