#include <zisla/core/AIAgentWorkspace.hpp>

#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

template <typename Command>
bool is_command(const AgentWorkspaceCommand& value, const Command& expected) {
    const auto* actual = std::get_if<Command>(&value);
    return actual != nullptr && *actual == expected;
}

std::vector<AgentSkill> available_skills() {
    return {
        {
            .name = "release-plan",
            .path = std::filesystem::path{"/skills/release-plan"},
            .source = "user",
        },
        {
            .name = "code-review",
            .path = std::filesystem::path{"/skills/code-review"},
            .source = "user",
        },
        {
            .name = "code review",
            .path = std::filesystem::path{"/skills/code-review-spaced"},
            .source = "user",
        },
    };
}

void parsesConversationModesAndPlainMessages() {
    const auto skills = available_skills();
    expect(is_command(
               AgentWorkspaceCommandParser::parse("/plan 拆分里程碑", skills),
               AgentWorkspaceSetModeCommand{
                .mode = AgentWorkspaceChatMode::plan,
                .content = "拆分里程碑",
            }),
        "plan command should select plan mode");
    expect(is_command(
               AgentWorkspaceCommandParser::parse("/goal 完成发布", skills),
               AgentWorkspaceSetGoalPromptCommand{.content = "完成发布"}),
        "goal command should preserve its prompt");
    expect(is_command(
               AgentWorkspaceCommandParser::parse("  继续讨论  ", skills),
               AgentWorkspaceMessageCommand{
                .content = "继续讨论",
                .skill_references = {},
            }),
        "plain text should remain an ordinary message");
}

void selectsEnabledSkillsAndPreservesTheirOrder() {
    const auto skills = available_skills();
    expect(is_command(
               AgentWorkspaceCommandParser::parse("/release-plan /code-review 检查风险", skills),
               AgentWorkspaceMessageCommand{
                .content = "检查风险",
                .skill_references = {
                    {.name = "release-plan", .path = "/skills/release-plan"},
                    {.name = "code-review", .path = "/skills/code-review"},
                },
            }),
        "named Skills should be selected in composer order");
    expect(is_command(
               AgentWorkspaceCommandParser::parse("/skill code review 生成计划", skills),
               AgentWorkspaceMessageCommand{
                .content = "生成计划",
                .skill_references = {
                    {.name = "code review", .path = "/skills/code-review-spaced"},
                },
            }),
        "skill alias should select the longest enabled matching Skill name");
    expect(is_command(
               AgentWorkspaceCommandParser::parse(
                   "/release-plan /skill code review /release-plan 检查风险", skills),
               AgentWorkspaceMessageCommand{
                .content = "检查风险",
                .skill_references = {
                    {.name = "release-plan", .path = "/skills/release-plan"},
                    {.name = "code review", .path = "/skills/code-review-spaced"},
                },
            }),
        "repeated Skill references should be de-duplicated without reordering");
}

void rejectsUnavailableSkillsAndLeavesPathsUntouched() {
    auto skills = available_skills();
    skills.push_back({
        .name = "disabled",
        .path = std::filesystem::path{"/skills/disabled"},
        .source = "user",
        .is_enabled = false,
    });
    try {
        (void)AgentWorkspaceCommandParser::parse("/disabled 运行", skills);
        throw std::runtime_error("disabled Skill should not be selected");
    } catch (const AgentWorkspaceParseError& error) {
        expect(error.code() == AgentWorkspaceParseErrorCode::unavailable_skill
                && error.subject() == "disabled",
            "unavailable Skill errors should keep the requested name");
    }
    try {
        (void)AgentWorkspaceCommandParser::parse("/skill", skills);
        throw std::runtime_error("skill alias should require a name");
    } catch (const AgentWorkspaceParseError& error) {
        expect(error.code() == AgentWorkspaceParseErrorCode::missing_skill_name,
            "empty skill alias should have a stable error code");
    }
    expect(is_command(
               AgentWorkspaceCommandParser::parse("/Users/wzz/notes.txt", skills),
               AgentWorkspaceMessageCommand{
                .content = "/Users/wzz/notes.txt",
                .skill_references = {},
            }),
        "filesystem paths must remain ordinary message content");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"parses conversation modes and plain messages", parsesConversationModesAndPlainMessages},
        {"selects enabled Skills and preserves their order", selectsEnabledSkillsAndPreservesTheirOrder},
        {"rejects unavailable Skills and leaves paths untouched", rejectsUnavailableSkillsAndLeavesPathsUntouched},
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
