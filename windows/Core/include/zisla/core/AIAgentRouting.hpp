#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace zisla::core {

enum class AgentChannelProtocol {
    openai_compatible,
    anthropic_messages,
    gemini_generate_content,
};

[[nodiscard]] std::optional<AgentChannelProtocol> parse_agent_channel_protocol(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_channel_protocol_token(
    AgentChannelProtocol protocol) noexcept;

enum class AgentBalanceProbeKind {
    openai_credits,
    anthropic_usage,
    new_api_quota,
    custom_script,
};

[[nodiscard]] std::optional<AgentBalanceProbeKind> parse_agent_balance_probe_kind(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_balance_probe_kind_token(
    AgentBalanceProbeKind kind) noexcept;

struct AgentBalanceProbe {
    AgentBalanceProbeKind kind{AgentBalanceProbeKind::new_api_quota};
    std::optional<std::string> script_path;
    std::optional<double> minimum_balance;

    AgentBalanceProbe() = default;
    AgentBalanceProbe(
        AgentBalanceProbeKind kind,
        std::optional<std::string> script_path = std::nullopt,
        std::optional<double> minimum_balance = std::nullopt);

    friend bool operator==(const AgentBalanceProbe&, const AgentBalanceProbe&) = default;
};

struct AgentBalanceSnapshot {
    std::optional<double> available;
    std::optional<double> used;
    std::string currency{"USD"};
    std::int64_t checked_at_unix_ms{0};
    std::optional<std::string> detail;

    friend bool operator==(const AgentBalanceSnapshot&, const AgentBalanceSnapshot&) = default;
};

enum class AgentAccountCredentialKind {
    api_key,
    cli_profile,
};

[[nodiscard]] std::optional<AgentAccountCredentialKind>
parse_agent_account_credential_kind(std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_account_credential_kind_token(
    AgentAccountCredentialKind kind) noexcept;

enum class AgentCLIKind {
    claude,
    codex,
    gemini,
    grok,
    opencode,
};

[[nodiscard]] std::optional<AgentCLIKind> parse_agent_cli_kind(
    std::string_view token) noexcept;
[[nodiscard]] std::string_view agent_cli_kind_token(AgentCLIKind kind) noexcept;

struct AgentCLIProfile {
    AgentCLIKind cli_kind{AgentCLIKind::codex};
    std::string configuration_file_path;
    std::string authentication_file_path;

    [[nodiscard]] bool is_complete() const noexcept;

    friend bool operator==(const AgentCLIProfile&, const AgentCLIProfile&) = default;
};

struct AgentAccount {
    std::string id;
    std::string name;
    std::string provider;
    std::string secret_reference;
    AgentAccountCredentialKind credential_kind{AgentAccountCredentialKind::api_key};
    std::optional<AgentCLIProfile> cli_profile;
    bool is_enabled{true};
    std::optional<AgentBalanceProbe> balance_probe;
    std::optional<AgentBalanceSnapshot> balance;
    std::uint32_t consecutive_failures{0};
    std::optional<std::int64_t> disabled_until_unix_ms;

    [[nodiscard]] bool is_eligible(std::int64_t now_unix_ms) const noexcept;

    friend bool operator==(const AgentAccount&, const AgentAccount&) = default;
};

struct AgentEndpointGroup {
    std::string id;
    std::string name;
    std::vector<std::string> base_urls;
    std::vector<std::string> account_ids;
    bool is_enabled{true};
    int priority{0};

    [[nodiscard]] static AgentEndpointGroup make(
        std::string id,
        std::string name,
        std::vector<std::string> base_urls,
        std::vector<std::string> account_ids,
        bool is_enabled = true,
        int priority = 0);
    [[nodiscard]] static std::vector<std::string> normalize_base_urls(
        std::vector<std::string> values);
    [[nodiscard]] static std::vector<std::string> normalize_account_ids(
        std::vector<std::string> values);

    friend bool operator==(const AgentEndpointGroup&, const AgentEndpointGroup&) = default;
};

struct AgentChannel {
    std::string id;
    std::string name;
    AgentChannelProtocol protocol_kind{AgentChannelProtocol::openai_compatible};
    std::string default_model;
    std::vector<AgentEndpointGroup> endpoint_groups;
    bool is_enabled{true};

    friend bool operator==(const AgentChannel&, const AgentChannel&) = default;
};

struct AgentRoute {
    std::string channel_id;
    std::string endpoint_group_id;
    std::string account_id;
    std::string base_url;
    AgentChannelProtocol protocol_kind{AgentChannelProtocol::openai_compatible};
    std::string model;

    friend bool operator==(const AgentRoute&, const AgentRoute&) = default;
};

/// Callers serialize access when a shared router selects routes for one channel.
class AgentRouteRouter {
public:
    [[nodiscard]] std::optional<AgentRoute> next_route(
        const AgentChannel& channel,
        std::span<const AgentAccount> accounts,
        std::optional<std::string_view> model_override,
        std::int64_t now_unix_ms,
        std::span<const std::string> unavailable_endpoint_group_ids = {});
    void reset_channel(std::string_view channel_id);

private:
    std::unordered_map<std::string, std::size_t> cursors_;
};

enum class AgentChannelHealth {
    unknown,
    healthy,
    degraded,
    unavailable,
};

struct AgentChannelProbe {
    std::string id;
    std::string channel_id;
    std::string endpoint_group_id;
    std::string base_url;
    AgentChannelHealth health{AgentChannelHealth::unknown};
    std::optional<std::int32_t> latency_milliseconds;
    std::optional<std::string> detail;
    std::int64_t checked_at_unix_ms{0};

    friend bool operator==(const AgentChannelProbe&, const AgentChannelProbe&) = default;
};

struct AgentChannelModelCatalog {
    std::string channel_id;
    std::string endpoint_group_id;
    std::string base_url;
    std::vector<std::string> models;
    std::int64_t checked_at_unix_ms{0};
    std::optional<std::string> detail;

    [[nodiscard]] std::string id() const;
    [[nodiscard]] static std::vector<std::string> normalize_models(
        std::vector<std::string> values);

    friend bool operator==(
        const AgentChannelModelCatalog&,
        const AgentChannelModelCatalog&) = default;
};

}  // namespace zisla::core
