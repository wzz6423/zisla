#pragma once

#include "zisla/core/AIAgentRouting.hpp"
#include "zisla/core/AIAgentSkills.hpp"

#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace zisla::core {

enum class AgentWorkspaceChatMode {
    standard,
    plan,
};

[[nodiscard]] std::optional<AgentWorkspaceChatMode>
parse_agent_workspace_chat_mode(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_workspace_chat_mode_token(
    AgentWorkspaceChatMode mode) noexcept;

enum class AgentWorkspaceGoalStatus {
    active,
    completed,
    abandoned,
};

[[nodiscard]] std::optional<AgentWorkspaceGoalStatus>
parse_agent_workspace_goal_status(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_workspace_goal_status_token(
    AgentWorkspaceGoalStatus status) noexcept;

enum class AgentWorkspaceMessageRole {
    system,
    user,
    assistant,
};

[[nodiscard]] std::optional<AgentWorkspaceMessageRole>
parse_agent_workspace_message_role(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_workspace_message_role_token(
    AgentWorkspaceMessageRole role) noexcept;

enum class AgentWorkspaceAccessMode {
    auto_review,
    read_only,
    workspace_write,
    full_access,
};

[[nodiscard]] std::optional<AgentWorkspaceAccessMode>
parse_agent_workspace_access_mode(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_workspace_access_mode_token(
    AgentWorkspaceAccessMode mode) noexcept;

enum class AgentWorkspaceThinkingDepth {
    low,
    medium,
    high,
    extra_high,
};

[[nodiscard]] std::optional<AgentWorkspaceThinkingDepth>
parse_agent_workspace_thinking_depth(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_workspace_thinking_depth_token(
    AgentWorkspaceThinkingDepth depth) noexcept;

struct AgentWorkspaceSkillReference {
    std::string name;
    std::string path;

    friend bool operator==(const AgentWorkspaceSkillReference&,
                           const AgentWorkspaceSkillReference&) = default;
};

struct AgentWorkspaceGoal {
    std::string id;
    std::string title;
    AgentWorkspaceGoalStatus status{AgentWorkspaceGoalStatus::active};
    std::int64_t created_at_unix_ms{0};
    std::int64_t updated_at_unix_ms{0};

    friend bool operator==(const AgentWorkspaceGoal&, const AgentWorkspaceGoal&) = default;
};

struct AgentWorkspaceProject {
    std::string id;
    std::string name;
    std::string instructions;
    std::string directory_path;
    bool is_pinned{false};
    bool is_collapsed{false};
    std::int64_t created_at_unix_ms{0};
    std::int64_t updated_at_unix_ms{0};

    friend bool operator==(const AgentWorkspaceProject&,
                           const AgentWorkspaceProject&) = default;
};

struct AgentWorkspaceThread {
    std::string id;
    std::string title;
    std::optional<std::string> channel_id;
    std::optional<std::string> local_model_id;
    std::optional<AgentCLIKind> cli_kind;
    std::optional<std::string> account_id;
    std::optional<std::string> external_history_id;
    AgentWorkspaceChatMode mode{AgentWorkspaceChatMode::standard};
    std::optional<std::string> goal_id;
    std::optional<std::string> goal_prompt;
    std::optional<std::string> project_id;
    AgentWorkspaceAccessMode access_mode{AgentWorkspaceAccessMode::auto_review};
    std::optional<std::string> selected_model;
    AgentWorkspaceThinkingDepth thinking_depth{AgentWorkspaceThinkingDepth::high};
    bool is_pinned{false};
    std::optional<std::int64_t> archived_at_unix_ms;
    std::int64_t created_at_unix_ms{0};
    std::int64_t updated_at_unix_ms{0};

    friend bool operator==(const AgentWorkspaceThread&,
                           const AgentWorkspaceThread&) = default;
};

struct AgentWorkspaceMessage {
    std::string id;
    std::string thread_id;
    AgentWorkspaceMessageRole role{AgentWorkspaceMessageRole::user};
    std::string content;
    std::optional<std::string> account_id;
    std::vector<AgentWorkspaceSkillReference> skill_references;
    AgentWorkspaceChatMode mode{AgentWorkspaceChatMode::standard};
    std::optional<std::string> goal_title;
    std::int64_t created_at_unix_ms{0};

    friend bool operator==(const AgentWorkspaceMessage&,
                           const AgentWorkspaceMessage&) = default;
};

struct AIAgentWorkspaceState {
    std::vector<AgentWorkspaceProject> projects;
    std::vector<AgentWorkspaceGoal> goals;
    std::vector<AgentWorkspaceThread> threads;
    std::vector<AgentWorkspaceMessage> messages;

    friend bool operator==(const AIAgentWorkspaceState&,
                           const AIAgentWorkspaceState&) = default;
};

struct AgentWorkspaceMessageCommand {
    std::string content;
    std::vector<AgentWorkspaceSkillReference> skill_references;

    friend bool operator==(const AgentWorkspaceMessageCommand&,
                           const AgentWorkspaceMessageCommand&) = default;
};

struct AgentWorkspaceSetModeCommand {
    AgentWorkspaceChatMode mode{AgentWorkspaceChatMode::standard};
    std::string content;

    friend bool operator==(const AgentWorkspaceSetModeCommand&,
                           const AgentWorkspaceSetModeCommand&) = default;
};

struct AgentWorkspaceSetGoalPromptCommand {
    std::string content;

    friend bool operator==(const AgentWorkspaceSetGoalPromptCommand&,
                           const AgentWorkspaceSetGoalPromptCommand&) = default;
};

using AgentWorkspaceCommand = std::variant<
    AgentWorkspaceMessageCommand,
    AgentWorkspaceSetModeCommand,
    AgentWorkspaceSetGoalPromptCommand>;

enum class AgentWorkspaceParseErrorCode {
    missing_skill_name,
    unavailable_skill,
};

class AgentWorkspaceParseError : public std::runtime_error {
public:
    AgentWorkspaceParseError(
        AgentWorkspaceParseErrorCode code,
        std::string message,
        std::string subject = {});

    [[nodiscard]] AgentWorkspaceParseErrorCode code() const noexcept;
    [[nodiscard]] const std::string& subject() const noexcept;

private:
    AgentWorkspaceParseErrorCode code_;
    std::string subject_;
};

/// Parses local composer commands without executing a Skill or reading its files.
class AgentWorkspaceCommandParser {
public:
    [[nodiscard]] static AgentWorkspaceCommand parse(
        std::string_view raw_value,
        std::span<const AgentSkill> skills);
};

}  // namespace zisla::core
