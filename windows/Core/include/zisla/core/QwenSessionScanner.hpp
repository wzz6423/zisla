#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct QwenSessionScanOptions {
    std::filesystem::path projects_directory;
    std::size_t max_runtime_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
    std::size_t maximum_runtime_bytes{1'024 * 1'024};
    std::function<bool(std::uint32_t)> is_process_alive;
};

/// Scans Qwen Code runtime sidecars and transcripts without retaining message text.
class QwenSessionScanner {
public:
    explicit QwenSessionScanner(QwenSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view session_id);

private:
    QwenSessionScanOptions options_;
};

}  // namespace zisla::core
