#include "zisla/core/ClipboardHistory.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cctype>
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

std::optional<std::filesystem::path> normalized_existing_path(
    const std::filesystem::path& path) noexcept {
    if (path.empty()) {
        return std::nullopt;
    }
    std::error_code error;
    if (!std::filesystem::exists(path, error) || error) {
        return std::nullopt;
    }
    auto canonical = std::filesystem::weakly_canonical(path, error);
    if (!error) {
        return canonical.lexically_normal();
    }
    error.clear();
    auto absolute = std::filesystem::absolute(path, error);
    if (error) {
        return std::nullopt;
    }
    return absolute.lexically_normal();
}

bool blank(std::string_view value) noexcept {
    return value.empty() || std::all_of(value.begin(), value.end(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    });
}

std::string default_display_name(const std::filesystem::path& path) {
    return path_as_utf8(path.filename());
}

std::optional<ClipboardHistoryContent> normalized_content(
    ClipboardHistoryContent content,
    std::size_t max_image_bytes) noexcept {
    try {
        switch (content.kind) {
        case ClipboardContentKind::text:
            if (blank(content.text)) {
                return std::nullopt;
            }
            content.image.clear();
            content.file_path.clear();
            content.file_display_name.clear();
            return content;
        case ClipboardContentKind::image:
            if (content.image.empty() || content.image.size() > max_image_bytes) {
                return std::nullopt;
            }
            content.text.clear();
            content.file_path.clear();
            content.file_display_name.clear();
            return content;
        case ClipboardContentKind::file: {
            const auto path = normalized_existing_path(content.file_path);
            if (!path) {
                return std::nullopt;
            }
            content.text.clear();
            content.image.clear();
            content.file_path = *path;
            if (content.file_display_name.empty()) {
                content.file_display_name = default_display_name(*path);
            }
            if (content.file_display_name.empty()) {
                return std::nullopt;
            }
            return content;
        }
        }
    } catch (...) {
    }
    return std::nullopt;
}

