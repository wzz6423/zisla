#include "zisla/core/AIAgentSkills.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <string_view>
#include <system_error>
#include <unordered_set>
#include <utility>

namespace zisla::core {
namespace {

namespace fs = std::filesystem;

std::atomic<std::uint64_t> staging_counter{0};

std::string path_as_utf8(const fs::path& path) {
    const auto encoded = path.generic_u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size()};
}

char ascii_lower(char value) noexcept {
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value + ('a' - 'A'))
        : value;
}

std::string ascii_case_fold(std::string_view value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), ascii_lower);
    return result;
}

bool is_hidden_name(const fs::path& path) {
    const auto name = path.filename().string();
    return name.size() > 1 && name.front() == '.';
}

std::optional<fs::path> canonical_existing_path(const fs::path& path) {
    std::error_code error;
    const auto status = fs::symlink_status(path, error);
    if (error || status.type() == fs::file_type::not_found) {
        return std::nullopt;
    }
    const auto normalized = fs::weakly_canonical(path, error);
    if (error) {
        return std::nullopt;
    }
    return normalized.lexically_normal();
}

bool is_same_or_descendant(
    const fs::path& path,
    const fs::path& ancestor) noexcept {
    auto path_part = path.begin();
    auto ancestor_part = ancestor.begin();
    while (path_part != path.end() && ancestor_part != ancestor.end()) {
        if (*path_part != *ancestor_part) {
            return false;
        }
        ++path_part;
        ++ancestor_part;
    }
    return ancestor_part == ancestor.end();
}

[[noreturn]] void throw_synchronization_error(
    AgentSkillSynchronizationErrorCode code,
    std::string message) {
    throw AgentSkillSynchronizationError(code, std::move(message));
}

fs::path require_managed_directory(const fs::path& managed_directory) {
    std::error_code error;
    fs::create_directories(managed_directory, error);
    if (error) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to create the managed AI Agent skills directory: " + error.message());
    }

    const auto status = fs::symlink_status(managed_directory, error);
    if (error || std::filesystem::is_symlink(status) || !fs::is_directory(status)) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::invalid_managed_directory,
            "The managed AI Agent skills directory must be a real directory");
    }

    const auto canonical = canonical_existing_path(managed_directory);
    if (!canonical) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to normalize the managed AI Agent skills directory");
    }
    return *canonical;
}

void create_destination_parent(const fs::path& destination) {
    const auto parent = destination.parent_path();
    if (parent.empty()) {
        return;
    }

    std::error_code error;
    fs::create_directories(parent, error);
    if (error) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to create the AI Agent skill destination parent: " + error.message());
    }
}

bool destination_exists(const fs::path& destination, fs::file_status& status) {
    std::error_code error;
    status = fs::symlink_status(destination, error);
    if (error) {
        if (error == std::errc::no_such_file_or_directory) {
            return false;
        }
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to inspect the AI Agent skill destination: " + error.message());
    }
    return status.type() != fs::file_type::not_found;
}

bool has_managed_marker(
    const fs::path& destination,
    const fs::path& managed_directory) {
    const auto marker = destination / AgentSkillSynchronizer::marker_file_name;
    std::error_code error;
    const auto status = fs::symlink_status(marker, error);
    if (error || std::filesystem::is_symlink(status)
        || !fs::is_regular_file(status)) {
        return false;
    }

    const auto size = fs::file_size(marker, error);
    if (error || size > 16 * 1024) {
        return false;
    }

    std::ifstream input(marker, std::ios::binary);
    if (!input) {
        return false;
    }
    std::string contents(static_cast<std::size_t>(size), '\0');
    if (!input.read(contents.data(), static_cast<std::streamsize>(contents.size()))) {
        return false;
    }
    return contents == path_as_utf8(managed_directory);
}

void remove_destination_if_managed(
    const fs::path& destination,
    const fs::path& managed_directory) {
    fs::file_status status;
    if (!destination_exists(destination, status)) {
        return;
    }

    std::error_code error;
    if (fs::is_symlink(status)) {
        auto target = fs::read_symlink(destination, error);
        if (error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to read the AI Agent skill destination link: " + error.message());
        }
        if (target.is_relative()) {
            target = destination.parent_path() / target;
        }
        if (!fs::equivalent(target, managed_directory, error) || error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::destination_not_managed,
                "The AI Agent skill destination is not managed by Zisla");
        }
        fs::remove(destination, error);
    } else {
        if (!fs::is_directory(status) || !has_managed_marker(destination, managed_directory)) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::destination_not_managed,
                "The AI Agent skill destination is not managed by Zisla");
        }
        fs::remove_all(destination, error);
    }

    if (error) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to remove the managed AI Agent skill destination: " + error.message());
    }
}

