#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <vector>

namespace zisla::core {

struct DoubaoSessionScanOptions {
    std::vector<std::filesystem::path> data_roots;
    std::size_t max_files{32};
    std::int64_t recency_threshold_ms{10 * 60 * 1'000};
    bool application_running{false};
    std::int64_t now_unix_ms{0};
};

/// Reports recent Doubao local-data activity only while the app process is running.
class DoubaoSessionScanner {
public:
    explicit DoubaoSessionScanner(DoubaoSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;

private:
    DoubaoSessionScanOptions options_;
};

}  // namespace zisla::core
