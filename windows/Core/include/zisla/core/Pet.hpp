#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class PetActivity {
    idle,
    working,
    waiting,
    failed,
    succeeded,
};

[[nodiscard]] PetActivity pet_activity_for_ai(
    std::span<const AIProgressTask> tasks) noexcept;

struct PetAnimationProfile {
    double amplitude_ratio{0.0};
    std::int64_t period_ms{0};

    friend bool operator==(
        const PetAnimationProfile&,
        const PetAnimationProfile&) = default;
};

[[nodiscard]] PetAnimationProfile animation_profile_for(
    PetActivity activity) noexcept;

class PetBehavior {
public:
    PetBehavior();
    explicit PetBehavior(std::int64_t tap_feedback_duration_ms);

    void set_activity(std::optional<PetActivity> activity) noexcept;
    void handle_tap(std::int64_t now_ms) noexcept;
    void advance(std::int64_t now_ms) noexcept;

    [[nodiscard]] PetActivity activity() const noexcept { return activity_; }

private:
    PetActivity activity_{PetActivity::idle};
    std::optional<PetActivity> external_activity_;
    std::optional<std::int64_t> tap_reset_deadline_ms_;
    std::int64_t tap_feedback_duration_ms_{800};
};

struct PetManifest {
    std::string id;
    std::string display_name;
    std::string description;
    std::string sprite_path;
    std::optional<int> frame_width;
    int frames{1};
    double fps{6.0};

    friend bool operator==(const PetManifest&, const PetManifest&) = default;
};

struct PetLibraryEntry {
    PetManifest manifest;
    std::filesystem::path directory;
    std::filesystem::path sprite_file;

    friend bool operator==(const PetLibraryEntry&, const PetLibraryEntry&) = default;
};

class PetLibrary {
public:
    static constexpr std::size_t maximum_manifest_bytes = 64 * 1024;
    static constexpr std::size_t maximum_directory_entries = 512;

    [[nodiscard]] static std::vector<std::string> builtin_pet_ids(
        const std::filesystem::path& pets_root);

    [[nodiscard]] static std::optional<PetManifest> load_manifest(
        const std::filesystem::path& directory);

    [[nodiscard]] static std::vector<PetManifest> load_all_manifests(
        const std::filesystem::path& pets_root);

    [[nodiscard]] static std::vector<PetLibraryEntry> entries(
        const std::filesystem::path& pets_root);

    [[nodiscard]] static std::optional<PetLibraryEntry> find(
        const std::filesystem::path& pets_root,
        std::string_view id);

private:
    [[nodiscard]] static bool is_valid_slug(std::string_view slug) noexcept;
    [[nodiscard]] static bool is_safe_relative_path(
        std::string_view path) noexcept;
};

}  // namespace zisla::core
