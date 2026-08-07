#include "zisla/core/Calendar.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <chrono>
#include <memory>
#include <limits>
#include <tuple>
#include <utility>

namespace zisla::core {
namespace {

constexpr CalendarWeekdayMask all_weekdays = 0x7f;

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

class Statement {
public:
    Statement(sqlite3* connection, const char* sql) {
        if (sqlite3_prepare_v2(connection, sql, -1, &value_, nullptr) != SQLITE_OK) {
            throw CalendarRepositoryError(sqlite3_errmsg(connection));
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
    explicit Database(const CalendarRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw CalendarRepositoryError(error.message());
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
                : "Unable to open calendar database";
            close();
            throw CalendarRepositoryError(message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw CalendarRepositoryError(sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS calendar_items ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "kind INTEGER NOT NULL CHECK(kind IN (0, 1)),"
                "title TEXT NOT NULL,"
                "start_unix_ms INTEGER NOT NULL,"
                "end_unix_ms INTEGER NOT NULL,"
                "is_all_day INTEGER NOT NULL CHECK(is_all_day IN (0, 1)),"
                "is_completed INTEGER NOT NULL CHECK(is_completed IN (0, 1)),"
                "recurrence_frequency INTEGER CHECK(recurrence_frequency IN (0, 1)),"
                "recurrence_interval INTEGER NOT NULL DEFAULT 1,"
                "recurrence_weekday_mask INTEGER NOT NULL DEFAULT 0,"
                "recurrence_source_day_ordinal INTEGER NOT NULL DEFAULT 0,"
                "recurrence_source_weekday INTEGER NOT NULL DEFAULT 1,"
                "recurrence_first_weekday INTEGER NOT NULL DEFAULT 1,"
                "recurrence_until_unix_ms INTEGER,"
                "created_at_unix_ms INTEGER NOT NULL,"
                "modified_at_unix_ms INTEGER NOT NULL,"
                "CHECK(kind = 1 OR is_completed = 0),"
                "CHECK(recurrence_frequency IS NULL OR kind = 1))");
            execute(
                "CREATE INDEX IF NOT EXISTS calendar_items_range_idx "
                "ON calendar_items(start_unix_ms, end_unix_ms)");
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
        const auto result = sqlite3_exec(
            connection_, sql, nullptr, nullptr, &raw_error);
        const std::unique_ptr<char, decltype(&sqlite3_free)> error(
            raw_error, sqlite3_free);
        if (result != SQLITE_OK) {
            throw CalendarRepositoryError(
                error ? error.get() : sqlite3_errmsg(connection_));
        }
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
        throw CalendarRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_int64(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::int64_t value) {
    if (sqlite3_bind_int64(statement, index, value) != SQLITE_OK) {
        throw CalendarRepositoryError(sqlite3_errmsg(connection));
    }
}

void bind_optional_int64(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::optional<std::int64_t> value) {
    const auto result = value
        ? sqlite3_bind_int64(statement, index, *value)
        : sqlite3_bind_null(statement, index);
    if (result != SQLITE_OK) {
        throw CalendarRepositoryError(sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw CalendarRepositoryError(sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column) {
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw CalendarRepositoryError("Calendar database contains invalid text");
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

CalendarItemKind column_kind(sqlite3_stmt* statement, int column) {
    switch (sqlite3_column_int(statement, column)) {
    case 0:
        return CalendarItemKind::event;
    case 1:
        return CalendarItemKind::reminder;
    default:
        throw CalendarRepositoryError("Calendar database contains invalid item kind");
    }
}

std::optional<CalendarRecurrenceRule> column_recurrence(
    sqlite3_stmt* statement,
    int first_column) {
    if (sqlite3_column_type(statement, first_column) == SQLITE_NULL) {
        return std::nullopt;
    }
    CalendarRecurrenceRule rule{
        .frequency = sqlite3_column_int(statement, first_column) == 0
            ? CalendarRecurrenceFrequency::daily
            : CalendarRecurrenceFrequency::weekly,
        .interval = static_cast<unsigned>(
            sqlite3_column_int(statement, first_column + 1)),
        .weekday_mask = static_cast<CalendarWeekdayMask>(
            sqlite3_column_int(statement, first_column + 2)),
        .source_day_ordinal = sqlite3_column_int64(statement, first_column + 3),
        .source_weekday = static_cast<std::uint8_t>(
            sqlite3_column_int(statement, first_column + 4)),
        .first_weekday = static_cast<std::uint8_t>(
            sqlite3_column_int(statement, first_column + 5)),
    };
    if (sqlite3_column_type(statement, first_column + 6) != SQLITE_NULL) {
        rule.until_unix_ms = sqlite3_column_int64(statement, first_column + 6);
    }
    try {
        return CalendarEngine::validated(rule);
    } catch (const CalendarMutationError& error) {
        throw CalendarRepositoryError(error.what());
    }
}

CalendarLocalItem read_item(sqlite3_stmt* statement) {
    CalendarLocalItem item{
        .id = sqlite3_column_int64(statement, 0),
        .kind = column_kind(statement, 1),
        .title = column_text(statement, 2),
        .start_unix_ms = sqlite3_column_int64(statement, 3),
        .end_unix_ms = sqlite3_column_int64(statement, 4),
        .is_all_day = sqlite3_column_int(statement, 5) != 0,
        .is_completed = sqlite3_column_int(statement, 6) != 0,
        .recurrence = column_recurrence(statement, 7),
        .created_at_unix_ms = sqlite3_column_int64(statement, 14),
        .modified_at_unix_ms = sqlite3_column_int64(statement, 15),
    };
    if (item.id <= 0 || item.title.empty()
        || (item.kind == CalendarItemKind::event
            && item.end_unix_ms <= item.start_unix_ms)) {
        throw CalendarRepositoryError("Calendar database contains invalid item data");
    }
    return item;
}

constexpr const char* select_item_columns =
    "id, kind, title, start_unix_ms, end_unix_ms, is_all_day, is_completed, "
    "recurrence_frequency, recurrence_interval, recurrence_weekday_mask, "
    "recurrence_source_day_ordinal, recurrence_source_weekday, "
    "recurrence_first_weekday, recurrence_until_unix_ms, "
    "created_at_unix_ms, modified_at_unix_ms";

void bind_recurrence(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int first_index,
    const std::optional<CalendarRecurrenceRule>& recurrence) {
    if (!recurrence) {
        if (sqlite3_bind_null(statement, first_index) != SQLITE_OK) {
            throw CalendarRepositoryError(sqlite3_errmsg(connection));
        }
        bind_int64(connection, statement, first_index + 1, 1);
        bind_int64(connection, statement, first_index + 2, 0);
        bind_int64(connection, statement, first_index + 3, 0);
        bind_int64(connection, statement, first_index + 4, 1);
        bind_int64(connection, statement, first_index + 5, 1);
        bind_optional_int64(connection, statement, first_index + 6, std::nullopt);
        return;
    }

    const auto rule = CalendarEngine::validated(*recurrence);
    bind_int64(
        connection,
        statement,
        first_index,
        rule.frequency == CalendarRecurrenceFrequency::daily ? 0 : 1);
    bind_int64(connection, statement, first_index + 1, rule.interval);
    bind_int64(connection, statement, first_index + 2, rule.weekday_mask);
    bind_int64(connection, statement, first_index + 3, rule.source_day_ordinal);
    bind_int64(connection, statement, first_index + 4, rule.source_weekday);
    bind_int64(connection, statement, first_index + 5, rule.first_weekday);
    bind_optional_int64(
        connection,
        statement,
        first_index + 6,
        rule.until_unix_ms);
}

std::int64_t insert_item(
    Database& database,
    CalendarItemKind kind,
    std::string_view title,
    std::int64_t start_unix_ms,
    std::int64_t end_unix_ms,
    bool is_all_day,
    std::optional<CalendarRecurrenceRule> recurrence,
    std::int64_t now_unix_ms) {
    Statement statement(
        database.get(),
        "INSERT INTO calendar_items("
        "kind, title, start_unix_ms, end_unix_ms, is_all_day, is_completed, "
        "recurrence_frequency, recurrence_interval, recurrence_weekday_mask, "
        "recurrence_source_day_ordinal, recurrence_source_weekday, "
        "recurrence_first_weekday, recurrence_until_unix_ms, "
        "created_at_unix_ms, modified_at_unix_ms) "
        "VALUES(?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    bind_int64(database.get(), statement.get(), 1,
        kind == CalendarItemKind::event ? 0 : 1);
    bind_text(database.get(), statement.get(), 2, title);
    bind_int64(database.get(), statement.get(), 3, start_unix_ms);
    bind_int64(database.get(), statement.get(), 4, end_unix_ms);
    bind_int64(database.get(), statement.get(), 5, is_all_day ? 1 : 0);
    bind_recurrence(database.get(), statement.get(), 6, recurrence);
    bind_int64(database.get(), statement.get(), 13, now_unix_ms);
    bind_int64(database.get(), statement.get(), 14, now_unix_ms);
    step_done(database.get(), statement.get());
    return sqlite3_last_insert_rowid(database.get());
}

bool update_item(
    Database& database,
    std::int64_t id,
    CalendarItemKind kind,
    std::string_view title,
    std::int64_t start_unix_ms,
    std::int64_t end_unix_ms,
    bool is_all_day,
    std::optional<CalendarRecurrenceRule> recurrence,
    std::int64_t now_unix_ms) {
    Statement statement(
        database.get(),
        "UPDATE calendar_items SET title = ?, start_unix_ms = ?, end_unix_ms = ?, "
        "is_all_day = ?, recurrence_frequency = ?, recurrence_interval = ?, "
        "recurrence_weekday_mask = ?, recurrence_source_day_ordinal = ?, "
        "recurrence_source_weekday = ?, recurrence_first_weekday = ?, "
        "recurrence_until_unix_ms = ?, modified_at_unix_ms = ? "
        "WHERE id = ? AND kind = ?");
    bind_text(database.get(), statement.get(), 1, title);
    bind_int64(database.get(), statement.get(), 2, start_unix_ms);
    bind_int64(database.get(), statement.get(), 3, end_unix_ms);
    bind_int64(database.get(), statement.get(), 4, is_all_day ? 1 : 0);
    bind_recurrence(database.get(), statement.get(), 5, recurrence);
    bind_int64(database.get(), statement.get(), 12, now_unix_ms);
    bind_int64(database.get(), statement.get(), 13, id);
    bind_int64(database.get(), statement.get(), 14,
        kind == CalendarItemKind::event ? 0 : 1);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

std::chrono::sys_days to_sys_days(CalendarCivilDate date) {
    const auto value = std::chrono::year{date.year}
        / std::chrono::month{date.month}
        / std::chrono::day{date.day};
    if (!value.ok()) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::invalid_date,
            "日期无效");
    }
    return std::chrono::sys_days{value};
}

std::uint8_t weekday_number(std::chrono::sys_days day) noexcept {
    const auto encoded = std::chrono::weekday{day}.c_encoding();
    return static_cast<std::uint8_t>(encoded == 0 ? 7 : encoded);
}

CalendarWeekday calendar_day(std::chrono::sys_days day) {
    const std::chrono::year_month_day value{day};
    return {
        .date = {
            .year = static_cast<int>(value.year()),
            .month = static_cast<unsigned>(value.month()),
            .day = static_cast<unsigned>(value.day()),
        },
        .weekday = weekday_number(day),
        .day_ordinal = day.time_since_epoch().count(),
    };
}

bool valid_day(CalendarDayInterval day) noexcept {
    return day.start_unix_ms < day.end_unix_ms
        && day.weekday >= 1
        && day.weekday <= 7;
}

bool contains(CalendarDayInterval day, std::int64_t value) noexcept {
    return valid_day(day)
        && value >= day.start_unix_ms
        && value < day.end_unix_ms;
}

std::int64_t weekly_anchor(
    std::int64_t source_day_ordinal,
    std::uint8_t source_weekday,
    std::uint8_t first_weekday) noexcept {
    const auto offset = static_cast<std::int64_t>(
        (source_weekday + 7U - first_weekday) % 7U);
    return source_day_ordinal - offset;
}

bool recurrence_matches(
    const CalendarRecurrenceRule& rule,
    const CalendarProjectionDay& day) noexcept {
    const auto day_ordinal = day.interval.day_ordinal;
    if (day_ordinal < rule.source_day_ordinal) {
        return false;
    }

    switch (rule.frequency) {
    case CalendarRecurrenceFrequency::daily:
        return static_cast<std::uint64_t>(
                   day_ordinal - rule.source_day_ordinal)
                % rule.interval
            == 0;
    case CalendarRecurrenceFrequency::weekly: {
        if ((rule.weekday_mask
             & calendar_weekday_bit(day.interval.weekday)) == 0) {
            return false;
        }
        const auto anchor = weekly_anchor(
            rule.source_day_ordinal,
            rule.source_weekday,
            rule.first_weekday);
        const auto week_index = static_cast<std::uint64_t>(
            (day_ordinal - anchor) / 7);
        return week_index % rule.interval == 0;
    }
    }
    return false;
}

void validate_recurrence(const CalendarRecurrenceRule& rule) {
    if (rule.interval == 0
        || rule.interval > 366
        || rule.first_weekday < 1
        || rule.first_weekday > 7
        || (rule.frequency == CalendarRecurrenceFrequency::weekly
            && ((rule.weekday_mask & all_weekdays) == 0
                || rule.source_weekday < 1
                || rule.source_weekday > 7))) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::invalid_recurrence,
            "重复规则无效");
    }
}

}  // namespace

CalendarMutationError::CalendarMutationError(
    CalendarMutationErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

CalendarMutationErrorCode CalendarMutationError::code() const noexcept {
    return code_;
}

std::string CalendarEngine::normalized_title(std::string_view title) {
    const auto first = title.find_first_not_of(" \t\n\r");
    if (first == std::string_view::npos) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::empty_title,
            "请输入标题");
    }
    const auto last = title.find_last_not_of(" \t\n\r");
    return std::string(title.substr(first, last - first + 1));
}

CalendarEventDraft CalendarEngine::validated(CalendarEventDraft draft) {
    draft.title = normalized_title(draft.title);
    if (draft.end_unix_ms <= draft.start_unix_ms) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::invalid_date_range,
            "结束时间必须晚于开始时间");
    }
    return draft;
}

CalendarReminderDraft CalendarEngine::validated(CalendarReminderDraft draft) {
    draft.title = normalized_title(draft.title);
    return draft;
}

CalendarRecurrenceRule CalendarEngine::validated(CalendarRecurrenceRule rule) {
    rule.weekday_mask &= all_weekdays;
    validate_recurrence(rule);
    if (rule.frequency == CalendarRecurrenceFrequency::daily) {
        rule.weekday_mask = 0;
    }
    return rule;
}

CalendarWeekday CalendarEngine::civil_day(CalendarCivilDate date) {
    return calendar_day(to_sys_days(date));
}

CalendarCivilDate CalendarEngine::add_days(
    CalendarCivilDate date,
    int offset) {
    return calendar_day(to_sys_days(date) + std::chrono::days{offset}).date;
}

std::vector<CalendarWeekday> CalendarEngine::days_of_week(
    CalendarCivilDate reference,
    std::uint8_t first_weekday) {
    if (first_weekday < 1 || first_weekday > 7) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::invalid_date,
            "一周起始日无效");
    }

