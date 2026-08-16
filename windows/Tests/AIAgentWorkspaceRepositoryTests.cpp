#include "zisla/core/AIAgentWorkspaceRepository.hpp"

#include <sqlite3.h>

#include <chrono>
#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-ai-agent-workspace-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

void insert_orphaned_message(const std::filesystem::path& database_path) {
    sqlite3* database = nullptr;
    const auto encoded_path = path_as_utf8(database_path);
    const auto open_result = sqlite3_open_v2(
        encoded_path.c_str(),
        &database,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nullptr);
    if (open_result != SQLITE_OK || !database) {
        const std::string message = database
            ? sqlite3_errmsg(database)
            : "unable to open test database";
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }

    char* raw_error = nullptr;
    constexpr std::string_view sql =
        "PRAGMA foreign_keys=OFF;"
        "INSERT INTO agent_workspace_messages("
        "id, thread_id, position, role, content, account_id, mode, goal_title, "
        "created_at_unix_ms) VALUES("
        "'orphan-message', 'missing-thread', 0, 'user', 'corrupted', NULL, "
        "'standard', NULL, 1);";
    const auto execute_result = sqlite3_exec(
        database,
        sql.data(),
        nullptr,
        nullptr,
        &raw_error);
    const std::string message = execute_result == SQLITE_OK
        ? std::string{}
        : (raw_error ? raw_error : sqlite3_errmsg(database));
    sqlite3_free(raw_error);
    sqlite3_close_v2(database);
    if (execute_result != SQLITE_OK) {
        throw std::runtime_error(message);
    }
}

AgentWorkspaceProject make_project(std::string id = "project-one") {
    return {
        .id = std::move(id),
        .name = "Release workspace",
        .instructions = "Keep the Windows release focused.",
        .directory_path = "C:/work/zisla",
        .is_pinned = true,
        .is_collapsed = false,
        .created_at_unix_ms = 10,
        .updated_at_unix_ms = 20,
    };
}

AgentWorkspaceGoal make_goal(std::string id = "goal-one") {
    return {
        .id = std::move(id),
        .title = "Ship Windows 0.1.2",
        .status = AgentWorkspaceGoalStatus::completed,
        .created_at_unix_ms = 30,
        .updated_at_unix_ms = 40,
    };
}

AgentWorkspaceThread make_thread(std::string id = "thread-one") {
    return {
        .id = std::move(id),
        .title = "Windows release",
        .channel_id = "channel-one",
        .local_model_id = "local-model-one",
        .cli_kind = AgentCLIKind::codex,
        .account_id = "account-one",
        .external_history_id = "history-one",
        .mode = AgentWorkspaceChatMode::plan,
        .goal_id = std::nullopt,
        .goal_prompt = "Complete the Windows release.",
        .project_id = std::nullopt,
        .access_mode = AgentWorkspaceAccessMode::workspace_write,
        .selected_model = "gpt-5",
        .thinking_depth = AgentWorkspaceThinkingDepth::extra_high,
        .is_pinned = true,
        .archived_at_unix_ms = 50,
        .created_at_unix_ms = 60,
        .updated_at_unix_ms = 70,
    };
}

AgentWorkspaceMessage make_message(
    std::string id = "message-one",
    std::string thread_id = "thread-one") {
    return {
        .id = std::move(id),
        .thread_id = std::move(thread_id),
        .role = AgentWorkspaceMessageRole::assistant,
        .content = "The Core repository is ready for verification.",
        .account_id = "account-one",
        .skill_references = {
            {.name = "release-plan", .path = "/skills/release-plan"},
            {.name = "code-review", .path = "/skills/code-review"},
        },
        .mode = AgentWorkspaceChatMode::plan,
        .goal_title = "Ship Windows 0.1.2",
        .created_at_unix_ms = 80,
    };
}

void expect_invalid_value(
    const std::function<void()>& operation,
    std::string_view subject) {
    try {
        operation();
        throw std::runtime_error("operation should reject invalid input");
    } catch (const AIAgentWorkspaceRepositoryError& error) {
        expect(error.code() == AIAgentWorkspaceRepositoryErrorCode::invalid_value,
            "invalid input should have a stable error code");
        expect(error.subject() == subject,
            "invalid input should identify its rejected field");
    }
}

void metadata_round_trips_across_repository_instances() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());
    const auto project = make_project();
    const auto goal = make_goal();
    auto thread = make_thread();
    thread.project_id = project.id;
    thread.goal_id = goal.id;
    const auto message = make_message();

    repository.upsert_project(project);
    repository.upsert_goal(goal);
    repository.upsert_thread(thread);
    repository.append_message(message);

    const auto state = AIAgentWorkspaceRepository(temporary.path()).load();
    expect(state == AIAgentWorkspaceState{
                        .projects = {project},
                        .goals = {goal},
                        .threads = {thread},
                        .messages = {message},
                    },
        "project, goal, thread, message, and Skill metadata should round trip");
}

