#include <zisla/core/AIAgentCLIRelay.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

AgentWorkspaceMessage message(
    std::string thread_id,
    AgentWorkspaceMessageRole role,
    std::string content) {
    return {
        .id = "message-" + content,
        .thread_id = std::move(thread_id),
        .role = role,
        .content = std::move(content),
    };
}

void usesFixedArgumentsForOfficialCLIs() {
    expect(
        AIAgentCLIRelay::arguments_for(AgentCLIKind::claude)
            == std::vector<std::string>{"-p"},
        "Claude should read the relay prompt from standard input");
    expect(
        AIAgentCLIRelay::arguments_for(AgentCLIKind::codex)
            == std::vector<std::string>{"exec", "--skip-git-repo-check", "-"},
        "Codex should receive the relay prompt through its documented stdin argument");
    expect(
        AIAgentCLIRelay::arguments_for(AgentCLIKind::gemini)
            == std::vector<std::string>{"-p", "-"},
        "Gemini should receive the relay prompt through standard input");
    expect(
        AIAgentCLIRelay::arguments_for(AgentCLIKind::grok)
            == std::vector<std::string>{"--prompt-file", "-"},
        "Grok should receive the relay prompt through standard input");
    expect(
        AIAgentCLIRelay::arguments_for(AgentCLIKind::opencode)
            == std::vector<std::string>{"run", "-"},
        "OpenCode should receive the relay prompt through standard input");
}

void buildsBoundedThreadScopedPrompt() {
    AgentWorkspaceThread thread{
        .id = "target-thread",
        .mode = AgentWorkspaceChatMode::plan,
        .goal_prompt = "完成 Windows 版",
        .access_mode = AgentWorkspaceAccessMode::workspace_write,
        .selected_model = "preferred-model",
        .thinking_depth = AgentWorkspaceThinkingDepth::extra_high,
    };
    std::vector<AgentWorkspaceMessage> messages;
    messages.push_back(message("other-thread", AgentWorkspaceMessageRole::user, "不应出现"));
    for (int index = 0; index < 33; ++index) {
        auto current = message(
            thread.id,
            index % 2 == 0 ? AgentWorkspaceMessageRole::user
                           : AgentWorkspaceMessageRole::assistant,
            "历史-" + std::to_string(index));
        current.mode = AgentWorkspaceChatMode::plan;
        current.goal_title = "完成 Windows 版";
        messages.push_back(std::move(current));
    }
    messages.back().skill_references.push_back({
        .name = "release-plan",
        .path = "C:/skills/release-plan",
    });

    const auto prompt = AIAgentCLIRelay::build_prompt(
        messages,
        thread,
        AgentCLIRelayProjectContext{
            .name = "Zisla",
            .instructions = "保持最小修改",
        });

    expect(
        prompt.find("不应出现") == std::string::npos,
        "messages from another thread must not enter the CLI prompt");
    expect(
        prompt.find("历史-0") == std::string::npos,
        "the oldest message beyond the retained history limit must be omitted");
    expect(
        prompt.find("历史-1") != std::string::npos
            && prompt.find("历史-32") != std::string::npos,
        "the latest retained messages should remain in chronological order");
    expect(
        prompt.find("访问模式：工作区写入") != std::string::npos
            && prompt.find("模型：preferred-model") != std::string::npos
            && prompt.find("思考深度：超高") != std::string::npos,
        "thread preferences should be included without becoming command-line arguments");
    expect(
        prompt.find("[项目：Zisla]") != std::string::npos
            && prompt.find("保持最小修改") != std::string::npos,
        "project context should be relayed when the thread has one");
    expect(
        prompt.find("[调用 Skills]") != std::string::npos
            && prompt.find("release-plan：C:/skills/release-plan") != std::string::npos,
        "only the newest message's explicit Skill selections should be relayed");
}

void rejectsEmptyAndOversizedValues() {
    const AgentWorkspaceThread thread{.id = "thread"};
    try {
        (void)AIAgentCLIRelay::make_command(AgentCLIKind::codex, {}, thread);
        throw std::runtime_error("an empty thread history should be rejected");
    } catch (const std::invalid_argument&) {
    }

    const auto response = AIAgentCLIRelay::response_from_stdout(" \n answer \r\n");
    expect(response == "answer", "CLI output should be trimmed before persistence");

    try {
        const std::string oversized(AIAgentCLIRelay::maximum_response_bytes + 1U, 'x');
        (void)AIAgentCLIRelay::response_from_stdout(oversized);
        throw std::runtime_error("oversized CLI output should be rejected");
    } catch (const std::length_error&) {
    }
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"uses fixed arguments for official CLIs", usesFixedArgumentsForOfficialCLIs},
        {"builds bounded thread-scoped prompt", buildsBoundedThreadScopedPrompt},
        {"rejects empty and oversized values", rejectsEmptyAndOversizedValues},
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
