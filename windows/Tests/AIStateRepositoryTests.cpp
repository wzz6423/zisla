#include "zisla/core/AIStateRepository.hpp"

#include <sqlite3.h>

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

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
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch()
            .count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-ai-state-" + std::to_string(suffix));
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

std::string pathAsUtf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

void insertTaskPayload(
    const std::filesystem::path& database_path,
    std::string_view id,
    std::string_view payload) {
    sqlite3* database = nullptr;
    const auto encoded_path = pathAsUtf8(database_path);
    if (sqlite3_open_v2(
            encoded_path.c_str(),
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr) != SQLITE_OK) {
        const std::string message = database
            ? sqlite3_errmsg(database)
            : "unable to open test database";
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }

    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(
            database,
            "INSERT INTO tasks(id, payload) VALUES(?, ?)",
            -1,
            &statement,
            nullptr) != SQLITE_OK
        || sqlite3_bind_text(
            statement, 1, id.data(), static_cast<int>(id.size()), SQLITE_TRANSIENT) != SQLITE_OK
        || sqlite3_bind_blob(
            statement,
            2,
            payload.data(),
            static_cast<int>(payload.size()),
            SQLITE_TRANSIENT) != SQLITE_OK
        || sqlite3_step(statement) != SQLITE_DONE) {
        const std::string message = sqlite3_errmsg(database);
        sqlite3_finalize(statement);
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }
    sqlite3_finalize(statement);
    sqlite3_close_v2(database);
}

void insertNoticePayload(
    const std::filesystem::path& database_path,
    std::string_view payload) {
    sqlite3* database = nullptr;
    const auto encoded_path = pathAsUtf8(database_path);
    if (sqlite3_open_v2(
            encoded_path.c_str(),
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr) != SQLITE_OK) {
        const std::string message = database
            ? sqlite3_errmsg(database)
            : "unable to open test database";
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }

    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(
            database,
            "INSERT INTO notices(payload) VALUES(?)",
            -1,
            &statement,
            nullptr) != SQLITE_OK
        || sqlite3_bind_blob(
            statement,
            1,
            payload.data(),
            static_cast<int>(payload.size()),
            SQLITE_TRANSIENT) != SQLITE_OK
        || sqlite3_step(statement) != SQLITE_DONE) {
        const std::string message = sqlite3_errmsg(database);
        sqlite3_finalize(statement);
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }
    sqlite3_finalize(statement);
    sqlite3_close_v2(database);
}

std::int64_t noticeRowCount(const std::filesystem::path& database_path) {
    sqlite3* database = nullptr;
    const auto encoded_path = pathAsUtf8(database_path);
    if (sqlite3_open_v2(
            encoded_path.c_str(),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nullptr) != SQLITE_OK) {
        const std::string message = database
            ? sqlite3_errmsg(database)
            : "unable to open test database";
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }

    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(
            database,
            "SELECT COUNT(*) FROM notices",
            -1,
            &statement,
            nullptr) != SQLITE_OK
        || sqlite3_step(statement) != SQLITE_ROW) {
        const std::string message = sqlite3_errmsg(database);
        sqlite3_finalize(statement);
        sqlite3_close_v2(database);
        throw std::runtime_error(message);
    }
    const auto count = sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    sqlite3_close_v2(database);
    return count;
}

void corruptedDatabaseIsReportedAndNeverOverwritten() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    std::filesystem::create_directories(directory.path());
    const std::string invalid = "not a sqlite database";
    {
        std::ofstream output(repository.database_path(), std::ios::binary);
        output.write(invalid.data(), static_cast<std::streamsize>(invalid.size()));
    }

    try {
        repository.upsert({
            .id = "x",
            .provider = AIProvider::grok,
            .title = "Task",
            .progress = std::nullopt,
            .updated_at_unix_ms = 1'700'000'000'000,
        });
        throw std::runtime_error("corrupted database should fail");
    } catch (const AIStateRepositoryError& error) {
        expect(error.code() == AIStateRepositoryErrorCode::storage_failure,
            "corrupted database should report a storage failure");
    }

    std::ifstream input(repository.database_path(), std::ios::binary);
    const std::string retained{
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()};
    expect(retained == invalid,
        "corrupted database bytes must remain untouched");
}

