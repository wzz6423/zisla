#include <zisla/core/AIAgentServiceResponses.hpp>

#include <cmath>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void balanceResponsesMatchProviderContracts() {
    const auto openai = AIAgentBalanceResponseParser::parse(
        AgentBalanceProbeKind::openai_credits,
        R"({"total_granted":"12.5","total_used":2.25})",
        10);
    expect(openai && openai->available && std::abs(*openai->available - 10.25) < 0.0001
            && openai->used && std::abs(*openai->used - 2.25) < 0.0001
            && openai->checked_at_unix_ms == 10,
        "OpenAI credit grants should derive available credit from grants and usage");

    const auto anthropic = AIAgentBalanceResponseParser::parse(
        AgentBalanceProbeKind::anthropic_usage,
        R"({"data":[{"input_tokens":5,"output_tokens":3},{"nested":{"input_tokens":2}}]})",
        11);
    expect(anthropic && !anthropic->available && anthropic->used
            && std::abs(*anthropic->used - 10.0) < 0.0001
            && anthropic->currency == "tokens",
        "Anthropic usage should sum nested input and output token counts");

    const auto new_api = AIAgentBalanceResponseParser::parse(
        AgentBalanceProbeKind::new_api_quota,
        R"({"data":{"quota":20,"used_quota":4}})",
        12);
    expect(new_api && new_api->available && std::abs(*new_api->available - 16.0) < 0.0001
            && new_api->used && std::abs(*new_api->used - 4.0) < 0.0001,
        "New API quota should derive available quota when no balance field is supplied");

    expect(!AIAgentBalanceResponseParser::parse(
                AgentBalanceProbeKind::new_api_quota, R"({"data":{}})", 13).has_value(),
        "quota responses without a usable balance field should be rejected");
    expect(!AIAgentBalanceResponseParser::parse(
                AgentBalanceProbeKind::custom_script, R"({"available":1})", 14).has_value(),
        "custom script responses must not be interpreted as remote provider responses");
}

void modelCatalogAndHealthResponsesAreNormalized() {
    const auto models = AIAgentModelCatalogResponseParser::parse(
        R"({"models":[{"name":"models/gemini-2.5"},{"name":"gemini-2.5"},{"id":"claude-test"},{"name":3}]})");
    expect(models && models->size() == 2
            && models->front() == "claude-test" && models->back() == "gemini-2.5",
        "model catalogs should strip Gemini prefixes, sort, and deduplicate names");
    expect(!AIAgentModelCatalogResponseParser::parse("{}").has_value(),
        "model catalog responses without a supported model array should be rejected");
    expect(!AIAgentModelCatalogResponseParser::parse(
                R"({"data":[{"id":""},{"name":3}]})").has_value(),
        "model catalog responses without usable model IDs should be rejected");

    expect(agent_channel_health_for_http_status(200) == AgentChannelHealth::healthy
            && agent_channel_health_for_http_status(403) == AgentChannelHealth::degraded
            && agent_channel_health_for_http_status(500) == AgentChannelHealth::unavailable,
        "HTTP status should map to the shared route health contract");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"balance responses match provider contracts", balanceResponsesMatchProviderContracts},
        {"model catalog and health responses are normalized", modelCatalogAndHealthResponsesAreNormalized},
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
