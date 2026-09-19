#include "zisla/core/Pet.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void activityPriorityFailedBeatsAll() {
    std::vector<AIProgressTask> tasks{
        {.id = "1", .status = AIProgressStatus::running},
        {.id = "2", .status = AIProgressStatus::failed},
        {.id = "3", .status = AIProgressStatus::succeeded},
    };
    const auto activity = pet_activity_for_ai(tasks);
    expect(activity == PetActivity::failed, "failed status should have highest priority");
}

void activityPriorityErrorEqualsFailedAndBeatsAll() {
    std::vector<AIProgressTask> tasks{
        {.id = "1", .status = AIProgressStatus::blocked},
        {.id = "2", .status = AIProgressStatus::error},
        {.id = "3", .status = AIProgressStatus::succeeded},
    };
    const auto activity = pet_activity_for_ai(tasks);
    expect(activity == PetActivity::failed, "error status should map to failed activity");
}

void activityPriorityActiveBlockedBeatsOthers() {
    std::vector<AIProgressTask> tasks{
        {.id = "1", .status = AIProgressStatus::queued},
        {.id = "2", .status = AIProgressStatus::blocked},
        {.id = "3", .status = AIProgressStatus::succeeded},
    };
    const auto activity = pet_activity_for_ai(tasks);
    expect(activity == PetActivity::waiting, "active blocked should beat queued/running/succeeded");
}

void activityPriorityQueuedOrRunningBeatsSucceeded() {
    std::vector<AIProgressTask> tasks_queued{
        {.id = "1", .status = AIProgressStatus::queued},
        {.id = "2", .status = AIProgressStatus::succeeded},
    };
    const auto activity_queued = pet_activity_for_ai(tasks_queued);
    expect(activity_queued == PetActivity::working, "queued should beat succeeded");

    std::vector<AIProgressTask> tasks_running{
        {.id = "1", .status = AIProgressStatus::running},
        {.id = "2", .status = AIProgressStatus::succeeded},
    };
    const auto activity_running = pet_activity_for_ai(tasks_running);
    expect(activity_running == PetActivity::working, "running should beat succeeded");
}

void activityPrioritySucceededBeatsIdle() {
    std::vector<AIProgressTask> tasks{
        {.id = "1", .status = AIProgressStatus::succeeded},
    };
    const auto activity = pet_activity_for_ai(tasks);
    expect(activity == PetActivity::succeeded, "succeeded should be selected when no active tasks");
}

void activityPriorityIdleWhenNoTasks() {
    std::vector<AIProgressTask> tasks;
    const auto activity = pet_activity_for_ai(tasks);
    expect(activity == PetActivity::idle, "idle when no tasks exist");
}

void animationProfileMatchesMacOSParameters() {
    const auto idle_profile = animation_profile_for(PetActivity::idle);
    expect(idle_profile.amplitude_ratio == 0.04, "idle amplitude should be 0.04");
    expect(idle_profile.period_ms == 1400, "idle period should be 1400ms");

    const auto working_profile = animation_profile_for(PetActivity::working);
    expect(working_profile.amplitude_ratio == 0.07, "working amplitude should be 0.07");
    expect(working_profile.period_ms == 800, "working period should be 800ms");

    const auto waiting_profile = animation_profile_for(PetActivity::waiting);
    expect(waiting_profile.amplitude_ratio == 0.02, "waiting amplitude should be 0.02");
    expect(waiting_profile.period_ms == 2400, "waiting period should be 2400ms");

    const auto failed_profile = animation_profile_for(PetActivity::failed);
    expect(failed_profile.amplitude_ratio == 0.015, "failed amplitude should be 0.015");
    expect(failed_profile.period_ms == 2000, "failed period should be 2000ms");

    const auto succeeded_profile = animation_profile_for(PetActivity::succeeded);
    expect(succeeded_profile.amplitude_ratio == 0.11, "succeeded amplitude should be 0.11");
    expect(succeeded_profile.period_ms == 640, "succeeded period should be 640ms");
}

void behaviorTapDoesNotOverrideExternalActivity() {
    PetBehavior behavior(1);
    behavior.set_activity(PetActivity::working);

    behavior.handle_tap(100);

    expect(behavior.activity() == PetActivity::working,
        "tap should not override external activity");
}