void repositoryLoadsSwiftCodableTaskPayload() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const auto initial = repository.load(false);
    expect(initial == AIState{},
        "new repository should initialize an empty SQLite database");
    insertTaskPayload(
        repository.database_path(),
        "swift-task",
        R"({"id":"swift-task","provider":"codex","title":"Swift payload","detail":"from macOS","progress":0.25,"status":"running","updatedAt":721692800,"sessionURL":"https:\/\/example.com\/sessions\/1","effort":"high","startedAt":721692790})");

    const auto state = repository.load(false);
    expect(state.tasks.size() == 1,
        "repository should load one Swift task payload");
    const auto& task = state.tasks.front();
    expect(task.id == "swift-task", "Swift payload id should decode");
    expect(task.provider == AIProvider::codex, "Swift payload provider should decode");
    expect(task.title == "Swift payload", "Swift payload title should decode");
    expect(task.detail == "from macOS", "Swift payload detail should decode");
    expect(task.progress == 0.25, "Swift payload progress should decode");
    expect(task.status == AIProgressStatus::running, "Swift payload status should decode");
    expect(task.updated_at_unix_ms == 1'700'000'000'000,
        "Swift payload updatedAt should decode from reference-date seconds");
    expect(task.session_uri == "https://example.com/sessions/1",
        "Swift payload sessionURL should decode");
    expect(task.effort == "high", "Swift payload effort should decode");
    expect(task.started_at_unix_ms == 1'699'999'990'000,
        "Swift payload startedAt should decode from reference-date seconds");
}

void upsertPersistsAcrossRepositoryInstances() {
    const TemporaryDirectory directory;
    const AIProgressTask original{
        .id = "compile",
        .provider = AIProvider::claude,
        .title = "Compile project",
        .detail = "12/30",
        .progress = 0.4,
        .status = AIProgressStatus::running,
        .updated_at_unix_ms = 1'700'000'000'000,
    };

    AIStateRepository(directory.path()).upsert(original);

    auto updated = original;
    updated.detail = "18/30";
    updated.progress = 0.6;
    updated.updated_at_unix_ms += 1'000;
    AIStateRepository(directory.path()).upsert(updated);

    const auto state = AIStateRepository(directory.path()).load();
    expect(state.tasks == std::vector{updated},
        "upsert should replace one task and a new repository should reopen it");
}

void finishAppliesTerminalStateAndReportsMissingTasks() {
    const TemporaryDirectory directory;
    const AIProgressTask successful{
        .id = "success",
        .provider = AIProvider::codex,
        .title = "Successful task",
        .detail = "Working",
        .progress = 0.35,
        .status = AIProgressStatus::running,
        .updated_at_unix_ms = 10'000,
    };
    const AIProgressTask failed{
        .id = "failure",
        .provider = AIProvider::grok,
        .title = "Failed task",
        .detail = "Last good step",
        .progress = 0.4,
        .status = AIProgressStatus::running,
        .updated_at_unix_ms = 11'000,
    };
    const AIStateRepository repository(directory.path());
    repository.upsert(successful);
    repository.upsert(failed);

    repository.finish(successful.id, false, std::string("Done"), 20'000);
    repository.finish(failed.id, true, std::nullopt, 21'000);

    const auto state = repository.load();
    expect(state.tasks[0].status == AIProgressStatus::succeeded
            && state.tasks[0].progress == 1.0
            && state.tasks[0].detail == "Done"
            && state.tasks[0].updated_at_unix_ms == 20'000,
        "successful finish should set terminal state, full progress, detail, and time");
    expect(state.tasks[1].status == AIProgressStatus::failed
            && state.tasks[1].progress == 0.4
            && state.tasks[1].detail == "Last good step"
            && state.tasks[1].updated_at_unix_ms == 21'000,
        "failed finish should preserve progress and omitted detail");

    try {
        repository.finish("missing", false, std::nullopt, 22'000);
        throw std::runtime_error("missing task should fail");
    } catch (const AIStateRepositoryError& error) {
        expect(error.code() == AIStateRepositoryErrorCode::task_not_found
                && error.subject() == "missing",
            "missing finish should expose task_not_found and the task id");
    }
}

void removeReportsWhetherATaskExisted() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    repository.upsert({
        .id = "remove-me",
        .provider = AIProvider::gemini,
        .title = "Temporary task",
        .progress = std::nullopt,
        .updated_at_unix_ms = 30'000,
    });

    expect(repository.remove("remove-me"),
        "remove should report an existing task");
    expect(!repository.remove("remove-me"),
        "remove should report a missing task after deletion");
    expect(repository.load().tasks.empty(),
        "removed task should no longer be persisted");
}

void clearTasksPreservesUsageHistory() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    repository.upsert({
        .id = "clear-me",
        .provider = AIProvider::claude,
        .title = "Temporary task",
        .progress = 0.5,
        .updated_at_unix_ms = 40'000,
    });
    const AIUsageSample sample{
        .provider = AIProvider::codex,
        .timestamp_unix_ms = 41'000,
        .input_tokens = 12,
        .output_tokens = 3,
    };
    repository.record_usage(sample);

    repository.clear_tasks();

    const auto state = repository.load();
    expect(state.tasks.empty(), "clear should remove every task");
    expect(state.usage_samples == std::vector{sample},
        "clear should preserve usage history");
}

void storageChangeTokenIgnoresLegacyJsonAndTracksSqliteWrites() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const auto initial = repository.storage_change_token();

    std::filesystem::create_directories(directory.path());
    {
        std::ofstream legacy(directory.path() / "ai-state.json", std::ios::binary);
        legacy << R"({"usageSamples":[]})";
    }
    expect(repository.storage_change_token() == initial,
        "legacy JSON writes should not change the SQLite storage token");

    repository.record_usage({
        .source_id = "sqlite-write",
        .provider = AIProvider::codex,
        .timestamp_unix_ms = 1'000'000,
        .input_tokens = 1,
        .output_tokens = 1,
    });
    expect(repository.storage_change_token() != initial,
        "SQLite writes should change the storage token");
}

