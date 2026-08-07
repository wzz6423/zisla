#include "zisla/core/OpenCodeSessionScanner.hpp"

#include <sqlite3.h>

#include <atomic>
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
#include <system_error>
#include <utility>

namespace {

using namespace zisla::core;
namespace fs = std::filesystem;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        static std::atomic_uint64_t sequence{0};
        const auto timestamp = std::chrono::steady_clock::now()
                                   .time_since_epoch()
                                   .count();
        path_ = fs::temp_directory_path()
            / ("zisla-opencode-scanner-" + std::to_string(timestamp) + "-"
                + std::to_string(sequence.fetch_add(1)));
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

void execute(sqlite3* database, const char* sql) {
    char* error = nullptr;
    if (sqlite3_exec(database, sql, nullptr, nullptr, &error) != SQLITE_OK) {
        const std::string message = error ? error : "SQLite fixture failed";
        sqlite3_free(error);
        throw std::runtime_error(message);
    }
}

sqlite3* create_database(const fs::path& path, bool current_messages) {
    sqlite3* database = nullptr;
    const auto encoded = path.u8string();
    const std::string utf8_path{
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
    if (sqlite3_open(utf8_path.c_str(), &database) != SQLITE_OK) {
        sqlite3_close(database);
        throw std::runtime_error("unable to create OpenCode database fixture");
    }
    execute(
        database,
        "CREATE TABLE session ("
        "id TEXT PRIMARY KEY, title TEXT, time_updated INTEGER NOT NULL, "
        "time_archived INTEGER)");
    if (current_messages) {
        execute(
            database,
            "CREATE TABLE session_message ("
            "id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, "
            "seq INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL)");
    } else {
        execute(
            database,
            "CREATE TABLE message ("
            "id TEXT PRIMARY KEY, session_id TEXT NOT NULL, "
            "time_updated INTEGER NOT NULL, data TEXT NOT NULL)");
    }
    return database;
}

void insert_session(
    sqlite3* database,
    std::string_view id,
    std::string_view title,
    std::int64_t updated_at,
    bool archived = false) {
    sqlite3_stmt* statement = nullptr;
    const auto sql = "INSERT INTO session (id, title, time_updated, time_archived) VALUES (?, ?, ?, ?)";
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) != SQLITE_OK) {
        throw std::runtime_error("unable to prepare session insert");
    }
    sqlite3_bind_text(statement, 1, id.data(), static_cast<int>(id.size()), SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, title.data(), static_cast<int>(title.size()), SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement, 3, updated_at);
    if (archived) {
        sqlite3_bind_int64(statement, 4, updated_at);
    } else {
        sqlite3_bind_null(statement, 4);
    }
    if (sqlite3_step(statement) != SQLITE_DONE) {
        sqlite3_finalize(statement);
        throw std::runtime_error("unable to insert session fixture");
    }
    sqlite3_finalize(statement);
}

