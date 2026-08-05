#include "zisla/core/AIAgentRoutingRepository.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <utility>

namespace zisla::core {
namespace {

[[noreturn]] void throw_corrupted_state(std::string subject = {}) {
    throw AIAgentRoutingRepositoryError(
        AIAgentRoutingRepositoryErrorCode::corrupted_state,
        "AI Agent routing state contains invalid data",
        std::move(subject));
}

void validate_identifier(std::string_view value, std::string_view field) {
    if (value.empty()) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::invalid_value,
            "AI Agent routing identifier must not be empty",
            std::string(field));
    }
}

void validate_finite(std::optional<double> value, std::string_view field) {
    if (value && !std::isfinite(*value)) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::invalid_value,
            "AI Agent routing value must be finite",
            std::string(field));
    }
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
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
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
    explicit Database(const AIAgentRoutingRepository& repository) {
        std::error_code error;
        std::filesystem::create_directories(repository.directory(), error);
        if (error) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
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
                : "Unable to open AI Agent routing database";
            close();
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                message);
        }

        try {
            if (sqlite3_busy_timeout(connection_, 1'000) != SQLITE_OK) {
                throw AIAgentRoutingRepositoryError(
                    AIAgentRoutingRepositoryErrorCode::storage_failure,
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
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
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
            "CREATE TABLE IF NOT EXISTS agent_accounts ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "name TEXT NOT NULL,"
            "provider TEXT NOT NULL,"
            "secret_reference TEXT NOT NULL,"
            "credential_kind TEXT NOT NULL,"
            "cli_kind TEXT,"
            "cli_configuration_path TEXT,"
            "cli_authentication_path TEXT,"
            "is_enabled INTEGER NOT NULL,"
            "probe_kind TEXT,"
            "probe_script_path TEXT,"
            "probe_minimum_balance REAL,"
            "balance_available REAL,"
            "balance_used REAL,"
            "balance_currency TEXT,"
            "balance_checked_at_unix_ms INTEGER,"
            "balance_detail TEXT,"
            "consecutive_failures INTEGER NOT NULL,"
            "disabled_until_unix_ms INTEGER)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_channels ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "name TEXT NOT NULL,"
            "protocol_kind TEXT NOT NULL,"
            "default_model TEXT NOT NULL,"
            "is_enabled INTEGER NOT NULL)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_endpoint_groups ("
            "id TEXT PRIMARY KEY NOT NULL,"
            "channel_id TEXT NOT NULL REFERENCES agent_channels(id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL,"
            "name TEXT NOT NULL,"
            "is_enabled INTEGER NOT NULL,"
            "priority INTEGER NOT NULL)");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_endpoint_urls ("
            "group_id TEXT NOT NULL REFERENCES agent_endpoint_groups(id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL,"
            "base_url TEXT NOT NULL,"
            "PRIMARY KEY(group_id, position))");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_endpoint_account_ids ("
            "group_id TEXT NOT NULL REFERENCES agent_endpoint_groups(id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL,"
            "account_id TEXT NOT NULL,"
            "PRIMARY KEY(group_id, position))");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_channel_probes ("
            "channel_id TEXT NOT NULL,"
            "endpoint_group_id TEXT NOT NULL,"
            "base_url TEXT NOT NULL,"
            "id TEXT NOT NULL,"
            "health INTEGER NOT NULL,"
            "latency_milliseconds INTEGER,"
            "detail TEXT,"
            "checked_at_unix_ms INTEGER NOT NULL,"
            "PRIMARY KEY(channel_id, endpoint_group_id, base_url))");
        execute(
            "CREATE TABLE IF NOT EXISTS agent_model_catalogs ("
            "channel_id TEXT NOT NULL,"
            "endpoint_group_id TEXT NOT NULL,"
            "base_url TEXT NOT NULL,"
            "models TEXT NOT NULL,"
            "checked_at_unix_ms INTEGER NOT NULL,"
            "detail TEXT,"
            "PRIMARY KEY(channel_id, endpoint_group_id, base_url))");
    }

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
            value.empty() ? "" : value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT) != SQLITE_OK) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::storage_failure,
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
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(connection));
        }
        return;
    }
    bind_text(connection, statement, index, *value);
}

void bind_optional_real(
    sqlite3* connection,
    sqlite3_stmt* statement,
    int index,
    std::optional<double> value) {
    if (!value) {
        if (sqlite3_bind_null(statement, index) != SQLITE_OK) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(connection));
        }
        return;
    }
    if (!std::isfinite(*value)
        || sqlite3_bind_double(statement, index, *value) != SQLITE_OK) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::storage_failure,
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
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void bind_int64(sqlite3* connection, sqlite3_stmt* statement, int index, std::int64_t value) {
    if (sqlite3_bind_int64(statement, index, value) != SQLITE_OK) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

void step_done(sqlite3* connection, sqlite3_stmt* statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::storage_failure,
            sqlite3_errmsg(connection));
    }
}