void noticesPersistInOrderAndLoadWithoutUsageHistory() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const std::vector notices = {
        IslandNotice{
            .id = "notice-1",
            .title = "Build complete",
            .detail = "All checks passed",
            .kind = NoticeKind::success,
            .side = NoticeSide::right,
            .created_at_unix_ms = 101'000,
            .progress = 1.0,
            .style = NoticeStyle::standard,
            .symbol_name = "checkmark.circle.fill",
        },
        IslandNotice{
            .id = "message-pair-left",
            .title = "Alice",
            .detail = "Messages",
            .kind = NoticeKind::info,
            .side = NoticeSide::left,
            .created_at_unix_ms = 102'000,
            .style = NoticeStyle::message,
            .app_name = "Messages",
            .app_bundle_identifier = "com.example.messages",
        },
    };
    repository.record_usage({
        .provider = AIProvider::gpt,
        .timestamp_unix_ms = 100'000,
        .input_tokens = 3,
        .output_tokens = 2,
    });

    repository.enqueue_notices(notices);

    const auto state = repository.load(false);
    expect(state.usage_samples.empty(),
        "task-only loads should continue to skip usage history");
    expect(state.notices == notices,
        "notices should load in insertion order with display fields intact");
}

void messageNotificationNormalizesAndPersistsItsNoticePair() {
    expect(MessageNotification::normalize_content("  hello\n\nworld   from   zisla  ")
            == "hello world from zisla",
        "message content should collapse surrounding whitespace");
    const auto truncated = MessageNotification::normalize_content(std::string(60, 'a'));
    expect(truncated == std::string(MessageNotification::maximum_content_length, 'a')
            + "\xE2\x80\xA6",
        "long message content should retain the limit and append an ellipsis");

    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const MessageNotification message{
        .app_name = "Messages",
        .sender = "Alice",
        .content = "See you at 7",
        .app_bundle_identifier = "com.example.messages",
        .created_at_unix_ms = 1'700'000'100'000,
        .pair_id = "pair-1",
    };
    const auto pair = message.make_notices();
    const std::vector notices{pair.first, pair.second};

    repository.enqueue_notices(notices);

    expect(repository.load(false).notices == notices,
        "message notification should persist its left and right notices together");
    expect(pair.first.id == "message-pair-1-left"
            && pair.first.side == NoticeSide::left
            && pair.first.title == "Alice"
            && pair.first.detail == "Messages"
            && pair.first.style == NoticeStyle::message,
        "message left notice should identify the sender and app");
    expect(pair.second.id == "message-pair-1-right"
            && pair.second.side == NoticeSide::right
            && pair.second.title == "See you at 7"
            && !pair.second.detail
            && pair.second.style == NoticeStyle::message
            && pair.first.created_at_unix_ms == pair.second.created_at_unix_ms,
        "message right notice should contain the body and share the timestamp");
}

void takingNoticesAtomicallyConsumesOnlyNoticeRows() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const AIProgressTask task{
        .id = "active-task",
        .provider = AIProvider::codex,
        .title = "Keep running",
        .updated_at_unix_ms = 100'000,
    };
    const AIUsageSample usage{
        .provider = AIProvider::gpt,
        .timestamp_unix_ms = 101'000,
        .input_tokens = 7,
        .output_tokens = 3,
    };
    const MessageNotification message{
        .app_name = "Messages",
        .sender = "Alice",
        .content = "Atomic pair",
        .created_at_unix_ms = 102'000,
        .pair_id = "atomic",
    };
    const auto pair = message.make_notices();
    const std::vector notices{pair.first, pair.second};
    repository.upsert(task);
    repository.record_usage(usage);
    repository.enqueue_notices(notices);

    expect(repository.take_notices() == notices,
        "take should return every notice in insertion order");
    expect(repository.take_notices().empty(),
        "a consumed notice must not be delivered a second time");
    const auto retained = repository.load();
    expect(retained.notices.empty(), "take should delete consumed notice rows");
    expect(retained.tasks == std::vector{task},
        "taking notices must preserve AI tasks");
    expect(retained.usage_samples == std::vector{usage},
        "taking notices must preserve usage samples");
}

