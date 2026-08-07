#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct HarnessSessionScanOptions {
    std::filesystem::path data_directory;
    std::size_t max_files{8};
    std::int64_t recency_threshold_ms{30 * 60 * 1'000};
    std::int64_t now_unix_ms{0};
};

/// Reports recent harnext data files without reading their contents.
class HarnessSessionScanner {
public:
    explicit HarnessSessionScanner(HarnessSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view file_name);

private:
    HarnessSessionScanOptions options_;
};

}  // namespace zisla::core
