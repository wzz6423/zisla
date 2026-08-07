#include <zisla/core/AIAgentRoutingRepository.hpp>

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using namespace zisla::core;

namespace {

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-ai-agent-routing-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

AgentAccount account(std::string id) {
    return {
        .id = std::move(id),
        .name = "Primary account",
        .provider = "OpenAI",
        .secret_reference = "credential-primary",
        .credential_kind = AgentAccountCredentialKind::api_key,
        .balance_probe = AgentBalanceProbe{
            AgentBalanceProbeKind::new_api_quota,
            std::nullopt,
            2.5,
        },
        .balance = AgentBalanceSnapshot{
            .available = 6.0,
            .used = 1.0,
            .currency = "USD",
            .checked_at_unix_ms = 100,
            .detail = "from test",
        },
    };
}

AgentChannel channel(std::string id, std::string group_id, std::string account_id) {
    return {
        .id = std::move(id),
        .name = "Primary channel",
        .protocol_kind = AgentChannelProtocol::openai_compatible,
        .default_model = "gpt-test",
        .endpoint_groups = {AgentEndpointGroup::make(
            std::move(group_id),
            "Primary endpoint",
            {"https://one.example/v1"},
            {std::move(account_id)},
            true,
            10)},
    };
}

void metadataPersistsWithoutSecretContents() {
    TemporaryDirectory temporary;
    AIAgentRoutingRepository repository(temporary.path());
    const auto original_account = account("account-one");
    const auto original_channel = channel("channel-one", "group-one", original_account.id);
    repository.upsert_account(original_account);
    repository.upsert_channel(original_channel);
    repository.replace_channel_probe({
        .id = "probe-one",
        .channel_id = original_channel.id,
        .endpoint_group_id = "group-one",
        .base_url = "https://one.example/v1",
        .health = AgentChannelHealth::healthy,
        .latency_milliseconds = 42,
        .checked_at_unix_ms = 200,
    });
    repository.replace_model_catalog({
        .channel_id = original_channel.id,
        .endpoint_group_id = "group-one",
        .base_url = "https://one.example/v1",
        .models = {" model-b ", "model-a", "model-b"},
        .checked_at_unix_ms = 300,
    });

    const auto state = AIAgentRoutingRepository(temporary.path()).load();
    expect(state.accounts == std::vector<AgentAccount>{original_account},
        "account metadata should persist exactly");
    expect(state.channels == std::vector<AgentChannel>{original_channel},
        "channel metadata and endpoint order should persist exactly");
    expect(state.channel_probes.size() == 1
            && state.channel_probes.front().latency_milliseconds == 42,
        "channel probes should persist");
    expect(state.model_catalogs.size() == 1
            && state.model_catalogs.front().models
                == std::vector<std::string>{"model-a", "model-b"},
        "model catalogs should normalize before persistence");

    std::ifstream database(repository.database_path(), std::ios::binary);
    const std::string bytes{
        std::istreambuf_iterator<char>(database),
        std::istreambuf_iterator<char>()};
    expect(bytes.find("api_key") == std::string::npos,
        "routing database schema must not create an API key field");
}

void removingAccountsCleansEndpointReferences() {
    TemporaryDirectory temporary;
    AIAgentRoutingRepository repository(temporary.path());
    const auto first = account("first");
    auto second = account("second");
    second.secret_reference = "credential-second";
    repository.upsert_account(first);
    repository.upsert_account(second);
    repository.upsert_channel({
        .id = "channel",
        .name = "Channel",
        .default_model = "model",
        .endpoint_groups = {AgentEndpointGroup::make(
            "group",
            "Group",
            {"https://one.example/v1"},
            {first.id, second.id})},
    });

    expect(repository.remove_account(first.id), "existing accounts should be removed");
    expect(!repository.remove_account(first.id), "repeated removal should report false");

    const auto state = repository.load();
    expect(state.accounts == std::vector<AgentAccount>{second},
        "only the retained account should remain");
    expect(state.channels.size() == 1
            && state.channels.front().endpoint_groups.front().account_ids
                == std::vector<std::string>{second.id},
        "deleted accounts must be removed from every endpoint group");
}

void replacingChannelsClearsStaleEndpointCaches() {
    TemporaryDirectory temporary;
    AIAgentRoutingRepository repository(temporary.path());
    const auto original_account = account("account");
    repository.upsert_account(original_account);
    const auto original_channel = channel("channel", "old-group", original_account.id);
    repository.upsert_channel(original_channel);
    repository.replace_channel_probe({
        .id = "old-probe",
        .channel_id = original_channel.id,
        .endpoint_group_id = "old-group",
        .base_url = "https://one.example/v1",
        .health = AgentChannelHealth::healthy,
        .checked_at_unix_ms = 100,
    });
    repository.replace_model_catalog({
        .channel_id = original_channel.id,
        .endpoint_group_id = "old-group",
        .base_url = "https://one.example/v1",
        .models = {"model"},
        .checked_at_unix_ms = 100,
    });

    const auto replacement = channel("channel", "new-group", original_account.id);
    repository.upsert_channel(replacement);
    const auto state = repository.load();
    expect(state.channels == std::vector<AgentChannel>{replacement},
        "updating a channel should replace its endpoint groups atomically");
    expect(state.channel_probes.empty() && state.model_catalogs.empty(),
        "endpoint caches must not outlive the endpoint topology they describe");
}

void routeFailuresAndSuccessPersistCooldownState() {
    TemporaryDirectory temporary;
    AIAgentRoutingRepository repository(temporary.path());
    const auto original = account("account");
    repository.upsert_account(original);

    expect(repository.record_route_failure(original.id, 1'000),
        "first routing failure should be recorded");
    expect(repository.record_route_failure(original.id, 2'000),
        "second routing failure should be recorded");
    auto restored = repository.load().accounts.front();
    expect(restored.consecutive_failures == 2,
        "failure count should persist");
    expect(restored.disabled_until_unix_ms
            == 2'000 + AIAgentRoutingRepository::default_route_cooldown_ms,
        "second failure should start the default cooldown");
    expect(!restored.is_eligible(2'001),
        "an account remains unavailable during its cooldown");
    expect(restored.is_eligible(*restored.disabled_until_unix_ms),
        "an account becomes eligible at the cooldown boundary");

    expect(repository.record_route_success(original.id),
        "successful requests should clear route failure state");
    restored = repository.load().accounts.front();
    expect(restored.consecutive_failures == 0 && !restored.disabled_until_unix_ms,
        "successful requests should clear the persisted cooldown");
}

void emptyModelCatalogsAndCorruptedDatabasesAreHandledSafely() {
    TemporaryDirectory temporary;
    AIAgentRoutingRepository repository(temporary.path() / "valid");
    repository.replace_model_catalog({
        .channel_id = "channel",
        .endpoint_group_id = "group",
        .base_url = "https://one.example/v1",
        .models = {},
        .checked_at_unix_ms = 100,
    });
    const auto state = repository.load();
    expect(state.model_catalogs.size() == 1 && state.model_catalogs.front().models.empty(),
        "an empty successful model list should round trip");

    AIAgentRoutingRepository corrupted(temporary.path() / "corrupted");
    std::filesystem::create_directories(corrupted.directory());
    constexpr std::string_view invalid = "not an SQLite database";
    {
        std::ofstream output(corrupted.database_path(), std::ios::binary);
        output.write(invalid.data(), static_cast<std::streamsize>(invalid.size()));
    }
    try {
        (void)corrupted.load();
        throw std::runtime_error("corrupted routing database should fail");
    } catch (const AIAgentRoutingRepositoryError& error) {
        expect(error.code() == AIAgentRoutingRepositoryErrorCode::storage_failure,
            "corrupted database should be reported as a storage failure");
    }
    std::ifstream input(corrupted.database_path(), std::ios::binary);
    const std::string retained{
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()};
    expect(retained == invalid, "corrupted database bytes must not be overwritten");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"routing metadata persists without secret contents", metadataPersistsWithoutSecretContents},
        {"removing accounts cleans endpoint references", removingAccountsCleansEndpointReferences},
        {"replacing channels clears stale endpoint caches", replacingChannelsClearsStaleEndpointCaches},
        {"route failures and success persist cooldown state", routeFailuresAndSuccessPersistCooldownState},
        {"empty model catalogs and corrupted databases are safe", emptyModelCatalogsAndCorruptedDatabasesAreHandledSafely},
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
