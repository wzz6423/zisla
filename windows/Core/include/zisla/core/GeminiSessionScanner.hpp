#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct GeminiSessionScanOptions {
    std::filesystem::path sessions_directory;
    std::size_t max_session_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
    std::size_t maximum_legacy_json_bytes{1'024 * 1'024};
};

/// Scans Gemini CLI session records without retaining prompts or responses.
class GeminiSessionScanner {
public:
    explicit GeminiSessionScanner(GeminiSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view session_id);

private:
    GeminiSessionScanOptions options_;
};

}  // namespace zisla::core
