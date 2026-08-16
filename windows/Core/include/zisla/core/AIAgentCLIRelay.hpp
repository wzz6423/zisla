#pragma once

#include "zisla/core/AIAgentWorkspace.hpp"

#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct AgentCLIRelayProjectContext {
    std::string_view name;
    std::string_view instructions;
};

struct AgentCLIRelayCommand {
    AgentCLIKind cli_kind{AgentCLIKind::codex};
    std::vector<std::string> arguments;
    std::string standard_input;

    friend bool operator==(const AgentCLIRelayCommand&, const AgentCLIRelayCommand&) = default;
};

/// Builds the fixed command contract used to relay a local workspace conversation to an official CLI.
class AIAgentCLIRelay {
public:
    static constexpr std::size_t maximum_history_messages = 32;
    static constexpr std::size_t maximum_prompt_bytes = 4U * 1024U * 1024U;
    static constexpr std::size_t maximum_response_bytes = 4U * 1024U * 1024U;

    [[nodiscard]] static std::vector<std::string> arguments_for(AgentCLIKind cli_kind);
    [[nodiscard]] static std::string build_prompt(
        std::span<const AgentWorkspaceMessage> messages,
        const AgentWorkspaceThread& thread,
        std::optional<AgentCLIRelayProjectContext> project = std::nullopt);
    [[nodiscard]] static AgentCLIRelayCommand make_command(
        AgentCLIKind cli_kind,
        std::span<const AgentWorkspaceMessage> messages,
        const AgentWorkspaceThread& thread,
        std::optional<AgentCLIRelayProjectContext> project = std::nullopt);
    [[nodiscard]] static std::string response_from_stdout(std::string_view standard_output);
};

}  // namespace zisla::core
