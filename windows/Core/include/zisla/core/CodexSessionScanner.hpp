#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <vector>

namespace zisla::core {

struct CodexSessionScanOptions {
    std::filesystem::path sessions_directory;
    std::filesystem::path session_index_path;
    std::size_t max_rollout_files{12};
    std::size_t initial_tail_bytes{1'024 * 1'024};
};

class CodexSessionScanner {
public:
    explicit CodexSessionScanner(CodexSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;

private:
    CodexSessionScanOptions options_;
};

}  // namespace zisla::core
