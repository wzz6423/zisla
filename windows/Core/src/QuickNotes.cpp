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

bool is_ascii_whitespace(char character) noexcept {
    return character == ' ' || character == '\t';
}

void append_markdown_inline(
    std::vector<QuickNoteMarkdownInline>& result,
    QuickNoteMarkdownInlineKind kind,
    std::string_view text,
    std::string_view link = {}) {
    if (text.empty()) {
        return;
    }
    if (kind == QuickNoteMarkdownInlineKind::text && !result.empty()
        && result.back().kind == QuickNoteMarkdownInlineKind::text) {
        result.back().text.append(text);
        return;
    }
    result.push_back({
        .kind = kind,
        .text = std::string(text),
        .link = std::string(link),
    });
}

std::vector<QuickNoteMarkdownInline> parse_markdown_inlines(std::string_view text) {
    std::vector<QuickNoteMarkdownInline> result;
    std::size_t cursor = 0;
    std::size_t plain_start = 0;
    const auto flush_plain = [&] {
        append_markdown_inline(
            result,
            QuickNoteMarkdownInlineKind::text,
            text.substr(plain_start, cursor - plain_start));
    };

    while (cursor < text.size()) {
        if (text[cursor] == '[') {
            const auto close_label = text.find(']', cursor + 1);
            if (close_label != std::string_view::npos
                && close_label + 1 < text.size()
                && text[close_label + 1] == '(') {
                const auto close_link = text.find(')', close_label + 2);
                if (close_link != std::string_view::npos && close_label > cursor + 1
                    && close_link > close_label + 2) {
                    flush_plain();
                    append_markdown_inline(
                        result,
                        QuickNoteMarkdownInlineKind::link,
                        text.substr(cursor + 1, close_label - cursor - 1),
                        text.substr(close_label + 2, close_link - close_label - 2));
                    cursor = close_link + 1;
                    plain_start = cursor;
                    continue;
                }
            }
        }

        const auto consume_delimited = [&](std::string_view marker,
                                           QuickNoteMarkdownInlineKind kind) {
            if (!text.substr(cursor).starts_with(marker)) {
                return false;
            }
            const auto close = text.find(marker, cursor + marker.size());
            if (close == std::string_view::npos || close == cursor + marker.size()) {
                return false;
            }
            flush_plain();
            append_markdown_inline(
                result,
                kind,
                text.substr(cursor + marker.size(), close - cursor - marker.size()));
            cursor = close + marker.size();
            plain_start = cursor;
            return true;
        };

        if (consume_delimited("`", QuickNoteMarkdownInlineKind::code)
            || consume_delimited("**", QuickNoteMarkdownInlineKind::strong)
            || consume_delimited("__", QuickNoteMarkdownInlineKind::strong)
            || consume_delimited("~~", QuickNoteMarkdownInlineKind::strikethrough)
            || consume_delimited("*", QuickNoteMarkdownInlineKind::emphasis)
            || consume_delimited("_", QuickNoteMarkdownInlineKind::emphasis)) {
            continue;
        }

        ++cursor;
    }
    flush_plain();
    return result;
}

bool is_thematic_break(std::string_view line) noexcept {
    char marker = '\0';
    std::size_t count = 0;
    for (const char character : line) {
        if (is_ascii_whitespace(character)) {
            continue;
        }
        if ((character != '-' && character != '*' && character != '_')
            || (marker != '\0' && marker != character)) {
            return false;
        }
        marker = character;
        ++count;
    }
    return marker != '\0' && count >= 3;
}

bool ordered_list_content_start(std::string_view line, std::size_t& start) noexcept {
    std::size_t digits = 0;
    while (digits < line.size() && line[digits] >= '0' && line[digits] <= '9') {
        ++digits;
    }
    if (digits == 0 || digits + 1 >= line.size() || line[digits] != '.'
        || !is_ascii_whitespace(line[digits + 1])) {
        return false;
    }
    start = digits + 2;
    while (start < line.size() && is_ascii_whitespace(line[start])) {
        ++start;
    }
    return true;
}