    const auto reference_day = to_sys_days(reference);
    const auto reference_weekday = weekday_number(reference_day);
    const auto offset = static_cast<unsigned>(
        (reference_weekday + 7U - first_weekday) % 7U);
    const auto week_start = reference_day - std::chrono::days{offset};

    std::vector<CalendarWeekday> days;
    days.reserve(week_day_count);
    for (int index = 0; index < week_day_count; ++index) {
        days.push_back(calendar_day(
            week_start + std::chrono::days{index}));
    }
    return days;
}

bool CalendarEngine::item_occurs_on_day(
    const CalendarEventSnapshot& item,
    CalendarDayInterval day) noexcept {
    if (!valid_day(day)) {
        return false;
    }
    if (item.end_unix_ms <= item.start_unix_ms) {
        return contains(day, item.start_unix_ms);
    }
    return item.start_unix_ms < day.end_unix_ms
        && item.end_unix_ms > day.start_unix_ms;
}

std::vector<CalendarEventSnapshot> CalendarEngine::events_on_day(
    std::span<const CalendarEventSnapshot> events,
    CalendarDayInterval day) {
    std::vector<CalendarEventSnapshot> result;
    for (const auto& event : events) {
        if (item_occurs_on_day(event, day)) {
            result.push_back(event);
        }
    }
    return result;
}

bool CalendarEngine::sort_agenda_items(
    const CalendarEventSnapshot& lhs,
    const CalendarEventSnapshot& rhs) {
    if (lhs.start_unix_ms != rhs.start_unix_ms) {
        return lhs.start_unix_ms < rhs.start_unix_ms;
    }
    if (lhs.kind != rhs.kind) {
        return lhs.kind == CalendarItemKind::reminder;
    }
    return lhs.id < rhs.id;
}

std::vector<CalendarEventSnapshot> CalendarEngine::prepared_agenda_items(
    std::span<const CalendarEventSnapshot> items) {
    std::vector<CalendarEventSnapshot> result(items.begin(), items.end());
    std::sort(result.begin(), result.end(), sort_agenda_items);
    return result;
}

std::vector<CalendarEventSnapshot>
CalendarEngine::project_reminder_occurrences(
    const CalendarEventSnapshot& source,
    CalendarRecurrenceRule rule,
    std::span<const CalendarProjectionDay> days,
    std::size_t maximum_results) {
    if (source.kind != CalendarItemKind::reminder) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::action_not_supported,
            "只有待办支持重复投影");
    }
    rule = validated(rule);
    maximum_results = std::min(maximum_results, maximum_projected_occurrences);
    if (maximum_results == 0) {
        return {};
    }

