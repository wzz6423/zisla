#include <zisla/core/AIAgentChatRequestPlanner.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

AgentChannel openai_channel(std::string id, std::string account_id) {
    return {
        .id = std::move(id),
        .name = "OpenAI compatible",
        .protocol_kind = AgentChannelProtocol::openai_compatible,
        .default_model = "default-model",
        .endpoint_groups = {AgentEndpointGroup::make(
            "primary",
            "Primary",
            {"https://api.example/v1"},
            {std::move(account_id)})},
    };
}

AgentAccount api_account() {
    return {
        .id = "account",
        .name = "Primary account",
        .provider = "OpenAI compatible",
        .secret_reference = "primary",
        .credential_kind = AgentAccountCredentialKind::api_key,
    };
}

void plannerBuildsHistoryAndModePrompt() {
    const auto account = api_account();
    const AgentAccount cli_account{
        .id = "cli-account",
        .name = "CLI account",
        .provider = "CLI",
        .secret_reference = "cli-profile",
        .credential_kind = AgentAccountCredentialKind::cli_profile,
    };
    const AgentWorkspaceThread thread{
        .id = "thread",
        .mode = AgentWorkspaceChatMode::plan,
        .goal_prompt = "Ship the Windows client",
        .selected_model = " override-model ",
    };
    const AIAgentWorkspaceState workspace{
        .threads = {thread},
        .messages = {
            {
                .id = "system",
                .thread_id = thread.id,
                .role = AgentWorkspaceMessageRole::system,
                .content = "Use concise answers.",
            },
            {
                .id = "user-one",
                .thread_id = thread.id,
                .role = AgentWorkspaceMessageRole::user,
                .content = "What is left?",
            },
            {
                .id = "assistant-one",
                .thread_id = thread.id,
                .role = AgentWorkspaceMessageRole::assistant,
                .content = "The network adapter.",
            },
            {
                .id = "other-thread",
                .thread_id = "other",
                .role = AgentWorkspaceMessageRole::user,
                .content = "Do not include this.",
            },
        },
    };
    auto channel = openai_channel("default", cli_account.id);
    channel.endpoint_groups.front().account_ids = {cli_account.id, account.id};
    const AIAgentRoutingState routing{
        .accounts = {cli_account, account},
        .channels = {channel},
    };
    AgentRouteRouter router;

    const auto plan = AIAgentChatRequestPlanner::make_plan(
        workspace,
        thread,
        routing,
        router,
        10);

    expect(plan.route.channel_id == "default" && plan.route.account_id == account.id,
        "an unassigned thread should select an API-key account from the first enabled OpenAI-compatible channel");
    expect(plan.request.model == "override-model",
        "a selected model should override the channel default");
    expect(plan.request.system_prompt.find("Use concise answers.") != std::string::npos
            && plan.request.system_prompt.find("[Plan mode]") != std::string::npos
            && plan.request.system_prompt.find("Ship the Windows client") != std::string::npos,
        "stored system messages, plan mode, and the thread goal should share the system prompt");
    expect(plan.request.messages.size() == 2
            && plan.request.messages.front().content == "What is left?"
            && plan.request.messages.back().content == "The network adapter.",
        "only the selected thread's non-system history should be sent");
}

void plannerRoutesNonOpenAIProtocolsAndRejectsMissingChannels() {
    const auto account = api_account();
    const AgentWorkspaceThread thread{.id = "thread", .channel_id = "anthropic"};
    const AIAgentWorkspaceState workspace{
        .threads = {thread},
        .messages = {{
            .id = "message",
            .thread_id = thread.id,
            .role = AgentWorkspaceMessageRole::user,
            .content = "Hello",
        }},
    };
    const AIAgentRoutingState unsupported{
        .accounts = {account},
        .channels = {{
            .id = "anthropic",
            .name = "Anthropic",
            .protocol_kind = AgentChannelProtocol::anthropic_messages,
            .default_model = "claude-test",
            .endpoint_groups = {AgentEndpointGroup::make(
                "primary",
                "Primary",
                {"https://api.example/v1"},
                {account.id})},
        }},
    };
    AgentRouteRouter router;
    const auto anthropic_plan = AIAgentChatRequestPlanner::make_plan(
        workspace, thread, unsupported, router, 10);
    expect(anthropic_plan.route.protocol_kind == AgentChannelProtocol::anthropic_messages,
        "Anthropic channels should route through the shared API request planner");
    expect(anthropic_plan.request.model == "claude-test"
            && anthropic_plan.request.messages.size() == 1,
        "non-OpenAI routes should retain their selected model and message history");

    const AIAgentRoutingState empty{};
    bool rejected_missing_channel = false;
    try {
        (void)AIAgentChatRequestPlanner::make_plan(
            workspace,
            AgentWorkspaceThread{.id = thread.id},
            empty,
            router,
            10);
    } catch (const std::runtime_error&) {
        rejected_missing_channel = true;
    }
    expect(rejected_missing_channel, "missing channels should be rejected");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"planner builds history and mode prompt", plannerBuildsHistoryAndModePrompt},
        {"planner routes non-OpenAI protocols", plannerRoutesNonOpenAIProtocolsAndRejectsMissingChannels},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
