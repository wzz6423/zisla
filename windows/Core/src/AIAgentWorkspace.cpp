#include "zisla/core/AIAgentWorkspace.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <optional>
#include <utility>

namespace zisla::core {
namespace {

bool is_ascii_whitespace(unsigned char value) noexcept {
    return value == ' '
        || value == '\t'
        || value == '\n'
        || value == '\r'
        || value == '\f'
        || value == '\v';
}

std::string trim_ascii(std::string_view value) {
    std::size_t first = 0;
    while (first < value.size()
        && is_ascii_whitespace(static_cast<unsigned char>(value[first]))) {
        ++first;
    }
    std::size_t last = value.size();
    while (last > first
        && is_ascii_whitespace(static_cast<unsigned char>(value[last - 1]))) {
        --last;
    }
    return std::string(value.substr(first, last - first));
}

char ascii_lower(char value) noexcept {
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value + ('a' - 'A'))
        : value;
}

bool ascii_case_equal(std::string_view lhs, std::string_view rhs) noexcept {
    return lhs.size() == rhs.size()
        && std::equal(
            lhs.begin(),
            lhs.end(),
            rhs.begin(),
            [](char left, char right) {
                return ascii_lower(left) == ascii_lower(right);
            });
}

struct CommandToken {
    std::string_view name;
    std::string arguments;
};

std::optional<CommandToken> command_token(std::string_view value) {
    if (value.empty() || value.front() != '/') {
        return std::nullopt;
    }
    const auto token_start = std::size_t{1};
    std::size_t token_end = token_start;
    while (token_end < value.size()
        && !is_ascii_whitespace(static_cast<unsigned char>(value[token_end]))) {
        ++token_end;
    }
    if (token_end == token_start) {
        return std::nullopt;
    }
    return CommandToken{
        .name = value.substr(token_start, token_end - token_start),
        .arguments = trim_ascii(value.substr(token_end)),
    };
}

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.generic_u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size()};
}

AgentWorkspaceSkillReference skill_reference(const AgentSkill& skill) {
    return {
        .name = skill.name,
        .path = path_as_utf8(skill.path),
    };
}

const AgentSkill* skill_named(
    std::string_view name,
    std::span<const AgentSkill> skills) noexcept {
    const auto found = std::find_if(skills.begin(), skills.end(), [name](const AgentSkill& skill) {
        return skill.is_enabled && ascii_case_equal(skill.name, name);
    });
    return found == skills.end() ? nullptr : &*found;
}

struct SkillMatch {
    const AgentSkill* skill{nullptr};
    std::string content;
};

std::optional<SkillMatch> skill_match(
    std::string_view arguments,
    std::span<const AgentSkill> skills) {
    const AgentSkill* selected = nullptr;
    for (const auto& skill : skills) {
        if (!skill.is_enabled) {
            continue;
        }
        const auto name = trim_ascii(skill.name);
        if (name.empty() || arguments.size() < name.size()
            || !ascii_case_equal(arguments.substr(0, name.size()), name)) {
            continue;
        }
        if (arguments.size() > name.size()
            && !is_ascii_whitespace(static_cast<unsigned char>(arguments[name.size()]))) {
            continue;
        }
        if (!selected || name.size() > trim_ascii(selected->name).size()) {
            selected = &skill;
        }
    }
    if (!selected) {
        return std::nullopt;
    }
    const auto selected_name = trim_ascii(selected->name);
    return SkillMatch{
        .skill = selected,
        .content = trim_ascii(arguments.substr(selected_name.size())),
    };
}

std::string requested_skill_name(std::string_view arguments) {
    std::size_t end = 0;
    while (end < arguments.size()
        && !is_ascii_whitespace(static_cast<unsigned char>(arguments[end]))) {
        ++end;
    }
    return std::string(arguments.substr(0, end));
}

void append_reference(
    std::vector<AgentWorkspaceSkillReference>& references,
    AgentWorkspaceSkillReference reference) {
    if (std::find(references.begin(), references.end(), reference) == references.end()) {
        references.push_back(std::move(reference));
    }
}

}  // namespace

std::optional<AgentWorkspaceChatMode> parse_agent_workspace_chat_mode(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "standard")) {
        return AgentWorkspaceChatMode::standard;
    }
    if (ascii_case_equal(token, "plan")) {
        return AgentWorkspaceChatMode::plan;
    }
    return std::nullopt;
}

std::string_view agent_workspace_chat_mode_token(
    AgentWorkspaceChatMode mode) noexcept {
    switch (mode) {
    case AgentWorkspaceChatMode::standard: return "standard";
    case AgentWorkspaceChatMode::plan: return "plan";
    }
    return {};
}

std::optional<AgentWorkspaceGoalStatus> parse_agent_workspace_goal_status(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "active")) {
        return AgentWorkspaceGoalStatus::active;
    }
    if (ascii_case_equal(token, "completed")) {
        return AgentWorkspaceGoalStatus::completed;
    }
    if (ascii_case_equal(token, "abandoned")) {
        return AgentWorkspaceGoalStatus::abandoned;
    }
    return std::nullopt;
}

std::string_view agent_workspace_goal_status_token(
    AgentWorkspaceGoalStatus status) noexcept {
    switch (status) {
    case AgentWorkspaceGoalStatus::active: return "active";
    case AgentWorkspaceGoalStatus::completed: return "completed";
    case AgentWorkspaceGoalStatus::abandoned: return "abandoned";
    }
    return {};
}

