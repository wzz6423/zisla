#include "zisla/core/AIAgentRouting.hpp"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <utility>

namespace zisla::core {
namespace {

char ascii_lower(char value) noexcept {
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

bool is_absolute_agent_path(std::string_view value) noexcept {
    if (value.empty()) {
        return false;
    }
    if (value.front() == '/') {
        return true;
    }
    if (value.size() >= 2
        && ((value[0] == '\\' && value[1] == '\\')
            || (value[0] == '/' && value[1] == '/'))) {
        return true;
    }
    return value.size() >= 3
        && std::isalpha(static_cast<unsigned char>(value[0]))
        && value[1] == ':'
        && (value[2] == '\\' || value[2] == '/');
}

bool is_unavailable(
    std::string_view endpoint_group_id,
    std::span<const std::string> unavailable_endpoint_group_ids) {
    return std::any_of(
        unavailable_endpoint_group_ids.begin(),
        unavailable_endpoint_group_ids.end(),
        [endpoint_group_id](const std::string& value) {
            return value == endpoint_group_id;
        });
}

const AgentAccount* account_with_id(
    std::span<const AgentAccount> accounts,
    std::string_view id) noexcept {
    const auto found = std::find_if(
        accounts.begin(), accounts.end(), [id](const AgentAccount& account) {
            return account.id == id;
        });
    return found == accounts.end() ? nullptr : &*found;
}

}  // namespace

std::optional<AgentChannelProtocol> parse_agent_channel_protocol(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "openai-compatible")) {
        return AgentChannelProtocol::openai_compatible;
    }
    if (ascii_case_equal(token, "anthropic-messages")) {
        return AgentChannelProtocol::anthropic_messages;
    }
    if (ascii_case_equal(token, "gemini-generate-content")) {
        return AgentChannelProtocol::gemini_generate_content;
    }
    return std::nullopt;
}

std::string_view agent_channel_protocol_token(
    AgentChannelProtocol protocol) noexcept {
    switch (protocol) {
    case AgentChannelProtocol::openai_compatible: return "openai-compatible";
    case AgentChannelProtocol::anthropic_messages: return "anthropic-messages";
    case AgentChannelProtocol::gemini_generate_content: return "gemini-generate-content";
    }
    return {};
}

std::optional<AgentBalanceProbeKind> parse_agent_balance_probe_kind(
    std::string_view token) noexcept {
    if (ascii_case_equal(token, "openai-credits")) {
        return AgentBalanceProbeKind::openai_credits;
    }
    if (ascii_case_equal(token, "anthropic-usage")) {
        return AgentBalanceProbeKind::anthropic_usage;
    }
    if (ascii_case_equal(token, "new-api-quota")) {
        return AgentBalanceProbeKind::new_api_quota;
    }
    if (ascii_case_equal(token, "custom-script")) {
        return AgentBalanceProbeKind::custom_script;
    }
    return std::nullopt;
}

std::string_view agent_balance_probe_kind_token(
    AgentBalanceProbeKind kind) noexcept {
    switch (kind) {
    case AgentBalanceProbeKind::openai_credits: return "openai-credits";
    case AgentBalanceProbeKind::anthropic_usage: return "anthropic-usage";
    case AgentBalanceProbeKind::new_api_quota: return "new-api-quota";
    case AgentBalanceProbeKind::custom_script: return "custom-script";
    }
    return {};
}

AgentBalanceProbe::AgentBalanceProbe(
    AgentBalanceProbeKind kind,
    std::optional<std::string> script_path,
    std::optional<double> minimum_balance)
    : kind(kind),
      script_path(std::move(script_path)),
      minimum_balance(minimum_balance) {
    if (this->minimum_balance) {
        if (!std::isfinite(*this->minimum_balance)) {
            this->minimum_balance.reset();
        } else {
            *this->minimum_balance = std::max(0.0, *this->minimum_balance);
        }
    }
}

std::optional<AgentAccountCredentialKind>
parse_agent_account_credential_kind(std::string_view token) noexcept {
    if (ascii_case_equal(token, "api-key")) {
        return AgentAccountCredentialKind::api_key;
    }
    if (ascii_case_equal(token, "cli-profile")) {
        return AgentAccountCredentialKind::cli_profile;
    }
    return std::nullopt;
}

std::string_view agent_account_credential_kind_token(
    AgentAccountCredentialKind kind) noexcept {
    switch (kind) {
    case AgentAccountCredentialKind::api_key: return "api-key";
    case AgentAccountCredentialKind::cli_profile: return "cli-profile";
    }
    return {};
}

std::optional<AgentCLIKind> parse_agent_cli_kind(std::string_view token) noexcept {
    if (ascii_case_equal(token, "claude")) return AgentCLIKind::claude;
    if (ascii_case_equal(token, "codex")) return AgentCLIKind::codex;
    if (ascii_case_equal(token, "gemini")) return AgentCLIKind::gemini;
    if (ascii_case_equal(token, "grok")) return AgentCLIKind::grok;
    if (ascii_case_equal(token, "opencode")) return AgentCLIKind::opencode;
    return std::nullopt;
}

