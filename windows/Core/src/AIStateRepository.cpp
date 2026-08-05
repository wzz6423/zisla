#include "zisla/core/AIStateRepository.hpp"

#include <sqlite3.h>
#include <yyjson.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <memory>
#include <optional>
#include <string_view>
#include <utility>

namespace zisla::core {
namespace {

constexpr double apple_reference_date_unix_seconds = 978'307'200.0;

[[noreturn]] void throw_corrupted_state() {
    throw AIStateRepositoryError(
        AIStateRepositoryErrorCode::corrupted_state,
        "AI state contains invalid data");
}

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

std::pair<
    std::optional<std::filesystem::file_time_type>,
    std::optional<std::uintmax_t>> file_version(
        const std::filesystem::path& path) noexcept {
    std::error_code error;
    const auto modification_time = std::filesystem::last_write_time(path, error);
    if (error) {
        return {};
    }
    const auto size = std::filesystem::file_size(path, error);
    if (error) {
        return {modification_time, std::nullopt};
    }
    return {modification_time, size};
}

double reference_seconds(std::int64_t unix_ms) noexcept {
    return static_cast<double>(unix_ms) / 1'000.0
        - apple_reference_date_unix_seconds;
}

std::int64_t unix_ms(double reference_time) {
    const auto value = (reference_time + apple_reference_date_unix_seconds)
        * 1'000.0;
    if (!std::isfinite(value)
        || value < static_cast<double>(std::numeric_limits<std::int64_t>::min())
        || value > static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
        throw_corrupted_state();
    }
    return static_cast<std::int64_t>(std::llround(value));
}

using MutableDocument = std::unique_ptr<yyjson_mut_doc, decltype(&yyjson_mut_doc_free)>;
using ImmutableDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

bool add_string(
    yyjson_mut_doc* document,
    yyjson_mut_val* object,
    const char* key,
    std::string_view value) {
    return yyjson_mut_obj_add_strncpy(
        document,
        object,
        key,
        value.data(),
        value.size());
}

std::string encode_task(const AIProgressTask& task) {
    MutableDocument document(yyjson_mut_doc_new(nullptr), yyjson_mut_doc_free);
    if (!document) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to allocate task JSON document");
    }
    auto* root = yyjson_mut_obj(document.get());
    yyjson_mut_doc_set_root(document.get(), root);

    bool valid = root
        && add_string(document.get(), root, "id", task.id)
        && add_string(document.get(), root, "provider", ai_provider_token(task.provider))
        && add_string(document.get(), root, "title", task.title)
        && add_string(
            document.get(), root, "status", ai_progress_status_token(task.status))
        && yyjson_mut_obj_add_real(
            document.get(), root, "updatedAt", reference_seconds(task.updated_at_unix_ms));
    if (task.detail) {
        valid = valid && add_string(document.get(), root, "detail", *task.detail);
    }
    if (task.progress) {
        valid = valid && std::isfinite(*task.progress)
            && yyjson_mut_obj_add_real(document.get(), root, "progress", *task.progress);
    }
    if (task.session_uri) {
        valid = valid && add_string(document.get(), root, "sessionURL", *task.session_uri);
    }
    if (task.effort) {
        valid = valid && add_string(document.get(), root, "effort", *task.effort);
    }
    if (task.started_at_unix_ms) {
        valid = valid && yyjson_mut_obj_add_real(
            document.get(), root, "startedAt", reference_seconds(*task.started_at_unix_ms));
    }
    if (!valid) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to encode task JSON");
    }

    std::size_t length = 0;
    std::unique_ptr<char, decltype(&std::free)> json(
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        std::free);
    if (!json) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to serialize task JSON");
    }
    return {json.get(), length};
}