    std::vector<CalendarEventSnapshot> result;
    result.reserve(std::min(days.size(), maximum_results));
    for (const auto& day : days) {
        if (!valid_day(day.interval)) {
            continue;
        }

        const bool actual_occurrence = contains(
            day.interval,
            source.start_unix_ms);
        const bool projected_occurrence = !source.is_completed
            && !source.is_projected_occurrence
            && recurrence_matches(rule, day)
            && day.occurrence_unix_ms >= source.start_unix_ms
            && (!rule.until_unix_ms
                || day.occurrence_unix_ms <= *rule.until_unix_ms);
        if (!actual_occurrence && !projected_occurrence) {
            continue;
        }

        CalendarEventSnapshot occurrence = source;
        if (!actual_occurrence) {
            occurrence.id = source.id + ":" + std::to_string(day.occurrence_unix_ms);
            occurrence.start_unix_ms = day.occurrence_unix_ms;
            occurrence.end_unix_ms = source.is_all_day
                ? day.interval.end_unix_ms
                : day.occurrence_unix_ms;
            occurrence.is_projected_occurrence = true;
        }
        result.push_back(std::move(occurrence));
    }

    std::sort(result.begin(), result.end(), sort_agenda_items);
    result.erase(
        std::unique(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
            return lhs.id == rhs.id
                || (lhs.start_unix_ms == rhs.start_unix_ms
                    && lhs.source_identifier == rhs.source_identifier);
        }),
        result.end());
    if (result.size() > maximum_results) {
        result.resize(maximum_results);
    }
    return result;
}

