#include "zisla/core/Pet.hpp"

#include <yyjson.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <limits>
#include <system_error>
#include <unordered_set>

namespace zisla::core {
namespace {

bool has_status(
    std::span<const AIProgressTask> tasks,
    AIProgressStatus status) noexcept {
    return std::any_of(
        tasks.begin(),
        tasks.end(),
        [status](const AIProgressTask& task) {
            return task.status == status;
        });
}

bool has_active_status(
    std::span<const AIProgressTask> tasks,
    AIProgressStatus status) noexcept {
    return std::any_of(
        tasks.begin(),
        tasks.end(),
        [status](const AIProgressTask& task) {
            return task.status == status && is_active(task.status);
        });
}

bool is_safe_path_char(char ch) noexcept {
    return (ch >= 'a' && ch <= 'z')
        || (ch >= 'A' && ch <= 'Z')
        || (ch >= '0' && ch <= '9')
        || ch == '_'
        || ch == '-'
        || ch == '.';
}

bool read_json_string(
    yyjson_val* obj,
    const char* key,
    std::string_view default_value,
    std::string& result) {
    auto* val = yyjson_obj_get(obj, key);
    if (!val) {
        result = default_value;
        return true;
    }
    if (!yyjson_is_str(val)) {
        return false;
    }
    result = yyjson_get_str(val);
    return true;
}

bool read_json_int(
    yyjson_val* obj,
    const char* key,
    int default_value,
    int& result) {
    auto* val = yyjson_obj_get(obj, key);
    if (!val) {
        result = default_value;
        return true;
    }
    if (!yyjson_is_int(val)) {
        return false;
    }
    const auto value = yyjson_get_sint(val);
    if (value < std::numeric_limits<int>::min()
        || value > std::numeric_limits<int>::max()) {
        return false;
    }
    result = static_cast<int>(value);
    return true;
}

bool read_optional_json_int(
    yyjson_val* obj,
    const char* key,
    std::optional<int>& result) {
    auto* val = yyjson_obj_get(obj, key);
    if (!val) {
        result.reset();
        return true;
    }
    if (!yyjson_is_int(val)) {
        return false;
    }
    const auto value = yyjson_get_sint(val);
    if (value < std::numeric_limits<int>::min()
        || value > std::numeric_limits<int>::max()) {
        return false;
    }
    result = static_cast<int>(value);
    return true;
}

bool read_json_double(
    yyjson_val* obj,
    const char* key,
    double default_value,
    double& result) {
    auto* val = yyjson_obj_get(obj, key);
    if (!val) {
        result = default_value;
        return true;
    }
    if (!yyjson_is_num(val)) {
        return false;
    }
    result = yyjson_get_real(val);
    if (!std::isfinite(result)) {
        return false;
    }
    return true;
}

}  // namespace

PetActivity pet_activity_for_ai(
    std::span<const AIProgressTask> tasks) noexcept {
    if (has_status(tasks, AIProgressStatus::failed)
        || has_status(tasks, AIProgressStatus::error)) {
        return PetActivity::failed;
    }
    if (has_active_status(tasks, AIProgressStatus::blocked)) {
        return PetActivity::waiting;
    }
    if (has_active_status(tasks, AIProgressStatus::queued)
        || has_active_status(tasks, AIProgressStatus::running)) {
        return PetActivity::working;
    }
    if (has_status(tasks, AIProgressStatus::succeeded)) {
        return PetActivity::succeeded;
    }
    return PetActivity::idle;
}

PetAnimationProfile animation_profile_for(PetActivity activity) noexcept {
    switch (activity) {
    case PetActivity::idle:
        return {.amplitude_ratio = 0.04, .period_ms = 1400};
    case PetActivity::working:
        return {.amplitude_ratio = 0.07, .period_ms = 800};
    case PetActivity::waiting:
        return {.amplitude_ratio = 0.02, .period_ms = 2400};
    case PetActivity::failed:
        return {.amplitude_ratio = 0.015, .period_ms = 2000};
    case PetActivity::succeeded:
        return {.amplitude_ratio = 0.11, .period_ms = 640};
    }
    return {.amplitude_ratio = 0.04, .period_ms = 1400};
}

PetBehavior::PetBehavior()
    : tap_feedback_duration_ms_(800) {}

PetBehavior::PetBehavior(std::int64_t tap_feedback_duration_ms)
    : tap_feedback_duration_ms_(std::max<std::int64_t>(0, tap_feedback_duration_ms)) {}

void PetBehavior::set_activity(std::optional<PetActivity> activity) noexcept {
    external_activity_ = activity;
    tap_reset_deadline_ms_ = std::nullopt;
    activity_ = activity.value_or(PetActivity::idle);
}

void PetBehavior::handle_tap(std::int64_t now_ms) noexcept {
    if (external_activity_.has_value()) {
        return;
    }
    const auto maximum = std::numeric_limits<std::int64_t>::max();
    tap_reset_deadline_ms_ = now_ms > maximum - tap_feedback_duration_ms_
        ? maximum
        : now_ms + tap_feedback_duration_ms_;
    activity_ = PetActivity::succeeded;
}

void PetBehavior::advance(std::int64_t now_ms) noexcept {
    if (!tap_reset_deadline_ms_.has_value()) {
        return;
    }
    if (now_ms < *tap_reset_deadline_ms_) {
        return;
    }
    if (external_activity_.has_value()) {
        return;
    }
    if (activity_ != PetActivity::succeeded) {
        return;
    }
    activity_ = PetActivity::idle;
    tap_reset_deadline_ms_ = std::nullopt;
}

bool PetLibrary::is_valid_slug(std::string_view slug) noexcept {
    if (slug.empty() || slug.size() > 64) {
        return false;
    }
    for (const auto ch : slug) {
        if (!((ch >= 'a' && ch <= 'z')
              || (ch >= 'A' && ch <= 'Z')
              || (ch >= '0' && ch <= '9')
              || ch == '_'
              || ch == '-')) {
            return false;
        }
    }
    return true;
}

bool PetLibrary::is_safe_relative_path(std::string_view path) noexcept {
    if (path.empty() || path.size() > 256) {
        return false;
    }
    if (path == "." || path == ".."
        || path.find('/') != std::string_view::npos
        || path.find('\\') != std::string_view::npos) {
        return false;
    }
    for (const auto ch : path) {
        if (!is_safe_path_char(ch)) {
            return false;
        }
    }
    return true;
}

std::vector<std::string> PetLibrary::builtin_pet_ids(
    const std::filesystem::path& pets_root) {
    std::vector<std::string> result;
    for (const auto& entry : entries(pets_root)) {
        result.push_back(entry.manifest.id);
    }
    return result;
}

std::optional<PetManifest> PetLibrary::load_manifest(
    const std::filesystem::path& directory) {
    std::error_code ec;
    const auto directory_status = std::filesystem::symlink_status(directory, ec);
    if (ec || std::filesystem::is_symlink(directory_status)
        || !std::filesystem::is_directory(directory_status)) {
        return std::nullopt;
    }

    const auto manifest_path = directory / "pet.json";
    const auto manifest_status = std::filesystem::symlink_status(manifest_path, ec);
    if (ec || std::filesystem::is_symlink(manifest_status)
        || !std::filesystem::is_regular_file(manifest_status)) {
        return std::nullopt;
    }

    const auto size = std::filesystem::file_size(manifest_path, ec);
    if (ec || size > maximum_manifest_bytes) {
        return std::nullopt;
    }

    std::ifstream file(manifest_path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }

    std::string content(size, '\0');
    if (!file.read(content.data(), static_cast<std::streamsize>(size))) {
        return std::nullopt;
    }

    yyjson_doc* doc = yyjson_read(
        content.data(),
        content.size(),
        YYJSON_READ_NOFLAG);
    if (!doc) {
        return std::nullopt;
    }

    yyjson_val* root = yyjson_doc_get_root(doc);
    if (!root || !yyjson_is_obj(root)) {
        yyjson_doc_free(doc);
        return std::nullopt;
    }

    PetManifest manifest;
    const bool fields_valid = read_json_string(root, "id", "", manifest.id)
        && read_json_string(root, "displayName", manifest.id, manifest.display_name)
        && read_json_string(root, "description", "", manifest.description)
        && read_json_string(root, "spritePath", "sprite.png", manifest.sprite_path)
        && read_optional_json_int(root, "frameWidth", manifest.frame_width)
        && read_json_int(root, "frames", 1, manifest.frames)
        && read_json_double(root, "fps", 6.0, manifest.fps);

    yyjson_doc_free(doc);

    if (!fields_valid) {
        return std::nullopt;
    }

    if (!is_valid_slug(manifest.id)) {
        return std::nullopt;
    }

    if (!is_safe_relative_path(manifest.sprite_path)) {
        return std::nullopt;
    }

    const auto sprite_full_path = directory / manifest.sprite_path;
    if (!std::filesystem::is_regular_file(sprite_full_path, ec)) {
        return std::nullopt;
    }

    std::filesystem::path canonical_dir;
    std::filesystem::path canonical_sprite;
    try {
        canonical_dir = std::filesystem::canonical(directory, ec);
        if (ec) {
            return std::nullopt;
        }
        canonical_sprite = std::filesystem::canonical(sprite_full_path, ec);
        if (ec) {
            return std::nullopt;
        }
    } catch (...) {
        return std::nullopt;
    }

    if (canonical_sprite.parent_path() != canonical_dir) {
        return std::nullopt;
    }

    if (manifest.frames < 1) {
        return std::nullopt;
    }

    if (manifest.frames > 1) {
        if (!manifest.frame_width || *manifest.frame_width <= 0) {
            return std::nullopt;
        }
    } else {
        manifest.frame_width.reset();
    }

    if (manifest.fps < 1.0 || manifest.fps > 12.0) {
        return std::nullopt;
    }
    if (manifest.display_name.empty()) {
        manifest.display_name = manifest.id;
    }

    return manifest;
}

std::vector<PetManifest> PetLibrary::load_all_manifests(
    const std::filesystem::path& pets_root) {
    std::vector<PetManifest> result;
    for (auto& entry : entries(pets_root)) {
        result.push_back(std::move(entry.manifest));
    }
    return result;
}

std::vector<PetLibraryEntry> PetLibrary::entries(
    const std::filesystem::path& pets_root) {
    std::vector<PetLibraryEntry> result;
    std::vector<std::filesystem::path> directories;
    std::error_code error;
    const auto root_status = std::filesystem::symlink_status(pets_root, error);
    if (error || std::filesystem::is_symlink(root_status)
        || !std::filesystem::is_directory(root_status)) {
        return result;
    }

    for (const auto& entry : std::filesystem::directory_iterator(pets_root, error)) {
        if (error || directories.size() >= maximum_directory_entries) {
            break;
        }
        const auto status = entry.symlink_status(error);
        if (error) {
            break;
        }
        if (!std::filesystem::is_symlink(status)
            && std::filesystem::is_directory(status)) {
            directories.push_back(entry.path());
        }
    }
    std::sort(directories.begin(), directories.end());

    std::unordered_set<std::string> seen;
    for (const auto& directory : directories) {
        auto manifest = load_manifest(directory);
        if (!manifest || !seen.insert(manifest->id).second) {
            continue;
        }
        PetLibraryEntry entry{
            .manifest = std::move(*manifest),
            .directory = directory,
            .sprite_file = {},
        };
        entry.sprite_file = directory / entry.manifest.sprite_path;
        result.push_back(std::move(entry));
    }
    std::sort(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
        return lhs.manifest.id < rhs.manifest.id;
    });
    return result;
}

std::optional<PetLibraryEntry> PetLibrary::find(
    const std::filesystem::path& pets_root,
    std::string_view id) {
    auto available = entries(pets_root);
    const auto found = std::find_if(
        available.begin(),
        available.end(),
        [id](const auto& entry) { return entry.manifest.id == id; });
    return found == available.end()
        ? std::nullopt
        : std::optional<PetLibraryEntry>{std::move(*found)};
}

}  // namespace zisla::core
