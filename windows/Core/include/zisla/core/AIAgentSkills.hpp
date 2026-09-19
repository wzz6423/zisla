#pragma once

#include <cstddef>
#include <filesystem>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace zisla::core {

struct AgentSkill {
    std::string name;
    std::filesystem::path path;
    std::string source;
    bool is_enabled{true};
    std::optional<std::filesystem::file_time_type> modified_at;

    friend bool operator==(const AgentSkill&, const AgentSkill&) = default;
};

class AgentSkillCatalog {
public:
    static constexpr std::size_t maximum_skill_count = 1'024;

    [[nodiscard]] static std::vector<std::filesystem::path> default_roots(
        const std::filesystem::path& home_directory);

    [[nodiscard]] static std::vector<AgentSkill> scan(
        std::span<const std::filesystem::path> roots,
        std::span<const std::filesystem::path> disabled_paths = {},
        std::span<const std::filesystem::path> ignored_paths = {});
};

enum class AgentSkillSynchronizationMode {
    symbolic_link,
    file_copy,
};

enum class AgentSkillSynchronizationErrorCode {
    destination_not_managed,
    invalid_managed_directory,
    source_contains_symbolic_link,
    io_failure,
};

class AgentSkillSynchronizationError : public std::runtime_error {
public:
    AgentSkillSynchronizationError(
        AgentSkillSynchronizationErrorCode code,
        std::string message);

    [[nodiscard]] AgentSkillSynchronizationErrorCode code() const noexcept;

private:
    AgentSkillSynchronizationErrorCode code_;
};

class AgentSkillSynchronizer {
public:
    inline static constexpr char marker_file_name[] = ".zisla-skill-sync";

    void ensure_managed_directory(const std::filesystem::path& managed_directory) const;
    void synchronize(
        const std::filesystem::path& managed_directory,
        const std::filesystem::path& destination,
        AgentSkillSynchronizationMode mode) const;
    void disable(
        const std::filesystem::path& destination,
        const std::filesystem::path& managed_directory) const;
};

}  // namespace zisla::core