fs::path staging_path(const fs::path& destination, std::uint64_t nonce) {
    auto result = destination;
    result += ".zisla-stage-" + std::to_string(nonce);
    return result;
}

fs::path create_staging_directory(const fs::path& destination) {
    const auto clock = std::chrono::steady_clock::now().time_since_epoch().count();
    for (std::size_t attempt = 0; attempt < 64; ++attempt) {
        const auto candidate = staging_path(
            destination,
            static_cast<std::uint64_t>(clock) + staging_counter.fetch_add(1));
        std::error_code error;
        if (fs::create_directory(candidate, error)) {
            return candidate;
        }
        if (error && error != std::errc::file_exists) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to create an AI Agent skill staging directory: " + error.message());
        }
    }
    throw_synchronization_error(
        AgentSkillSynchronizationErrorCode::io_failure,
        "Unable to reserve an AI Agent skill staging directory");
}

fs::path create_staging_link(
    const fs::path& destination,
    const fs::path& managed_directory) {
    const auto clock = std::chrono::steady_clock::now().time_since_epoch().count();
    for (std::size_t attempt = 0; attempt < 64; ++attempt) {
        const auto candidate = staging_path(
            destination,
            static_cast<std::uint64_t>(clock) + staging_counter.fetch_add(1));
        std::error_code error;
        fs::create_directory_symlink(managed_directory, candidate, error);
        if (!error) {
            return candidate;
        }
        if (error != std::errc::file_exists) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to create an AI Agent skill symbolic link: " + error.message());
        }
    }
    throw_synchronization_error(
        AgentSkillSynchronizationErrorCode::io_failure,
        "Unable to reserve an AI Agent skill staging link");
}

void copy_managed_contents(
    const fs::path& managed_directory,
    const fs::path& staging_directory) {
    std::error_code error;
    for (fs::recursive_directory_iterator iterator(managed_directory, error), end;
         iterator != end;
         iterator.increment(error)) {
        if (error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to enumerate managed AI Agent skills: " + error.message());
        }

        const auto entry = *iterator;
        const auto status = entry.symlink_status(error);
        if (error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to inspect a managed AI Agent skill: " + error.message());
        }
        if (fs::is_symlink(status)) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::source_contains_symbolic_link,
                "Managed AI Agent skills may not contain symbolic links");
        }

        const auto relative = entry.path().lexically_relative(managed_directory);
        if (relative.empty() || relative == "." || relative.string().starts_with("..")) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to derive a managed AI Agent skill relative path");
        }
        const auto target = staging_directory / relative;
        if (fs::is_directory(status)) {
            fs::create_directories(target, error);
        } else if (fs::is_regular_file(status)) {
            fs::create_directories(target.parent_path(), error);
            if (!error) {
                fs::copy_file(entry.path(), target, fs::copy_options::none, error);
            }
        } else {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Managed AI Agent skills contain an unsupported file type");
        }
        if (error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to stage managed AI Agent skills: " + error.message());
        }
    }
}

void write_managed_marker(
    const fs::path& staging_directory,
    const fs::path& managed_directory) {
    const auto marker = staging_directory / AgentSkillSynchronizer::marker_file_name;
    std::ofstream output(marker, std::ios::binary | std::ios::trunc);
    if (!output) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to create the AI Agent skill managed marker");
    }
    const auto contents = path_as_utf8(managed_directory);
    output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!output) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::io_failure,
            "Unable to write the AI Agent skill managed marker");
    }
}

void replace_destination_with_staging(
    const fs::path& staging,
    const fs::path& destination,
    const fs::path& managed_directory) {
    try {
        remove_destination_if_managed(destination, managed_directory);
        std::error_code error;
        fs::rename(staging, destination, error);
        if (error) {
            throw_synchronization_error(
                AgentSkillSynchronizationErrorCode::io_failure,
                "Unable to activate staged AI Agent skills: " + error.message());
        }
    } catch (...) {
        std::error_code cleanup_error;
        fs::remove_all(staging, cleanup_error);
        throw;
    }
}

}  // namespace

