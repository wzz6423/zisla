#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace zisla::core {

enum class AIProvider {
    claude,
    codex,
    gemini,
    grok,
    gpt,
    copilot,
    kimi,
    qwen,
    coder,
    trae,
    opencode,
    harness,
    doubao,
};

[[nodiscard]] std::optional<AIProvider> parse_ai_provider(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view ai_provider_token(AIProvider provider) noexcept;

enum class NoticeKind {
    info,
    success,
    warning,
    error,
};

[[nodiscard]] std::optional<NoticeKind> parse_notice_kind(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view notice_kind_token(NoticeKind kind) noexcept;

enum class NoticeSide {
    left,
    right,
};

[[nodiscard]] std::optional<NoticeSide> parse_notice_side(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view notice_side_token(NoticeSide side) noexcept;

enum class NoticeStyle {
    standard,
    message,
    status,
    headphone,
};

[[nodiscard]] std::optional<NoticeStyle> parse_notice_style(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view notice_style_token(NoticeStyle style) noexcept;

struct IslandNotice {
    std::string id;
    std::string title;
    std::optional<std::string> detail;
    NoticeKind kind{NoticeKind::info};
    NoticeSide side{NoticeSide::right};
    std::int64_t created_at_unix_ms{0};
    std::optional<double> progress;
    NoticeStyle style{NoticeStyle::standard};
    std::optional<std::string> app_name;
    std::optional<std::string> app_bundle_identifier;
    std::optional<std::string> symbol_name;

    friend bool operator==(const IslandNotice&, const IslandNotice&) = default;
};

struct MessageNotification {
    static constexpr std::size_t maximum_content_length = 48;

    std::string app_name;
    std::string sender;
    std::string content;
    std::optional<std::string> app_bundle_identifier;
    std::int64_t created_at_unix_ms{0};
    std::string pair_id;

    [[nodiscard]] static std::string normalize_content(
        std::string_view raw,
        std::size_t maximum_length = maximum_content_length);
    [[nodiscard]] std::pair<IslandNotice, IslandNotice> make_notices() const;

    friend bool operator==(
        const MessageNotification&,
        const MessageNotification&) = default;
};

enum class AIProgressStatus {
    queued,
    running,
    blocked,
    error,
    succeeded,
    failed,
};

[[nodiscard]] std::optional<AIProgressStatus> parse_ai_progress_status(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view ai_progress_status_token(
    AIProgressStatus status) noexcept;

[[nodiscard]] bool is_active(AIProgressStatus status) noexcept;
[[nodiscard]] NoticeKind notice_kind_for(AIProgressStatus status) noexcept;

struct AIProgressTask {
    std::string id;
    AIProvider provider{AIProvider::claude};
    std::string title;
    std::optional<std::string> detail;
    std::optional<double> progress;
    AIProgressStatus status{AIProgressStatus::running};
    std::int64_t updated_at_unix_ms{0};
    std::optional<std::string> session_uri;
    std::optional<std::string> effort;
    std::optional<std::int64_t> started_at_unix_ms;

    friend bool operator==(const AIProgressTask&, const AIProgressTask&) = default;
};

struct AIUsageSample {
    std::optional<std::string> source_id;
    AIProvider provider{AIProvider::claude};
    std::int64_t timestamp_unix_ms{0};
    std::uint64_t input_tokens{0};
    std::uint64_t output_tokens{0};
    std::optional<double> cost_usd;
    std::optional<std::string> model;

    [[nodiscard]] std::uint64_t total_tokens() const noexcept;

    friend bool operator==(const AIUsageSample&, const AIUsageSample&) = default;
};

}  // namespace zisla::core