void insert_message(
    sqlite3* database,
    bool current_messages,
    std::string_view id,
    std::string_view session_id,
    std::string_view type,
    std::int64_t updated_at,
    std::string_view data) {
    const auto sql = current_messages
        ? "INSERT INTO session_message (id, session_id, type, seq, time_updated, data) VALUES (?, ?, ?, 1, ?, ?)"
        : "INSERT INTO message (id, session_id, time_updated, data) VALUES (?, ?, ?, ?)";
    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) != SQLITE_OK) {
        throw std::runtime_error("unable to prepare message insert");
    }
    sqlite3_bind_text(statement, 1, id.data(), static_cast<int>(id.size()), SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, session_id.data(), static_cast<int>(session_id.size()), SQLITE_TRANSIENT);
    int column = 3;
    if (current_messages) {
        sqlite3_bind_text(statement, column++, type.data(), static_cast<int>(type.size()), SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(statement, column++, updated_at);
    sqlite3_bind_text(statement, column, data.data(), static_cast<int>(data.size()), SQLITE_TRANSIENT);
    if (sqlite3_step(statement) != SQLITE_DONE) {
        sqlite3_finalize(statement);
        throw std::runtime_error("unable to insert message fixture");
    }
    sqlite3_finalize(statement);
}

OpenCodeSessionScanOptions options_for(
    const fs::path& database,
    std::int64_t now) {
    return {
        .database_paths = {database},
        .data_roots = {},
        .max_sessions = 10,
        .recency_threshold_ms = 60 * 60 * 1'000,
        .now_unix_ms = now,
    };
}

void scans_legacy_sqlite_user_and_unfinished_assistant_messages() {
    TemporaryDirectory temporary;
    const auto database_path = temporary.path() / "opencode.db";
    constexpr std::int64_t now = 1'785'027'700'000LL;
    sqlite3* database = create_database(database_path, false);
    insert_session(database, "legacy-user", "Legacy user", now - 1'000);
    insert_message(
        database,
        false,
        "msg-user",
        "legacy-user",
        "",
        now - 1'000,
        R"({"role":"user","time":{"created":1785027699000}})");
    insert_session(database, "legacy-assistant", "Generating", now - 2'000);
    insert_message(
        database,
        false,
        "msg-assistant",
        "legacy-assistant",
        "",
        now - 2'000,
        R"({"role":"assistant","modelID":"model-a","time":{"created":1785027698000}})");
    insert_session(database, "legacy-done", "Done", now - 3'000);
    insert_message(
        database,
        false,
        "msg-done",
        "legacy-done",
        "",
        now - 3'000,
        R"({"role":"assistant","finish":"stop","time":{"completed":1785027697000}})");
    sqlite3_close(database);

    const OpenCodeSessionScanner scanner(options_for(database_path, now));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 2, "legacy database should omit completed assistants");
    expect(tasks.front().id == "opencode-session-legacy-user",
        "latest user session should be first");
    expect(tasks.back().detail == "model-a",
        "assistant model metadata should be retained");
}

void scans_current_event_table_and_archived_sessions() {
    TemporaryDirectory temporary;
    const auto database_path = temporary.path() / "opencode-current.db";
    constexpr std::int64_t now = 1'785'027'700'000LL;
    sqlite3* database = create_database(database_path, true);
    insert_session(database, "tool-running", "Tool", now - 1'000);
    insert_message(
        database,
        true,
        "event-tool",
        "tool-running",
        "tool",
        now - 1'000,
        R"({"status":"running"})");
    insert_session(database, "tool-error", "Tool error", now - 2'000);
    insert_message(
        database,
        true,
        "event-error",
        "tool-error",
        "tool",
        now - 2'000,
        R"({"status":"error"})");
    insert_session(database, "archived", "Archived", now - 3'000, true);
    insert_message(
        database,
        true,
        "event-archived",
        "archived",
        "user",
        now - 3'000,
        R"({"role":"user"})");
    sqlite3_close(database);

    const OpenCodeSessionScanner scanner(options_for(database_path, now));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 2, "current event table should omit archived sessions");
    expect(tasks.front().status == AIProgressStatus::running,
        "running tool should be active");
    expect(tasks.back().status == AIProgressStatus::error,
        "errored tool should surface an error");
}

void falls_back_to_bounded_storage_json_when_no_database_exists() {
    TemporaryDirectory temporary;
    constexpr std::int64_t now = 1'785'027'700'000LL;
    const auto session = temporary.path()
        / "storage" / "session" / "project-1" / "storage-session.json";
    const auto message = temporary.path()
        / "storage" / "message" / "storage-session" / "message-1.json";
    fs::create_directories(session.parent_path());
    fs::create_directories(message.parent_path());
    {
        std::ofstream stream(session, std::ios::binary | std::ios::trunc);
        stream << R"({"id":"storage-session","title":"Storage session","time":{"updated":1785027699000}})";
    }
    {
        std::ofstream stream(message, std::ios::binary | std::ios::trunc);
        stream << R"({"sessionID":"storage-session","role":"assistant","modelID":"storage-model","time":{"updated":1785027699500}})";
    }

    const OpenCodeSessionScanner scanner({
        .database_paths = {temporary.path() / "missing.db"},
        .data_roots = {temporary.path()},
        .max_sessions = 10,
        .max_storage_files = 8,
        .recency_threshold_ms = 60 * 60 * 1'000,
        .now_unix_ms = now,
    });
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1, "JSON storage should be a legacy fallback");
    expect(tasks.front().id == "opencode-session-storage-session",
        "storage session ID should be retained");
    expect(tasks.front().detail == "storage-model",
        "storage model metadata should be retained");
}

void handles_missing_and_oversized_storage_files() {
    TemporaryDirectory temporary;
    const auto session = temporary.path()
        / "storage" / "session" / "project-1" / "too-large.json";
    fs::create_directories(session.parent_path());
    {
        std::ofstream stream(session, std::ios::binary | std::ios::trunc);
        stream << std::string(1'024, 'x');
    }
    const OpenCodeSessionScanner scanner({
        .database_paths = {},
        .data_roots = {temporary.path(), temporary.path() / "missing"},
        .max_storage_files = 8,
        .maximum_json_bytes = 128,
        .now_unix_ms = 1'785'027'700'000LL,
    });
    expect(scanner.active_tasks().empty(),
        "missing or oversized storage data should be ignored");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"legacy SQLite", scans_legacy_sqlite_user_and_unfinished_assistant_messages},
        {"current SQLite", scans_current_event_table_and_archived_sessions},
        {"storage fallback", falls_back_to_bounded_storage_json_when_no_database_exists},
        {"missing and oversized", handles_missing_and_oversized_storage_files},
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