void deleting_project_and_goal_preserves_thread_without_references() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());
    const auto project = make_project();
    const auto goal = make_goal();
    auto thread = make_thread();
    thread.project_id = project.id;
    thread.goal_id = goal.id;

    repository.upsert_project(project);
    repository.upsert_goal(goal);
    repository.upsert_thread(thread);
    expect(repository.remove_project(project.id), "an existing project should be removed");
    expect(repository.remove_goal(goal.id), "an existing goal should be removed");
    expect(!repository.remove_project(project.id), "removing a project twice should report false");
    expect(!repository.remove_goal(goal.id), "removing a goal twice should report false");

    const auto state = repository.load();
    expect(state.projects.empty() && state.goals.empty(),
        "removed project and goal metadata should stay deleted");
    expect(state.threads.size() == 1
            && !state.threads.front().project_id
            && !state.threads.front().goal_id,
        "foreign-key deletion should retain the thread and clear both references");
}

void empty_goal_prompt_retains_goal_mode() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());
    auto thread = make_thread();
    thread.goal_prompt = std::string{};

    repository.upsert_thread(thread);

    const auto state = repository.load();
    expect(state.threads.size() == 1
            && state.threads.front().goal_prompt
            && state.threads.front().goal_prompt->empty(),
        "an empty goal prompt should persist the enabled goal-mode state");
}

void deleting_thread_cascades_messages_and_skill_references() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());
    const auto first_thread = make_thread("thread-first");
    repository.upsert_thread(first_thread);
    repository.append_message(make_message("reused-message", first_thread.id));

    expect(repository.remove_thread(first_thread.id), "an existing thread should be removed");
    expect(!repository.remove_thread(first_thread.id), "removing a thread twice should report false");

    const auto replacement_thread = make_thread("thread-replacement");
    auto replacement_message = make_message("reused-message", replacement_thread.id);
    replacement_message.skill_references = {
        {.name = "verification", .path = "/skills/verification"},
    };
    repository.upsert_thread(replacement_thread);
    repository.append_message(replacement_message);

    const auto state = repository.load();
    expect(state.threads == std::vector<AgentWorkspaceThread>{replacement_thread},
        "only the replacement thread should remain");
    expect(state.messages == std::vector<AgentWorkspaceMessage>{replacement_message},
        "cascading deletion should free message and Skill primary keys for reuse");
    expect(repository.remove_message(replacement_message.id),
        "a persisted message should be removable");
    expect(!repository.remove_message(replacement_message.id),
        "removing a message twice should report false");
}

void invalid_values_and_missing_references_are_rejected() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());

    auto invalid_goal = make_goal();
    invalid_goal.status = static_cast<AgentWorkspaceGoalStatus>(999);
    expect_invalid_value(
        [&] { repository.upsert_goal(invalid_goal); },
        "goal status");

    auto invalid_project = make_project();
    invalid_project.name.assign(AIAgentWorkspaceRepository::maximum_title_bytes + 1, 'x');
    expect_invalid_value(
        [&] { repository.upsert_project(invalid_project); },
        "project name");

    auto missing_project_thread = make_thread("missing-project-thread");
    missing_project_thread.project_id = "missing-project";
    expect_invalid_value(
        [&] { repository.upsert_thread(missing_project_thread); },
        "thread project id");

    auto missing_goal_thread = make_thread("missing-goal-thread");
    missing_goal_thread.goal_id = "missing-goal";
    expect_invalid_value(
        [&] { repository.upsert_thread(missing_goal_thread); },
        "thread goal id");

    auto invalid_thread = make_thread("invalid-thread");
    invalid_thread.mode = static_cast<AgentWorkspaceChatMode>(999);
    expect_invalid_value(
        [&] { repository.upsert_thread(invalid_thread); },
        "thread enum");

    expect_invalid_value(
        [&] { repository.append_message(make_message("missing-thread-message", "missing-thread")); },
        "message thread id");

    const auto persisted_thread = make_thread("persisted-thread");
    repository.upsert_thread(persisted_thread);
    auto oversized_message = make_message("oversized-message", persisted_thread.id);
    oversized_message.content.assign(
        AIAgentWorkspaceRepository::maximum_message_bytes + 1,
        'x');
    expect_invalid_value(
        [&] { repository.append_message(oversized_message); },
        "message content");
}

void corrupted_database_does_not_return_orphaned_messages() {
    TemporaryDirectory temporary;
    AIAgentWorkspaceRepository repository(temporary.path());
    repository.upsert_thread(make_thread());
    insert_orphaned_message(repository.database_path());

    try {
        (void)repository.load();
        throw std::runtime_error("orphaned messages should be rejected as corrupted state");
    } catch (const AIAgentWorkspaceRepositoryError& error) {
        expect(error.code() == AIAgentWorkspaceRepositoryErrorCode::corrupted_state,
            "orphaned messages should report corrupted state");
        expect(error.subject() == "orphaned message",
            "orphaned messages should have a stable corruption subject");
    }
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"workspace metadata round trips", metadata_round_trips_across_repository_instances},
        {"project and goal deletion clears thread references",
            deleting_project_and_goal_preserves_thread_without_references},
        {"empty goal prompt retains goal mode", empty_goal_prompt_retains_goal_mode},
        {"thread deletion cascades messages and Skills",
            deleting_thread_cascades_messages_and_skill_references},
        {"invalid values and references are rejected",
            invalid_values_and_missing_references_are_rejected},
        {"orphaned messages are rejected", corrupted_database_does_not_return_orphaned_messages},
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
