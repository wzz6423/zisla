#pragma once

#include "zisla/core/AIAgentRoutingRepository.hpp"
#include "zisla/core/OpenAIChatCompletions.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace zisla::core {

struct AIAgentChatRequestPlan {
    AgentRoute route;
    OpenAIChatCompletionRequest request;

    friend bool operator==(const AIAgentChatRequestPlan&,
                           const AIAgentChatRequestPlan&) = default;
};

/// Builds a protocol-neutral outbound request from persisted workspace state.
/// Network and credential handling intentionally remain in the platform adapter.
class AIAgentChatRequestPlanner {
public:
    [[nodiscard]] static std::optional<std::string> default_api_channel_id(
        const AIAgentRoutingState& routing);
    [[nodiscard]] static std::optional<std::string> default_openai_channel_id(
        const AIAgentRoutingState& routing);
    [[nodiscard]] static AIAgentChatRequestPlan make_plan(
        const AIAgentWorkspaceState& workspace,
        const AgentWorkspaceThread& thread,
        const AIAgentRoutingState& routing,
        AgentRouteRouter& router,
        std::int64_t now_unix_ms);
};

}  // namespace zisla::core
