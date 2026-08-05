#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <vector>

namespace zisla::core {

struct OpenCodeSessionScanOptions {
    std::vector<std::filesystem::path> database_paths;
    std::vector<std::filesystem::path> data_roots;
    std::size_t max_sessions{10};
    std::size_t max_storage_files{64};
    std::size_t maximum_json_bytes{1U * 1024U * 1024U};
    std::int64_t recency_threshold_ms{30 * 60 * 1'000};
    std::int64_t now_unix_ms{0};
};

/// Reads OpenCode's current SQLite state with bounded JSON-storage fallback.
class OpenCodeSessionScanner {
public:
    explicit OpenCodeSessionScanner(OpenCodeSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view session_id);

private:
    OpenCodeSessionScanOptions options_;
};

}  // namespace zisla::core