std::string encode_notice(const IslandNotice& notice) {
    MutableDocument document(yyjson_mut_doc_new(nullptr), yyjson_mut_doc_free);
    if (!document) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to allocate notice JSON document");
    }
    auto* root = yyjson_mut_obj(document.get());
    yyjson_mut_doc_set_root(document.get(), root);

    bool valid = root
        && add_string(document.get(), root, "id", notice.id)
        && add_string(document.get(), root, "title", notice.title)
        && add_string(document.get(), root, "kind", notice_kind_token(notice.kind))
        && add_string(document.get(), root, "side", notice_side_token(notice.side))
        && yyjson_mut_obj_add_real(
            document.get(), root, "createdAt", reference_seconds(notice.created_at_unix_ms))
        && add_string(document.get(), root, "style", notice_style_token(notice.style));
    if (notice.detail) {
        valid = valid && add_string(document.get(), root, "detail", *notice.detail);
    }
    if (notice.progress) {
        valid = valid && std::isfinite(*notice.progress)
            && yyjson_mut_obj_add_real(document.get(), root, "progress", *notice.progress);
    }
    if (notice.app_name) {
        valid = valid && add_string(document.get(), root, "appName", *notice.app_name);
    }
    if (notice.app_bundle_identifier) {
        valid = valid && add_string(
            document.get(), root, "appBundleIdentifier", *notice.app_bundle_identifier);
    }
    if (notice.symbol_name) {
        valid = valid && add_string(document.get(), root, "symbolName", *notice.symbol_name);
    }
    if (!valid) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to encode notice JSON");
    }

    std::size_t length = 0;
    std::unique_ptr<char, decltype(&std::free)> json(
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        std::free);
    if (!json) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "Unable to serialize notice JSON");
    }
    return {json.get(), length};
}

std::optional<std::string> optional_json_string(yyjson_val* value) {
    if (!value || yyjson_is_null(value)) {
        return std::nullopt;
    }
    if (!yyjson_is_str(value)) {
        throw_corrupted_state();
    }
    return std::string(yyjson_get_str(value), yyjson_get_len(value));
}

std::string required_json_string(yyjson_val* object, const char* key) {
    const auto value = optional_json_string(yyjson_obj_get(object, key));
    if (!value) {
        throw_corrupted_state();
    }
    return *value;
}

std::optional<double> optional_json_number(yyjson_val* value) {
    if (!value || yyjson_is_null(value)) {
        return std::nullopt;
    }
    if (!yyjson_is_num(value)) {
        throw_corrupted_state();
    }
    const auto number = yyjson_get_num(value);
    if (!std::isfinite(number)) {
        throw_corrupted_state();
    }
    return number;
}

AIProgressTask decode_task(const void* bytes, std::size_t size) {
    if (!bytes || size == 0) {
        throw_corrupted_state();
    }
    ImmutableDocument document(
        yyjson_read(static_cast<const char*>(bytes), size, YYJSON_READ_NOFLAG),
        yyjson_doc_free);
    auto* root = document ? yyjson_doc_get_root(document.get()) : nullptr;
    if (!yyjson_is_obj(root)) {
        throw_corrupted_state();
    }

    const auto provider_text = required_json_string(root, "provider");
    const auto provider = parse_ai_provider(provider_text);
    const auto status_text = required_json_string(root, "status");
    const auto status = parse_ai_progress_status(status_text);
    const auto updated_at = optional_json_number(yyjson_obj_get(root, "updatedAt"));
    if (!provider || !status || !updated_at) {
        throw_corrupted_state();
    }

    AIProgressTask task{
        .id = required_json_string(root, "id"),
        .provider = *provider,
        .title = required_json_string(root, "title"),
        .detail = optional_json_string(yyjson_obj_get(root, "detail")),
        .progress = optional_json_number(yyjson_obj_get(root, "progress")),
        .status = *status,
        .updated_at_unix_ms = unix_ms(*updated_at),
        .session_uri = optional_json_string(yyjson_obj_get(root, "sessionURL")),
        .effort = optional_json_string(yyjson_obj_get(root, "effort")),
    };
    if (const auto started_at = optional_json_number(yyjson_obj_get(root, "startedAt"))) {
        task.started_at_unix_ms = unix_ms(*started_at);
    }
    return task;
}

