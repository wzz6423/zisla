#include <zisla/core/AIAgentSkills.hpp>

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using namespace zisla::core;

namespace {

namespace fs = std::filesystem;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
        path_ = fs::temp_directory_path()
            / ("zisla-ai-agent-skills-" + std::to_string(suffix));
        fs::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        fs::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const fs::path& path() const noexcept {
        return path_;
    }

private:
    fs::path path_;
};

void write_file(const fs::path& path, std::string_view contents) {
    std::error_code error;
    fs::create_directories(path.parent_path(), error);
    if (error) {
        throw std::runtime_error(error.message());
    }
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        throw std::runtime_error("unable to create test file");
    }
    output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!output) {
        throw std::runtime_error("unable to write test file");
    }
}

std::string read_file(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("unable to read test file");
    }
    return {
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()};
}

void catalogScansSkillsWithoutFollowingLinks() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "skills";
    const auto alpha = root / "alpha";
    const auto beta = root / "nested" / "beta";
    write_file(alpha / "SKILL.md", "alpha");
    write_file(beta / "SKILL.md", "beta");
    write_file(root / ".hidden" / "SKILL.md", "hidden");

    const auto external = temporary.path() / "external";
    write_file(external / "SKILL.md", "external");
    std::error_code link_error;
    fs::create_directory_symlink(external, root / "linked", link_error);

    const std::vector<fs::path> roots{root};
    const std::vector<fs::path> disabled{beta};
    const auto skills = AgentSkillCatalog::scan(roots, disabled);

    expect(skills.size() == 2, "catalog should ignore hidden and linked skill directories");
    expect(skills[0].name == "alpha" && skills[1].name == "beta",
        "catalog should sort skills by name");
    expect(skills[0].source == "skills", "catalog should retain its source root");
    expect(skills[0].is_enabled, "unlisted skill should be enabled");
    expect(!skills[1].is_enabled, "disabled skill should retain its state");
    expect(skills[0].modified_at.has_value(), "catalog should retain modification time");
}

void catalogSkipsIgnoredManagedDestination() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "skills";
    const auto visible = root / "review";
    const auto managed_destination = root / "zisla-managed";
    write_file(visible / "SKILL.md", "review");
    write_file(managed_destination / "review" / "SKILL.md", "managed review");

    const std::vector<fs::path> roots{root};
    const std::vector<fs::path> ignored{managed_destination};
    const auto skills = AgentSkillCatalog::scan(roots, {}, ignored);

    expect(skills.size() == 1,
        "managed copy destination should not duplicate a scanned skill");
    expect(skills.front().path == fs::weakly_canonical(visible),
        "catalog should retain skills outside ignored destinations");
}

void fileCopySynchronizationIsManagedAndRepeatable() {
    TemporaryDirectory temporary;
    const auto managed = temporary.path() / "managed";
    const auto destination = temporary.path() / "codex" / "zisla-managed";
    const auto skill_file = managed / "review" / "SKILL.md";
    write_file(skill_file, "first");

    AgentSkillSynchronizer synchronizer;
    synchronizer.synchronize(managed, destination, AgentSkillSynchronizationMode::file_copy);
    expect(read_file(destination / "review" / "SKILL.md") == "first",
        "file copy should create an independent destination");
    expect(fs::exists(destination / AgentSkillSynchronizer::marker_file_name),
        "file copy destination should have a managed marker");

    write_file(skill_file, "updated");
    expect(read_file(destination / "review" / "SKILL.md") == "first",
        "file copy destination should not follow source changes before a refresh");
    synchronizer.synchronize(managed, destination, AgentSkillSynchronizationMode::file_copy);
    expect(read_file(destination / "review" / "SKILL.md") == "updated",
        "a managed destination should refresh safely");

    synchronizer.disable(destination, managed);
    expect(!fs::exists(destination), "disable should remove the managed destination");
    expect(fs::exists(skill_file), "disable should preserve managed skills");
}

void symbolicLinkSynchronizationReflectsManagedSkillChanges() {
    TemporaryDirectory temporary;
    const auto managed = temporary.path() / "managed";
    const auto destination = temporary.path() / "claude" / "zisla-managed";
    const auto skill_file = managed / "review" / "SKILL.md";
    write_file(skill_file, "first");

    AgentSkillSynchronizer synchronizer;
    try {
        synchronizer.synchronize(
            managed,
            destination,
            AgentSkillSynchronizationMode::symbolic_link);
    } catch (const AgentSkillSynchronizationError& error) {
        if (error.code() == AgentSkillSynchronizationErrorCode::io_failure) {
            std::cout << "skipping symbolic-link synchronization test (links unavailable)\n";
            return;
        }
        throw;
    }

    write_file(skill_file, "updated");
    expect(read_file(destination / "review" / "SKILL.md") == "updated",
        "symbolic-link destination should reflect managed changes");
    expect(fs::is_symlink(fs::symlink_status(destination)),
        "symbolic-link mode should create a symbolic link");
}

void synchronizationRefusesUnmanagedDestinations() {
    TemporaryDirectory temporary;
    const auto managed = temporary.path() / "managed";
    const auto destination = temporary.path() / "agents" / "zisla-managed";
    write_file(managed / "review" / "SKILL.md", "managed");
    write_file(destination / "keep.txt", "keep");

    AgentSkillSynchronizer synchronizer;
    try {
        synchronizer.synchronize(managed, destination, AgentSkillSynchronizationMode::file_copy);
        throw std::runtime_error("synchronization should reject unmanaged destination");
    } catch (const AgentSkillSynchronizationError& error) {
        expect(error.code() == AgentSkillSynchronizationErrorCode::destination_not_managed,
            "unmanaged destination should have a specific error");
    }
    expect(read_file(destination / "keep.txt") == "keep",
        "unmanaged destination contents must remain intact");
}

void fileCopyRejectsManagedSourceLinks() {
    TemporaryDirectory temporary;
    const auto managed = temporary.path() / "managed";
    const auto destination = temporary.path() / "codex" / "zisla-managed";
    write_file(managed / "review" / "SKILL.md", "managed");
    const auto external = temporary.path() / "external.txt";
    write_file(external, "external");

    std::error_code link_error;
    fs::create_symlink(external, managed / "review" / "linked.txt", link_error);
    if (link_error) {
        std::cout << "skipping source-link rejection test (links unavailable)\n";
        return;
    }

    AgentSkillSynchronizer synchronizer;
    try {
        synchronizer.synchronize(managed, destination, AgentSkillSynchronizationMode::file_copy);
        throw std::runtime_error("file copy should reject source links");
    } catch (const AgentSkillSynchronizationError& error) {
        expect(error.code() == AgentSkillSynchronizationErrorCode::source_contains_symbolic_link,
            "source links should not be followed into the destination");
    }
    expect(!fs::exists(destination), "failed source copy must not create a destination");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"catalog scans skills without following links", catalogScansSkillsWithoutFollowingLinks},
        {"catalog skips ignored managed destination", catalogSkipsIgnoredManagedDestination},
        {"file copy synchronization is managed and repeatable", fileCopySynchronizationIsManagedAndRepeatable},
        {"symbolic-link synchronization reflects managed skill changes", symbolicLinkSynchronizationReflectsManagedSkillChanges},
        {"synchronization refuses unmanaged destinations", synchronizationRefusesUnmanagedDestinations},
        {"file copy rejects managed source links", fileCopyRejectsManagedSourceLinks},
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