class Statement {
public:
    Statement(sqlite3* connection, const char* sql) {
        if (sqlite3_prepare_v2(connection, sql, -1, &value_, nullptr) != SQLITE_OK) {
            throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection));
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
    explicit Database(const std::filesystem::path& path) {
        std::error_code error;
        std::filesystem::create_directories(path.parent_path(), error);
        if (error) {
            throw ClipboardHistoryRepositoryError(error.message());
        }

        const auto encoded = path_as_utf8(path);
        const auto result = sqlite3_open_v2(
            encoded.c_str(),
            &connection_,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr);
        if (result != SQLITE_OK || !connection_) {
            const std::string message = connection_
                ? sqlite3_errmsg(connection_)
                : "Unable to open clipboard history database";
            close();
            throw ClipboardHistoryRepositoryError(message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS clipboard_history_items ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "content_type INTEGER NOT NULL,"
                "text_value TEXT,"
                "image_data BLOB,"
                "file_path TEXT,"
                "file_display_name TEXT,"
                "last_copied_at_unix_ms INTEGER NOT NULL,"
                "is_pinned INTEGER NOT NULL)");
            execute(
                "CREATE INDEX IF NOT EXISTS clipboard_history_order "
                "ON clipboard_history_items(is_pinned DESC, last_copied_at_unix_ms DESC)");
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
            throw ClipboardHistoryRepositoryError(
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
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_blob(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::span<const std::uint8_t> value) {
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || sqlite3_bind_blob(
            statement,
            index,
            value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_int64(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::int64_t value) {
    if (sqlite3_bind_int64(statement, index, value) != SQLITE_OK) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column) {
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw ClipboardHistoryRepositoryError("Clipboard history contains invalid text");
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

std::vector<std::uint8_t> column_blob(sqlite3_stmt* statement, int column) {
    const auto* value = static_cast<const std::uint8_t*>(
        sqlite3_column_blob(statement, column));
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size <= 0) {
        return {};
    }
    return {value, value + size};
}

void trim_to_capacity(Database& database, std::size_t capacity) {
    Statement statement(
        database.get(),
        "DELETE FROM clipboard_history_items "
        "WHERE is_pinned = 0 AND id NOT IN ("
        "SELECT id FROM clipboard_history_items WHERE is_pinned = 0 "
        "ORDER BY last_copied_at_unix_ms DESC, id DESC LIMIT ?)");
    if (capacity > static_cast<std::size_t>(std::numeric_limits<sqlite3_int64>::max())) {
        throw ClipboardHistoryRepositoryError("Clipboard history capacity is too large");
    }
    bind_int64(
        database.get(),
        statement.get(),
        1,
        static_cast<std::int64_t>(capacity));
    step_done(database.get(), statement.get());
}

std::optional<std::int64_t> existing_id(
    Database& database,
    const ClipboardHistoryContent& content) {
    const char* sql = nullptr;
    switch (content.kind) {
    case ClipboardContentKind::text:
        sql = "SELECT id FROM clipboard_history_items "
              "WHERE content_type = 0 AND text_value = ? LIMIT 1";
        break;
    case ClipboardContentKind::image:
        sql = "SELECT id FROM clipboard_history_items "
              "WHERE content_type = 1 AND image_data = ? LIMIT 1";
        break;
    case ClipboardContentKind::file:
        sql = "SELECT id FROM clipboard_history_items "
              "WHERE content_type = 2 AND file_path = ? COLLATE NOCASE LIMIT 1";
        break;
    }

    Statement statement(database.get(), sql);
    switch (content.kind) {
    case ClipboardContentKind::text:
        bind_text(database.get(), statement.get(), 1, content.text);
        break;
    case ClipboardContentKind::image:
        bind_blob(database.get(), statement.get(), 1, content.image);
        break;
    case ClipboardContentKind::file:
        bind_text(database.get(), statement.get(), 1, path_as_utf8(content.file_path));
        break;
    }
    const auto result = sqlite3_step(statement.get());
    if (result == SQLITE_DONE) {
        return std::nullopt;
    }
    if (result != SQLITE_ROW) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
    }
    return sqlite3_column_int64(statement.get(), 0);
}

void insert_content(
    Database& database,
    const ClipboardHistoryContent& content,
    std::int64_t copied_at_unix_ms,
    bool pinned) {
    Statement statement(
        database.get(),
        "INSERT INTO clipboard_history_items("
        "content_type, text_value, image_data, file_path, file_display_name, "
        "last_copied_at_unix_ms, is_pinned) VALUES(?, ?, ?, ?, ?, ?, ?)");
    if (sqlite3_bind_int(statement.get(), 1, static_cast<int>(content.kind)) != SQLITE_OK) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
    }
    switch (content.kind) {
    case ClipboardContentKind::text:
        bind_text(database.get(), statement.get(), 2, content.text);
        (void)sqlite3_bind_null(statement.get(), 3);
        (void)sqlite3_bind_null(statement.get(), 4);
        (void)sqlite3_bind_null(statement.get(), 5);
        break;
    case ClipboardContentKind::image:
        (void)sqlite3_bind_null(statement.get(), 2);
        bind_blob(database.get(), statement.get(), 3, content.image);
        (void)sqlite3_bind_null(statement.get(), 4);
        (void)sqlite3_bind_null(statement.get(), 5);
        break;
    case ClipboardContentKind::file:
        (void)sqlite3_bind_null(statement.get(), 2);
        (void)sqlite3_bind_null(statement.get(), 3);
        bind_text(database.get(), statement.get(), 4, path_as_utf8(content.file_path));
        bind_text(database.get(), statement.get(), 5, content.file_display_name);
        break;
    }
    bind_int64(database.get(), statement.get(), 6, copied_at_unix_ms);
    if (sqlite3_bind_int(statement.get(), 7, pinned ? 1 : 0) != SQLITE_OK) {
        throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
    }
    step_done(database.get(), statement.get());
}

bool database_exists(const std::filesystem::path& path) {
    std::error_code error;
    const bool exists = std::filesystem::exists(path, error);
    if (error) {
        throw ClipboardHistoryRepositoryError(error.message());
    }
    return exists;
}

std::string lower_ascii(std::string_view value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), [](char character) {
        const auto byte = static_cast<unsigned char>(character);
        return byte < 0x80
            ? static_cast<char>(std::tolower(byte))
            : character;
    });
    return result;
}

}  // namespace

ClipboardHistoryContent ClipboardHistoryContent::make_text(std::string value) {
    return {
        .kind = ClipboardContentKind::text,
        .text = std::move(value),
    };
}

ClipboardHistoryContent ClipboardHistoryContent::make_image(
    std::vector<std::uint8_t> value) {
    return {
        .kind = ClipboardContentKind::image,
        .image = std::move(value),
    };
}

ClipboardHistoryContent ClipboardHistoryContent::make_file(
    std::filesystem::path path,
    std::string display_name) {
    return {
        .kind = ClipboardContentKind::file,
        .file_path = std::move(path),
        .file_display_name = std::move(display_name),
    };
}

ClipboardHistoryRepositoryError::ClipboardHistoryRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

ClipboardHistoryRepository::ClipboardHistoryRepository(
    std::filesystem::path directory,
    std::size_t capacity,
    std::size_t max_image_bytes)
    : directory_(std::move(directory)),
      capacity_(std::max<std::size_t>(1, capacity)),
      max_image_bytes_(std::max<std::size_t>(1, max_image_bytes)) {}

const std::filesystem::path& ClipboardHistoryRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path ClipboardHistoryRepository::database_path() const {
    return directory_ / "clipboard-history.sqlite";
}

std::size_t ClipboardHistoryRepository::capacity() const noexcept {
    return capacity_;
}

std::size_t ClipboardHistoryRepository::max_image_bytes() const noexcept {
    return max_image_bytes_;
}

std::vector<ClipboardHistoryItem> ClipboardHistoryRepository::load() const {
    if (!database_exists(database_path())) {
        return {};
    }
    Database database(database_path());
    trim_to_capacity(database, capacity_);

    std::vector<ClipboardHistoryItem> items;
    std::vector<std::int64_t> stale_ids;
    {
        Statement statement(
            database.get(),
            "SELECT id, content_type, text_value, image_data, file_path, "
            "file_display_name, last_copied_at_unix_ms, is_pinned "
            "FROM clipboard_history_items "
            "ORDER BY is_pinned DESC, last_copied_at_unix_ms DESC, id DESC");
        while (true) {
            const auto result = sqlite3_step(statement.get());
            if (result == SQLITE_DONE) {
                break;
            }
            if (result != SQLITE_ROW) {
                throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
            }

            const auto id = sqlite3_column_int64(statement.get(), 0);
            ClipboardHistoryContent content;
            try {
                switch (sqlite3_column_int(statement.get(), 1)) {
                case 0:
                    content = ClipboardHistoryContent::make_text(column_text(statement.get(), 2));
                    break;
                case 1:
                    content = ClipboardHistoryContent::make_image(column_blob(statement.get(), 3));
                    break;
                case 2:
                    content = ClipboardHistoryContent::make_file(
                        path_from_utf8(column_text(statement.get(), 4)),
                        column_text(statement.get(), 5));
                    break;
                default:
                    stale_ids.push_back(id);
                    continue;
                }
            } catch (...) {
                stale_ids.push_back(id);
                continue;
            }
            const auto normalized = normalized_content(std::move(content), max_image_bytes_);
            if (!normalized) {
                stale_ids.push_back(id);
                continue;
            }
            items.push_back({
                .id = id,
                .content = std::move(*normalized),
                .last_copied_at_unix_ms = sqlite3_column_int64(statement.get(), 6),
                .pinned = sqlite3_column_int(statement.get(), 7) != 0,
            });
        }
    }

    if (!stale_ids.empty()) {
        database.execute("BEGIN IMMEDIATE");
        try {
            Statement remove(database.get(), "DELETE FROM clipboard_history_items WHERE id = ?");
            for (const auto id : stale_ids) {
                bind_int64(database.get(), remove.get(), 1, id);
                step_done(database.get(), remove.get());
                if (sqlite3_reset(remove.get()) != SQLITE_OK
                    || sqlite3_clear_bindings(remove.get()) != SQLITE_OK) {
                    throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
                }
            }
            database.execute("COMMIT");
        } catch (...) {
            database.rollback();
            throw;
        }
    }
    return items;
}

bool ClipboardHistoryRepository::record(
    ClipboardHistoryContent content,
    std::int64_t copied_at_unix_ms,
    bool pinned) const {
    const auto normalized = normalized_content(std::move(content), max_image_bytes_);
    if (!normalized) {
        return false;
    }

    Database database(database_path());
    database.execute("BEGIN IMMEDIATE");
    try {
        if (const auto id = existing_id(database, *normalized)) {
            Statement update(
                database.get(),
                "UPDATE clipboard_history_items SET last_copied_at_unix_ms = ?, "
                "is_pinned = CASE WHEN ? <> 0 THEN 1 ELSE is_pinned END WHERE id = ?");
            bind_int64(database.get(), update.get(), 1, copied_at_unix_ms);
            if (sqlite3_bind_int(update.get(), 2, pinned ? 1 : 0) != SQLITE_OK) {
                throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
            }
            bind_int64(database.get(), update.get(), 3, *id);
            step_done(database.get(), update.get());
        } else {
            insert_content(database, *normalized, copied_at_unix_ms, pinned);
        }
        trim_to_capacity(database, capacity_);
        database.execute("COMMIT");
        return true;
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool ClipboardHistoryRepository::set_pinned(
    std::int64_t id,
    bool pinned,
    std::int64_t copied_at_unix_ms) const {
    if (!database_exists(database_path())) {
        return false;
    }
    Database database(database_path());
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement statement(
            database.get(),
            "UPDATE clipboard_history_items SET is_pinned = ?, "
            "last_copied_at_unix_ms = ? WHERE id = ?");
        if (sqlite3_bind_int(statement.get(), 1, pinned ? 1 : 0) != SQLITE_OK) {
            throw ClipboardHistoryRepositoryError(sqlite3_errmsg(database.get()));
        }
        bind_int64(database.get(), statement.get(), 2, copied_at_unix_ms);
        bind_int64(database.get(), statement.get(), 3, id);
        step_done(database.get(), statement.get());
        const bool changed = sqlite3_changes(database.get()) > 0;
        trim_to_capacity(database, capacity_);
        database.execute("COMMIT");
        return changed;
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool ClipboardHistoryRepository::remove(std::int64_t id) const {
    if (!database_exists(database_path())) {
        return false;
    }
    Database database(database_path());
    Statement statement(database.get(), "DELETE FROM clipboard_history_items WHERE id = ?");
    bind_int64(database.get(), statement.get(), 1, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

void ClipboardHistoryRepository::clear_history() const {
    if (!database_exists(database_path())) {
        return;
    }
    Database database(database_path());
    database.execute("DELETE FROM clipboard_history_items WHERE is_pinned = 0");
}

void ClipboardHistoryRepository::clear_all() const {
    if (!database_exists(database_path())) {
        return;
    }
    Database database(database_path());
    database.execute("DELETE FROM clipboard_history_items");
}

bool clipboard_history_matches(
    const ClipboardHistoryItem& item,
    ClipboardHistoryFilter filter,
    std::string_view query) {
    if ((filter == ClipboardHistoryFilter::pinned && !item.pinned)
        || (filter == ClipboardHistoryFilter::history && item.pinned)) {
        return false;
    }

    const auto normalized_query = lower_ascii(query);
    if (normalized_query.empty()) {
        return true;
    }

    std::string_view searchable;
    switch (item.content.kind) {
    case ClipboardContentKind::text:
        searchable = item.content.text;
        break;
    case ClipboardContentKind::file:
        searchable = item.content.file_display_name;
        break;
    case ClipboardContentKind::image:
        return false;
    }
    return lower_ascii(searchable).find(normalized_query) != std::string::npos;
}

std::vector<ClipboardHistoryItem> filter_clipboard_history(
    std::span<const ClipboardHistoryItem> items,
    ClipboardHistoryFilter filter,
    std::string_view query) {
    std::vector<ClipboardHistoryItem> result;
    for (const auto& item : items) {
        if (clipboard_history_matches(item, filter, query)) {
            result.push_back(item);
        }
    }
    return result;
}

}  // namespace zisla::core
