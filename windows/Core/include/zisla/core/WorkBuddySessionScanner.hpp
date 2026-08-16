#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct WorkBuddySessionScanOptions {
    std::filesystem::path sessions_file;
    std::size_t max_sessions{8};
    std::size_t maximum_file_bytes{1U * 1024U * 1024U};
    std::int64_t recency_threshold_ms{30 * 60 * 1'000};
    std::int64_t now_unix_ms{0};
};

/// Reads WorkBuddy's session index without retaining conversation content.
class WorkBuddySessionScanner {
public:
    explicit WorkBuddySessionScanner(WorkBuddySessionScanOptions options);

    [[nodiscard]] std::vector<AIProgressTask> active_tasks() const;
    [[nodiscard]] static std::string task_id(std::string_view conversation_id);

private:
    WorkBuddySessionScanOptions options_;
};

}  // namespace zisla::core
