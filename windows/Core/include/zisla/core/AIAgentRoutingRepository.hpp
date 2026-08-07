#pragma once

#include <zisla/core/AIAgentRouting.hpp>

#include <cstdint>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct AIAgentRoutingState {
    std::vector<AgentAccount> accounts;
    std::vector<AgentChannel> channels;
    std::vector<AgentChannelProbe> channel_probes;
    std::vector<AgentChannelModelCatalog> model_catalogs;

    friend bool operator==(const AIAgentRoutingState&, const AIAgentRoutingState&) = default;
};

enum class AIAgentRoutingRepositoryErrorCode {
    corrupted_state,
    invalid_value,
    storage_failure,
};

class AIAgentRoutingRepositoryError : public std::runtime_error {
public:
    AIAgentRoutingRepositoryError(
        AIAgentRoutingRepositoryErrorCode code,
        std::string message,
        std::string subject = {});

    [[nodiscard]] AIAgentRoutingRepositoryErrorCode code() const noexcept;
    [[nodiscard]] const std::string& subject() const noexcept;

private:
    AIAgentRoutingRepositoryErrorCode code_;
    std::string subject_;
};

/// Stores routing metadata only. API keys and CLI credential contents stay in a platform secret store.
class AIAgentRoutingRepository {
public:
    static constexpr std::int64_t default_route_cooldown_ms = 5 * 60 * 1'000;
    static constexpr std::uint32_t default_route_failure_threshold = 2;

    explicit AIAgentRoutingRepository(std::filesystem::path directory);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] AIAgentRoutingState load() const;

    void upsert_account(const AgentAccount& account) const;
    [[nodiscard]] bool remove_account(std::string_view account_id) const;
    void upsert_channel(const AgentChannel& channel) const;
    [[nodiscard]] bool remove_channel(std::string_view channel_id) const;
    void replace_channel_probe(const AgentChannelProbe& probe) const;
    void replace_model_catalog(const AgentChannelModelCatalog& catalog) const;
    [[nodiscard]] bool record_balance(
        std::string_view account_id,
        std::optional<AgentBalanceSnapshot> snapshot) const;
    [[nodiscard]] bool record_route_success(std::string_view account_id) const;
    [[nodiscard]] bool record_route_failure(
        std::string_view account_id,
        std::int64_t now_unix_ms,
        std::int64_t cooldown_ms = default_route_cooldown_ms,
        std::uint32_t failure_threshold = default_route_failure_threshold) const;

private:
    std::filesystem::path directory_;
};

}  // namespace zisla::core
