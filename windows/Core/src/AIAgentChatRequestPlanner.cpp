#include "zisla/core/AIAgentChatRequestPlanner.hpp"

#include <algorithm>
#include <stdexcept>
#include <string_view>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

std::string trim_ascii(std::string_view value) {
    const auto is_space = [](unsigned char character) noexcept {
        return character == ' ' || character == '\t' || character == '\n'
            || character == '\r' || character == '\f' || character == '\v';
    };
    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return std::string(value);
}

const AgentChannel* find_channel(
    const AIAgentRoutingState& routing,
    std::string_view id) {
    const auto found = std::find_if(
        routing.channels.begin(),
        routing.channels.end(),
        [id](const AgentChannel& channel) { return channel.id == id; });
    return found == routing.channels.end() ? nullptr : &*found;
}

std::string system_prompt(
    const AIAgentWorkspaceState& workspace,
    const AgentWorkspaceThread& thread) {
    std::vector<std::string> sections;
    for (const auto& message : workspace.messages) {
        if (message.thread_id == thread.id
            && message.role == AgentWorkspaceMessageRole::system) {
            const auto content = trim_ascii(message.content);
            if (!content.empty()) {
                sections.push_back(std::move(content));
            }
        }
    }
    if (thread.mode == AgentWorkspaceChatMode::plan) {
        sections.emplace_back(
            "[Plan mode]\nProvide an executable plan, current progress, and the next step.");
    }
    const auto goal = thread.goal_prompt ? trim_ascii(*thread.goal_prompt) : std::string{};
    if (!goal.empty()) {
        sections.emplace_back(
            "[Goal mode]\nCurrent conversation goal: " + goal
            + "\nStay focused on this goal.");
    }

    std::string result;
    for (const auto& section : sections) {
        if (!result.empty()) {
            result.append("\n\n");
        }
        result.append(section);
    }
    return result;
}

std::vector<AgentAccount> api_accounts(const AIAgentRoutingState& routing) {
    std::vector<AgentAccount> result;
    result.reserve(routing.accounts.size());
    for (const auto& account : routing.accounts) {
        if (account.credential_kind == AgentAccountCredentialKind::api_key) {
            result.push_back(account);
        }
    }
    return result;
}

}  // namespace

std::optional<std::string> AIAgentChatRequestPlanner::default_api_channel_id(
    const AIAgentRoutingState& routing) {
    const auto found = std::find_if(
        routing.channels.begin(),
        routing.channels.end(),
        [](const AgentChannel& channel) {
            return channel.is_enabled;
        });
    if (found == routing.channels.end()) {
        return std::nullopt;
    }
    return found->id;
}

std::optional<std::string> AIAgentChatRequestPlanner::default_openai_channel_id(
    const AIAgentRoutingState& routing) {
    const auto found = std::find_if(
        routing.channels.begin(),
        routing.channels.end(),
        [](const AgentChannel& channel) {
            return channel.is_enabled
                && channel.protocol_kind == AgentChannelProtocol::openai_compatible;
        });
    return found == routing.channels.end()
        ? std::nullopt
        : std::optional<std::string>{found->id};
}

AIAgentChatRequestPlan AIAgentChatRequestPlanner::make_plan(
    const AIAgentWorkspaceState& workspace,
    const AgentWorkspaceThread& thread,
    const AIAgentRoutingState& routing,
    AgentRouteRouter& router,
    std::int64_t now_unix_ms) {
    const auto channel_id = thread.channel_id
        ? thread.channel_id
        : default_api_channel_id(routing);
    if (!channel_id) {
        throw std::runtime_error("No enabled API channel is configured");
    }
    const auto* channel = find_channel(routing, *channel_id);
    if (!channel || !channel->is_enabled) {
        throw std::runtime_error("The selected AI Agent channel is unavailable");
    }
    const auto accounts = api_accounts(routing);
    std::optional<std::string_view> model_override;
    if (thread.selected_model) {
        model_override = *thread.selected_model;
    }
    const auto route = router.next_route(
        *channel,
        accounts,
        model_override,
        now_unix_ms);
    if (!route) {
        throw std::runtime_error("No eligible API key route is available");
    }

    OpenAIChatCompletionRequest request{
        .model = route->model,
        .system_prompt = system_prompt(workspace, thread),
        .messages = {},
    };
    for (const auto& message : workspace.messages) {
        if (message.thread_id != thread.id
            || message.role == AgentWorkspaceMessageRole::system
            || message.content.empty()) {
            continue;
        }
        request.messages.push_back({
            .role = message.role,
            .content = message.content,
        });
    }
    if (request.messages.empty()) {
        throw std::runtime_error("No message is available for the AI Agent request");
    }
    return {
        .route = *route,
        .request = std::move(request),
    };
}

}  // namespace zisla::core
