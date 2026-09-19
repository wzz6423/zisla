#pragma once

#include <zisla/core/AIAgentRouting.hpp>
#include <zisla/core/OpenAIChatCompletions.hpp>

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace winrt::Zisla {

/// Performs bounded, non-streaming API requests for supported AI Agent protocols.
class AIAgentHTTPClient {
public:
    static constexpr std::size_t maximum_request_bytes = 4U * 1024U * 1024U;
    static constexpr std::size_t maximum_response_bytes = 4U * 1024U * 1024U;

    static void validateOpenAICompatibleBaseUrl(std::string_view base_url);
    static void validateBaseUrl(
        zisla::core::AgentChannelProtocol protocol,
        std::string_view base_url,
        std::string_view model);
    [[nodiscard]] std::string complete(
        const zisla::core::AgentRoute& route,
        std::string_view api_key,
        const zisla::core::OpenAIChatCompletionRequest& request) const;
    [[nodiscard]] zisla::core::AgentChannelProbe probe(
        const zisla::core::AgentRoute& route,
        std::string_view api_key,
        std::int64_t checked_at_unix_ms) const;
    [[nodiscard]] zisla::core::AgentChannelModelCatalog fetchModelCatalog(
        const zisla::core::AgentRoute& route,
        std::string_view api_key,
        std::int64_t checked_at_unix_ms) const;
    [[nodiscard]] zisla::core::AgentBalanceSnapshot checkBalance(
        const zisla::core::AgentBalanceProbe& probe,
        const zisla::core::AgentRoute& route,
        std::string_view api_key,
        std::int64_t checked_at_unix_ms) const;
};

}