std::string_view agent_cli_kind_token(AgentCLIKind kind) noexcept {
    switch (kind) {
    case AgentCLIKind::claude: return "claude";
    case AgentCLIKind::codex: return "codex";
    case AgentCLIKind::gemini: return "gemini";
    case AgentCLIKind::grok: return "grok";
    case AgentCLIKind::opencode: return "opencode";
    }
    return {};
}

bool AgentCLIProfile::is_complete() const noexcept {
    return configuration_file_path != authentication_file_path
        && is_absolute_agent_path(configuration_file_path)
        && is_absolute_agent_path(authentication_file_path);
}

bool AgentAccount::is_eligible(std::int64_t now_unix_ms) const noexcept {
    if (!is_enabled
        || (disabled_until_unix_ms && *disabled_until_unix_ms > now_unix_ms)) {
        return false;
    }
    if (!balance_probe || !balance_probe->minimum_balance
        || !balance || !balance->available) {
        return true;
    }
    return std::isfinite(*balance->available)
        && *balance->available >= *balance_probe->minimum_balance;
}

AgentEndpointGroup AgentEndpointGroup::make(
    std::string id,
    std::string name,
    std::vector<std::string> base_urls,
    std::vector<std::string> account_ids,
    bool is_enabled,
    int priority) {
    return {
        .id = std::move(id),
        .name = std::move(name),
        .base_urls = normalize_base_urls(std::move(base_urls)),
        .account_ids = normalize_account_ids(std::move(account_ids)),
        .is_enabled = is_enabled,
        .priority = priority,
    };
}

std::vector<std::string> AgentEndpointGroup::normalize_base_urls(
    std::vector<std::string> values) {
    std::vector<std::string> normalized;
    normalized.reserve(values.size());
    for (auto& value : values) {
        value = trim_ascii(value);
        if (value.empty()
            || std::find(normalized.begin(), normalized.end(), value) != normalized.end()) {
            continue;
        }
        normalized.push_back(std::move(value));
    }
    return normalized;
}

std::vector<std::string> AgentEndpointGroup::normalize_account_ids(
    std::vector<std::string> values) {
    std::vector<std::string> normalized;
    normalized.reserve(values.size());
    for (auto& value : values) {
        value = trim_ascii(value);
        if (value.empty()
            || std::find(normalized.begin(), normalized.end(), value) != normalized.end()) {
            continue;
        }
        normalized.push_back(std::move(value));
    }
    return normalized;
}

std::optional<AgentRoute> AgentRouteRouter::next_route(
    const AgentChannel& channel,
    std::span<const AgentAccount> accounts,
    std::optional<std::string_view> model_override,
    std::int64_t now_unix_ms,
    std::span<const std::string> unavailable_endpoint_group_ids) {
    if (!channel.is_enabled) {
        return std::nullopt;
    }
    const auto model = trim_ascii(model_override.value_or(channel.default_model));
    if (model.empty()) {
        return std::nullopt;
    }

    std::vector<const AgentEndpointGroup*> groups;
    groups.reserve(channel.endpoint_groups.size());
    for (const auto& group : channel.endpoint_groups) {
        if (group.is_enabled
            && !is_unavailable(group.id, unavailable_endpoint_group_ids)) {
            groups.push_back(&group);
        }
    }
    std::stable_sort(groups.begin(), groups.end(), [](const auto* lhs, const auto* rhs) {
        return lhs->priority > rhs->priority;
    });

    struct Candidate {
        const AgentEndpointGroup* group;
        const std::string* base_url;
        const AgentAccount* account;
    };
    std::vector<Candidate> candidates;
    std::optional<int> selected_priority;
    for (const auto* group : groups) {
        if (selected_priority && group->priority != *selected_priority) {
            if (!candidates.empty()) {
                break;
            }
            selected_priority = group->priority;
        }
        if (!selected_priority) {
            selected_priority = group->priority;
        }
        for (const auto& base_url : group->base_urls) {
            for (const auto& account_id : group->account_ids) {
                const auto* account = account_with_id(accounts, account_id);
                if (account && account->is_eligible(now_unix_ms)) {
                    candidates.push_back({group, &base_url, account});
                }
            }
        }
    }
    if (candidates.empty()) {
        return std::nullopt;
    }

    auto& cursor = cursors_[channel.id];
    const auto& candidate = candidates[cursor % candidates.size()];
    cursor = (cursor + 1) % candidates.size();
    return AgentRoute{
        .channel_id = channel.id,
        .endpoint_group_id = candidate.group->id,
        .account_id = candidate.account->id,
        .base_url = *candidate.base_url,
        .protocol_kind = channel.protocol_kind,
        .model = model,
    };
}

void AgentRouteRouter::reset_channel(std::string_view channel_id) {
    cursors_.erase(std::string(channel_id));
}

std::string AgentChannelModelCatalog::id() const {
    return channel_id + "|" + endpoint_group_id + "|" + base_url;
}

std::vector<std::string> AgentChannelModelCatalog::normalize_models(
    std::vector<std::string> values) {
    auto normalized = AgentEndpointGroup::normalize_base_urls(std::move(values));
    std::sort(normalized.begin(), normalized.end());
    return normalized;
}

}  // namespace zisla::core