CalendarRepositoryError::CalendarRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

CalendarRepository::CalendarRepository(std::filesystem::path directory)
    : directory_(std::move(directory)) {}

const std::filesystem::path& CalendarRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path CalendarRepository::database_path() const {
    return directory_ / "calendar.sqlite";
}

std::optional<CalendarLocalItem> CalendarRepository::find(std::int64_t id) const {
    if (id <= 0) {
        return std::nullopt;
    }
    Database database(*this);
    const std::string sql = std::string("SELECT ") + select_item_columns
        + " FROM calendar_items WHERE id = ?";
    Statement statement(database.get(), sql.c_str());
    bind_int64(database.get(), statement.get(), 1, id);
    const auto result = sqlite3_step(statement.get());
    if (result == SQLITE_DONE) {
        return std::nullopt;
    }
    if (result != SQLITE_ROW) {
        throw CalendarRepositoryError(sqlite3_errmsg(database.get()));
    }
    return read_item(statement.get());
}

std::vector<CalendarLocalItem> CalendarRepository::load_for_range(
    std::int64_t range_start_unix_ms,
    std::int64_t range_end_unix_ms) const {
    if (range_end_unix_ms <= range_start_unix_ms) {
        throw CalendarMutationError(
            CalendarMutationErrorCode::invalid_date_range,
            "日程查询范围无效");
    }
    Database database(*this);
    const std::string sql = std::string("SELECT ") + select_item_columns
        + " FROM calendar_items WHERE "
          "(kind = 1 AND is_completed = 0 AND recurrence_frequency IS NOT NULL "
          "AND start_unix_ms < ? AND "
          "(recurrence_until_unix_ms IS NULL OR recurrence_until_unix_ms >= ?)) "
          "OR ((end_unix_ms > start_unix_ms AND start_unix_ms < ? "
          "AND end_unix_ms > ?) OR "
          "(end_unix_ms <= start_unix_ms AND start_unix_ms >= ? "
          "AND start_unix_ms < ?)) "
          "ORDER BY start_unix_ms, kind DESC, id";
    Statement statement(database.get(), sql.c_str());
    bind_int64(database.get(), statement.get(), 1, range_end_unix_ms);
    bind_int64(database.get(), statement.get(), 2, range_start_unix_ms);
    bind_int64(database.get(), statement.get(), 3, range_end_unix_ms);
    bind_int64(database.get(), statement.get(), 4, range_start_unix_ms);
    bind_int64(database.get(), statement.get(), 5, range_start_unix_ms);
    bind_int64(database.get(), statement.get(), 6, range_end_unix_ms);

    std::vector<CalendarLocalItem> items;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw CalendarRepositoryError(sqlite3_errmsg(database.get()));
        }
        items.push_back(read_item(statement.get()));
    }
    return items;
}