std::string column_text(sqlite3_stmt* statement, int column, std::string subject) {
    if (sqlite3_column_type(statement, column) != SQLITE_TEXT) {
        throw_corrupted_state(std::move(subject));
    }
    const auto* value = sqlite3_column_text(statement, column);
    const auto length = sqlite3_column_bytes(statement, column);
    if (!value || length < 0) {
        throw_corrupted_state(std::move(subject));
    }
    return {
        reinterpret_cast<const char*>(value),
        static_cast<std::size_t>(length),
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
    const auto type = sqlite3_column_type(statement, column);
    if (type != SQLITE_INTEGER) {
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

std::optional<double> optional_column_real(
    sqlite3_stmt* statement,
    int column,
    std::string subject) {
    const auto type = sqlite3_column_type(statement, column);
    if (type == SQLITE_NULL) {
        return std::nullopt;
    }
    if (type != SQLITE_FLOAT && type != SQLITE_INTEGER) {
        throw_corrupted_state(std::move(subject));
    }
    const auto value = sqlite3_column_double(statement, column);
    if (!std::isfinite(value)) {
        throw_corrupted_state(std::move(subject));
    }
    return value;
}

bool column_bool(sqlite3_stmt* statement, int column, std::string subject) {
    const auto value = column_int64(statement, column, std::move(subject));
    if (value != 0 && value != 1) {
        throw_corrupted_state("boolean value");
    }
    return value != 0;
}

std::uint32_t column_uint32(sqlite3_stmt* statement, int column, std::string subject) {
    const auto value = column_int64(statement, column, std::move(subject));
    if (value < 0
        || value > static_cast<std::int64_t>(std::numeric_limits<std::uint32_t>::max())) {
        throw_corrupted_state("failure count");
    }
    return static_cast<std::uint32_t>(value);
}

void validate_account(const AgentAccount& account) {
    validate_identifier(account.id, "account id");
    validate_identifier(account.secret_reference, "secret reference");
    if (account.balance_probe) {
        validate_finite(account.balance_probe->minimum_balance, "minimum balance");
    }
    if (account.balance) {
        validate_finite(account.balance->available, "available balance");
        validate_finite(account.balance->used, "used balance");
    }
}

void validate_channel(const AgentChannel& channel) {
    validate_identifier(channel.id, "channel id");
    std::vector<std::string> group_ids;
    group_ids.reserve(channel.endpoint_groups.size());
    for (const auto& group : channel.endpoint_groups) {
        validate_identifier(group.id, "endpoint group id");
        if (std::find(group_ids.begin(), group_ids.end(), group.id) != group_ids.end()) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::invalid_value,
                "Endpoint group IDs must be unique within a channel",
                group.id);
        }
        group_ids.push_back(group.id);
    }
}

void validate_probe(const AgentChannelProbe& probe) {
    validate_identifier(probe.id, "probe id");
    validate_identifier(probe.channel_id, "probe channel id");
    validate_identifier(probe.endpoint_group_id, "probe endpoint group id");
    validate_identifier(probe.base_url, "probe base URL");
    if (probe.latency_milliseconds && *probe.latency_milliseconds < 0) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::invalid_value,
            "Probe latency cannot be negative",
            probe.id);
    }
}

void validate_catalog(const AgentChannelModelCatalog& catalog) {
    validate_identifier(catalog.channel_id, "catalog channel id");
    validate_identifier(catalog.endpoint_group_id, "catalog endpoint group id");
    validate_identifier(catalog.base_url, "catalog base URL");
}

