#include <zisla/core/AIAgentRouting.hpp>

#include <array>
#include <exception>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

using namespace zisla::core;

namespace {

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void tokensRoundTrip() {
    expect(
        parse_agent_channel_protocol("ANTHROPIC-MESSAGES")
            == AgentChannelProtocol::anthropic_messages,
        "channel protocol should parse case-insensitively");
    expect(
        agent_channel_protocol_token(AgentChannelProtocol::gemini_generate_content)
            == "gemini-generate-content",
        "channel protocol should have a stable token");
    expect(
        parse_agent_balance_probe_kind("custom-script")
            == AgentBalanceProbeKind::custom_script,
        "balance probe should round trip");
    expect(
        agent_account_credential_kind_token(AgentAccountCredentialKind::cli_profile)
            == "cli-profile",
        "credential kind should have a stable token");
    expect(
        parse_agent_cli_kind("codex") == AgentCLIKind::codex,
        "CLI kind should parse");
    expect(
        !parse_agent_cli_kind("unknown").has_value(),
        "unknown CLI kinds should be rejected");
}

void cliProfilesRequireDistinctAbsolutePaths() {
    expect(
        AgentCLIProfile{
            .cli_kind = AgentCLIKind::codex,
            .configuration_file_path = "C:\\Users\\Zisla\\.codex\\config.toml",
            .authentication_file_path = "C:\\Users\\Zisla\\.codex\\auth.json",
        }.is_complete(),
        "drive-qualified Windows paths should be accepted");
    expect(
        AgentCLIProfile{
            .cli_kind = AgentCLIKind::claude,
            .configuration_file_path = "\\\\server\\share\\claude.json",
            .authentication_file_path = "\\\\server\\share\\credentials.json",
        }.is_complete(),
        "UNC paths should be accepted");
    expect(
        !AgentCLIProfile{
            .cli_kind = AgentCLIKind::gemini,
            .configuration_file_path = ".gemini/settings.json",
            .authentication_file_path = ".gemini/oauth.json",
        }.is_complete(),
        "relative paths should be rejected");
    expect(
        !AgentCLIProfile{
            .cli_kind = AgentCLIKind::grok,
            .configuration_file_path = "/Users/zisla/.grok/auth.json",
            .authentication_file_path = "/Users/zisla/.grok/auth.json",
        }.is_complete(),
        "configuration and authentication paths must differ");
}

void endpointGroupsNormalizeInputs() {
    const auto group = AgentEndpointGroup::make(
        "primary",
        "Primary",
        {" https://one.example/v1 ", "", "https://one.example/v1", "https://two.example/v1"},
        {" first ", "", "first", "second"},
        true,
        10);

    expect(
        group.base_urls
            == std::vector<std::string>{"https://one.example/v1", "https://two.example/v1"},
        "endpoint URLs should be trimmed and deduplicated in order");
    expect(
        group.account_ids == std::vector<std::string>{"first", "second"},
        "account IDs should be trimmed and deduplicated in order");
}

void routeRouterRotatesStablePairsAndSkipsInsufficientBalance() {
    const AgentAccount low_balance{
        .id = "low",
        .name = "Low balance",
        .provider = "OpenAI",
        .secret_reference = "low-secret",
        .balance_probe = AgentBalanceProbe{
            AgentBalanceProbeKind::new_api_quota,
            std::nullopt,
            5.0,
        },
        .balance = AgentBalanceSnapshot{.available = 1.0},
    };
    const AgentAccount first{
        .id = "first",
        .name = "First",
        .provider = "OpenAI",
        .secret_reference = "first-secret",
    };
    const AgentAccount second{
        .id = "second",
        .name = "Second",
        .provider = "OpenAI",
        .secret_reference = "second-secret",
    };
    const auto group = AgentEndpointGroup::make(
        "main",
        "Main",
        {"https://one.example/v1", "https://two.example/v1"},
        {low_balance.id, first.id, second.id},
        true,
        10);
    const AgentChannel channel{
        .id = "channel",
        .name = "Main channel",
        .default_model = "gpt-test",
        .endpoint_groups = {group},
    };
    const std::array accounts{low_balance, first, second};
    AgentRouteRouter router;

    const auto route1 = router.next_route(channel, accounts, std::nullopt, 100);
    const auto route2 = router.next_route(channel, accounts, std::nullopt, 100);
    const auto route3 = router.next_route(channel, accounts, std::nullopt, 100);

    expect(route1 && route2 && route3, "available routes should be selected");
    expect(
        route1->base_url == "https://one.example/v1" && route1->account_id == first.id,
        "first eligible URL/account pair should be selected first");
    expect(
        route2->base_url == "https://one.example/v1" && route2->account_id == second.id,
        "second account should follow in stable order");
    expect(
        route3->base_url == "https://two.example/v1" && route3->account_id == first.id,
        "router should rotate to the next URL/account pair");
}

void routerFallsBackAndRespectsTemporaryUnavailability() {
    const AgentAccount unavailable{
        .id = "unavailable",
        .name = "Unavailable",
        .provider = "OpenAI",
        .secret_reference = "unavailable-secret",
        .balance_probe = AgentBalanceProbe{
            AgentBalanceProbeKind::new_api_quota,
            std::nullopt,
            1.0,
        },
        .balance = AgentBalanceSnapshot{.available = 0.0},
    };
    const AgentAccount backup{
        .id = "backup",
        .name = "Backup",
        .provider = "OpenAI",
        .secret_reference = "backup-secret",
    };
    const auto primary = AgentEndpointGroup::make(
        "primary", "Primary", {"https://primary.example/v1"}, {unavailable.id}, true, 10);
    const auto secondary = AgentEndpointGroup::make(
        "secondary", "Secondary", {"https://backup.example/v1"}, {backup.id}, true, 0);
    const AgentChannel channel{
        .id = "channel",
        .name = "Channel",
        .default_model = "model",
        .endpoint_groups = {primary, secondary},
    };
    const std::array accounts{unavailable, backup};
    AgentRouteRouter router;

    const auto fallback = router.next_route(channel, accounts, std::nullopt, 100);
    expect(
        fallback && fallback->endpoint_group_id == secondary.id,
        "router should fall back when the highest-priority group has no eligible account");

    const std::array blocked{secondary.id};
    expect(
        !router.next_route(channel, accounts, std::nullopt, 100, blocked),
        "temporarily unavailable endpoint groups should not be selected");
}

void routesRespectCooldownAndRequireAModel() {
    const AgentAccount cooling_down{
        .id = "cooldown",
        .name = "Cooldown",
        .provider = "OpenAI",
        .secret_reference = "cooldown-secret",
        .disabled_until_unix_ms = 101,
    };
    const auto group = AgentEndpointGroup::make(
        "main", "Main", {"https://one.example/v1"}, {cooling_down.id});
    const AgentChannel no_model{
        .id = "no-model",
        .name = "No model",
        .default_model = "  ",
        .endpoint_groups = {group},
    };
    const AgentChannel channel{
        .id = "channel",
        .name = "Channel",
        .default_model = " default-model ",
        .endpoint_groups = {group},
    };
    const std::array accounts{cooling_down};
    AgentRouteRouter router;

    expect(
        !router.next_route(channel, accounts, std::nullopt, 100),
        "accounts in cooldown should not route");
    expect(
        router.next_route(channel, accounts, std::nullopt, 101).has_value(),
        "accounts should become eligible when their cooldown expires");
    expect(
        !router.next_route(no_model, accounts, std::nullopt, 101),
        "channels without a model should not consume a route");
    const auto overridden = router.next_route(
        channel, accounts, std::string_view{"  override-model  "}, 101);
    expect(
        overridden && overridden->model == "override-model",
        "model overrides should be trimmed before use");
}

void modelCatalogsNormalizeModelsAndHaveStableIDs() {
    AgentChannelModelCatalog catalog{
        .channel_id = "channel",
        .endpoint_group_id = "group",
        .base_url = "https://one.example/v1",
        .models = AgentChannelModelCatalog::normalize_models(
            {" model-b ", "", "model-a", "model-b"}),
    };

    expect(
        catalog.models == std::vector<std::string>{"model-a", "model-b"},
        "model catalogs should trim, deduplicate, and sort names");
    expect(
        catalog.id() == "channel|group|https://one.example/v1",
        "model catalog IDs should be deterministic");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"tokens round trip", tokensRoundTrip},
        {"CLI profiles require distinct absolute paths", cliProfilesRequireDistinctAbsolutePaths},
        {"endpoint groups normalize inputs", endpointGroupsNormalizeInputs},
        {"route router rotates stable pairs", routeRouterRotatesStablePairsAndSkipsInsufficientBalance},
        {"router falls back and respects temporary unavailability", routerFallsBackAndRespectsTemporaryUnavailability},
        {"routes respect cooldown and require a model", routesRespectCooldownAndRequireAModel},
        {"model catalogs normalize names", modelCatalogsNormalizeModelsAndHaveStableIDs},
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