void behaviorExternalActivityCancelsTapFeedback() {
    PetBehavior behavior(10);
    behavior.handle_tap(100);
    expect(behavior.activity() == PetActivity::succeeded,
        "tap should enter succeeded state");

    behavior.set_activity(PetActivity::working);

    expect(behavior.activity() == PetActivity::working,
        "external activity should cancel tap feedback");
}

void behaviorTapEntersSucceededStateWhenNoExternal() {
    PetBehavior behavior(800);
    behavior.handle_tap(1000);

    expect(behavior.activity() == PetActivity::succeeded,
        "tap should enter succeeded state when no external activity");
}

void behaviorAdvanceResetsToIdleAfterTapDeadline() {
    PetBehavior behavior(100);
    behavior.handle_tap(1000);
    expect(behavior.activity() == PetActivity::succeeded, "tap should enter succeeded");

    behavior.advance(1050);
    expect(behavior.activity() == PetActivity::succeeded, "should stay succeeded before deadline");

    behavior.advance(1100);
    expect(behavior.activity() == PetActivity::idle, "should reset to idle at deadline");
}

void behaviorAdvanceIgnoresOldDeadlineWithNewExternalState() {
    PetBehavior behavior(100);
    behavior.handle_tap(1000);
    expect(behavior.activity() == PetActivity::succeeded, "tap should enter succeeded");

    behavior.set_activity(PetActivity::failed);
    behavior.advance(1200);

    expect(behavior.activity() == PetActivity::failed,
        "advance should not reset when external activity is set");
}

void behaviorAdvanceDoesNotResetIfActivityChanged() {
    PetBehavior behavior(100);
    behavior.handle_tap(1000);
    expect(behavior.activity() == PetActivity::succeeded, "tap should enter succeeded");

    behavior.set_activity(PetActivity::working);
    behavior.set_activity(std::nullopt);

    behavior.advance(1200);

    expect(behavior.activity() == PetActivity::idle,
        "advance should not reset from idle even if old deadline exists");
}

void behaviorAdvanceIgnoresOldTimestamps() {
    PetBehavior behavior(100);
    behavior.handle_tap(2000);

    behavior.advance(1500);

    expect(behavior.activity() == PetActivity::succeeded,
        "advance with old timestamp should not reset");
}

void behaviorHandlesNegativeTapDuration() {
    PetBehavior behavior(-100);
    behavior.handle_tap(1000);

    expect(behavior.activity() == PetActivity::succeeded,
        "negative duration should be clamped to 0");

    behavior.advance(1000);

    expect(behavior.activity() == PetActivity::idle,
        "should reset immediately with 0 duration");
}

void behaviorHandlesDeadlineOverflow() {
    PetBehavior behavior(1000);
    const auto max_time = std::numeric_limits<std::int64_t>::max();
    behavior.handle_tap(max_time - 100);

    expect(behavior.activity() == PetActivity::succeeded,
        "should handle tap near max timestamp");

    behavior.advance(max_time);

    expect(behavior.activity() == PetActivity::idle,
        "should reset at max timestamp without overflow");
}

class TempDirectory {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() / ("zisla_pet_test_" + random_suffix());
        std::filesystem::create_directories(path_);
    }

    ~TempDirectory() {
        std::error_code ec;
        std::filesystem::remove_all(path_, ec);
    }

    const std::filesystem::path& path() const { return path_; }

private:
    std::filesystem::path path_;

    static std::string random_suffix() {
        return std::to_string(
            std::chrono::system_clock::now().time_since_epoch().count());
    }
};

void write_file(const std::filesystem::path& path, std::string_view content) {
    std::ofstream file(path, std::ios::binary);
    if (!file) {
        throw std::runtime_error("failed to create file: " + path.string());
    }
    file.write(content.data(), static_cast<std::streamsize>(content.size()));
}

void manifestLoadsWithDefaultFields() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "test_pet";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "test_pet"})");
    write_file(pet_dir / "sprite.png", "fake_png_data");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(manifest.has_value(), "manifest should load with minimal fields");
    expect(manifest->id == "test_pet", "id should be loaded");
    expect(manifest->display_name == "test_pet", "displayName should default to id");
    expect(manifest->description == "", "description should default to empty");
    expect(manifest->sprite_path == "sprite.png", "spritePath should default to sprite.png");
    expect(manifest->frames == 1, "frames should default to 1");
    expect(manifest->fps == 6.0, "fps should default to 6.0");
}

