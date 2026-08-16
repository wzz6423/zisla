#include "zisla/core/FileShelfRepository.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <limits>
#include <memory>
#include <optional>
#include <string_view>
#include <utility>

namespace zisla::core {
namespace {

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

std::filesystem::path path_from_utf8(std::string_view value) {
    const std::u8string encoded(
        reinterpret_cast<const char8_t*>(value.data()),
        value.size());
    return std::filesystem::path(encoded);
}

std::optional<std::filesystem::path> normalized_path(
    const std::filesystem::path& path,
    bool must_exist) noexcept {
    if (path.empty()) {
        return std::nullopt;
    }

    std::error_code error;
    const bool exists = std::filesystem::exists(path, error);
    if (error || (must_exist && !exists)) {
        return std::nullopt;
    }

    if (exists) {
        auto canonical = std::filesystem::weakly_canonical(path, error);
        if (!error) {
            return canonical.lexically_normal();
        }
        error.clear();
    }

    auto absolute = std::filesystem::absolute(path, error);
    if (error) {
        return std::nullopt;
    }
    return absolute.lexically_normal();
}

class Statement {
public:
    Statement(sqlite3* connection, const char* sql) {
        if (sqlite3_prepare_v2(connection, sql, -1, &value_, nullptr) != SQLITE_OK) {
            throw FileShelfRepositoryError(sqlite3_errmsg(connection));
        }
    }

    ~Statement() {
        sqlite3_finalize(value_);
    }

    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    [[nodiscard]] sqlite3_stmt* get() const noexcept {
        return value_;
    }

private:
    sqlite3_stmt* value_{nullptr};
};

class Database {
public:
    explicit Database(const FileShelfRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw FileShelfRepositoryError(error.message());
        }