AgentAccount read_account(sqlite3_stmt* statement) {
    const auto credential_kind_text = column_text(statement, 4, "credential kind");
    const auto credential_kind = parse_agent_account_credential_kind(credential_kind_text);
    if (!credential_kind) {
        throw_corrupted_state("credential kind");
    }

    const auto cli_kind_text = optional_column_text(statement, 5, "CLI kind");
    const auto cli_configuration_path = optional_column_text(statement, 6, "CLI configuration path");
    const auto cli_authentication_path = optional_column_text(statement, 7, "CLI authentication path");
    std::optional<AgentCLIProfile> cli_profile;
    if (cli_kind_text || cli_configuration_path || cli_authentication_path) {
        if (!cli_kind_text || !cli_configuration_path || !cli_authentication_path) {
            throw_corrupted_state("CLI profile");
        }
        const auto cli_kind = parse_agent_cli_kind(*cli_kind_text);
        if (!cli_kind) {
            throw_corrupted_state("CLI kind");
        }
        cli_profile = AgentCLIProfile{
            .cli_kind = *cli_kind,
            .configuration_file_path = *cli_configuration_path,
            .authentication_file_path = *cli_authentication_path,
        };
    }

    const auto probe_kind_text = optional_column_text(statement, 9, "balance probe kind");
    const auto probe_script_path = optional_column_text(statement, 10, "balance probe script path");
    const auto probe_minimum_balance = optional_column_real(statement, 11, "balance probe minimum");
    std::optional<AgentBalanceProbe> balance_probe;
    if (probe_kind_text || probe_script_path || probe_minimum_balance) {
        if (!probe_kind_text) {
            throw_corrupted_state("balance probe");
        }
        const auto kind = parse_agent_balance_probe_kind(*probe_kind_text);
        if (!kind) {
            throw_corrupted_state("balance probe kind");
        }
        balance_probe = AgentBalanceProbe{
            *kind,
            probe_script_path,
            probe_minimum_balance,
        };
    }

    const auto balance_available = optional_column_real(statement, 12, "available balance");
    const auto balance_used = optional_column_real(statement, 13, "used balance");
    const auto balance_currency = optional_column_text(statement, 14, "balance currency");
    const auto balance_checked_at = optional_column_int64(statement, 15, "balance checked time");
    const auto balance_detail = optional_column_text(statement, 16, "balance detail");
    std::optional<AgentBalanceSnapshot> balance;
    if (balance_available || balance_used || balance_currency || balance_checked_at || balance_detail) {
        if (!balance_currency || !balance_checked_at) {
            throw_corrupted_state("balance snapshot");
        }
        balance = AgentBalanceSnapshot{
            .available = balance_available,
            .used = balance_used,
            .currency = *balance_currency,
            .checked_at_unix_ms = *balance_checked_at,
            .detail = balance_detail,
        };
    }

    return {
        .id = column_text(statement, 0, "account id"),
        .name = column_text(statement, 1, "account name"),
        .provider = column_text(statement, 2, "account provider"),
        .secret_reference = column_text(statement, 3, "secret reference"),
        .credential_kind = *credential_kind,
        .cli_profile = cli_profile,
        .is_enabled = column_bool(statement, 8, "account enabled"),
        .balance_probe = balance_probe,
        .balance = balance,
        .consecutive_failures = column_uint32(statement, 17, "failure count"),
        .disabled_until_unix_ms = optional_column_int64(statement, 18, "disabled until"),
    };
}