IslandNotice decode_notice(const void* bytes, std::size_t size) {
    if (!bytes || size == 0) {
        throw_corrupted_state();
    }
    ImmutableDocument document(
        yyjson_read(static_cast<const char*>(bytes), size, YYJSON_READ_NOFLAG),
        yyjson_doc_free);
    auto* root = document ? yyjson_doc_get_root(document.get()) : nullptr;
    if (!yyjson_is_obj(root)) {
        throw_corrupted_state();
    }

    const auto kind_text = required_json_string(root, "kind");
    const auto kind = parse_notice_kind(kind_text);
    const auto side_text = required_json_string(root, "side");
    const auto side = parse_notice_side(side_text);
    const auto created_at = optional_json_number(yyjson_obj_get(root, "createdAt"));
    if (!kind || !side || !created_at) {
        throw_corrupted_state();
    }

    NoticeStyle style = NoticeStyle::standard;
    if (const auto style_text = optional_json_string(yyjson_obj_get(root, "style"))) {
        const auto parsed = parse_notice_style(*style_text);
        if (!parsed) {
            throw_corrupted_state();
        }
        style = *parsed;
    }

    return {
        .id = required_json_string(root, "id"),
        .title = required_json_string(root, "title"),
        .detail = optional_json_string(yyjson_obj_get(root, "detail")),
        .kind = *kind,
        .side = *side,
        .created_at_unix_ms = unix_ms(*created_at),
        .progress = optional_json_number(yyjson_obj_get(root, "progress")),
        .style = style,
        .app_name = optional_json_string(yyjson_obj_get(root, "appName")),
        .app_bundle_identifier = optional_json_string(
            yyjson_obj_get(root, "appBundleIdentifier")),
        .symbol_name = optional_json_string(yyjson_obj_get(root, "symbolName")),
    };
}

