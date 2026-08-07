#pragma once

#include <zisla/core/AIAgentSkills.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

enum class AIAgentSkillDestination {
    codex,
    claude,
    agents,
};

struct AIAgentSkillDestinationState {
    AIAgentSkillDestination destination{AIAgentSkillDestination::codex};
    std::filesystem::path path;
    bool enabled{false};
};

struct AIAgentSkillsServiceSnapshot {
    std::vector<zisla::core::AgentSkill> skills;
    std::filesystem::path managed_directory;
    std::vector<AIAgentSkillDestinationState> destinations;
    zisla::core::AgentSkillSynchronizationMode mode{
        zisla::core::AgentSkillSynchronizationMode::file_copy};
    std::string error;
    bool loading{true};
    bool synchronizing{false};
    std::uint64_t revision{0};
};

class AIAgentSkillsService {
public:
    explicit AIAgentSkillsService(std::filesystem::path state_directory);
    ~AIAgentSkillsService();

    AIAgentSkillsService(const AIAgentSkillsService&) = delete;
    AIAgentSkillsService& operator=(const AIAgentSkillsService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void reload();
    void setSkillEnabled(std::filesystem::path path, bool enabled);
    void setSynchronizationMode(zisla::core::AgentSkillSynchronizationMode mode);
    void setDestinationEnabled(AIAgentSkillDestination destination, bool enabled);
    void synchronize();

    [[nodiscard]] std::filesystem::path managedDirectory() const;
    [[nodiscard]] std::shared_ptr<const AIAgentSkillsServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        reload,
        set_skill_enabled,
        set_synchronization_mode,
        set_destination_enabled,
        synchronize,
    };

    struct Command {
        CommandKind kind{CommandKind::reload};
        std::filesystem::path path;
        zisla::core::AgentSkillSynchronizationMode mode{
            zisla::core::AgentSkillSynchronizationMode::file_copy};
        AIAgentSkillDestination destination{AIAgentSkillDestination::codex};
        bool enabled{false};
    };

    struct Configuration {
        zisla::core::AgentSkillSynchronizationMode mode{
            zisla::core::AgentSkillSynchronizationMode::file_copy};
        bool codex_enabled{false};
        bool claude_enabled{false};
        bool agents_enabled{false};
        std::vector<std::filesystem::path> disabled_paths;
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    void loadConfiguration();
    void saveConfiguration() const;
    void reloadSkills();
    void synchronizeConfiguredDestinations();
    void publish() noexcept;
    void publishError(std::string error) noexcept;
    void notify() noexcept;
    [[nodiscard]] bool isDestinationEnabled(
        AIAgentSkillDestination destination) const noexcept;
    void setDestinationConfigurationEnabled(
        AIAgentSkillDestination destination,
        bool enabled) noexcept;
    [[nodiscard]] std::filesystem::path destinationDirectory(
        AIAgentSkillDestination destination) const;

    std::filesystem::path state_directory_;
    std::filesystem::path managed_directory_;
    std::filesystem::path home_directory_;
    zisla::core::AgentSkillSynchronizer synchronizer_;
    std::vector<zisla::core::AgentSkill> skills_;
    Configuration configuration_;
    std::atomic<std::shared_ptr<const AIAgentSkillsServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    std::string error_;
    std::uint64_t revision_{0};
    bool running_{false};
    bool loading_{true};
    bool synchronizing_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