AgentChannel read_channel(Database& database, sqlite3_stmt* statement) {
    const auto protocol_text = column_text(statement, 2, "channel protocol");
    const auto protocol = parse_agent_channel_protocol(protocol_text);
    if (!protocol) {
        throw_corrupted_state("channel protocol");
    }
    AgentChannel channel{
        .id = column_text(statement, 0, "channel id"),
        .name = column_text(statement, 1, "channel name"),
        .protocol_kind = *protocol,
        .default_model = column_text(statement, 3, "channel model"),
        .is_enabled = column_bool(statement, 4, "channel enabled"),
    };

    Statement groups(
        database.get(),
        "SELECT id, name, is_enabled, priority "
        "FROM agent_endpoint_groups WHERE channel_id = ? ORDER BY position ASC");
    bind_text(database.get(), groups.get(), 1, channel.id);
    while (true) {
        const auto result = sqlite3_step(groups.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        const auto priority = column_int64(groups.get(), 3, "endpoint priority");
        if (priority < std::numeric_limits<int>::min()
            || priority > std::numeric_limits<int>::max()) {
            throw_corrupted_state("endpoint priority");
        }
        AgentEndpointGroup group{
            .id = column_text(groups.get(), 0, "endpoint group id"),
            .name = column_text(groups.get(), 1, "endpoint group name"),
            .is_enabled = column_bool(groups.get(), 2, "endpoint group enabled"),
            .priority = static_cast<int>(priority),
        };
        Statement urls(
            database.get(),
            "SELECT base_url FROM agent_endpoint_urls WHERE group_id = ? ORDER BY position ASC");
        bind_text(database.get(), urls.get(), 1, group.id);
        while (true) {
            const auto url_result = sqlite3_step(urls.get());
            if (url_result == SQLITE_DONE) {
                break;
            }
            if (url_result != SQLITE_ROW) {
                throw AIAgentRoutingRepositoryError(
                    AIAgentRoutingRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(database.get()));
            }
            group.base_urls.push_back(column_text(urls.get(), 0, "endpoint URL"));
        }
        Statement account_ids(
            database.get(),
            "SELECT account_id FROM agent_endpoint_account_ids "
            "WHERE group_id = ? ORDER BY position ASC");
        bind_text(database.get(), account_ids.get(), 1, group.id);
        while (true) {
            const auto account_result = sqlite3_step(account_ids.get());
            if (account_result == SQLITE_DONE) {
                break;
            }
            if (account_result != SQLITE_ROW) {
                throw AIAgentRoutingRepositoryError(
                    AIAgentRoutingRepositoryErrorCode::storage_failure,
                    sqlite3_errmsg(database.get()));
            }
            group.account_ids.push_back(column_text(account_ids.get(), 0, "endpoint account id"));
        }
        channel.endpoint_groups.push_back(std::move(group));
    }
    return channel;
}

void bind_account(sqlite3* connection, sqlite3_stmt* statement, const AgentAccount& account) {
    bind_text(connection, statement, 1, account.id);
    bind_text(connection, statement, 2, account.name);
    bind_text(connection, statement, 3, account.provider);
    bind_text(connection, statement, 4, account.secret_reference);
    bind_text(
        connection,
        statement,
        5,
        agent_account_credential_kind_token(account.credential_kind));
    std::optional<std::string> cli_kind;
    std::optional<std::string> cli_configuration_path;
    std::optional<std::string> cli_authentication_path;
    if (account.cli_profile) {
        cli_kind = std::string(agent_cli_kind_token(account.cli_profile->cli_kind));
        cli_configuration_path = account.cli_profile->configuration_file_path;
        cli_authentication_path = account.cli_profile->authentication_file_path;
    }
    bind_optional_text(connection, statement, 6, cli_kind);
    bind_optional_text(connection, statement, 7, cli_configuration_path);
    bind_optional_text(connection, statement, 8, cli_authentication_path);
    bind_int64(connection, statement, 9, account.is_enabled ? 1 : 0);
    std::optional<std::string> probe_kind;
    std::optional<std::string> probe_script_path;
    std::optional<double> probe_minimum_balance;
    if (account.balance_probe) {
        probe_kind = std::string(agent_balance_probe_kind_token(account.balance_probe->kind));
        probe_script_path = account.balance_probe->script_path;
        probe_minimum_balance = account.balance_probe->minimum_balance;
    }
    bind_optional_text(connection, statement, 10, probe_kind);
    bind_optional_text(connection, statement, 11, probe_script_path);
    bind_optional_real(connection, statement, 12, probe_minimum_balance);
    std::optional<double> balance_available;
    std::optional<double> balance_used;
    std::optional<std::string> balance_currency;
    std::optional<std::int64_t> balance_checked_at;
    std::optional<std::string> balance_detail;
    if (account.balance) {
        balance_available = account.balance->available;
        balance_used = account.balance->used;
        balance_currency = account.balance->currency;
        balance_checked_at = account.balance->checked_at_unix_ms;
        balance_detail = account.balance->detail;
    }
    bind_optional_real(connection, statement, 13, balance_available);
    bind_optional_real(connection, statement, 14, balance_used);
    bind_optional_text(connection, statement, 15, balance_currency);
    bind_optional_int64(connection, statement, 16, balance_checked_at);
    bind_optional_text(connection, statement, 17, balance_detail);
    bind_int64(connection, statement, 18, account.consecutive_failures);
    bind_optional_int64(connection, statement, 19, account.disabled_until_unix_ms);
}

std::optional<AgentChannelHealth> health_from_database(std::int64_t value) noexcept {
    switch (value) {
    case 0: return AgentChannelHealth::unknown;
    case 1: return AgentChannelHealth::healthy;
    case 2: return AgentChannelHealth::degraded;
    case 3: return AgentChannelHealth::unavailable;
    }
    return std::nullopt;
}

std::int64_t health_to_database(AgentChannelHealth value) noexcept {
    switch (value) {
    case AgentChannelHealth::unknown: return 0;
    case AgentChannelHealth::healthy: return 1;
    case AgentChannelHealth::degraded: return 2;
    case AgentChannelHealth::unavailable: return 3;
    }
    return -1;
}

std::string encode_models(const std::vector<std::string>& models) {
    std::string encoded;
    for (const auto& model : models) {
        if (model.find('\n') != std::string::npos || model.find('\r') != std::string::npos) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::invalid_value,
                "Model names cannot contain line breaks",
                model);
        }
        if (!encoded.empty()) {
            encoded.push_back('\n');
        }
        encoded += model;
    }
    return encoded;
}

