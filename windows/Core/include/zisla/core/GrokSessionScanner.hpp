#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct GrokSessionScanOptions {
    std::filesystem::path sessions_directory;
    std::size_t max_session_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
};

/// Scans Grok CLI event logs without retaining prompt or response text.
class GrokSessionScanner {
public:
    explicit GrokSessionScanner(GrokSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view session_id);

private:
    GrokSessionScanOptions options_;
};

}  // namespace zisla::core