std::size_t ordered_list_ordinal(std::string_view line) noexcept {
    std::size_t value = 0;
    for (const char character : line) {
        if (character < '0' || character > '9') {
            break;
        }
        const auto digit = static_cast<std::size_t>(character - '0');
        if (value > (std::numeric_limits<std::size_t>::max() - digit) / 10) {
            return 0;
        }
        value = value * 10 + digit;
    }
    return value;
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

std::vector<QuickNoteMarkdownBlock> quick_note_markdown_blocks(
    std::string_view markdown) {
    std::vector<QuickNoteMarkdownBlock> blocks;
    std::string code_fence;
    std::string code;
    std::size_t line_start = 0;

    const auto append_inlines = [&blocks](
                                    QuickNoteMarkdownBlockKind kind,
                                    std::string_view content,
                                    std::uint8_t heading_level = 0,
                                    std::size_t list_ordinal = 0) {
        blocks.push_back({
            .kind = kind,
            .heading_level = heading_level,
            .list_ordinal = list_ordinal,
            .inlines = parse_markdown_inlines(content),
        });
    };
    const auto append_code = [&blocks, &code] {
        if (!code.empty() && code.back() == '\n') {
            code.pop_back();
        }
        blocks.push_back({
            .kind = QuickNoteMarkdownBlockKind::code_block,
            .code = std::move(code),
        });
        code.clear();
    };

    while (line_start <= markdown.size()) {
        const auto newline = markdown.find('\n', line_start);
        const auto line_end = newline == std::string_view::npos ? markdown.size() : newline;
        auto line = markdown.substr(line_start, line_end - line_start);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        const auto trimmed = trim_ascii(line);

        if (!code_fence.empty()) {
            if (trimmed.starts_with(code_fence)) {
                append_code();
                code_fence.clear();
            } else {
                code.append(line);
                code.push_back('\n');
            }
        } else if (trimmed.starts_with("```") || trimmed.starts_with("~~~")) {
            code_fence.assign(trimmed.substr(0, 3));
        } else if (trimmed.empty()) {
            // Blank lines separate paragraphs and do not need an empty visual block.
        } else if (is_thematic_break(trimmed)) {
            blocks.push_back({.kind = QuickNoteMarkdownBlockKind::thematic_break});
        } else {
            std::size_t heading_level = 0;
            while (heading_level < trimmed.size() && heading_level < 6
                && trimmed[heading_level] == '#') {
                ++heading_level;
            }
            if (heading_level > 0 && heading_level < trimmed.size()
                && is_ascii_whitespace(trimmed[heading_level])) {
                auto content = trim_ascii(trimmed.substr(heading_level + 1));
                while (content.size() >= 2 && content.back() == '#') {
                    content.remove_suffix(1);
                    content = trim_ascii(content);
                }
                append_inlines(
                    QuickNoteMarkdownBlockKind::heading,
                    content,
                    static_cast<std::uint8_t>(heading_level));
            } else if (trimmed.front() == '>'
                && (trimmed.size() == 1 || is_ascii_whitespace(trimmed[1]))) {
                append_inlines(
                    QuickNoteMarkdownBlockKind::quote,
                    trim_ascii(trimmed.substr(1)));
            } else if (trimmed.size() >= 2
                && (trimmed.front() == '-' || trimmed.front() == '*' || trimmed.front() == '+')
                && is_ascii_whitespace(trimmed[1])) {
                append_inlines(
                    QuickNoteMarkdownBlockKind::unordered_list_item,
                    trim_ascii(trimmed.substr(2)));
            } else {
                std::size_t content_start = 0;
                if (ordered_list_content_start(trimmed, content_start)) {
                    append_inlines(
                        QuickNoteMarkdownBlockKind::ordered_list_item,
                        trimmed.substr(content_start),
                        0,
                        ordered_list_ordinal(trimmed));
                } else {
                    append_inlines(QuickNoteMarkdownBlockKind::paragraph, trimmed);
                }
            }
        }

        if (newline == std::string_view::npos) {
            break;
        }
        line_start = newline + 1;
    }
    if (!code_fence.empty()) {
        append_code();
    }
    return blocks;
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