std::vector<std::string> decode_models(std::string_view encoded) {
    if (encoded.empty()) {
        return {};
    }
    std::vector<std::string> models;
    while (true) {
        const auto newline = encoded.find('\n');
        const auto value = encoded.substr(0, newline);
        if (value.empty()) {
            throw_corrupted_state("model catalog");
        }
        models.emplace_back(value);
        if (newline == std::string_view::npos) {
            break;
        }
        encoded.remove_prefix(newline + 1);
    }
    return AgentChannelModelCatalog::normalize_models(std::move(models));
}

}  // namespace

AIAgentRoutingRepositoryError::AIAgentRoutingRepositoryError(
    AIAgentRoutingRepositoryErrorCode code,
    std::string message,
    std::string subject)
    : std::runtime_error(std::move(message)),
      code_(code),
      subject_(std::move(subject)) {}

AIAgentRoutingRepositoryErrorCode AIAgentRoutingRepositoryError::code() const noexcept {
    return code_;
}

const std::string& AIAgentRoutingRepositoryError::subject() const noexcept {
    return subject_;
}

AIAgentRoutingRepository::AIAgentRoutingRepository(std::filesystem::path directory)
    : directory_(std::move(directory)) {}

const std::filesystem::path& AIAgentRoutingRepository::directory() const noexcept {
    return directory_;
}

std::filesystem::path AIAgentRoutingRepository::database_path() const {
    return directory_ / "ai-agent-routing.sqlite";
}