void failedNoticeTakeRollsBackTheWholeBatch() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    repository.enqueue_notice({
        .id = "valid",
        .title = "Valid notice",
        .created_at_unix_ms = 103'000,
    });
    insertNoticePayload(repository.database_path(), "not-json");

    try {
        (void)repository.take_notices();
        throw std::runtime_error("invalid notice payload should fail the take");
    } catch (const AIStateRepositoryError& error) {
        expect(error.code() == AIStateRepositoryErrorCode::corrupted_state,
            "invalid notice data should report corrupted_state");
    }

    expect(noticeRowCount(repository.database_path()) == 2,
        "a failed take must leave the complete notice batch in storage");
}

void usageSourceIdsAreIdempotentWhileAnonymousSamplesAppend() {
    const TemporaryDirectory directory;
    const AIStateRepository repository(directory.path());
    const AIUsageSample original{
        .source_id = "codex:event:1",
        .provider = AIProvider::codex,
        .timestamp_unix_ms = 100'000,
        .input_tokens = 120,
        .output_tokens = 30,
        .cost_usd = 0.02,
        .model = "gpt-5.2-codex",
    };

    expect(repository.record_usage(original),
        "first source id should insert one usage row");
    expect(!repository.record_usage(original),
        "identical source id should be idempotent");

    auto corrected = original;
    corrected.input_tokens = 150;
    corrected.output_tokens = 50;
    expect(!repository.record_usage(corrected),
        "correcting an existing source id should update rather than insert");

    auto anonymous = corrected;
    anonymous.source_id.reset();
    anonymous.timestamp_unix_ms = 200'000;
    expect(repository.record_usage(anonymous),
        "first anonymous sample should append");
    expect(repository.record_usage(anonymous),
        "same anonymous sample should append again");

    const auto state = repository.load();
    expect(state.usage_samples == std::vector({corrected, anonymous, anonymous}),
        "source ids should occupy one row while anonymous usage remains append-only");
}

void usageCapacityKeepsNewestTimestampsAndSupportsTaskOnlyLoads() {
    const TemporaryDirectory directory;
    const std::vector samples = {
        AIUsageSample{
            .source_id = "newest",
            .provider = AIProvider::gpt,
            .timestamp_unix_ms = 300'000,
            .input_tokens = 30,
            .output_tokens = 3,
        },
        AIUsageSample{
            .source_id = "oldest",
            .provider = AIProvider::claude,
            .timestamp_unix_ms = 100'000,
            .input_tokens = 10,
            .output_tokens = 1,
        },
        AIUsageSample{
            .source_id = "middle",
            .provider = AIProvider::grok,
            .timestamp_unix_ms = 200'000,
            .input_tokens = 20,
            .output_tokens = 2,
        },
    };
    AIStateRepository(directory.path(), 3).record_usage(samples);

    const AIStateRepository compacted(directory.path(), 2);
    const auto task_only = compacted.load(false);
    expect(task_only.usage_samples.empty(),
        "task-only load should not materialize usage history");

    const auto retained = compacted.load().usage_samples;
    expect(retained == std::vector({samples[0], samples[2]}),
        "capacity should retain newest timestamps in original row order");

    expect(compacted.record_usage(samples[1]) == 1,
        "a previously trimmed source id may be scanned again");
    expect(compacted.load().usage_samples == retained,
        "rescanning a trimmed old sample must not evict newer history");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"corrupted database remains untouched", corruptedDatabaseIsReportedAndNeverOverwritten},
        {"Swift Codable task payload loads", repositoryLoadsSwiftCodableTaskPayload},
        {"upsert persists across repository instances", upsertPersistsAcrossRepositoryInstances},
        {"finish applies terminal state", finishAppliesTerminalStateAndReportsMissingTasks},
        {"remove reports task existence", removeReportsWhetherATaskExisted},
        {"clear preserves usage history", clearTasksPreservesUsageHistory},
        {"storage token tracks SQLite", storageChangeTokenIgnoresLegacyJsonAndTracksSqliteWrites},
        {"notices persist without usage", noticesPersistInOrderAndLoadWithoutUsageHistory},
        {"message notification persists a pair", messageNotificationNormalizesAndPersistsItsNoticePair},
        {"taking notices consumes only notice rows", takingNoticesAtomicallyConsumesOnlyNoticeRows},
        {"failed notice take rolls back", failedNoticeTakeRollsBackTheWholeBatch},
        {"usage source ids and anonymous samples", usageSourceIdsAreIdempotentWhileAnonymousSamplesAppend},
        {"usage capacity keeps newest timestamps", usageCapacityKeepsNewestTimestampsAndSupportsTaskOnlyLoads},
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
