#include "zisla/core/AIAgentWorkspaceRepository.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace zisla::core {
namespace {

constexpr std::size_t maximum_identifier_bytes = 512;

[[noreturn]] void throw_corrupted_state(std::string subject = {}) {
    throw AIAgentWorkspaceRepositoryError(
        AIAgentWorkspaceRepositoryErrorCode::corrupted_state,
        "AI Agent workspace state contains invalid data",
        std::move(subject));
}

[[noreturn]] void throw_invalid_value(std::string message, std::string subject) {
    throw AIAgentWorkspaceRepositoryError(
        AIAgentWorkspaceRepositoryErrorCode::invalid_value,
        std::move(message),
        std::move(subject));
}

bool is_ascii_whitespace(unsigned char value) noexcept {
    return value == ' '
        || value == '\t'
        || value == '\n'
        || value == '\r'
        || value == '\f'
        || value == '\v';
}

std::string trim_ascii(std::string_view value) {
    std::size_t first = 0;
    while (first < value.size()
        && is_ascii_whitespace(static_cast<unsigned char>(value[first]))) {
        ++first;
    }
    std::size_t last = value.size();
    while (last > first
        && is_ascii_whitespace(static_cast<unsigned char>(value[last - 1]))) {
        --last;
    }
    return std::string(value.substr(first, last - first));
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
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
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
    explicit Database(const AIAgentWorkspaceRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                error.message());
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
                : "Unable to open AI Agent workspace database";
            close();
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw AIAgentWorkspaceRepositoryError(
                    AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(connection_));
            }
            execute("PRAGMA foreign_keys=ON");
            execute("PRAGMA journal_mode=WAL");
            execute("PRAGMA synchronous=NORMAL");
            create_schema();
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
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
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
    void create_schema() {
        execute(
            "CREATE TABLE IF NOT EXISTS agent_workspace_projects ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "name TEXT NOT NULL,"
            "instructions TEXT NOT NULL,"
            "directory_path TEXT NOT NULL,"
            "is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),"
            "is_collapsed INTEGER NOT NULL CHECK(is_collapsed IN (0, 1)),"
            "created_at_unix_ms INTEGER NOT NULL,"
            "updated_at_unix_ms INTEGER NOT NULL)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_workspace_goals ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "title TEXT NOT NULL,"
            "status TEXT NOT NULL CHECK(status IN ('active', 'completed', 'abandoned')),"
            "created_at_unix_ms INTEGER NOT NULL,"
            "updated_at_unix_ms INTEGER NOT NULL)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_workspace_threads ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "title TEXT NOT NULL,"
            "channel_id TEXT,"
            "local_model_id TEXT,"
            "cli_kind TEXT,"
            "account_id TEXT,"
            "external_history_id TEXT,"
            "mode TEXT NOT NULL CHECK(mode IN ('standard', 'plan')),"
            "goal_id TEXT REFERENCES agent_workspace_goals(id) ON DELETE SET NULL,"
            "goal_prompt TEXT,"
            "project_id TEXT REFERENCES agent_workspace_projects(id) ON DELETE SET NULL,"
            "access_mode TEXT NOT NULL CHECK(access_mode IN "
            "('auto-review', 'read-only', 'workspace-write', 'full-access')),"
            "selected_model TEXT,"
            "thinking_depth TEXT NOT NULL CHECK(thinking_depth IN "
            "('low', 'medium', 'high', 'extra-high')),"
            "is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),"
            "archived_at_unix_ms INTEGER,"
            "created_at_unix_ms INTEGER NOT NULL,"
            "updated_at_unix_ms INTEGER NOT NULL)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_workspace_messages ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "thread_id TEXT NOT NULL REFERENCES agent_workspace_threads(id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL,"
            "role TEXT NOT NULL CHECK(role IN ('system', 'user', 'assistant')),"
            "content TEXT NOT NULL,"
            "account_id TEXT,"
            "mode TEXT NOT NULL CHECK(mode IN ('standard', 'plan')),"
            "goal_title TEXT,"
            "created_at_unix_ms INTEGER NOT NULL,"
            "UNIQUE(thread_id, position))");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_workspace_message_skills ("
            "message_id TEXT NOT NULL REFERENCES agent_workspace_messages(id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL,"
            "name TEXT NOT NULL,"
            "path TEXT NOT NULL,"
            "PRIMARY KEY(message_id, position))");
        execute(
            "CREATE INDEX IF NOT EXISTS agent_workspace_threads_order_idx "
            "ON agent_workspace_threads(is_pinned DESC, updated_at_unix_ms DESC)");
        execute(
            "CREATE INDEX IF NOT EXISTS agent_workspace_messages_thread_idx "
            "ON agent_workspace_messages(thread_id, position)");
    }

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
        throw AIAgentWorkspaceRepositoryError(
            AIAgentWorkspaceRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void bind_optional_text(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    const std::optional<std::string>& value) {
    if (!value) {
        if (sqlite3_bind_null(statement, index) != SQLITE_OK) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(connection));
        }
        return;
    }
    bind_text(connection, statement, index, *value);
}

void bind_int64(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::int64_t value) {
    if (sqlite3_bind_int64(statement, index, value) != SQLITE_OK) {
        throw AIAgentWorkspaceRepositoryError(
            AIAgentWorkspaceRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
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
        throw AIAgentWorkspaceRepositoryError(
            AIAgentWorkspaceRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw AIAgentWorkspaceRepositoryError(
            AIAgentWorkspaceRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column, std::string subject) {
    if (sqlite3_column_type(statement, column) != SQLITE_TEXT) {
        throw_corrupted_state(std::move(subject));
    }
    const auto* value = sqlite3_column_text(statement, column);
    const auto size = sqlite3_column_bytes(statement, column);
    if (!value || size < 0) {
        throw_corrupted_state(std::move(subject));
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(size),
    };
}

std::optional<std::string> optional_column_text(
    sqlite3_stmt* statement,
    int column,
    std::string subject) {
    if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
        return std::nullopt;
    }
    return column_text(statement, column, std::move(subject));
}

std::int64_t column_int64(sqlite3_stmt* statement, int column, std::string subject) {
    if (sqlite3_column_type(statement, column) != SQLITE_INTEGER) {
        throw_corrupted_state(std::move(subject));
    }
    return sqlite3_column_int64(statement, column);
}

std::optional<std::int64_t> optional_column_int64(
    sqlite3_stmt* statement,
    int column,
    std::string subject) {
    if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
        return std::nullopt;
    }
    return column_int64(statement, column, std::move(subject));
}

bool column_bool(sqlite3_stmt* statement, int column, std::string subject) {
    const auto value = column_int64(statement, column, std::move(subject));
    if (value != 0 && value != 1) {
        throw_corrupted_state("boolean value");
    }
    return value != 0;
}

void validate_identifier(std::string_view value, std::string_view subject) {
    if (value.empty() || value.size() > maximum_identifier_bytes) {
        throw_invalid_value(
            "AI Agent workspace identifier is invalid",
            std::string(subject));
    }
}

std::string normalized_title(std::string value, std::string_view subject) {
    value = trim_ascii(value);
    if (value.empty() || value.size() > AIAgentWorkspaceRepository::maximum_title_bytes) {
        throw_invalid_value("AI Agent workspace title is invalid", std::string(subject));
    }
    return value;
}

std::string normalized_instruction(std::string value, std::string_view subject) {
    value = trim_ascii(value);
    if (value.size() > AIAgentWorkspaceRepository::maximum_instruction_bytes) {
        throw_invalid_value("AI Agent workspace text is too large", std::string(subject));
    }
    return value;
}

std::optional<std::string> normalized_optional_identifier(
    std::optional<std::string> value,
    std::string_view subject) {
    if (!value) {
        return std::nullopt;
    }
    *value = trim_ascii(*value);
    if (value->empty()) {
        return std::nullopt;
    }
    validate_identifier(*value, subject);
    return value;
}

std::optional<std::string> normalized_optional_title(
    std::optional<std::string> value,
    std::string_view subject) {
    if (!value) {
        return std::nullopt;
    }
    *value = trim_ascii(*value);
    if (value->empty()) {
        return std::nullopt;
    }
    if (value->size() > AIAgentWorkspaceRepository::maximum_title_bytes) {
        throw_invalid_value("AI Agent workspace title is too large", std::string(subject));
    }
    return value;
}

std::optional<std::string> normalized_optional_prompt(
    std::optional<std::string> value,
    std::string_view subject) {
    if (!value) {
        return std::nullopt;
    }
    *value = trim_ascii(*value);
    if (value->size() > AIAgentWorkspaceRepository::maximum_message_bytes) {
        throw_invalid_value("AI Agent workspace prompt is too large", std::string(subject));
    }
    return value;
}

void validate_skill_references(std::vector<AgentWorkspaceSkillReference>& references) {
    if (references.size() > AIAgentWorkspaceRepository::maximum_skill_references_per_message) {
        throw_invalid_value("Too many AI Agent Skill references", "skill references");
    }
    std::vector<AgentWorkspaceSkillReference> normalized;
    normalized.reserve(references.size());
    for (auto& reference : references) {
        reference.name = normalized_title(std::move(reference.name), "Skill name");
        reference.path = trim_ascii(reference.path);
        if (reference.path.empty()
            || reference.path.size() > AIAgentWorkspaceRepository::maximum_instruction_bytes) {
            throw_invalid_value("AI Agent Skill path is invalid", "Skill path");
        }
        if (std::find(normalized.begin(), normalized.end(), reference) == normalized.end()) {
            normalized.push_back(std::move(reference));
        }
    }
    references = std::move(normalized);
}

void normalize_project(AgentWorkspaceProject& project) {
    validate_identifier(project.id, "project id");
    project.name = normalized_title(std::move(project.name), "project name");
    project.instructions = normalized_instruction(
        std::move(project.instructions), "project instructions");
    project.directory_path = trim_ascii(project.directory_path);
    if (project.directory_path.size()
        > AIAgentWorkspaceRepository::maximum_instruction_bytes) {
        throw_invalid_value("AI Agent workspace directory path is too large", "directory path");
    }
}

void normalize_goal(AgentWorkspaceGoal& goal) {
    validate_identifier(goal.id, "goal id");
    goal.title = normalized_title(std::move(goal.title), "goal title");
    if (agent_workspace_goal_status_token(goal.status).empty()) {
        throw_invalid_value("AI Agent workspace goal status is invalid", "goal status");
    }
}

void normalize_thread(AgentWorkspaceThread& thread) {
    validate_identifier(thread.id, "thread id");
    thread.title = normalized_title(std::move(thread.title), "thread title");
    thread.channel_id = normalized_optional_identifier(
        std::move(thread.channel_id), "channel id");
    thread.local_model_id = normalized_optional_identifier(
        std::move(thread.local_model_id), "local model id");
    thread.account_id = normalized_optional_identifier(
        std::move(thread.account_id), "account id");
    thread.external_history_id = normalized_optional_identifier(
        std::move(thread.external_history_id), "external history id");
    thread.goal_id = normalized_optional_identifier(std::move(thread.goal_id), "goal id");
    thread.project_id = normalized_optional_identifier(
        std::move(thread.project_id), "project id");
    thread.goal_prompt = normalized_optional_prompt(
        std::move(thread.goal_prompt), "goal prompt");
    thread.selected_model = normalized_optional_title(
        std::move(thread.selected_model), "selected model");
    if (agent_workspace_chat_mode_token(thread.mode).empty()
        || agent_workspace_access_mode_token(thread.access_mode).empty()
        || agent_workspace_thinking_depth_token(thread.thinking_depth).empty()
        || (thread.cli_kind && agent_cli_kind_token(*thread.cli_kind).empty())) {
        throw_invalid_value("AI Agent workspace thread enum is invalid", "thread enum");
    }
}

void normalize_message(AgentWorkspaceMessage& message) {
    validate_identifier(message.id, "message id");
    validate_identifier(message.thread_id, "message thread id");
    if (message.content.size() > AIAgentWorkspaceRepository::maximum_message_bytes) {
        throw_invalid_value("AI Agent message is too large", "message content");
    }
    message.account_id = normalized_optional_identifier(
        std::move(message.account_id), "message account id");
    message.goal_title = normalized_optional_title(
        std::move(message.goal_title), "message goal title");
    validate_skill_references(message.skill_references);
    if (agent_workspace_message_role_token(message.role).empty()
        || agent_workspace_chat_mode_token(message.mode).empty()) {
        throw_invalid_value("AI Agent workspace message enum is invalid", "message enum");
    }
}

bool record_exists(Database& database, const char* table, std::string_view id) {
    const std::string sql = "SELECT 1 FROM " + std::string(table) + " WHERE id = ? LIMIT 1";
    Statement statement(database.get(), sql.c_str());
    bind_text(database.get(), statement.get(), 1, id);
    const auto result = sqlite3_step(statement.get());
    if (result == SQLITE_ROW) {
        return true;
    }
    if (result == SQLITE_DONE) {
        return false;
    }
    throw AIAgentWorkspaceRepositoryError(
        AIAgentWorkspaceRepositoryErrorCode::storage_failure,
        sqlite3_errmsg(database.get()));
}

void require_existing_reference(
    Database& database,
    const std::optional<std::string>& id,
    const char* table,
    std::string_view subject) {
    if (id && !record_exists(database, table, *id)) {
        throw_invalid_value("AI Agent workspace reference does not exist", std::string(subject));
    }
}

AgentWorkspaceProject read_project(sqlite3_stmt* statement) {
    AgentWorkspaceProject project{
        .id = column_text(statement, 0, "project id"),
        .name = column_text(statement, 1, "project name"),
        .instructions = column_text(statement, 2, "project instructions"),
        .directory_path = column_text(statement, 3, "project directory path"),
        .is_pinned = column_bool(statement, 4, "project pinned"),
        .is_collapsed = column_bool(statement, 5, "project collapsed"),
        .created_at_unix_ms = column_int64(statement, 6, "project created time"),
        .updated_at_unix_ms = column_int64(statement, 7, "project updated time"),
    };
    try {
        normalize_project(project);
    } catch (const AIAgentWorkspaceRepositoryError&) {
        throw_corrupted_state("project");
    }
    return project;
}

AgentWorkspaceGoal read_goal(sqlite3_stmt* statement) {
    const auto status = parse_agent_workspace_goal_status(
        column_text(statement, 2, "goal status"));
    if (!status) {
        throw_corrupted_state("goal status");
    }
    AgentWorkspaceGoal goal{
        .id = column_text(statement, 0, "goal id"),
        .title = column_text(statement, 1, "goal title"),
        .status = *status,
        .created_at_unix_ms = column_int64(statement, 3, "goal created time"),
        .updated_at_unix_ms = column_int64(statement, 4, "goal updated time"),
    };
    try {
        normalize_goal(goal);
    } catch (const AIAgentWorkspaceRepositoryError&) {
        throw_corrupted_state("goal");
    }
    return goal;
}

AgentWorkspaceThread read_thread(sqlite3_stmt* statement) {
    const auto cli_kind_token = optional_column_text(statement, 4, "thread CLI kind");
    const auto cli_kind = cli_kind_token
        ? parse_agent_cli_kind(*cli_kind_token)
        : std::optional<AgentCLIKind>{};
    const auto mode = parse_agent_workspace_chat_mode(
        column_text(statement, 7, "thread mode"));
    const auto access_mode = parse_agent_workspace_access_mode(
        column_text(statement, 11, "thread access mode"));
    const auto thinking_depth = parse_agent_workspace_thinking_depth(
        column_text(statement, 13, "thread thinking depth"));
    if ((cli_kind_token && !cli_kind) || !mode || !access_mode || !thinking_depth) {
        throw_corrupted_state("thread enum");
    }
    AgentWorkspaceThread thread{
        .id = column_text(statement, 0, "thread id"),
        .title = column_text(statement, 1, "thread title"),
        .channel_id = optional_column_text(statement, 2, "thread channel id"),
        .local_model_id = optional_column_text(statement, 3, "thread local model id"),
        .cli_kind = cli_kind,
        .account_id = optional_column_text(statement, 5, "thread account id"),
        .external_history_id = optional_column_text(statement, 6, "thread external history id"),
        .mode = *mode,
        .goal_id = optional_column_text(statement, 8, "thread goal id"),
        .goal_prompt = optional_column_text(statement, 9, "thread goal prompt"),
        .project_id = optional_column_text(statement, 10, "thread project id"),
        .access_mode = *access_mode,
        .selected_model = optional_column_text(statement, 12, "thread selected model"),
        .thinking_depth = *thinking_depth,
        .is_pinned = column_bool(statement, 14, "thread pinned"),
        .archived_at_unix_ms = optional_column_int64(statement, 15, "thread archive time"),
        .created_at_unix_ms = column_int64(statement, 16, "thread created time"),
        .updated_at_unix_ms = column_int64(statement, 17, "thread updated time"),
    };
    try {
        normalize_thread(thread);
    } catch (const AIAgentWorkspaceRepositoryError&) {
        throw_corrupted_state("thread");
    }
    return thread;
}

AgentWorkspaceMessage read_message(sqlite3_stmt* statement) {
    const auto role = parse_agent_workspace_message_role(
        column_text(statement, 2, "message role"));
    const auto mode = parse_agent_workspace_chat_mode(
        column_text(statement, 5, "message mode"));
    if (!role || !mode) {
        throw_corrupted_state("message enum");
    }
    AgentWorkspaceMessage message{
        .id = column_text(statement, 0, "message id"),
        .thread_id = column_text(statement, 1, "message thread id"),
        .role = *role,
        .content = column_text(statement, 3, "message content"),
        .account_id = optional_column_text(statement, 4, "message account id"),
        .mode = *mode,
        .goal_title = optional_column_text(statement, 6, "message goal title"),
        .created_at_unix_ms = column_int64(statement, 7, "message created time"),
    };
    try {
        normalize_message(message);
    } catch (const AIAgentWorkspaceRepositoryError&) {
        throw_corrupted_state("message");
    }
    return message;
}

}  // namespace

AIAgentWorkspaceRepositoryError::AIAgentWorkspaceRepositoryError(
    AIAgentWorkspaceRepositoryErrorCode code,
    std::string message,
    std::string subject)
    : std::runtime_error(std::move(message)),
      code_(code),
      subject_(std::move(subject)) {}

AIAgentWorkspaceRepositoryErrorCode
AIAgentWorkspaceRepositoryError::code() const noexcept {
    return code_;
}

const std::string& AIAgentWorkspaceRepositoryError::subject() const noexcept {
    return subject_;
}

AIAgentWorkspaceRepository::AIAgentWorkspaceRepository(std::filesystem::path directory)
    : directory_(std::move(directory)) {}

const std::filesystem::path& AIAgentWorkspaceRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path AIAgentWorkspaceRepository::database_path() const {
    return directory_ / "ai-agent-workspace.sqlite";
}

AIAgentWorkspaceState AIAgentWorkspaceRepository::load() const {
    Database database(*this);
    AIAgentWorkspaceState state;

    {
        Statement statement(
            database.get(),
            "SELECT id, name, instructions, directory_path, is_pinned, is_collapsed, "
            "created_at_unix_ms, updated_at_unix_ms "
            "FROM agent_workspace_projects "
            "ORDER BY is_pinned DESC, updated_at_unix_ms DESC, id ASC");
        int result = SQLITE_OK;
        while ((result = sqlite3_step(statement.get())) == SQLITE_ROW) {
            state.projects.push_back(read_project(statement.get()));
        }
        if (result != SQLITE_DONE) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
    }
    {
        Statement statement(
            database.get(),
            "SELECT id, title, status, created_at_unix_ms, updated_at_unix_ms "
            "FROM agent_workspace_goals "
            "ORDER BY updated_at_unix_ms DESC, id ASC");
        int result = SQLITE_OK;
        while ((result = sqlite3_step(statement.get())) == SQLITE_ROW) {
            state.goals.push_back(read_goal(statement.get()));
        }
        if (result != SQLITE_DONE) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
    }
    {
        Statement statement(
            database.get(),
            "SELECT id, title, channel_id, local_model_id, cli_kind, account_id, "
            "external_history_id, mode, goal_id, goal_prompt, project_id, access_mode, "
            "selected_model, thinking_depth, is_pinned, archived_at_unix_ms, "
            "created_at_unix_ms, updated_at_unix_ms "
            "FROM agent_workspace_threads "
            "ORDER BY is_pinned DESC, updated_at_unix_ms DESC, id ASC");
        int result = SQLITE_OK;
        while ((result = sqlite3_step(statement.get())) == SQLITE_ROW) {
            state.threads.push_back(read_thread(statement.get()));
        }
        if (result != SQLITE_DONE) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
    }

    std::unordered_set<std::string> thread_ids;
    for (const auto& thread : state.threads) {
        if (!thread_ids.emplace(thread.id).second) {
            throw_corrupted_state("duplicate thread id");
        }
    }

    std::unordered_map<std::string, std::size_t> message_indexes;
    {
        Statement statement(
            database.get(),
            "SELECT id, thread_id, role, content, account_id, mode, goal_title, "
            "created_at_unix_ms "
            "FROM agent_workspace_messages "
            "ORDER BY thread_id ASC, position ASC, id ASC");
        int result = SQLITE_OK;
        while ((result = sqlite3_step(statement.get())) == SQLITE_ROW) {
            auto message = read_message(statement.get());
            if (!thread_ids.contains(message.thread_id)) {
                throw_corrupted_state("orphaned message");
            }
            const auto index = state.messages.size();
            const auto [_, inserted] = message_indexes.emplace(message.id, index);
            if (!inserted) {
                throw_corrupted_state("duplicate message id");
            }
            state.messages.push_back(std::move(message));
        }
        if (result != SQLITE_DONE) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
    }
    {
        Statement statement(
            database.get(),
            "SELECT message_id, name, path FROM agent_workspace_message_skills "
            "ORDER BY message_id ASC, position ASC");
        int result = SQLITE_OK;
        while ((result = sqlite3_step(statement.get())) == SQLITE_ROW) {
            const auto message_id = column_text(statement.get(), 0, "Skill message id");
            const auto found = message_indexes.find(message_id);
            if (found == message_indexes.end()) {
                throw_corrupted_state("orphaned Skill reference");
            }
            auto reference = AgentWorkspaceSkillReference{
                .name = column_text(statement.get(), 1, "Skill name"),
                .path = column_text(statement.get(), 2, "Skill path"),
            };
            try {
                std::vector<AgentWorkspaceSkillReference> one_reference;
                one_reference.push_back(std::move(reference));
                validate_skill_references(one_reference);
                reference = std::move(one_reference.front());
            } catch (const AIAgentWorkspaceRepositoryError&) {
                throw_corrupted_state("Skill reference");
            }
            auto& references = state.messages[found->second].skill_references;
            if (references.size() >= maximum_skill_references_per_message
                || std::find(references.begin(), references.end(), reference) != references.end()) {
                throw_corrupted_state("duplicate Skill reference");
            }
            references.push_back(std::move(reference));
        }
        if (result != SQLITE_DONE) {
            throw AIAgentWorkspaceRepositoryError(
                AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
    }

    return state;
}

void AIAgentWorkspaceRepository::upsert_project(AgentWorkspaceProject project) const {
    normalize_project(project);
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO agent_workspace_projects("
        "id, name, instructions, directory_path, is_pinned, is_collapsed, "
        "created_at_unix_ms, updated_at_unix_ms) VALUES(?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "name=excluded.name, instructions=excluded.instructions, "
        "directory_path=excluded.directory_path, is_pinned=excluded.is_pinned, "
        "is_collapsed=excluded.is_collapsed, created_at_unix_ms=excluded.created_at_unix_ms, "
        "updated_at_unix_ms=excluded.updated_at_unix_ms");
    bind_text(database.get(), statement.get(), 1, project.id);
    bind_text(database.get(), statement.get(), 2, project.name);
    bind_text(database.get(), statement.get(), 3, project.instructions);
    bind_text(database.get(), statement.get(), 4, project.directory_path);
    bind_int64(database.get(), statement.get(), 5, project.is_pinned ? 1 : 0);
    bind_int64(database.get(), statement.get(), 6, project.is_collapsed ? 1 : 0);
    bind_int64(database.get(), statement.get(), 7, project.created_at_unix_ms);
    bind_int64(database.get(), statement.get(), 8, project.updated_at_unix_ms);
    step_done(database.get(), statement.get());
}

bool AIAgentWorkspaceRepository::remove_project(std::string_view project_id) const {
    if (project_id.empty()) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM agent_workspace_projects WHERE id = ?");
    bind_text(database.get(), statement.get(), 1, project_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

void AIAgentWorkspaceRepository::upsert_goal(AgentWorkspaceGoal goal) const {
    normalize_goal(goal);
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO agent_workspace_goals("
        "id, title, status, created_at_unix_ms, updated_at_unix_ms) VALUES(?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET title=excluded.title, status=excluded.status, "
        "created_at_unix_ms=excluded.created_at_unix_ms, "
        "updated_at_unix_ms=excluded.updated_at_unix_ms");
    bind_text(database.get(), statement.get(), 1, goal.id);
    bind_text(database.get(), statement.get(), 2, goal.title);
    bind_text(
        database.get(),
        statement.get(),
        3,
        agent_workspace_goal_status_token(goal.status));
    bind_int64(database.get(), statement.get(), 4, goal.created_at_unix_ms);
    bind_int64(database.get(), statement.get(), 5, goal.updated_at_unix_ms);
    step_done(database.get(), statement.get());
}

bool AIAgentWorkspaceRepository::remove_goal(std::string_view goal_id) const {
    if (goal_id.empty()) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM agent_workspace_goals WHERE id = ?");
    bind_text(database.get(), statement.get(), 1, goal_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

void AIAgentWorkspaceRepository::upsert_thread(AgentWorkspaceThread thread) const {
    normalize_thread(thread);
    Database database(*this);
    require_existing_reference(
        database,
        thread.goal_id,
        "agent_workspace_goals",
        "thread goal id");
    require_existing_reference(
        database,
        thread.project_id,
        "agent_workspace_projects",
        "thread project id");
    Statement statement(
        database.get(),
        "INSERT INTO agent_workspace_threads("
        "id, title, channel_id, local_model_id, cli_kind, account_id, external_history_id, "
        "mode, goal_id, goal_prompt, project_id, access_mode, selected_model, thinking_depth, "
        "is_pinned, archived_at_unix_ms, created_at_unix_ms, updated_at_unix_ms) "
        "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "title=excluded.title, channel_id=excluded.channel_id, "
        "local_model_id=excluded.local_model_id, cli_kind=excluded.cli_kind, "
        "account_id=excluded.account_id, external_history_id=excluded.external_history_id, "
        "mode=excluded.mode, goal_id=excluded.goal_id, goal_prompt=excluded.goal_prompt, "
        "project_id=excluded.project_id, access_mode=excluded.access_mode, "
        "selected_model=excluded.selected_model, thinking_depth=excluded.thinking_depth, "
        "is_pinned=excluded.is_pinned, archived_at_unix_ms=excluded.archived_at_unix_ms, "
        "created_at_unix_ms=excluded.created_at_unix_ms, "
        "updated_at_unix_ms=excluded.updated_at_unix_ms");
    bind_text(database.get(), statement.get(), 1, thread.id);
    bind_text(database.get(), statement.get(), 2, thread.title);
    bind_optional_text(database.get(), statement.get(), 3, thread.channel_id);
    bind_optional_text(database.get(), statement.get(), 4, thread.local_model_id);
    const auto cli_token = thread.cli_kind
        ? std::optional<std::string>{std::string(agent_cli_kind_token(*thread.cli_kind))}
        : std::nullopt;
    bind_optional_text(database.get(), statement.get(), 5, cli_token);
    bind_optional_text(database.get(), statement.get(), 6, thread.account_id);
    bind_optional_text(database.get(), statement.get(), 7, thread.external_history_id);
    bind_text(
        database.get(),
        statement.get(),
        8,
        agent_workspace_chat_mode_token(thread.mode));
    bind_optional_text(database.get(), statement.get(), 9, thread.goal_id);
    bind_optional_text(database.get(), statement.get(), 10, thread.goal_prompt);
    bind_optional_text(database.get(), statement.get(), 11, thread.project_id);
    bind_text(
        database.get(),
        statement.get(),
        12,
        agent_workspace_access_mode_token(thread.access_mode));
    bind_optional_text(database.get(), statement.get(), 13, thread.selected_model);
    bind_text(
        database.get(),
        statement.get(),
        14,
        agent_workspace_thinking_depth_token(thread.thinking_depth));
    bind_int64(database.get(), statement.get(), 15, thread.is_pinned ? 1 : 0);
    bind_optional_int64(database.get(), statement.get(), 16, thread.archived_at_unix_ms);
    bind_int64(database.get(), statement.get(), 17, thread.created_at_unix_ms);
    bind_int64(database.get(), statement.get(), 18, thread.updated_at_unix_ms);
    step_done(database.get(), statement.get());
}

bool AIAgentWorkspaceRepository::remove_thread(std::string_view thread_id) const {
    if (thread_id.empty()) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM agent_workspace_threads WHERE id = ?");
    bind_text(database.get(), statement.get(), 1, thread_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

void AIAgentWorkspaceRepository::append_message(AgentWorkspaceMessage message) const {
    normalize_message(message);
    Database database(*this);
    if (!record_exists(database, "agent_workspace_threads", message.thread_id)) {
        throw_invalid_value("AI Agent workspace thread does not exist", "message thread id");
    }
    database.execute("BEGIN IMMEDIATE");
    try {
        std::int64_t position = 0;
        {
            Statement select_position(
                database.get(),
                "SELECT COALESCE(MAX(position) + 1, 0) "
                "FROM agent_workspace_messages WHERE thread_id = ?");
            bind_text(database.get(), select_position.get(), 1, message.thread_id);
            if (sqlite3_step(select_position.get()) != SQLITE_ROW) {
                throw AIAgentWorkspaceRepositoryError(
                    AIAgentWorkspaceRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(database.get()));
            }
            position = column_int64(select_position.get(), 0, "message position");
        }
        {
            Statement statement(
                database.get(),
                "INSERT INTO agent_workspace_messages("
                "id, thread_id, position, role, content, account_id, mode, goal_title, "
                "created_at_unix_ms) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)");
            bind_text(database.get(), statement.get(), 1, message.id);
            bind_text(database.get(), statement.get(), 2, message.thread_id);
            bind_int64(database.get(), statement.get(), 3, position);
            bind_text(
                database.get(),
                statement.get(),
                4,
                agent_workspace_message_role_token(message.role));
            bind_text(database.get(), statement.get(), 5, message.content);
            bind_optional_text(database.get(), statement.get(), 6, message.account_id);
            bind_text(
                database.get(),
                statement.get(),
                7,
                agent_workspace_chat_mode_token(message.mode));
            bind_optional_text(database.get(), statement.get(), 8, message.goal_title);
            bind_int64(database.get(), statement.get(), 9, message.created_at_unix_ms);
            step_done(database.get(), statement.get());
        }
        for (std::size_t index = 0; index < message.skill_references.size(); ++index) {
            Statement statement(
                database.get(),
                "INSERT INTO agent_workspace_message_skills("
                "message_id, position, name, path) VALUES(?, ?, ?, ?)");
            bind_text(database.get(), statement.get(), 1, message.id);
            bind_int64(database.get(), statement.get(), 2, static_cast<std::int64_t>(index));
            bind_text(database.get(), statement.get(), 3, message.skill_references[index].name);
            bind_text(database.get(), statement.get(), 4, message.skill_references[index].path);
            step_done(database.get(), statement.get());
        }
        database.execute("COMMIT");
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool AIAgentWorkspaceRepository::remove_message(std::string_view message_id) const {
    if (message_id.empty()) {
        return false;
    }
    Database database(*this);
    Statement statement(database.get(), "DELETE FROM agent_workspace_messages WHERE id = ?");
    bind_text(database.get(), statement.get(), 1, message_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

}  // namespace zisla::core