AIAgentRoutingState AIAgentRoutingRepository::load() const {
    Database database(*this);
    AIAgentRoutingState state;
    Statement accounts(
        database.get(),
        "SELECT id, name, provider, secret_reference, credential_kind, cli_kind, "
        "cli_configuration_path, cli_authentication_path, is_enabled, probe_kind, "
        "probe_script_path, probe_minimum_balance, balance_available, balance_used, "
        "balance_currency, balance_checked_at_unix_ms, balance_detail, "
        "consecutive_failures, disabled_until_unix_ms "
        "FROM agent_accounts ORDER BY rowid ASC");
    while (true) {
        const auto result = sqlite3_step(accounts.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        state.accounts.push_back(read_account(accounts.get()));
    }

    Statement channels(
        database.get(),
        "SELECT id, name, protocol_kind, default_model, is_enabled "
        "FROM agent_channels ORDER BY rowid ASC");
    while (true) {
        const auto result = sqlite3_step(channels.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        state.channels.push_back(read_channel(database, channels.get()));
    }

    Statement probes(
        database.get(),
        "SELECT id, channel_id, endpoint_group_id, base_url, health, "
        "latency_milliseconds, detail, checked_at_unix_ms "
        "FROM agent_channel_probes ORDER BY rowid ASC");
    while (true) {
        const auto result = sqlite3_step(probes.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        const auto health = health_from_database(column_int64(probes.get(), 4, "probe health"));
        const auto latency = optional_column_int64(probes.get(), 5, "probe latency");
        if (!health || (latency && (*latency < 0
            || *latency > std::numeric_limits<std::int32_t>::max()))) {
            throw_corrupted_state("probe");
        }
        state.channel_probes.push_back({
            .id = column_text(probes.get(), 0, "probe id"),
            .channel_id = column_text(probes.get(), 1, "probe channel id"),
            .endpoint_group_id = column_text(probes.get(), 2, "probe endpoint group id"),
            .base_url = column_text(probes.get(), 3, "probe base URL"),
            .health = *health,
            .latency_milliseconds = latency
                ? std::optional<std::int32_t>{static_cast<std::int32_t>(*latency)}
                : std::nullopt,
            .detail = optional_column_text(probes.get(), 6, "probe detail"),
            .checked_at_unix_ms = column_int64(probes.get(), 7, "probe checked time"),
        });
    }

    Statement catalogs(
        database.get(),
        "SELECT channel_id, endpoint_group_id, base_url, models, checked_at_unix_ms, detail "
        "FROM agent_model_catalogs ORDER BY rowid ASC");
    while (true) {
        const auto result = sqlite3_step(catalogs.get());
        if (result == SQLITE_DONE) {
            break;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        state.model_catalogs.push_back({
            .channel_id = column_text(catalogs.get(), 0, "catalog channel id"),
            .endpoint_group_id = column_text(catalogs.get(), 1, "catalog endpoint group id"),
            .base_url = column_text(catalogs.get(), 2, "catalog base URL"),
            .models = decode_models(column_text(catalogs.get(), 3, "catalog models")),
            .checked_at_unix_ms = column_int64(catalogs.get(), 4, "catalog checked time"),
            .detail = optional_column_text(catalogs.get(), 5, "catalog detail"),
        });
    }
    return state;
}

void AIAgentRoutingRepository::upsert_account(const AgentAccount& account) const {
    validate_account(account);
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO agent_accounts("
        "id, name, provider, secret_reference, credential_kind, cli_kind, "
        "cli_configuration_path, cli_authentication_path, is_enabled, probe_kind, "
        "probe_script_path, probe_minimum_balance, balance_available, balance_used, "
        "balance_currency, balance_checked_at_unix_ms, balance_detail, "
        "consecutive_failures, disabled_until_unix_ms) "
        "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "name=excluded.name, provider=excluded.provider, "
        "secret_reference=excluded.secret_reference, "
        "credential_kind=excluded.credential_kind, cli_kind=excluded.cli_kind, "
        "cli_configuration_path=excluded.cli_configuration_path, "
        "cli_authentication_path=excluded.cli_authentication_path, "
        "is_enabled=excluded.is_enabled, probe_kind=excluded.probe_kind, "
        "probe_script_path=excluded.probe_script_path, "
        "probe_minimum_balance=excluded.probe_minimum_balance, "
        "balance_available=excluded.balance_available, balance_used=excluded.balance_used, "
        "balance_currency=excluded.balance_currency, "
        "balance_checked_at_unix_ms=excluded.balance_checked_at_unix_ms, "
        "balance_detail=excluded.balance_detail, "
        "consecutive_failures=excluded.consecutive_failures, "
        "disabled_until_unix_ms=excluded.disabled_until_unix_ms");
    bind_account(database.get(), statement.get(), account);
    step_done(database.get(), statement.get());
}

bool AIAgentRoutingRepository::remove_account(std::string_view account_id) const {
    if (account_id.empty()) {
        return false;
    }
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement remove_references(
            database.get(),
            "DELETE FROM agent_endpoint_account_ids WHERE account_id = ?");
        bind_text(database.get(), remove_references.get(), 1, account_id);
        step_done(database.get(), remove_references.get());
        Statement remove_account(database.get(), "DELETE FROM agent_accounts WHERE id = ?");
        bind_text(database.get(), remove_account.get(), 1, account_id);
        step_done(database.get(), remove_account.get());
        const bool removed = sqlite3_changes(database.get()) > 0;
        database.execute("COMMIT");
        return removed;
    } catch (...) {
        database.rollback();
        throw;
    }
}

void AIAgentRoutingRepository::upsert_channel(const AgentChannel& channel) const {
    validate_channel(channel);
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement save_channel(
            database.get(),
            "INSERT INTO agent_channels(id, name, protocol_kind, default_model, is_enabled) "
            "VALUES(?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET name=excluded.name, "
            "protocol_kind=excluded.protocol_kind, default_model=excluded.default_model, "
            "is_enabled=excluded.is_enabled");
        bind_text(database.get(), save_channel.get(), 1, channel.id);
        bind_text(database.get(), save_channel.get(), 2, channel.name);
        bind_text(
            database.get(),
            save_channel.get(),
            3,
            agent_channel_protocol_token(channel.protocol_kind));
        bind_text(database.get(), save_channel.get(), 4, channel.default_model);
        bind_int64(database.get(), save_channel.get(), 5, channel.is_enabled ? 1 : 0);
        step_done(database.get(), save_channel.get());

        Statement remove_groups(
            database.get(),
            "DELETE FROM agent_endpoint_groups WHERE channel_id = ?");
        bind_text(database.get(), remove_groups.get(), 1, channel.id);
        step_done(database.get(), remove_groups.get());

        Statement remove_probes(
            database.get(),
            "DELETE FROM agent_channel_probes WHERE channel_id = ?");
        bind_text(database.get(), remove_probes.get(), 1, channel.id);
        step_done(database.get(), remove_probes.get());
        Statement remove_catalogs(
            database.get(),
            "DELETE FROM agent_model_catalogs WHERE channel_id = ?");
        bind_text(database.get(), remove_catalogs.get(), 1, channel.id);
        step_done(database.get(), remove_catalogs.get());

        for (std::size_t group_index = 0; group_index < channel.endpoint_groups.size(); ++group_index) {
            const auto& group = channel.endpoint_groups[group_index];
            Statement save_group(
                database.get(),
                "INSERT INTO agent_endpoint_groups("
                "id, channel_id, position, name, is_enabled, priority) VALUES(?, ?, ?, ?, ?, ?)");
            bind_text(database.get(), save_group.get(), 1, group.id);
            bind_text(database.get(), save_group.get(), 2, channel.id);
            bind_int64(database.get(), save_group.get(), 3, static_cast<std::int64_t>(group_index));
            bind_text(database.get(), save_group.get(), 4, group.name);
            bind_int64(database.get(), save_group.get(), 5, group.is_enabled ? 1 : 0);
            bind_int64(database.get(), save_group.get(), 6, group.priority);
            step_done(database.get(), save_group.get());

            for (std::size_t url_index = 0; url_index < group.base_urls.size(); ++url_index) {
                Statement save_url(
                    database.get(),
                    "INSERT INTO agent_endpoint_urls(group_id, position, base_url) VALUES(?, ?, ?)");
                bind_text(database.get(), save_url.get(), 1, group.id);
                bind_int64(database.get(), save_url.get(), 2, static_cast<std::int64_t>(url_index));
                bind_text(database.get(), save_url.get(), 3, group.base_urls[url_index]);
                step_done(database.get(), save_url.get());
            }
            for (std::size_t account_index = 0; account_index < group.account_ids.size(); ++account_index) {
                Statement save_account_id(
                    database.get(),
                    "INSERT INTO agent_endpoint_account_ids(group_id, position, account_id) "
                    "VALUES(?, ?, ?)");
                bind_text(database.get(), save_account_id.get(), 1, group.id);
                bind_int64(
                    database.get(),
                    save_account_id.get(),
                    2,
                    static_cast<std::int64_t>(account_index));
                bind_text(database.get(), save_account_id.get(), 3, group.account_ids[account_index]);
                step_done(database.get(), save_account_id.get());
            }
        }
        database.execute("COMMIT");
    } catch (...) {
        database.rollback();
        throw;
    }
}

bool AIAgentRoutingRepository::remove_channel(std::string_view channel_id) const {
    if (channel_id.empty()) {
        return false;
    }
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement remove_probes(
            database.get(),
            "DELETE FROM agent_channel_probes WHERE channel_id = ?");
        bind_text(database.get(), remove_probes.get(), 1, channel_id);
        step_done(database.get(), remove_probes.get());
        Statement remove_catalogs(
            database.get(),
            "DELETE FROM agent_model_catalogs WHERE channel_id = ?");
        bind_text(database.get(), remove_catalogs.get(), 1, channel_id);
        step_done(database.get(), remove_catalogs.get());
        Statement remove_channel(database.get(), "DELETE FROM agent_channels WHERE id = ?");
        bind_text(database.get(), remove_channel.get(), 1, channel_id);
        step_done(database.get(), remove_channel.get());
        const bool removed = sqlite3_changes(database.get()) > 0;
        database.execute("COMMIT");
        return removed;
    } catch (...) {
        database.rollback();
        throw;
    }
}

void AIAgentRoutingRepository::replace_channel_probe(const AgentChannelProbe& probe) const {
    validate_probe(probe);
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO agent_channel_probes("
        "channel_id, endpoint_group_id, base_url, id, health, latency_milliseconds, "
        "detail, checked_at_unix_ms) VALUES(?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(channel_id, endpoint_group_id, base_url) DO UPDATE SET "
        "id=excluded.id, health=excluded.health, "
        "latency_milliseconds=excluded.latency_milliseconds, detail=excluded.detail, "
        "checked_at_unix_ms=excluded.checked_at_unix_ms");
    bind_text(database.get(), statement.get(), 1, probe.channel_id);
    bind_text(database.get(), statement.get(), 2, probe.endpoint_group_id);
    bind_text(database.get(), statement.get(), 3, probe.base_url);
    bind_text(database.get(), statement.get(), 4, probe.id);
    bind_int64(database.get(), statement.get(), 5, health_to_database(probe.health));
    bind_optional_int64(
        database.get(),
        statement.get(),
        6,
        probe.latency_milliseconds
            ? std::optional<std::int64_t>{*probe.latency_milliseconds}
            : std::nullopt);
    bind_optional_text(database.get(), statement.get(), 7, probe.detail);
    bind_int64(database.get(), statement.get(), 8, probe.checked_at_unix_ms);
    step_done(database.get(), statement.get());
}

void AIAgentRoutingRepository::replace_model_catalog(
    const AgentChannelModelCatalog& catalog) const {
    validate_catalog(catalog);
    const auto models = AgentChannelModelCatalog::normalize_models(catalog.models);
    if (models.empty() && catalog.detail) {
        throw AIAgentRoutingRepositoryError(
            AIAgentRoutingRepositoryErrorCode::invalid_value,
            "A failed model catalog must not be stored as an empty successful catalog",
            catalog.id());
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "INSERT INTO agent_model_catalogs("
        "channel_id, endpoint_group_id, base_url, models, checked_at_unix_ms, detail) "
        "VALUES(?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(channel_id, endpoint_group_id, base_url) DO UPDATE SET "
        "models=excluded.models, checked_at_unix_ms=excluded.checked_at_unix_ms, "
        "detail=excluded.detail");
    bind_text(database.get(), statement.get(), 1, catalog.channel_id);
    bind_text(database.get(), statement.get(), 2, catalog.endpoint_group_id);
    bind_text(database.get(), statement.get(), 3, catalog.base_url);
    bind_text(database.get(), statement.get(), 4, encode_models(models));
    bind_int64(database.get(), statement.get(), 5, catalog.checked_at_unix_ms);
    bind_optional_text(database.get(), statement.get(), 6, catalog.detail);
    step_done(database.get(), statement.get());
}

bool AIAgentRoutingRepository::record_balance(
    std::string_view account_id,
    std::optional<AgentBalanceSnapshot> snapshot) const {
    if (account_id.empty()) {
        return false;
    }
    if (snapshot) {
        validate_finite(snapshot->available, "available balance");
        validate_finite(snapshot->used, "used balance");
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "UPDATE agent_accounts SET balance_available=?, balance_used=?, balance_currency=?, "
        "balance_checked_at_unix_ms=?, balance_detail=?, consecutive_failures=0, "
        "disabled_until_unix_ms=NULL WHERE id=?");
    bind_optional_real(
        database.get(), statement.get(), 1, snapshot ? snapshot->available : std::nullopt);
    bind_optional_real(
        database.get(), statement.get(), 2, snapshot ? snapshot->used : std::nullopt);
    bind_optional_text(
        database.get(),
        statement.get(),
        3,
        snapshot ? std::optional<std::string>{snapshot->currency} : std::nullopt);
    bind_optional_int64(
        database.get(),
        statement.get(),
        4,
        snapshot ? std::optional<std::int64_t>{snapshot->checked_at_unix_ms} : std::nullopt);
    bind_optional_text(
        database.get(), statement.get(), 5, snapshot ? snapshot->detail : std::nullopt);
    bind_text(database.get(), statement.get(), 6, account_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

bool AIAgentRoutingRepository::record_route_success(std::string_view account_id) const {
    if (account_id.empty()) {
        return false;
    }
    Database database(*this);
    Statement statement(
        database.get(),
        "UPDATE agent_accounts SET consecutive_failures=0, disabled_until_unix_ms=NULL "
        "WHERE id=?");
    bind_text(database.get(), statement.get(), 1, account_id);
    step_done(database.get(), statement.get());
    return sqlite3_changes(database.get()) > 0;
}

bool AIAgentRoutingRepository::record_route_failure(
    std::string_view account_id,
    std::int64_t now_unix_ms,
    std::int64_t cooldown_ms,
    std::uint32_t failure_threshold) const {
    if (account_id.empty()) {
        return false;
    }
    const auto bounded_cooldown = std::max<std::int64_t>(0, cooldown_ms);
    const auto bounded_threshold = std::max<std::uint32_t>(1, failure_threshold);
    Database database(*this);
    database.execute("BEGIN IMMEDIATE");
    try {
        Statement read_failures(
            database.get(),
            "SELECT consecutive_failures FROM agent_accounts WHERE id=?");
        bind_text(database.get(), read_failures.get(), 1, account_id);
        const auto result = sqlite3_step(read_failures.get());
        if (result == SQLITE_DONE) {
            database.execute("COMMIT");
            return false;
        }
        if (result != SQLITE_ROW) {
            throw AIAgentRoutingRepositoryError(
                AIAgentRoutingRepositoryErrorCode::storage_failure,
                sqlite3_errmsg(database.get()));
        }
        const auto failures = column_uint32(read_failures.get(), 0, "failure count");
        const auto next_failures = failures == std::numeric_limits<std::uint32_t>::max()
            ? failures
            : failures + 1;
        std::optional<std::int64_t> disabled_until;
        if (next_failures >= bounded_threshold) {
            disabled_until = now_unix_ms > std::numeric_limits<std::int64_t>::max()
                    - bounded_cooldown
                ? std::numeric_limits<std::int64_t>::max()
                : now_unix_ms + bounded_cooldown;
        }
        Statement update(
            database.get(),
            "UPDATE agent_accounts SET consecutive_failures=?, disabled_until_unix_ms=? "
            "WHERE id=?");
        bind_int64(database.get(), update.get(), 1, next_failures);
        bind_optional_int64(database.get(), update.get(), 2, disabled_until);
        bind_text(database.get(), update.get(), 3, account_id);
        step_done(database.get(), update.get());
        database.execute("COMMIT");
        return true;
    } catch (...) {
        database.rollback();
        throw;
    }
}

}  // namespace zisla::core
