#include "zisla/core/AIModels.hpp"

#include <array>
#include <limits>
#include <utility>

namespace zisla::core {
namespace {

struct ProviderAlias {
    std::string_view token;
    AIProvider provider;
};

constexpr auto provider_aliases = std::to_array<ProviderAlias>({
    {"claude", AIProvider::claude},
    {"claude-code", AIProvider::claude},
    {"claude-cli", AIProvider::claude},
    {"claude-desktop", AIProvider::claude},
    {"anthropic-claude", AIProvider::claude},
    {"codex", AIProvider::codex},
    {"openai-codex", AIProvider::codex},
    {"codex-cli", AIProvider::codex},
    {"codex-desktop", AIProvider::codex},
    {"codex-app", AIProvider::codex},
    {"gemini", AIProvider::gemini},
    {"google-gemini", AIProvider::gemini},
    {"gemini-cli", AIProvider::gemini},
    {"gemini-code-assist", AIProvider::gemini},
    {"grok", AIProvider::grok},
    {"grok-cli", AIProvider::grok},
    {"xai", AIProvider::grok},
    {"x-ai", AIProvider::grok},
    {"gpt", AIProvider::gpt},
    {"openai", AIProvider::gpt},
    {"chatgpt", AIProvider::gpt},
    {"chat-gpt", AIProvider::gpt},
    {"openai-gpt", AIProvider::gpt},
    {"copilot", AIProvider::copilot},
    {"github-copilot", AIProvider::copilot},
    {"github copilot", AIProvider::copilot},
    {"copilot-cli", AIProvider::copilot},
    {"copilot-chat", AIProvider::copilot},
    {"github.copilot-chat", AIProvider::copilot},
    {"kimi", AIProvider::kimi},
    {"kimi-code", AIProvider::kimi},
    {"kimi-code-cli", AIProvider::kimi},
    {"kimi-vscode", AIProvider::kimi},
    {"moonshot-kimi", AIProvider::kimi},
    {"moonshot-ai.kimi-code", AIProvider::kimi},
    {"qwen", AIProvider::qwen},
    {"tongyi", AIProvider::qwen},
    {"qwen-code", AIProvider::qwen},
    {"qwen-code-cli", AIProvider::qwen},
    {"qwen-vscode", AIProvider::qwen},
    {"coder", AIProvider::coder},
    {"qwen-coder", AIProvider::coder},
    {"qoder", AIProvider::coder},
    {"qoder-cli", AIProvider::coder},
    {"qoderwork", AIProvider::coder},
    {"qoder-work", AIProvider::coder},
    {"qoderworkcn", AIProvider::coder},
    {"qoderwork-cn", AIProvider::coder},
    {"qoderwork cn", AIProvider::coder},
    {"qoderwake", AIProvider::coder},
    {"qoder-wake", AIProvider::coder},
    {"trae", AIProvider::trae},
    {"trae-work", AIProvider::trae},
    {"traework", AIProvider::trae},
    {"trae-work-cn", AIProvider::trae},
    {"trae-solo", AIProvider::trae},
    {"trae-solo-cn", AIProvider::trae},
    {"trae-cn", AIProvider::trae},
    {"opencode", AIProvider::opencode},
    {"open-code", AIProvider::opencode},
    {"open_code", AIProvider::opencode},
    {"harness", AIProvider::harness},
    {"harnext", AIProvider::harness},
    {"harnext-cli", AIProvider::harness},
    {"harness-cli", AIProvider::harness},
    {"doubao", AIProvider::doubao},
    {"\xE8\xB1\x86\xE5\x8C\x85", AIProvider::doubao},
});

constexpr char ascii_lower(char value) noexcept {
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value + ('a' - 'A'))
        : value;
}

bool ascii_case_equal(std::string_view lhs, std::string_view rhs) noexcept {
    if (lhs.size() != rhs.size()) {
        return false;
    }
    for (std::size_t index = 0; index < lhs.size(); ++index) {
        if (ascii_lower(lhs[index]) != ascii_lower(rhs[index])) {
            return false;
        }
    }
    return true;
}

constexpr bool ascii_whitespace(unsigned char value) noexcept {
    return value == ' '
        || value == '\t'
        || value == '\n'
        || value == '\r'
        || value == '\f'
        || value == '\v';
}

std::size_t utf8_prefix_bytes(
    std::string_view value,
    std::size_t maximum_code_points) noexcept {
    std::size_t code_points = 0;
    for (std::size_t index = 0; index < value.size(); ++index) {
        const auto byte = static_cast<unsigned char>(value[index]);
        if ((byte & 0xC0U) == 0x80U) {
            continue;
        }
        if (code_points == maximum_code_points) {
            return index;
        }
        ++code_points;
    }
    return value.size();
}

}  // namespace

std::optional<AIProvider> parse_ai_provider(std::string_view token) noexcept {
    for (const auto& alias : provider_aliases) {
        if (ascii_case_equal(token, alias.token)) {
            return alias.provider;
        }
    }
    return std::nullopt;
}

std::string_view ai_provider_token(AIProvider provider) noexcept {
    switch (provider) {
    case AIProvider::claude: return "claude";
    case AIProvider::codex: return "codex";
    case AIProvider::gemini: return "gemini";
    case AIProvider::grok: return "grok";
    case AIProvider::gpt: return "gpt";
    case AIProvider::copilot: return "copilot";
    case AIProvider::kimi: return "kimi";
    case AIProvider::qwen: return "qwen";
    case AIProvider::coder: return "coder";
    case AIProvider::trae: return "trae";
    case AIProvider::opencode: return "opencode";
    case AIProvider::harness: return "harness";
    case AIProvider::doubao: return "doubao";
    }
    return {};
}