std::optional<AgentWorkspaceMessageRole> parse_agent_workspace_message_role(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "system")) {
        return AgentWorkspaceMessageRole::system;
    }
    if (ascii_case_equal(token, "user")) {
        return AgentWorkspaceMessageRole::user;
    }
    if (ascii_case_equal(token, "assistant")) {
        return AgentWorkspaceMessageRole::assistant;
    }
    return std::nullopt;
}

std::string_view agent_workspace_message_role_token(
    AgentWorkspaceMessageRole role) noexcept {
    switch (role) {
    case AgentWorkspaceMessageRole::system: return "system";
    case AgentWorkspaceMessageRole::user: return "user";
    case AgentWorkspaceMessageRole::assistant: return "assistant";
    }
    return {};
}

std::optional<AgentWorkspaceAccessMode> parse_agent_workspace_access_mode(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "auto-review")) {
        return AgentWorkspaceAccessMode::auto_review;
    }
    if (ascii_case_equal(token, "read-only")) {
        return AgentWorkspaceAccessMode::read_only;
    }
    if (ascii_case_equal(token, "workspace-write")) {
        return AgentWorkspaceAccessMode::workspace_write;
    }
    if (ascii_case_equal(token, "full-access")) {
        return AgentWorkspaceAccessMode::full_access;
    }
    return std::nullopt;
}

std::string_view agent_workspace_access_mode_token(
    AgentWorkspaceAccessMode mode) noexcept {
    switch (mode) {
    case AgentWorkspaceAccessMode::auto_review: return "auto-review";
    case AgentWorkspaceAccessMode::read_only: return "read-only";
    case AgentWorkspaceAccessMode::workspace_write: return "workspace-write";
    case AgentWorkspaceAccessMode::full_access: return "full-access";
    }
    return {};
}

std::optional<AgentWorkspaceThinkingDepth>
parse_agent_workspace_thinking_depth(std::string_view token) noexcept {
    if (ascii_case_equal(token, "low")) {
        return AgentWorkspaceThinkingDepth::low;
    }
    if (ascii_case_equal(token, "medium")) {
        return AgentWorkspaceThinkingDepth::medium;
    }
    if (ascii_case_equal(token, "high")) {
        return AgentWorkspaceThinkingDepth::high;
    }
    if (ascii_case_equal(token, "extra-high")) {
        return AgentWorkspaceThinkingDepth::extra_high;
    }
    return std::nullopt;
}

std::string_view agent_workspace_thinking_depth_token(
    AgentWorkspaceThinkingDepth depth) noexcept {
    switch (depth) {
    case AgentWorkspaceThinkingDepth::low: return "low";
    case AgentWorkspaceThinkingDepth::medium: return "medium";
    case AgentWorkspaceThinkingDepth::high: return "high";
    case AgentWorkspaceThinkingDepth::extra_high: return "extra-high";
    }
    return {};
}

AgentWorkspaceParseError::AgentWorkspaceParseError(
    AgentWorkspaceParseErrorCode code,
    std::string message,
    std::string subject)
    : std::runtime_error(std::move(message)),
      code_(code),
      subject_(std::move(subject)) {}

AgentWorkspaceParseErrorCode AgentWorkspaceParseError::code() const noexcept {
    return code_;
}

const std::string& AgentWorkspaceParseError::subject() const noexcept {
    return subject_;
}

AgentWorkspaceCommand AgentWorkspaceCommandParser::parse(
    std::string_view raw_value,
    std::span<const AgentSkill> skills) {
    const auto value = trim_ascii(raw_value);
    const auto first = command_token(value);
    if (!first || first->name.find('/') != std::string_view::npos) {
        return AgentWorkspaceMessageCommand{
            .content = value,
            .skill_references = {},
        };
    }
    if (ascii_case_equal(first->name, "plan")) {
        return AgentWorkspaceSetModeCommand{
            .mode = AgentWorkspaceChatMode::plan,
            .content = std::move(first->arguments),
        };
    }
    if (ascii_case_equal(first->name, "goal")) {
        return AgentWorkspaceSetGoalPromptCommand{
            .content = std::move(first->arguments),
        };
    }

    std::string remaining = value;
    std::vector<AgentWorkspaceSkillReference> references;
    while (const auto token = command_token(remaining)) {
        if (token->name.find('/') != std::string_view::npos) {
            break;
        }

        if (ascii_case_equal(token->name, "skill")) {
            if (token->arguments.empty()) {
                throw AgentWorkspaceParseError(
                    AgentWorkspaceParseErrorCode::missing_skill_name,
                    "An AI Agent Skill name is required");
            }
            const auto match = skill_match(token->arguments, skills);
            if (!match) {
                const auto requested = requested_skill_name(token->arguments);
                throw AgentWorkspaceParseError(
                    AgentWorkspaceParseErrorCode::unavailable_skill,
                    "The requested AI Agent Skill is unavailable",
                    requested);
            }
            append_reference(references, skill_reference(*match->skill));
            remaining = std::move(match->content);
            continue;
        }

        const auto* skill = skill_named(token->name, skills);
        if (!skill) {
            throw AgentWorkspaceParseError(
                AgentWorkspaceParseErrorCode::unavailable_skill,
                "The requested AI Agent Skill is unavailable",
                std::string(token->name));
        }
        append_reference(references, skill_reference(*skill));
        remaining = std::move(token->arguments);
    }

    if (references.empty()) {
        return AgentWorkspaceMessageCommand{
            .content = value,
            .skill_references = {},
        };
    }
    return AgentWorkspaceMessageCommand{
        .content = std::move(remaining),
        .skill_references = std::move(references),
    };
}

}  // namespace zisla::core