void manifestLoadsAllFields() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "cat";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({
        "id": "cat",
        "displayName": "Cute Cat",
        "description": "A friendly pixel cat",
        "spritePath": "cat_sprite.png",
        "frameWidth": 32,
        "frames": 4,
        "fps": 8.0
    })");
    write_file(pet_dir / "cat_sprite.png", "fake_png");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(manifest.has_value(), "manifest should load all fields");
    expect(manifest->id == "cat", "id should match");
    expect(manifest->display_name == "Cute Cat", "displayName should match");
    expect(manifest->description == "A friendly pixel cat", "description should match");
    expect(manifest->sprite_path == "cat_sprite.png", "spritePath should match");
    expect(manifest->frame_width == 32, "frameWidth should match");
    expect(manifest->frames == 4, "frames should match");
    expect(manifest->fps == 8.0, "fps should match");
}

void manifestRejectsInvalidId() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "invalid";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "../evil"})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject id with path traversal");
}

void manifestRejectsEmptyId() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "empty";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": ""})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject empty id");
}

void manifestRejectsAbsoluteSpritePath() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "abs";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "abs", "spritePath": "/etc/passwd"})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject absolute sprite path");
}

void manifestRejectsPathTraversal() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "traversal";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "traversal", "spritePath": "../secret.png"})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject path with .. traversal");
}

void manifestRejectsMissingSprite() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "missing";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "missing"})");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject when sprite file is missing");
}

void manifestRejectsSymlinkEscape() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "symlink";
    std::filesystem::create_directories(pet_dir);

    const auto outside = temp.path() / "outside.png";
    write_file(outside, "outside_data");

    write_file(pet_dir / "pet.json", R"({"id": "symlink", "spritePath": "link.png"})");

    std::error_code ec;
    std::filesystem::create_symlink(outside, pet_dir / "link.png", ec);
    if (ec) {
        std::cout << "skipping symlink test (symlink creation failed)\n";
        return;
    }

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject symlink escaping pet directory");
}

void manifestRejectsInvalidFrames() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "frames";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "frames", "frames": 0})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject frames < 1");
}

void manifestRejectsInvalidStripMode() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "strip";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({
        "id": "strip",
        "frameWidth": 0,
        "frames": 4
    })");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject frameWidth <= 0 in strip mode");
}

void manifestRejectsMultiFrameWithoutFrameWidth() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "multi_no_width";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "multi_no_width", "frames": 4})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject frames > 1 without frameWidth");
}

void manifestRejectsFpsBelowRange() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "fps_low";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "fps_low", "fps": 0.5})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject fps < 1");
}

void manifestRejectsFpsAboveRange() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "fps_high";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "fps_high", "fps": 15.0})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject fps > 12");
}

void manifestRejectsInvalidJson() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "invalid_json";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", "{invalid json");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject invalid JSON");
}

void manifestRejectsWrongTypeFrames() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "wrong_frames";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "wrong_frames", "frames": "not_a_number"})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject non-integer frames");
}

void manifestRejectsWrongTypeFps() {
    TempDirectory temp;
    const auto pet_dir = temp.path() / "wrong_fps";
    std::filesystem::create_directories(pet_dir);

    write_file(pet_dir / "pet.json", R"({"id": "wrong_fps", "fps": "not_a_number"})");
    write_file(pet_dir / "sprite.png", "fake");

    const auto manifest = PetLibrary::load_manifest(pet_dir);

    expect(!manifest.has_value(), "manifest should reject non-numeric fps");
}

void libraryScansAndSortsPetIds() {
    TempDirectory temp;

    const auto zebra_dir = temp.path() / "zebra";
    std::filesystem::create_directories(zebra_dir);
    write_file(zebra_dir / "pet.json", R"({"id": "zebra"})");
    write_file(zebra_dir / "sprite.png", "fake");

    const auto ant_dir = temp.path() / "ant";
    std::filesystem::create_directories(ant_dir);
    write_file(ant_dir / "pet.json", R"({"id": "ant"})");
    write_file(ant_dir / "sprite.png", "fake");

    const auto ids = PetLibrary::builtin_pet_ids(temp.path());

    expect(ids.size() == 2, "should find 2 valid pets");
    expect(ids[0] == "ant", "first id should be ant (sorted)");
    expect(ids[1] == "zebra", "second id should be zebra (sorted)");
}