class Statement {
public:
    Statement(sqlite3* connection, const char* sql) {
        if (sqlite3_prepare_v2(connection, sql, -1, &value_, nullptr) != SQLITE_OK) {
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(connection));
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
    explicit Database(const AIStateRepository& repository) {
        std::error_code directory_error;
        std::filesystem::create_directories(repository.directory(), directory_error);
        if (directory_error) {
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
                directory_error.message());
        }

        const auto path = path_as_utf8(repository.database_path());
        sqlite3* opened = nullptr;
        const auto result = sqlite3_open_v2(
            path.c_str(),
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr);
        connection_ = opened;
        if (result != SQLITE_OK || !connection_) {
            const std::string message = connection_
                ? sqlite3_errmsg(connection_)
                : "Unable to open AI state database";
            close();
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
                message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw AIStateRepositoryError(
                    AIStateRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(connection_));
            }
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            execute(
                "CREATE TABLE IF NOT EXISTS tasks ("
                "position INTEGER PRIMARY KEY AUTOINCREMENT,"
                "id TEXT UNIQUE NOT NULL,"
                "payload BLOB NOT NULL)");
            execute(
                "CREATE TABLE IF NOT EXISTS usage_samples ("
                "position INTEGER PRIMARY KEY AUTOINCREMENT,"
                "source_id TEXT UNIQUE,"
                "provider TEXT NOT NULL,"
                "timestamp REAL NOT NULL,"
                "input_tokens INTEGER NOT NULL,"
                "output_tokens INTEGER NOT NULL,"
                "cost_usd REAL,"
                "model TEXT)");
            execute(
                "CREATE INDEX IF NOT EXISTS usage_samples_timestamp "
                "ON usage_samples(timestamp)");
            execute(
                "CREATE TABLE IF NOT EXISTS notices ("
                "position INTEGER PRIMARY KEY AUTOINCREMENT,"
                "payload BLOB NOT NULL)");
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
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
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

void bind_text(sqlite3* connection, sqlite3_stmt* statement, int index, std::string_view value) {
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || sqlite3_bind_text(
            statement,
            index,
            value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void bind_blob(sqlite3* connection, sqlite3_stmt* statement, int index, std::string_view value) {
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || sqlite3_bind_blob(
            statement,
            index,
            value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void bind_optional_text(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    const std::optional<std::string>& value) {
    if (value) {
        bind_text(connection, statement, index, *value);
    } else if (sqlite3_bind_null(statement, index) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void bind_optional_double(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    const std::optional<double>& value) {
    const auto result = value
        ? sqlite3_bind_double(statement, index, *value)
        : sqlite3_bind_null(statement, index);
    if (result != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

std::int64_t sqlite_token_count(std::uint64_t value) {
    if (value > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            "AI usage token count exceeds SQLite INTEGER range");
    }
    return static_cast<std::int64_t>(value);
}

void bind_usage(
    sqlite3* connection,
    sqlite3_stmt* statement,
    const AIUsageSample& sample) {
    bind_optional_text(connection, statement, 1, sample.source_id);
    bind_text(connection, statement, 2, ai_provider_token(sample.provider));
    if (sqlite3_bind_double(
            statement, 3, reference_seconds(sample.timestamp_unix_ms)) != SQLITE_OK
        || sqlite3_bind_int64(
            statement, 4, sqlite_token_count(sample.input_tokens)) != SQLITE_OK
        || sqlite3_bind_int64(
            statement, 5, sqlite_token_count(sample.output_tokens)) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
    bind_optional_double(connection, statement, 6, sample.cost_usd);
    bind_optional_text(connection, statement, 7, sample.model);
}

void bind_usage_update(
    sqlite3* connection,
    sqlite3_stmt* statement,
    const AIUsageSample& sample) {
    bind_text(connection, statement, 1, ai_provider_token(sample.provider));
    if (sqlite3_bind_double(
            statement, 2, reference_seconds(sample.timestamp_unix_ms)) != SQLITE_OK
        || sqlite3_bind_int64(
            statement, 3, sqlite_token_count(sample.input_tokens)) != SQLITE_OK
        || sqlite3_bind_int64(
            statement, 4, sqlite_token_count(sample.output_tokens)) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
    bind_optional_double(connection, statement, 5, sample.cost_usd);
    bind_optional_text(connection, statement, 6, sample.model);
    bind_optional_text(connection, statement, 7, sample.source_id);
}

std::optional<std::string> optional_column_text(sqlite3_stmt* statement, int column) {
    if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
        return std::nullopt;
    }
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw_corrupted_state();
    }
    return std::string(
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size));
}

AIUsageSample usage_sample(
    sqlite3_stmt* statement,
    std::optional<std::string> source_id,
    int column_offset) {
    const auto provider_text = optional_column_text(statement, column_offset);
    const auto provider = provider_text
        ? parse_ai_provider(*provider_text)
        : std::nullopt;
    const auto input = sqlite3_column_int64(statement, column_offset + 2);
    const auto output = sqlite3_column_int64(statement, column_offset + 3);
    if (!provider || input < 0 || output < 0) {
        throw_corrupted_state();
    }

    AIUsageSample sample{
        .source_id = std::move(source_id),
        .provider = *provider,
        .timestamp_unix_ms = unix_ms(
            sqlite3_column_double(statement, column_offset + 1)),
        .input_tokens = static_cast<std::uint64_t>(input),
        .output_tokens = static_cast<std::uint64_t>(output),
    };
    if (sqlite3_column_type(statement, column_offset + 4) != SQLITE_NULL) {
        sample.cost_usd = sqlite3_column_double(statement, column_offset + 4);
    }
    sample.model = optional_column_text(statement, column_offset + 5);
    return sample;
}

void reset_statement(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_reset(statement) != SQLITE_OK
        || sqlite3_clear_bindings(statement) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

std::vector<IslandNotice> read_notices(sqlite3* connection) {
    Statement statement(
        connection,
        "SELECT payload FROM notices ORDER BY position");
    std::vector<IslandNotice> notices;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(connection));
        }
        const auto size = sqlite3_column_bytes(statement.get(), 0);
        const auto* bytes = sqlite3_column_blob(statement.get(), 0);
        notices.push_back(decode_notice(
            bytes,
            size > 0 ? static_cast<std::size_t>(size) : 0));
    }
    return notices;
}

void trim_usage_if_needed(
    Database& database,
    std::size_t maximum_usage_samples) {
    Statement count(database.get(), "SELECT COUNT(*) FROM usage_samples");
    const auto count_result = sqlite3_step(count.get());
    if (count_result != SQLITE_ROW) {
        if (count_result == SQLITE_DONE) {
            return;
        }
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(database.get()));
    }
    if (sqlite3_column_int64(count.get(), 0)
        <= static_cast<sqlite3_int64>(maximum_usage_samples)) {
        return;
    }

    Statement trim(
        database.get(),
        "DELETE FROM usage_samples WHERE position NOT IN ("
        "SELECT position FROM usage_samples "
        "ORDER BY timestamp DESC, position DESC LIMIT ?)");
    if (maximum_usage_samples
            > static_cast<std::size_t>(std::numeric_limits<sqlite3_int64>::max())
        || sqlite3_bind_int64(
            trim.get(),
            1,
            static_cast<sqlite3_int64>(maximum_usage_samples)) != SQLITE_OK) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(database.get()));
    }
    step_done(database.get(), trim.get());
}

}  // namespace

AIStateRepositoryError::AIStateRepositoryError(
    AIStateRepositoryErrorCode code,
    std::string message,
    std::string subject)
    : std::runtime_error(std::move(message)),
      code_(code),
      subject_(std::move(subject)) {}

AIStateRepositoryErrorCode AIStateRepositoryError::code() const noexcept {
    return code_;
}

const std::string& AIStateRepositoryError::subject() const noexcept {
    return subject_;
}

AIStateRepository::AIStateRepository(
    std::filesystem::path directory,
    std::size_t maximum_usage_samples)
    : directory_(std::move(directory)),
      maximum_usage_samples_(std::max<std::size_t>(1, maximum_usage_samples)) {}

const std::filesystem::path& AIStateRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path AIStateRepository::database_path() const {
    return directory_ / "ai-state.sqlite";
}

AIStateStorageChangeToken AIStateRepository::storage_change_token() const noexcept {
    const auto database = file_version(database_path());
    auto wal_path = database_path();
    wal_path += "-wal";
    const auto wal = file_version(wal_path);
    return {
        .database_modification_time = database.first,
        .database_size = database.second,
        .wal_modification_time = wal.first,
        .wal_size = wal.second,
    };
}

AIState AIStateRepository::load(bool include_usage_samples) const {
    Database database(*this);
    trim_usage_if_needed(database, maximum_usage_samples_);
    Statement statement(
        database.get(),
        "SELECT payload FROM tasks ORDER BY position");

    AIState state;
    while (true) {
        const auto result = sqlite3_step(statement.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIStateRepositoryError(
                AIStateRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        const auto size = sqlite3_column_bytes(statement.get(), 0);
        const auto* bytes = sqlite3_column_blob(statement.get(), 0);
        state.tasks.push_back(decode_task(
            bytes,
            size > 0 ? static_cast<std::size_t>(size) : 0));
    }

    if (include_usage_samples) {
        Statement usage(
            database.get(),
            "SELECT source_id, provider, timestamp, input_tokens, "
            "output_tokens, cost_usd, model FROM usage_samples ORDER BY position");
        while (true) {
            const auto result = sqlite3_step(usage.get());
            if (result == SQLITE_DONE) {
                break;
            }
            if (result != SQLITE_ROW) {
                throw AIStateRepositoryError(
                    AIStateRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(database.get()));
            }
            state.usage_samples.push_back(usage_sample(
                usage.get(),
                optional_column_text(usage.get(), 0),
                1));
        }
    }

    state.notices = read_notices(database.get());
    return state;
}

void AIStateRepository::upsert(const AIProgressTask& task) const {
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO tasks(id, payload) VALUES(?, ?) "
        "ON CONFLICT(id) DO UPDATE SET payload = excluded.payload");
    const auto payload = encode_task(task);
    bind_text(database.get(), statement.get(), 1, task.id);
    bind_blob(database.get(), statement.get(), 2, payload);
    step_done(database.get(), statement.get());
}

void AIStateRepository::finish(
    std::string_view id,
    bool failed,
    std::optional<std::string> detail,
    std::int64_t at_unix_ms) const {
    auto state = load(false);
    const auto existing = std::find_if(
        state.tasks.begin(),
        state.tasks.end(),
        [id](const AIProgressTask& task) {
            return task.id == id;
        });
    if (existing == state.tasks.end()) {
        throw AIStateRepositoryError(
            AIStateRepositoryErrorCode::task_not_found,
            "AI task not found: " + std::string(id),
            std::string(id));
    }

    existing->status = failed
        ? AIProgressStatus::failed
        : AIProgressStatus::succeeded;
    if (!failed) {
        existing->progress = 1.0;
    }
    if (detail) {
        existing->detail = std::move(detail);
    }
    existing->updated_at_unix_ms = at_unix_ms;
    upsert(*existing);
}

bool AIStateRepository::remove(std::string_view id) const {
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM tasks WHERE id = ?");
    bind_text(database.get(), statement.get(), 1, id);
    step_done(database.get(), statement.get());
    return sqlite3_changes64(database.get()) > 0;
}

void AIStateRepository::clear_tasks() const {
    Database database(*this);
    database.execute("DELETE FROM tasks");
}

bool AIStateRepository::record_usage(const AIUsageSample& sample) const {
    return record_usage(std::span<const AIUsageSample>(&sample, 1)) > 0;
}

std::size_t AIStateRepository::record_usage(
    std::span<const AIUsageSample> samples) const {
    if (samples.empty()) {
        return 0;
    }

    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement lookup(
            database.get(),
            "SELECT provider, timestamp, input_tokens, output_tokens, cost_usd, model "
            "FROM usage_samples WHERE source_id = ? LIMIT 1");
        Statement insert(
            database.get(),
            "INSERT INTO usage_samples("
            "source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model"
            ") VALUES(?, ?, ?, ?, ?, ?, ?)");
        Statement update(
            database.get(),
            "UPDATE usage_samples SET provider = ?, timestamp = ?, input_tokens = ?, "
            "output_tokens = ?, cost_usd = ?, model = ? WHERE source_id = ?");

        std::size_t inserted = 0;
        for (const auto& sample : samples) {
            if (sample.source_id) {
                reset_statement(database.get(), lookup.get());
                bind_text(database.get(), lookup.get(), 1, *sample.source_id);
                const auto result = sqlite3_step(lookup.get());
                if (result == SQLITE_ROW) {
                    const auto existing = usage_sample(
                        lookup.get(),
                        sample.source_id,
                        0);
                    if (existing == sample) {
                        continue;
                    }
                    reset_statement(database.get(), update.get());
                    bind_usage_update(database.get(), update.get(), sample);
                    step_done(database.get(), update.get());
                    continue;
                }
                if (result != SQLITE_DONE) {
                    throw AIStateRepositoryError(
                        AIStateRepositoryErrorCode::storage_failure,
                        sqlite3_errmsg(database.get()));
                }
            }

            reset_statement(database.get(), insert.get());
            bind_usage(database.get(), insert.get(), sample);
            step_done(database.get(), insert.get());
            ++inserted;
        }
        trim_usage_if_needed(database, maximum_usage_samples_);
        database.execute("COMMIT");
        return inserted;
    } catch (...) {
        try {
            database.execute("ROLLBACK");
        } catch (...) {
        }
        throw;
    }
}

void AIStateRepository::enqueue_notice(const IslandNotice& notice) const {
    enqueue_notices(std::span<const IslandNotice>(&notice, 1));
}

void AIStateRepository::enqueue_notices(
    std::span<const IslandNotice> notices) const {
    if (notices.empty()) {
        return;
    }

    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement statement(
            database.get(),
            "INSERT INTO notices(payload) VALUES(?)");
        for (const auto& notice : notices) {
            reset_statement(database.get(), statement.get());
            const auto payload = encode_notice(notice);
            bind_blob(database.get(), statement.get(), 1, payload);
            step_done(database.get(), statement.get());
        }
        database.execute("COMMIT");
    } catch (...) {
        try {
            database.execute("ROLLBACK");
        } catch (...) {
        }
        throw;
    }
}

std::vector<IslandNotice> AIStateRepository::take_notices() const {
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        auto notices = read_notices(database.get());
        database.execute("DELETE FROM notices");
        database.execute("COMMIT");
        return notices;
    } catch (...) {
        try {
            database.execute("ROLLBACK");
        } catch (...) {
        }
        throw;
    }
}

}  // namespace zisla::core