AgentSkillSynchronizationError::AgentSkillSynchronizationError(
    AgentSkillSynchronizationErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

AgentSkillSynchronizationErrorCode AgentSkillSynchronizationError::code() const noexcept {
    return code_;
}

std::vector<fs::path> AgentSkillCatalog::default_roots(
    const fs::path& home_directory) {
    return {
        home_directory / ".codex" / "skills",
        home_directory / ".agents" / "skills",
        home_directory / ".claude" / "skills",
    };
}

std::vector<AgentSkill> AgentSkillCatalog::scan(
    std::span<const fs::path> roots,
    std::span<const fs::path> disabled_paths,
    std::span<const fs::path> ignored_paths) {
    std::unordered_set<std::string> disabled;
    for (const auto& path : disabled_paths) {
        if (const auto canonical = canonical_existing_path(path)) {
            disabled.insert(path_as_utf8(*canonical));
        }
    }

    std::vector<fs::path> ignored;
    ignored.reserve(ignored_paths.size());
    for (const auto& path : ignored_paths) {
        if (const auto canonical = canonical_existing_path(path)) {
            ignored.push_back(*canonical);
        }
    }

    std::vector<AgentSkill> result;
    for (const auto& root : roots) {
        std::error_code error;
        const auto root_status = fs::symlink_status(root, error);
        if (error || fs::is_symlink(root_status) || !fs::is_directory(root_status)) {
            continue;
        }

        const auto source = root.filename().empty()
            ? path_as_utf8(root)
            : root.filename().string();
        for (fs::recursive_directory_iterator iterator(
                 root,
                 fs::directory_options::skip_permission_denied,
                 error), end;
             iterator != end && result.size() < maximum_skill_count;
             iterator.increment(error)) {
            if (error) {
                error.clear();
                continue;
            }

            const auto entry = *iterator;
            const auto status = entry.symlink_status(error);
            if (error) {
                error.clear();
                continue;
            }
            const auto canonical = canonical_existing_path(entry.path());
            if (canonical && std::ranges::any_of(ignored, [&canonical](const auto& path) {
                    return is_same_or_descendant(*canonical, path);
                })) {
                if (fs::is_directory(status)) {
                    iterator.disable_recursion_pending();
                }
                continue;
            }
            if (is_hidden_name(entry.path())) {
                if (fs::is_directory(status)) {
                    iterator.disable_recursion_pending();
                }
                continue;
            }
            if (fs::is_symlink(status)) {
                iterator.disable_recursion_pending();
                continue;
            }
            if (!fs::is_regular_file(status) || entry.path().filename() != "SKILL.md") {
                continue;
            }

            const auto parent = canonical_existing_path(entry.path().parent_path());
            if (!parent) {
                continue;
            }
            const auto modified = fs::last_write_time(entry.path(), error);
            const auto modified_at = error
                ? std::optional<fs::file_time_type>{}
                : std::optional<fs::file_time_type>{modified};
            error.clear();
            result.push_back({
                .name = parent->filename().string(),
                .path = *parent,
                .source = source,
                .is_enabled = !disabled.contains(path_as_utf8(*parent)),
                .modified_at = modified_at,
            });
        }
    }

    std::sort(result.begin(), result.end(), [](const AgentSkill& lhs, const AgentSkill& rhs) {
        const auto left = ascii_case_fold(lhs.name);
        const auto right = ascii_case_fold(rhs.name);
        if (left != right) {
            return left < right;
        }
        return path_as_utf8(lhs.path) < path_as_utf8(rhs.path);
    });
    return result;
}

void AgentSkillSynchronizer::ensure_managed_directory(
    const fs::path& managed_directory) const {
    (void)require_managed_directory(managed_directory);
}

void AgentSkillSynchronizer::synchronize(
    const fs::path& managed_directory,
    const fs::path& destination,
    AgentSkillSynchronizationMode mode) const {
    const auto managed = require_managed_directory(managed_directory);
    create_destination_parent(destination);

    if (mode == AgentSkillSynchronizationMode::symbolic_link) {
        const auto staging = create_staging_link(destination, managed);
        replace_destination_with_staging(staging, destination, managed);
        return;
    }

    const auto staging = create_staging_directory(destination);
    try {
        copy_managed_contents(managed, staging);
        write_managed_marker(staging, managed);
        replace_destination_with_staging(staging, destination, managed);
    } catch (...) {
        std::error_code cleanup_error;
        fs::remove_all(staging, cleanup_error);
        throw;
    }
}

void AgentSkillSynchronizer::disable(
    const fs::path& destination,
    const fs::path& managed_directory) const {
    const auto managed = canonical_existing_path(managed_directory);
    if (!managed) {
        throw_synchronization_error(
            AgentSkillSynchronizationErrorCode::invalid_managed_directory,
            "Unable to normalize the managed AI Agent skills directory");
    }
    remove_destination_if_managed(destination, *managed);
}

}  // namespace zisla::core
