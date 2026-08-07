#pragma once

#include <zisla/core/AIAgentCLIRelay.hpp>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <filesystem>
#include <mutex>
#include <string>

namespace winrt::Zisla {

struct AIAgentCLIProcessResult {
    std::string standard_output;
    DWORD exit_code{0};
    bool cancelled{false};
    bool timed_out{false};
    bool output_limit_exceeded{false};
};

/// Runs one official CLI in a job object so cancellation also stops its descendants.
class AIAgentCLIRunner {
public:
    AIAgentCLIRunner() = default;
    ~AIAgentCLIRunner();

    AIAgentCLIRunner(const AIAgentCLIRunner&) = delete;
    AIAgentCLIRunner& operator=(const AIAgentCLIRunner&) = delete;

    [[nodiscard]] AIAgentCLIProcessResult run(
        const zisla::core::AgentCLIRelayCommand& command,
        const std::filesystem::path& requested_working_directory,
        std::atomic_bool& cancellation_requested,
        std::chrono::seconds timeout = std::chrono::seconds{300});
    void cancel() noexcept;

private:
    std::mutex mutex_;
    HANDLE active_job_{nullptr};
};

}