void libraryIgnoresInvalidEntries() {
    TempDirectory temp;

    const auto valid_dir = temp.path() / "valid";
    std::filesystem::create_directories(valid_dir);
    write_file(valid_dir / "pet.json", R"({"id": "valid"})");
    write_file(valid_dir / "sprite.png", "fake");

    const auto no_json = temp.path() / "no_json";
    std::filesystem::create_directories(no_json);
    write_file(no_json / "sprite.png", "fake");

    const auto no_sprite = temp.path() / "no_sprite";
    std::filesystem::create_directories(no_sprite);
    write_file(no_sprite / "pet.json", R"({"id": "no_sprite"})");

    write_file(temp.path() / "not_a_dir.txt", "file");

    const auto ids = PetLibrary::builtin_pet_ids(temp.path());

    expect(ids.size() == 1, "should only find 1 valid pet");
    expect(ids[0] == "valid", "should only include the valid pet");
}

void libraryLoadAllManifestsReturnsValidOnesOnly() {
    TempDirectory temp;

    const auto cat_dir = temp.path() / "cat";
    std::filesystem::create_directories(cat_dir);
    write_file(cat_dir / "pet.json", R"({"id": "cat", "displayName": "Cat"})");
    write_file(cat_dir / "sprite.png", "fake");

    const auto dog_dir = temp.path() / "dog";
    std::filesystem::create_directories(dog_dir);
    write_file(dog_dir / "pet.json", R"({"id": "dog", "displayName": "Dog"})");
    write_file(dog_dir / "sprite.png", "fake");

    const auto bad_dir = temp.path() / "bad";
    std::filesystem::create_directories(bad_dir);
    write_file(bad_dir / "pet.json", R"({"id": "../bad"})");

    const auto manifests = PetLibrary::load_all_manifests(temp.path());

    expect(manifests.size() == 2, "should load 2 valid manifests");
    expect(manifests[0].id == "cat" || manifests[0].id == "dog", "should contain cat or dog");
    expect(manifests[1].id == "cat" || manifests[1].id == "dog", "should contain cat or dog");
}

void libraryHandlesDuplicateIdsStably() {
    TempDirectory temp;

    const auto first_dir = temp.path() / "a_first";
    std::filesystem::create_directories(first_dir);
    write_file(first_dir / "pet.json", R"({"id": "pet", "displayName": "First"})");
    write_file(first_dir / "sprite.png", "fake");

    const auto second_dir = temp.path() / "z_second";
    std::filesystem::create_directories(second_dir);
    write_file(second_dir / "pet.json", R"({"id": "pet", "displayName": "Second"})");
    write_file(second_dir / "sprite.png", "fake");

    const auto entries = PetLibrary::entries(temp.path());

    expect(entries.size() == 1, "duplicate ids should result in single entry");
    expect(entries[0].manifest.display_name == "First",
        "duplicate ids should keep the lexicographically first directory");
    expect(entries[0].sprite_file == first_dir / "sprite.png",
        "duplicate id resolution should keep the matching sprite path");
}

void libraryIgnoresSymlinkedChildDirectory() {
    TempDirectory pets;
    TempDirectory external;

    const auto valid_dir = pets.path() / "valid";
    std::filesystem::create_directories(valid_dir);
    write_file(valid_dir / "pet.json", R"({"id": "valid"})");
    write_file(valid_dir / "sprite.png", "fake");

    const auto external_dir = external.path() / "outside";
    std::filesystem::create_directories(external_dir);
    write_file(external_dir / "pet.json", R"({"id": "outside"})");
    write_file(external_dir / "sprite.png", "fake");

    std::error_code ec;
    std::filesystem::create_directory_symlink(
        external_dir,
        pets.path() / "linked",
        ec);
    if (ec) {
        std::cout << "skipping child directory symlink test (symlink creation failed)\n";
        return;
    }

    const auto ids = PetLibrary::builtin_pet_ids(pets.path());

    expect(ids.size() == 1, "symlinked child directories should be ignored");
    expect(ids[0] == "valid", "only the real child directory should be loaded");
}

using TestFunction = std::function<void()>;

struct TestCase {
    const char* name;
    TestFunction func;
};

}  // namespace