        const auto path = path_as_utf8(repository.database_path());
        const auto result = sqlite3_open_v2(
            path.c_str(),
            &connection_,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr);
        if (result != SQLITE_OK || !connection_) {
            const std::string message = connection_
                ? sqlite3_errmsg(connection_)
                : "Unable to open file shelf database";
            close();
            throw FileShelfRepositoryError(message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw FileShelfRepositoryError(sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS file_shelf_items ("
                "position INTEGER PRIMARY KEY AUTOINCREMENT,"
                "path TEXT UNIQUE COLLATE NOCASE NOT NULL,"
                "added_at_unix_ms INTEGER NOT NULL)");
        } catch (...) {
            close();
            throw;
        }
    }

    ~Database() {
        close();
    }

    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    void execute(const char* sql) {
        char* raw_error = nullptr;
        const auto result = sqlite3_exec(connection_, sql, nullptr, nullptr, &raw_error);
        const std::unique_ptr<char, decltype(&sqlite3_free)> error(raw_error, sqlite3_free);
        if (result != SQLITE_OK) {
            throw FileShelfRepositoryError(
                error ? error.get() : sqlite3_errmsg(connection_));
        }
    }

    void rollback() noexcept {
        (void)sqlite3_exec(connection_, "ROLLBACK", nullptr, nullptr, nullptr);
    }

    [[nodiscard]] sqlite3* get() const noexcept {
        return connection_;
    }

private:
    void close() noexcept {
        if (connection_) {
            sqlite3_close_v2(connection_);
            connection_ = nullptr;
        }
    }

    sqlite3* connection_{nullptr};
};

void bind_text(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::string_view value) {
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || sqlite3_bind_text(
            statement,
            index,
            value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw FileShelfRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_capacity(
    sqlite3* connection,
    sqlite3_stmt* statement,
    std::size_t capacity) {
    if (capacity > static_cast<std::size_t>(std::numeric_limits<sqlite3_int64>::max())
        || sqlite3_bind_int64(
            statement,
            1,
            static_cast<sqlite3_int64>(capacity)) != SQLITE_OK) {
        throw FileShelfRepositoryError(sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw FileShelfRepositoryError(sqlite3_errmsg(connection));
    }
}

void reset_statement(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_reset(statement) != SQLITE_OK
        || sqlite3_clear_bindings(statement) != SQLITE_OK) {
        throw FileShelfRepositoryError(sqlite3_errmsg(connection));
    }
}

void trim_to_capacity(Database& database, std::size_t capacity) {
    Statement statement(
        database.get(),
        "DELETE FROM file_shelf_items WHERE position NOT IN ("
        "SELECT position FROM file_shelf_items ORDER BY position DESC LIMIT ?)");
    bind_capacity(database.get(), statement.get(), capacity);
    step_done(database.get(), statement.get());
}

std::string column_text(sqlite3_stmt* statement, int column) {
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw FileShelfRepositoryError("File shelf database contains an invalid path");
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

}  // namespace

FileShelfRepositoryError::FileShelfRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

FileShelfRepository::FileShelfRepository(
    std::filesystem::path directory,
    std::size_t capacity)
    : directory_(std::move(directory)),
      capacity_(std::max<std::size_t>(1, capacity)) {}

const std::filesystem::path& FileShelfRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path FileShelfRepository::database_path() const {
    return directory_ / "file-shelf.sqlite";
}

std::size_t FileShelfRepository::capacity() const noexcept {
    return capacity_;
}

std::vector<FileShelfItem> FileShelfRepository::load() const {
    Database database(*this);
    trim_to_capacity(database, capacity_);

    Statement statement(
        database.get(),
        "SELECT position, path, added_at_unix_ms "
        "FROM file_shelf_items ORDER BY position");
    std::vector<FileShelfItem> items;
    std::vector<sqlite3_int64> stale_positions;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw FileShelfRepositoryError(sqlite3_errmsg(database.get()));
        }

        const auto position = sqlite3_column_int64(statement.get(), 0);
        std::optional<std::filesystem::path> path;
        try {
            path = normalized_path(path_from_utf8(column_text(statement.get(), 1)), true);
        } catch (...) {
            path.reset();
        }
        if (!path) {
            stale_positions.push_back(position);
            continue;
        }
        items.push_back({
            .path = std::move(*path),
            .added_at_unix_ms = sqlite3_column_int64(statement.get(), 2),
        });
    }

    if (!stale_positions.empty()) {
        database.execute("BEGIN IMMEDIATE");
        try {
            Statement remove(database.get(),
                "DELETE FROM file_shelf_items WHERE position = ?");
            for (const auto position : stale_positions) {
                if (sqlite3_bind_int64(remove.get(), 1, position) != SQLITE_OK) {
                    throw FileShelfRepositoryError(sqlite3_errmsg(database.get()));
                }
                step_done(database.get(), remove.get());
                reset_statement(database.get(), remove.get());
            }
            database.execute("COMMIT");
        } catch (...) {
            database.rollback();
            throw;
        }
    }
    return items;
}

std::size_t FileShelfRepository::add(
    std::span<const std::filesystem::path> paths,
    std::int64_t added_at_unix_ms) const {
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement insert(
            database.get(),
            "INSERT OR IGNORE INTO file_shelf_items(path, added_at_unix_ms) "
            "VALUES(?, ?)");
        std::size_t added = 0;
        for (const auto& candidate : paths) {
            const auto path = normalized_path(candidate, true);
            if (!path) {
                continue;
            }
            const auto encoded = path_as_utf8(*path);
            bind_text(database.get(), insert.get(), 1, encoded);
            if (sqlite3_bind_int64(insert.get(), 2, added_at_unix_ms) != SQLITE_OK) {
                throw FileShelfRepositoryError(sqlite3_errmsg(database.get()));
            }
            step_done(database.get(), insert.get());
            added += sqlite3_changes(database.get()) > 0 ? 1 : 0;
            reset_statement(database.get(), insert.get());
        }
        trim_to_capacity(database, capacity_);
        database.execute("COMMIT");
        return added;
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool FileShelfRepository::remove(const std::filesystem::path& path) const {
    const auto normalized = normalized_path(path, false);
    if (!normalized) {
        return false;
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "DELETE FROM file_shelf_items WHERE path = ? COLLATE NOCASE");
    const auto encoded = path_as_utf8(*normalized);
    bind_text(database.get(), statement.get(), 1, encoded);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

void FileShelfRepository::clear() const {
    Database database(*this);
    database.execute("DELETE FROM file_shelf_items");
}

}  // namespace zisla::core