std::int64_t CalendarRepository::create_event(
    CalendarEventDraft draft,
    std::int64_t now_unix_ms) const {
    draft = CalendarEngine::validated(std::move(draft));
    Database database(*this);
    return insert_item(
        database,
        CalendarItemKind::event,
        draft.title,
        draft.start_unix_ms,
        draft.end_unix_ms,
        draft.is_all_day,
        std::nullopt,
        now_unix_ms);
}

std::int64_t CalendarRepository::create_reminder(
    CalendarReminderDraft draft,
    std::optional<CalendarRecurrenceRule> recurrence,
    std::int64_t now_unix_ms) const {
    draft = CalendarEngine::validated(std::move(draft));
    if (recurrence) {
        recurrence = CalendarEngine::validated(*recurrence);
        if (recurrence->until_unix_ms
            && *recurrence->until_unix_ms < draft.due_unix_ms) {
            throw CalendarMutationError(
                CalendarMutationErrorCode::invalid_recurrence,
                "重复结束时间不能早于首次到期时间");
        }
    }
    Database database(*this);
    return insert_item(
        database,
        CalendarItemKind::reminder,
        draft.title,
        draft.due_unix_ms,
        draft.due_unix_ms,
        draft.is_all_day,
        recurrence,
        now_unix_ms);
}

