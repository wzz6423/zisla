#include "zisla/core/Alarm.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <limits>
#include <memory>
#include <tuple>
#include <utility>

namespace zisla::core {
namespace {

constexpr AlarmWeekdayMask all_weekdays = 0x7f;
constexpr std::int64_t minutes_per_day = 24 * 60;

bool valid_id(std::string_view id) noexcept {
    return !id.empty() && id.size() <= 128;
}

std::int64_t estimated_fire_time(
    const AlarmOccurrence& occurrence,
    AlarmLocalClock now) noexcept {
    const auto current_seconds = static_cast<std::int64_t>(
        std::clamp(now.hour, 0, 23) * 3'600
        + std::clamp(now.minute, 0, 59) * 60
        + std::clamp(now.second, 0, 59));
    const auto target_seconds = static_cast<std::int64_t>(occurrence.day_offset)
            * minutes_per_day * 60
        + occurrence.hour * 3'600
        + occurrence.minute * 60;
    return now.now_unix_ms + (target_seconds - current_seconds) * 1'000;
}

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
            throw AlarmRepositoryError(sqlite3_errmsg(connection));
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
    explicit Database(const AlarmRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw AlarmRepositoryError(error.message());
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
                : "Unable to open alarm database";
            close();
            throw AlarmRepositoryError(message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw AlarmRepositoryError(sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS alarms ("
                "id TEXT PRIMARY KEY NOT NULL,"
                "hour INTEGER NOT NULL CHECK(hour BETWEEN 0 AND 23),"
                "minute INTEGER NOT NULL CHECK(minute BETWEEN 0 AND 59),"
                "label TEXT NOT NULL,"
                "weekday_mask INTEGER NOT NULL CHECK(weekday_mask BETWEEN 0 AND 127),"
                "enabled INTEGER NOT NULL CHECK(enabled IN (0, 1)),"
                "one_shot_fire_unix_ms INTEGER NOT NULL DEFAULT 0)");
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
            throw AlarmRepositoryError(
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
        throw AlarmRepositoryError(sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw AlarmRepositoryError(sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column) {
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw AlarmRepositoryError("Alarm database contains invalid text");
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

}  // namespace

bool AlarmItem::repeating() const noexcept {
    return weekday_mask != 0;
}

AlarmBook::AlarmBook(std::vector<AlarmItem> alarms) {
    alarms_.reserve(std::min(alarms.size(), maximum_alarms));
    for (auto& alarm : alarms) {
        alarm = normalized(std::move(alarm));
        if (!valid_id(alarm.id)
            || find(alarm.id).has_value()
            || alarms_.size() >= maximum_alarms) {
            continue;
        }
        alarms_.push_back(std::move(alarm));
    }
    sort();
}

const std::vector<AlarmItem>& AlarmBook::alarms() const noexcept {
    return alarms_;
}

std::optional<AlarmItem> AlarmBook::find(std::string_view id) const {
    const auto match = std::find_if(
        alarms_.begin(), alarms_.end(), [id](const AlarmItem& alarm) {
            return alarm.id == id;
        });
    return match == alarms_.end() ? std::nullopt : std::optional{*match};
}

bool AlarmBook::add(AlarmItem alarm) {
    alarm = normalized(std::move(alarm));
    if (!valid_id(alarm.id)
        || alarms_.size() >= maximum_alarms
        || find(alarm.id).has_value()) {
        return false;
    }
    alarms_.push_back(std::move(alarm));
    sort();
    return true;
}

bool AlarmBook::update(AlarmItem alarm) {
    alarm = normalized(std::move(alarm));
    if (!valid_id(alarm.id)) {
        return false;
    }
    const auto match = std::find_if(
        alarms_.begin(), alarms_.end(), [&alarm](const AlarmItem& candidate) {
            return candidate.id == alarm.id;
        });
    if (match == alarms_.end()) {
        return false;
    }
    *match = std::move(alarm);
    sort();
    return true;
}

bool AlarmBook::remove(std::string_view id) {
    const auto original_size = alarms_.size();
    std::erase_if(alarms_, [id](const AlarmItem& alarm) {
        return alarm.id == id;
    });
    return alarms_.size() != original_size;
}

bool AlarmBook::reconcile(
    std::int64_t now_unix_ms,
    std::int64_t delivery_grace_ms) noexcept {
    bool changed = false;
    for (auto& alarm : alarms_) {
        if (alarm.enabled && !alarm.repeating()
            && (alarm.one_shot_fire_unix_ms <= 0
                || delivery_deadline(
                       alarm.one_shot_fire_unix_ms,
                       delivery_grace_ms) <= now_unix_ms)) {
            alarm.enabled = false;
            changed = true;
        }
    }
    return changed;
}

std::optional<NextAlarm> AlarmBook::next_alarm(
    AlarmLocalClock now) const noexcept {
    std::optional<NextAlarm> result;
    for (const auto& alarm : alarms_) {
        if (!alarm.enabled) {
            continue;
        }

        std::int64_t fire_time = alarm.one_shot_fire_unix_ms;
        if (alarm.repeating()) {
            try {
                const auto occurrences = upcoming_repeating_occurrences(
                    alarm, now, 1);
                if (occurrences.empty()) {
                    continue;
                }
                fire_time = estimated_fire_time(occurrences.front(), now);
            } catch (...) {
                continue;
            }
        }
        if (fire_time <= now.now_unix_ms) {
            continue;
        }
        if (!result || fire_time < result->fire_unix_ms) {
            result = NextAlarm{
                .alarm = alarm,
                .fire_unix_ms = fire_time,
            };
        }
    }
    return result;
}

AlarmItem AlarmBook::normalized(AlarmItem alarm) {
    alarm.hour = std::clamp(alarm.hour, 0, 23);
    alarm.minute = std::clamp(alarm.minute, 0, 59);
    alarm.weekday_mask &= all_weekdays;
    alarm.one_shot_fire_unix_ms = std::max<std::int64_t>(
        0, alarm.one_shot_fire_unix_ms);
    if (alarm.repeating()) {
        alarm.one_shot_fire_unix_ms = 0;
    }
    return alarm;
}

std::string AlarmBook::format_time(const AlarmItem& alarm) {
    const auto normalized_alarm = normalized(alarm);
    std::array<char, 6> buffer{};
    const auto written = std::snprintf(
        buffer.data(),
        buffer.size(),
        "%02d:%02d",
        normalized_alarm.hour,
        normalized_alarm.minute);
    return written == 5 ? std::string(buffer.data(), 5) : std::string{};
}

std::string AlarmBook::format_repeat(AlarmWeekdayMask mask) {
    mask &= all_weekdays;
    constexpr auto weekdays = static_cast<AlarmWeekdayMask>(0x3e);
    constexpr auto weekend = static_cast<AlarmWeekdayMask>(0x41);
    if (mask == 0) {
        return "仅一次";
    }
    if (mask == all_weekdays) {
        return "每天";
    }
    if (mask == weekdays) {
        return "工作日";
    }
    if (mask == weekend) {
        return "周末";
    }

    constexpr std::string_view names[]{
        "周日", "周一", "周二", "周三", "周四", "周五", "周六",
    };
    std::string result;
    for (std::uint8_t weekday = 1; weekday <= 7; ++weekday) {
        if ((mask & alarm_weekday_bit(weekday)) == 0) {
            continue;
        }
        if (!result.empty()) {
            result.push_back(' ');
        }
        result.append(names[weekday - 1]);
    }
    return result;
}

std::int64_t AlarmBook::delivery_deadline(
    std::int64_t fire_unix_ms,
    std::int64_t delivery_grace_ms) noexcept {
    const auto grace = std::max<std::int64_t>(0, delivery_grace_ms);
    if (fire_unix_ms > std::numeric_limits<std::int64_t>::max() - grace) {
        return std::numeric_limits<std::int64_t>::max();
    }
    return fire_unix_ms + grace;
}

std::vector<AlarmOccurrence> AlarmBook::upcoming_repeating_occurrences(
    const AlarmItem& source,
    AlarmLocalClock now,
    std::size_t count) {
    const auto alarm = normalized(source);
    std::vector<AlarmOccurrence> result;
    if (!alarm.enabled || !alarm.repeating() || count == 0) {
        return result;
    }

    const auto current_weekday = std::clamp<std::uint8_t>(now.weekday, 1, 7);
    const auto current_second = std::clamp(now.hour, 0, 23) * 3'600
        + std::clamp(now.minute, 0, 59) * 60
        + std::clamp(now.second, 0, 59);
    const auto alarm_second = alarm.hour * 3'600 + alarm.minute * 60;
    const auto maximum_days = static_cast<std::size_t>(7) * count + 7;
    result.reserve(count);

    for (std::size_t day = 0;
         day < maximum_days && result.size() < count;
         ++day) {
        const auto weekday = static_cast<std::uint8_t>(
            ((current_weekday - 1U + day) % 7U) + 1U);
        if ((alarm.weekday_mask & alarm_weekday_bit(weekday)) == 0
            || (day == 0 && alarm_second <= current_second)) {
            continue;
        }
        result.push_back({
            .day_offset = static_cast<int>(day),
            .hour = alarm.hour,
            .minute = alarm.minute,
        });
    }
    return result;
}

void AlarmBook::sort() noexcept {
    std::sort(alarms_.begin(), alarms_.end(), [](const auto& lhs, const auto& rhs) {
        return std::tie(lhs.hour, lhs.minute, lhs.id)
            < std::tie(rhs.hour, rhs.minute, rhs.id);
    });
}

AlarmRepositoryError::AlarmRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

AlarmRepository::AlarmRepository(std::filesystem::path directory)
    : directory_(std::move(directory)) {}

const std::filesystem::path& AlarmRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path AlarmRepository::database_path() const {
    return directory_ / "alarms.sqlite";
}

std::vector<AlarmItem> AlarmRepository::load() const {
    Database database(*this);
    Statement statement(
        database.get(),
        "SELECT id, hour, minute, label, weekday_mask, enabled, "
        "one_shot_fire_unix_ms FROM alarms ORDER BY hour, minute, id");
    std::vector<AlarmItem> alarms;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AlarmRepositoryError(sqlite3_errmsg(database.get()));
        }
        alarms.push_back(AlarmBook::normalized({
            .id = column_text(statement.get(), 0),
            .hour = sqlite3_column_int(statement.get(), 1),
            .minute = sqlite3_column_int(statement.get(), 2),
            .label = column_text(statement.get(), 3),
            .weekday_mask = static_cast<AlarmWeekdayMask>(
                sqlite3_column_int(statement.get(), 4)),
            .enabled = sqlite3_column_int(statement.get(), 5) != 0,
            .one_shot_fire_unix_ms = sqlite3_column_int64(statement.get(), 6),
        }));
    }
    return AlarmBook(std::move(alarms)).alarms();
}

void AlarmRepository::replace(std::span<const AlarmItem> alarms) const {
    AlarmBook normalized_book({alarms.begin(), alarms.end()});
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        database.execute("DELETE FROM alarms");
        Statement insert(
            database.get(),
            "INSERT INTO alarms(id, hour, minute, label, weekday_mask, enabled, "
            "one_shot_fire_unix_ms) VALUES(?, ?, ?, ?, ?, ?, ?)");
        for (const auto& alarm : normalized_book.alarms()) {
            bind_text(database.get(), insert.get(), 1, alarm.id);
            if (sqlite3_bind_int(insert.get(), 2, alarm.hour) != SQLITE_OK
                || sqlite3_bind_int(insert.get(), 3, alarm.minute) != SQLITE_OK) {
                throw AlarmRepositoryError(sqlite3_errmsg(database.get()));
            }
            bind_text(database.get(), insert.get(), 4, alarm.label);
            if (sqlite3_bind_int(insert.get(), 5, alarm.weekday_mask) != SQLITE_OK
                || sqlite3_bind_int(insert.get(), 6, alarm.enabled ? 1 : 0) != SQLITE_OK
                || sqlite3_bind_int64(
                    insert.get(), 7, alarm.one_shot_fire_unix_ms) != SQLITE_OK) {
                throw AlarmRepositoryError(sqlite3_errmsg(database.get()));
            }
            step_done(database.get(), insert.get());
            if (sqlite3_reset(insert.get()) != SQLITE_OK
                || sqlite3_clear_bindings(insert.get()) != SQLITE_OK) {
                throw AlarmRepositoryError(sqlite3_errmsg(database.get()));
            }
        }
        database.execute("COMMIT");
    } catch (...) {
        database.rollback();
        throw;
    }
}

}  // namespace zisla::core
