#include "zisla/core/AIAgentCLIRelay.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>
#include <vector>

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
    while (!value.empty()
        && is_ascii_whitespace(static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty()
        && is_ascii_whitespace(static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return std::string(value);
}

void append_limited(std::string& target, std::string_view value) {
    if (value.size() > AIAgentCLIRelay::maximum_prompt_bytes - target.size()) {
        throw std::length_error("AI Agent CLI prompt exceeds the maximum size");
    }
    target.append(value);
}

void begin_section(std::string& target, bool& has_section) {
    if (has_section) {
        append_limited(target, "\n\n");
    }
    has_section = true;
}

std::string_view role_label(AgentWorkspaceMessageRole role) noexcept {
    switch (role) {
    case AgentWorkspaceMessageRole::system: return "系统";
    case AgentWorkspaceMessageRole::user: return "用户";
    case AgentWorkspaceMessageRole::assistant: return "Agent";
    }
    return "消息";
}

std::string_view access_mode_label(AgentWorkspaceAccessMode mode) noexcept {
    switch (mode) {
    case AgentWorkspaceAccessMode::auto_review: return "自动审阅";
    case AgentWorkspaceAccessMode::read_only: return "只读";
    case AgentWorkspaceAccessMode::workspace_write: return "工作区写入";
    case AgentWorkspaceAccessMode::full_access: return "完全访问";
    }
    return "自动审阅";
}

std::string_view thinking_depth_label(AgentWorkspaceThinkingDepth depth) noexcept {
    switch (depth) {
    case AgentWorkspaceThinkingDepth::low: return "低";
    case AgentWorkspaceThinkingDepth::medium: return "中";
    case AgentWorkspaceThinkingDepth::high: return "高";
    case AgentWorkspaceThinkingDepth::extra_high: return "超高";
    }
    return "高";
}

void append_skill_references(
    std::string& target,
    bool& has_section,
    std::span<const AgentWorkspaceSkillReference> references) {
    bool has_reference = false;
    for (const auto& reference : references) {
        if (trim_ascii(reference.name).empty() || trim_ascii(reference.path).empty()) {
            continue;
        }
        if (!has_reference) {
            begin_section(target, has_section);
            append_limited(target, "[调用 Skills]\n");
            has_reference = true;
        }
        append_limited(target, "- ");
        append_limited(target, reference.name);
        append_limited(target, "：");
        append_limited(target, reference.path);
        append_limited(target, "\n");
    }
    if (has_reference) {
        append_limited(
            target,
            "这是用户显式选择的 Skill。仅当本机可读取对应路径时加载其 SKILL.md。\n");
    }
}

}  // namespace

std::vector<std::string> AIAgentCLIRelay::arguments_for(AgentCLIKind cli_kind) {
    switch (cli_kind) {
    case AgentCLIKind::claude: return {"-p"};
    case AgentCLIKind::codex: return {"exec", "--skip-git-repo-check", "-"};
    case AgentCLIKind::gemini: return {"-p", "-"};
    case AgentCLIKind::grok: return {"--prompt-file", "-"};
    case AgentCLIKind::opencode: return {"run", "-"};
    }
    return {};
}

std::string AIAgentCLIRelay::build_prompt(
    std::span<const AgentWorkspaceMessage> messages,
    const AgentWorkspaceThread& thread,
    std::optional<AgentCLIRelayProjectContext> project) {
    std::vector<const AgentWorkspaceMessage*> history;
    history.reserve(std::min(messages.size(), maximum_history_messages));
    for (const auto& message : messages) {
        if (message.thread_id == thread.id && !trim_ascii(message.content).empty()) {
            history.push_back(&message);
        }
    }
    if (history.empty()) {
        throw std::invalid_argument("No message is available for the AI Agent CLI request");
    }
    if (history.size() > maximum_history_messages) {
        history.erase(history.begin(), history.end() - maximum_history_messages);
    }

    std::string result;
    bool has_section = false;
    begin_section(result, has_section);
    append_limited(result, "[转发偏好]\n访问模式：");
    append_limited(result, access_mode_label(thread.access_mode));
    if (const auto model = trim_ascii(thread.selected_model.value_or(std::string{}));
        !model.empty()) {
        append_limited(result, "\n模型：");
        append_limited(result, model);
    }
    append_limited(result, "\n思考深度：");
    append_limited(result, thinking_depth_label(thread.thinking_depth));
    append_limited(result, "\n请在外部 CLI 自身允许的权限范围内遵守这些偏好。");

    if (project) {
        const auto name = trim_ascii(project->name);
        const auto instructions = trim_ascii(project->instructions);
        if (!name.empty() || !instructions.empty()) {
            begin_section(result, has_section);
            append_limited(result, "[项目：");
            append_limited(result, name.empty() ? "未命名项目" : name);
            append_limited(result, "]");
            if (!instructions.empty()) {
                append_limited(result, "\n项目说明：");
                append_limited(result, instructions);
            }
            append_limited(result, "\n请将项目说明作为本项目所有会话的共享上下文。");
        }
    }

    for (std::size_t index = 0; index < history.size(); ++index) {
        const auto& message = *history[index];
        begin_section(result, has_section);
        append_limited(result, "[");
        append_limited(result, role_label(message.role));
        append_limited(result, "]\n");
        append_limited(result, message.content);
        if (message.mode == AgentWorkspaceChatMode::plan) {
            begin_section(result, has_section);
            append_limited(result, "[计划模式]\n请给出可执行计划、当前进展和下一步。");
        }
        if (const auto goal = message.goal_title ? trim_ascii(*message.goal_title) : std::string{};
            !goal.empty()) {
            begin_section(result, has_section);
            append_limited(result, "[目标模式]\n当前会话目标：");
            append_limited(result, goal);
            append_limited(result, "\n请围绕该目标推进，不要偏离。");
        }
        if (index + 1 == history.size()) {
            append_skill_references(result, has_section, message.skill_references);
        }
    }

    std::string prompt{"以下是从统一聊天历史转发的消息。请直接回复最后一条用户消息；不要声称此应用本身是 Agent。\n\n"};
    if (result.size() > maximum_prompt_bytes - prompt.size()) {
        throw std::length_error("AI Agent CLI prompt exceeds the maximum size");
    }
    prompt.append(result);
    return prompt;
}

AgentCLIRelayCommand AIAgentCLIRelay::make_command(
    AgentCLIKind cli_kind,
    std::span<const AgentWorkspaceMessage> messages,
    const AgentWorkspaceThread& thread,
    std::optional<AgentCLIRelayProjectContext> project) {
    return {
        .cli_kind = cli_kind,
        .arguments = arguments_for(cli_kind),
        .standard_input = build_prompt(messages, thread, project),
    };
}

std::string AIAgentCLIRelay::response_from_stdout(std::string_view standard_output) {
    if (standard_output.size() > maximum_response_bytes) {
        throw std::length_error("AI Agent CLI response exceeds the maximum size");
    }
    return trim_ascii(standard_output);
}

}  // namespace zisla::core
