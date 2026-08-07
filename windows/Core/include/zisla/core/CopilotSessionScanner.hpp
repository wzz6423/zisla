#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct CopilotSessionScanOptions {
    std::vector<std::filesystem::path> workspace_storage_roots;
    std::filesystem::path cli_session_state_directory;
    std::size_t max_transcript_files{12};
    std::size_t max_cli_sessions{12};
    std::size_t initial_tail_bytes{1U * 1024U * 1024U};
};

/// Reads bounded Copilot Chat metadata without retaining prompts or responses.
class CopilotSessionScanner {
public:
    explicit CopilotSessionScanner(CopilotSessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string vscode_task_id(std::string_view session_id);
    [[nodiscard]] static std::string cli_task_id(std::string_view session_id);

private:
    CopilotSessionScanOptions options_;
};

}  // namespace zisla::core