bool CalendarRepository::update_event(
    std::int64_t id,
    CalendarEventDraft draft,
    std::int64_t now_unix_ms) const {
    if (id <= 0) {
        return false;
    }
    draft = CalendarEngine::validated(std::move(draft));
    Database database(*this);
    return update_item(
        database,
        id,
        CalendarItemKind::event,
        draft.title,
        draft.start_unix_ms,
        draft.end_unix_ms,
        draft.is_all_day,
        std::nullopt,
        now_unix_ms);
}

bool CalendarRepository::update_reminder(
    std::int64_t id,
    CalendarReminderDraft draft,
    std::optional<CalendarRecurrenceRule> recurrence,
    std::int64_t now_unix_ms) const {
    if (id <= 0) {
        return false;
    }
    draft = CalendarEngine::validated(std::move(draft));
    if (recurrence) {
        recurrence = CalendarEngine::validated(*recurrence);
        if (recurrence->until_unix_ms
            && *recurrence->until_unix_ms < draft.due_unix_ms) {
            throw CalendarMutationError(
                CalendarMutationErrorCode::invalid_recurrence,
                "重复结束时间不能早于首次到期时间");
        }
    }
    Database database(*this);
    return update_item(
        database,
        id,
        CalendarItemKind::reminder,
        draft.title,
        draft.due_unix_ms,
        draft.due_unix_ms,
        draft.is_all_day,
        recurrence,
        now_unix_ms);
}

bool CalendarRepository::set_reminder_completed(
    std::int64_t id,
    bool completed,
    std::int64_t now_unix_ms) const {
    if (id <= 0) {
        return false;
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "UPDATE calendar_items SET is_completed = ?, modified_at_unix_ms = ? "
        "WHERE id = ? AND kind = 1");
    bind_int64(database.get(), statement.get(), 1, completed ? 1 : 0);
    bind_int64(database.get(), statement.get(), 2, now_unix_ms);
    bind_int64(database.get(), statement.get(), 3, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

bool CalendarRepository::remove(std::int64_t id) const {
    if (id <= 0) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM calendar_items WHERE id = ?");
    bind_int64(database.get(), statement.get(), 1, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

}  // namespace zisla::core
