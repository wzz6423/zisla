#pragma once

#include "AIAgentCLIRunner.h"
#include "AIAgentCredentialStore.h"
#include "AIAgentHTTPClient.h"

#include <zisla/core/AIAgentRoutingRepository.hpp>
#include <zisla/core/AIAgentWorkspaceRepository.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct AIAgentAPIConnectionSummary {
    std::string account_id;
    std::string channel_id;
    std::string name;
    std::vector<std::string> base_urls;
    std::string model;
    std::vector<std::string> model_catalog;
    zisla::core::AgentChannelProtocol protocol{
        zisla::core::AgentChannelProtocol::openai_compatible};
    std::optional<zisla::core::AgentBalanceProbe> balance_probe;
    std::optional<zisla::core::AgentBalanceSnapshot> balance;
    int endpoint_priority{0};
    bool is_configured{false};
    bool has_stored_api_key{false};
};

struct AIAgentWorkspaceServiceSnapshot {
    zisla::core::AIAgentWorkspaceState state;
    zisla::core::AIAgentRoutingState routing;
    std::optional<std::string> preferred_thread_id;
    std::optional<std::string> preferred_connection_channel_id;
    std::vector<AIAgentAPIConnectionSummary> connections;
    std::string error;
    bool loading{true};
    bool can_cancel{false};
    std::uint64_t revision{0};
};

/// Serializes local workspace mutations so the UI never accesses its SQLite store directly.
class AIAgentWorkspaceService {
public:
    explicit AIAgentWorkspaceService(std::filesystem::path state_directory);
    ~AIAgentWorkspaceService();

    AIAgentWorkspaceService(const AIAgentWorkspaceService&) = delete;
    AIAgentWorkspaceService& operator=(const AIAgentWorkspaceService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void reload();
    void createThread();
    void removeThread(std::string thread_id);
    void submitMessage(
        std::string thread_id,
        std::string content,
        std::vector<zisla::core::AgentSkill> skills,
        std::optional<zisla::core::AgentCLIKind> cli_kind,
        std::optional<std::string> channel_id);
    void cancelActiveRequest() noexcept;
    void refreshAccountBalance(std::string account_id);
    void refreshChannelModels(std::string channel_id);
    void configureAPIConnection(
        std::optional<std::string> channel_id,
        zisla::core::AgentChannelProtocol protocol,
        std::string name,
        std::string base_url,
        std::string model,
        std::string endpoint_priority,
        std::string api_key,
        std::optional<zisla::core::AgentBalanceProbe> balance_probe);
    void removeAPIConnection(std::string channel_id);

    [[nodiscard]] std::shared_ptr<const AIAgentWorkspaceServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        reload,
        create_thread,
        remove_thread,
        submit_message,
        configure_api_connection,
        remove_api_connection,
        refresh_account_balance,
        refresh_channel_models,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        std::string thread_id;
        std::string account_id;
        std::string channel_id;
        std::string content;
        std::vector<zisla::core::AgentSkill> skills;
        std::optional<zisla::core::AgentCLIKind> cli_kind;
        zisla::core::AgentChannelProtocol protocol{
            zisla::core::AgentChannelProtocol::openai_compatible};
        std::string connection_name;
        std::string base_url;
        std::string model;
        std::string endpoint_priority;
        std::string api_key;
        std::optional<zisla::core::AgentBalanceProbe> balance_probe;
    };

    void enqueue(Command command);
    void run() noexcept;
    [[nodiscard]] std::optional<std::string> execute(Command command);
    void configureAPIConnection(Command& command);
    void removeAPIConnection(Command& command);
    void refreshAccountBalance(Command& command);
    void refreshChannelModels(Command& command);
    void requestAPICompletion(
        zisla::core::AIAgentWorkspaceState& state,
        zisla::core::AgentWorkspaceThread& thread,
        std::int64_t now_unix_ms);
    void requestCompletion(
        zisla::core::AIAgentWorkspaceState& state,
        zisla::core::AgentWorkspaceThread& thread,
        std::int64_t now_unix_ms);
    void requestCLICompletion(
        zisla::core::AIAgentWorkspaceState& state,
        zisla::core::AgentWorkspaceThread& thread);
    [[nodiscard]] std::vector<AIAgentAPIConnectionSummary> connectionSummaries(
        const zisla::core::AIAgentRoutingState& routing);
    void publish(std::optional<std::string> preferred_thread_id);
    void publishError(std::string error) noexcept;
    void notify() noexcept;

    zisla::core::AIAgentWorkspaceRepository repository_;
    zisla::core::AIAgentRoutingRepository routing_repository_;
    zisla::core::AgentRouteRouter route_router_;
    AIAgentCredentialStore credential_store_;
    AIAgentHTTPClient http_client_;
    AIAgentCLIRunner cli_runner_;
    std::atomic_bool cli_cancellation_requested_{false};
    std::atomic_bool cli_cancellable_{false};
    std::atomic<std::shared_ptr<const AIAgentWorkspaceServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    bool running_{false};
    bool loading_{true};
    std::uint64_t revision_{0};
    std::optional<std::string> preferred_connection_channel_id_;
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
