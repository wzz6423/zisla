#pragma once

#include "zisla/core/AIAgentRouting.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

/// Parses provider responses without retaining credentials or transport details.
class AIAgentBalanceResponseParser {
public:
    [[nodiscard]] static std::optional<AgentBalanceSnapshot> parse(
        AgentBalanceProbeKind kind,
        std::string_view body,
        std::int64_t checked_at_unix_ms);
};

class AIAgentModelCatalogResponseParser {
public:
    [[nodiscard]] static std::optional<std::vector<std::string>> parse(
        std::string_view body);
};

[[nodiscard]] AgentChannelHealth agent_channel_health_for_http_status(
    std::uint32_t status) noexcept;

}  // namespace zisla::core
