#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct QoderSessionScanOptions {
    std::vector<std::filesystem::path> config_roots;
    std::vector<std::filesystem::path> text_log_roots;
    std::size_t max_log_files{16};
    std::size_t initial_tail_bytes{1U * 1024U * 1024U};
};

/// Parses bounded Qoder CLI and desktop SDK logs without retaining chat content.
class QoderSessionScanner {
public:
    explicit QoderSessionScanner(QoderSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string session_task_id(std::string_view session_id);
    [[nodiscard]] static std::string log_task_id(std::string_view path);

private:
    QoderSessionScanOptions options_;
};

}  // namespace zisla::core