std::optional<NoticeKind> parse_notice_kind(std::string_view token) noexcept {
    if (ascii_case_equal(token, "info")) return NoticeKind::info;
    if (ascii_case_equal(token, "success")) return NoticeKind::success;
    if (ascii_case_equal(token, "warning")) return NoticeKind::warning;
    if (ascii_case_equal(token, "error")) return NoticeKind::error;
    return std::nullopt;
}

std::string_view notice_kind_token(NoticeKind kind) noexcept {
    switch (kind) {
    case NoticeKind::info: return "info";
    case NoticeKind::success: return "success";
    case NoticeKind::warning: return "warning";
    case NoticeKind::error: return "error";
    }
    return {};
}

std::optional<NoticeSide> parse_notice_side(std::string_view token) noexcept {
    if (ascii_case_equal(token, "left")) return NoticeSide::left;
    if (ascii_case_equal(token, "right")) return NoticeSide::right;
    return std::nullopt;
}

std::string_view notice_side_token(NoticeSide side) noexcept {
    switch (side) {
    case NoticeSide::left: return "left";
    case NoticeSide::right: return "right";
    }
    return {};
}

std::optional<NoticeStyle> parse_notice_style(std::string_view token) noexcept {
    if (ascii_case_equal(token, "standard")) return NoticeStyle::standard;
    if (ascii_case_equal(token, "message")) return NoticeStyle::message;
    if (ascii_case_equal(token, "status")) return NoticeStyle::status;
    if (ascii_case_equal(token, "headphone")) return NoticeStyle::headphone;
    return std::nullopt;
}

std::string_view notice_style_token(NoticeStyle style) noexcept {
    switch (style) {
    case NoticeStyle::standard: return "standard";
    case NoticeStyle::message: return "message";
    case NoticeStyle::status: return "status";
    case NoticeStyle::headphone: return "headphone";
    }
    return {};
}

std::string MessageNotification::normalize_content(
    std::string_view raw,
    std::size_t maximum_length) {
    std::string collapsed;
    collapsed.reserve(raw.size());
    bool pending_space = false;
    for (const auto value : raw) {
        if (ascii_whitespace(static_cast<unsigned char>(value))) {
            pending_space = !collapsed.empty();
            continue;
        }
        if (pending_space) {
            collapsed.push_back(' ');
            pending_space = false;
        }
        collapsed.push_back(value);
    }

    const auto prefix_size = utf8_prefix_bytes(collapsed, maximum_length);
    if (prefix_size == collapsed.size()) {
        return collapsed;
    }
    collapsed.resize(prefix_size);
    collapsed += "\xE2\x80\xA6";
    return collapsed;
}

std::pair<IslandNotice, IslandNotice> MessageNotification::make_notices() const {
    IslandNotice left{
        .id = "message-" + pair_id + "-left",
        .title = sender,
        .detail = app_name,
        .kind = NoticeKind::info,
        .side = NoticeSide::left,
        .created_at_unix_ms = created_at_unix_ms,
        .style = NoticeStyle::message,
        .app_name = app_name,
        .app_bundle_identifier = app_bundle_identifier,
    };
    IslandNotice right{
        .id = "message-" + pair_id + "-right",
        .title = normalize_content(content),
        .kind = NoticeKind::info,
        .side = NoticeSide::right,
        .created_at_unix_ms = created_at_unix_ms,
        .style = NoticeStyle::message,
        .app_name = app_name,
        .app_bundle_identifier = app_bundle_identifier,
    };
    return {std::move(left), std::move(right)};
}

std::optional<AIProgressStatus> parse_ai_progress_status(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "queued")) return AIProgressStatus::queued;
    if (ascii_case_equal(token, "running")) return AIProgressStatus::running;
    if (ascii_case_equal(token, "blocked")) return AIProgressStatus::blocked;
    if (ascii_case_equal(token, "error")) return AIProgressStatus::error;
    if (ascii_case_equal(token, "succeeded")) return AIProgressStatus::succeeded;
    if (ascii_case_equal(token, "failed")) return AIProgressStatus::failed;
    return std::nullopt;
}

std::string_view ai_progress_status_token(AIProgressStatus status) noexcept {
    switch (status) {
    case AIProgressStatus::queued: return "queued";
    case AIProgressStatus::running: return "running";
    case AIProgressStatus::blocked: return "blocked";
    case AIProgressStatus::error: return "error";
    case AIProgressStatus::succeeded: return "succeeded";
    case AIProgressStatus::failed: return "failed";
    }
    return {};
}

bool is_active(AIProgressStatus status) noexcept {
    switch (status) {
    case AIProgressStatus::queued:
    case AIProgressStatus::running:
    case AIProgressStatus::blocked:
    case AIProgressStatus::error:
        return true;
    case AIProgressStatus::succeeded:
    case AIProgressStatus::failed:
        return false;
    }
    return false;
}

NoticeKind notice_kind_for(AIProgressStatus status) noexcept {
    switch (status) {
    case AIProgressStatus::queued:
    case AIProgressStatus::running:
        return NoticeKind::info;
    case AIProgressStatus::blocked:
        return NoticeKind::warning;
    case AIProgressStatus::error:
    case AIProgressStatus::failed:
        return NoticeKind::error;
    case AIProgressStatus::succeeded:
        return NoticeKind::success;
    }
    return NoticeKind::error;
}

std::uint64_t AIUsageSample::total_tokens() const noexcept {
    const auto remaining = std::numeric_limits<std::uint64_t>::max() - input_tokens;
    return output_tokens > remaining
        ? std::numeric_limits<std::uint64_t>::max()
        : input_tokens + output_tokens;
}

}  // namespace zisla::core
