#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct KimiSessionScanOptions {
    std::filesystem::path home_directory;
    std::size_t max_session_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
    std::size_t maximum_state_bytes{1'024 * 1'024};
};

/// Scans Kimi Code session state without retaining prompt or response text.
class KimiSessionScanner {
public:
    explicit KimiSessionScanner(KimiSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view session_id);

private:
    KimiSessionScanOptions options_;
};

}  // namespace zisla::core
