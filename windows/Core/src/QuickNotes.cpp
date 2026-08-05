#include "zisla/core/QuickNotes.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cctype>
#include <limits>
#include <memory>
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

std::string_view trim_ascii(std::string_view value) noexcept {
    while (!value.empty()
        && std::isspace(static_cast<unsigned char>(value.front())) != 0) {
        value.remove_prefix(1);
    }
    while (!value.empty()
        && std::isspace(static_cast<unsigned char>(value.back())) != 0) {
        value.remove_suffix(1);
    }
    return value;
}

std::string ascii_lower(std::string_view value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), [](char character) {
        const auto byte = static_cast<unsigned char>(character);
        return byte < 0x80
            ? static_cast<char>(std::tolower(byte))
            : character;
    });
    return result;
}

class Statement {
public:
    Statement(sqlite3* connection, const char* sql) {
        if (sqlite3_prepare_v2(connection, sql, -1, &value_, nullptr) != SQLITE_OK) {
            throw QuickNoteRepositoryError(sqlite3_errmsg(connection));
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
    explicit Database(const QuickNoteRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw QuickNoteRepositoryError(error.message());
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
                : "Unable to open quick notes database";
            close();
            throw QuickNoteRepositoryError(message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw QuickNoteRepositoryError(sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS quick_notes ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "title TEXT NOT NULL,"
                "markdown TEXT NOT NULL,"
                "created_at_unix_ms INTEGER NOT NULL,"
                "modified_at_unix_ms INTEGER NOT NULL)");
            execute(
                "CREATE TABLE IF NOT EXISTS quick_notes_metadata ("
                "key TEXT PRIMARY KEY NOT NULL,"
                "value TEXT NOT NULL)");
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
            throw QuickNoteRepositoryError(
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
            value.empty() ? "" : value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw QuickNoteRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_id(sqlite3* connection, sqlite3_stmt* statement, int index, std::int64_t id) {
    if (sqlite3_bind_int64(statement, index, id) != SQLITE_OK) {
        throw QuickNoteRepositoryError(sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw QuickNoteRepositoryError(sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column) {
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw QuickNoteRepositoryError("Quick notes database contains invalid text");
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

QuickNote read_note(sqlite3_stmt* statement, std::size_t max_markdown_bytes) {
    QuickNote note{
        .id = sqlite3_column_int64(statement, 0),
        .title = column_text(statement, 1),
        .markdown = column_text(statement, 2),
        .created_at_unix_ms = sqlite3_column_int64(statement, 3),
        .modified_at_unix_ms = sqlite3_column_int64(statement, 4),
    };
    if (note.id <= 0 || note.markdown.size() > max_markdown_bytes) {
        throw QuickNoteRepositoryError("Quick notes database contains an invalid note");
    }
    return note;
}

std::int64_t insert_note(
    Database& database,
    std::string_view markdown,
    std::int64_t now_unix_ms) {
    Statement statement(
        database.get(),
        "INSERT INTO quick_notes("
        "title, markdown, created_at_unix_ms, modified_at_unix_ms) "
        "VALUES(?, ?, ?, ?)");
    const auto title = quick_note_title(markdown);
    bind_text(database.get(), statement.get(), 1, title);
    bind_text(database.get(), statement.get(), 2, markdown);
    bind_id(database.get(), statement.get(), 3, now_unix_ms);
    bind_id(database.get(), statement.get(), 4, now_unix_ms);
    step_done(database.get(), statement.get());
    return sqlite3_last_insert_rowid(database.get());
}

}  // namespace

std::string quick_note_title(std::string_view markdown) {
    while (!markdown.empty()) {
        const auto newline = markdown.find('\n');
        auto line = trim_ascii(markdown.substr(0, newline));
        if (!line.empty()) {
            std::size_t heading = 0;
            while (heading < line.size() && heading < 6 && line[heading] == '#') {
                ++heading;
            }
            if (heading > 0) {
                line.remove_prefix(heading);
                line = trim_ascii(line);
            }
            return line.empty() ? "新随记" : std::string(line);
        }
        if (newline == std::string_view::npos) {
            break;
        }
        markdown.remove_prefix(newline + 1);
    }
    return "新随记";
}

bool quick_note_matches(const QuickNote& note, std::string_view query) {
    if (query.empty()) {
        return true;
    }
    const auto normalized_query = ascii_lower(query);
    return ascii_lower(note.title).find(normalized_query) != std::string::npos
        || ascii_lower(note.markdown).find(normalized_query) != std::string::npos;
}

QuickNoteRepositoryError::QuickNoteRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

QuickNoteRepository::QuickNoteRepository(
    std::filesystem::path directory,
    std::size_t max_markdown_bytes)
    : directory_(std::move(directory)),
      max_markdown_bytes_(std::max<std::size_t>(1, max_markdown_bytes)) {}

const std::filesystem::path& QuickNoteRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path QuickNoteRepository::database_path() const {
    return directory_ / "quick-notes.sqlite";
}

std::size_t QuickNoteRepository::max_markdown_bytes() const noexcept {
    return max_markdown_bytes_;
}

std::vector<QuickNote> QuickNoteRepository::load() const {
    Database database(*this);
    Statement statement(
        database.get(),
        "SELECT id, title, markdown, created_at_unix_ms, modified_at_unix_ms "
        "FROM quick_notes ORDER BY modified_at_unix_ms DESC, id DESC");
    std::vector<QuickNote> notes;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw QuickNoteRepositoryError(sqlite3_errmsg(database.get()));
        }
        notes.push_back(read_note(statement.get(), max_markdown_bytes_));
    }
    return notes;
}

std::optional<QuickNote> QuickNoteRepository::find(std::int64_t id) const {
    if (id <= 0) {
        return std::nullopt;
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "SELECT id, title, markdown, created_at_unix_ms, modified_at_unix_ms "
        "FROM quick_notes WHERE id = ?");
    bind_id(database.get(), statement.get(), 1, id);
    const auto result = sqlite3_step(statement.get());
    if (result == SQLITE_DONE) {
        return std::nullopt;
    }
    if (result != SQLITE_ROW) {
        throw QuickNoteRepositoryError(sqlite3_errmsg(database.get()));
    }
    return read_note(statement.get(), max_markdown_bytes_);
}

std::vector<QuickNote> QuickNoteRepository::search(std::string_view query) const {
    auto notes = load();
    std::erase_if(notes, [query](const auto& note) {
        return !quick_note_matches(note, query);
    });
    return notes;
}

std::optional<std::int64_t> QuickNoteRepository::create(
    std::string markdown,
    std::int64_t now_unix_ms) const {
    if (!valid_markdown(markdown)) {
        return std::nullopt;
    }
    Database database(*this);
    return insert_note(database, markdown, now_unix_ms);
}

bool QuickNoteRepository::update(
    std::int64_t id,
    std::string markdown,
    std::int64_t now_unix_ms) const {
    if (id <= 0 || !valid_markdown(markdown)) {
        return false;
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "UPDATE quick_notes SET title = ?, markdown = ?, modified_at_unix_ms = ? "
        "WHERE id = ?");
    const auto title = quick_note_title(markdown);
    bind_text(database.get(), statement.get(), 1, title);
    bind_text(database.get(), statement.get(), 2, markdown);
    bind_id(database.get(), statement.get(), 3, now_unix_ms);
    bind_id(database.get(), statement.get(), 4, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

bool QuickNoteRepository::remove(std::int64_t id) const {
    if (id <= 0) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM quick_notes WHERE id = ?");
    bind_id(database.get(), statement.get(), 1, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

bool QuickNoteRepository::ensure_welcome_note(
    std::string markdown,
    std::int64_t now_unix_ms) const {
    if (!valid_markdown(markdown)) {
        return false;
    }
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement marker(
            database.get(),
            "INSERT OR IGNORE INTO quick_notes_metadata(key, value) "
            "VALUES('welcome_seeded', '1')");
        step_done(database.get(), marker.get());
        if (sqlite3_changes(database.get()) == 0) {
            database.execute("COMMIT");
            return false;
        }
        (void)insert_note(database, markdown, now_unix_ms);
        database.execute("COMMIT");
        return true;
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool QuickNoteRepository::valid_markdown(std::string_view markdown) const noexcept {
    return markdown.size() <= max_markdown_bytes_;
}

}  // namespace zisla::core
