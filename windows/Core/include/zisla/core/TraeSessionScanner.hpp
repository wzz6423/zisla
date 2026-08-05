#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct TraeSessionScanOptions {
    std::vector<std::filesystem::path> logs_roots;
    std::size_t max_log_files{4};
    std::size_t tail_bytes{512U * 1024U};
};

/// Parses bounded TRAE ai-agent log tails without retaining chat contents.
class TraeSessionScanner {
public:
    explicit TraeSessionScanner(TraeSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view trae_task_id);

private:
    TraeSessionScanOptions options_;
};

}  // namespace zisla::core
