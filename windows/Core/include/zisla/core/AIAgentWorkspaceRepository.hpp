#pragma once

#include "zisla/core/AIAgentWorkspace.hpp"

#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

namespace zisla::core {

enum class AIAgentWorkspaceRepositoryErrorCode {
    corrupted_state,
    invalid_value,
    storage_failure,
};

class AIAgentWorkspaceRepositoryError : public std::runtime_error {
public:
    AIAgentWorkspaceRepositoryError(
        AIAgentWorkspaceRepositoryErrorCode code,
        std::string message,
        std::string subject = {});

    [[nodiscard]] AIAgentWorkspaceRepositoryErrorCode code() const noexcept;
    [[nodiscard]] const std::string& subject() const noexcept;

private:
    AIAgentWorkspaceRepositoryErrorCode code_;
    std::string subject_;
};

/// Stores local workspace metadata and transcript text only; credentials stay in a platform secret store.
class AIAgentWorkspaceRepository {
public:
    static constexpr std::size_t maximum_title_bytes = 4 * 1'024;
    static constexpr std::size_t maximum_instruction_bytes = 1 * 1'024 * 1'024;
    static constexpr std::size_t maximum_message_bytes = 1 * 1'024 * 1'024;
    static constexpr std::size_t maximum_skill_references_per_message = 64;

    explicit AIAgentWorkspaceRepository(std::filesystem::path directory);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] AIAgentWorkspaceState load() const;

    void upsert_project(AgentWorkspaceProject project) const;
    [[nodiscard]] bool remove_project(std::string_view project_id) const;
    void upsert_goal(AgentWorkspaceGoal goal) const;
    [[nodiscard]] bool remove_goal(std::string_view goal_id) const;
    void upsert_thread(AgentWorkspaceThread thread) const;
    [[nodiscard]] bool remove_thread(std::string_view thread_id) const;
    void append_message(AgentWorkspaceMessage message) const;
    [[nodiscard]] bool remove_message(std::string_view message_id) const;

private:
    std::filesystem::path directory_;
};

}  // namespace zisla::core