int main() {
    const TestCase tests[] = {
        {"activityPriorityFailedBeatsAll", activityPriorityFailedBeatsAll},
        {"activityPriorityErrorEqualsFailedAndBeatsAll", activityPriorityErrorEqualsFailedAndBeatsAll},
        {"activityPriorityActiveBlockedBeatsOthers", activityPriorityActiveBlockedBeatsOthers},
        {"activityPriorityQueuedOrRunningBeatsSucceeded", activityPriorityQueuedOrRunningBeatsSucceeded},
        {"activityPrioritySucceededBeatsIdle", activityPrioritySucceededBeatsIdle},
        {"activityPriorityIdleWhenNoTasks", activityPriorityIdleWhenNoTasks},
        {"animationProfileMatchesMacOSParameters", animationProfileMatchesMacOSParameters},
        {"behaviorTapDoesNotOverrideExternalActivity", behaviorTapDoesNotOverrideExternalActivity},
        {"behaviorExternalActivityCancelsTapFeedback", behaviorExternalActivityCancelsTapFeedback},
        {"behaviorTapEntersSucceededStateWhenNoExternal", behaviorTapEntersSucceededStateWhenNoExternal},
        {"behaviorAdvanceResetsToIdleAfterTapDeadline", behaviorAdvanceResetsToIdleAfterTapDeadline},
        {"behaviorAdvanceIgnoresOldDeadlineWithNewExternalState", behaviorAdvanceIgnoresOldDeadlineWithNewExternalState},
        {"behaviorAdvanceDoesNotResetIfActivityChanged", behaviorAdvanceDoesNotResetIfActivityChanged},
        {"behaviorAdvanceIgnoresOldTimestamps", behaviorAdvanceIgnoresOldTimestamps},
        {"behaviorHandlesNegativeTapDuration", behaviorHandlesNegativeTapDuration},
        {"behaviorHandlesDeadlineOverflow", behaviorHandlesDeadlineOverflow},
        {"manifestLoadsWithDefaultFields", manifestLoadsWithDefaultFields},
        {"manifestLoadsAllFields", manifestLoadsAllFields},
        {"manifestRejectsInvalidId", manifestRejectsInvalidId},
        {"manifestRejectsEmptyId", manifestRejectsEmptyId},
        {"manifestRejectsAbsoluteSpritePath", manifestRejectsAbsoluteSpritePath},
        {"manifestRejectsPathTraversal", manifestRejectsPathTraversal},
        {"manifestRejectsMissingSprite", manifestRejectsMissingSprite},
        {"manifestRejectsSymlinkEscape", manifestRejectsSymlinkEscape},
        {"manifestRejectsInvalidFrames", manifestRejectsInvalidFrames},
        {"manifestRejectsInvalidStripMode", manifestRejectsInvalidStripMode},
        {"manifestRejectsMultiFrameWithoutFrameWidth", manifestRejectsMultiFrameWithoutFrameWidth},
        {"manifestRejectsFpsBelowRange", manifestRejectsFpsBelowRange},
        {"manifestRejectsFpsAboveRange", manifestRejectsFpsAboveRange},
        {"manifestRejectsInvalidJson", manifestRejectsInvalidJson},
        {"manifestRejectsWrongTypeFrames", manifestRejectsWrongTypeFrames},
        {"manifestRejectsWrongTypeFps", manifestRejectsWrongTypeFps},
        {"libraryScansAndSortsPetIds", libraryScansAndSortsPetIds},
        {"libraryIgnoresInvalidEntries", libraryIgnoresInvalidEntries},
        {"libraryLoadAllManifestsReturnsValidOnesOnly", libraryLoadAllManifestsReturnsValidOnesOnly},
        {"libraryHandlesDuplicateIdsStably", libraryHandlesDuplicateIdsStably},
        {"libraryIgnoresSymlinkedChildDirectory", libraryIgnoresSymlinkedChildDirectory},
    };

    int passed = 0;
    int failed = 0;

    for (const auto& test : tests) {
        try {
            test.func();
            std::cout << "[PASS] " << test.name << "\n";
            ++passed;
        } catch (const std::exception& ex) {
            std::cout << "[FAIL] " << test.name << ": " << ex.what() << "\n";
            ++failed;
        }
    }

    std::cout << "\nTotal: " << (passed + failed)
              << " | Passed: " << passed
              << " | Failed: " << failed << "\n";

    return failed == 0 ? 0 : 1;
}
