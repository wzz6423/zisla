#include "pch.h"
#include "AIAgentWorkspaceService.h"

#include <zisla/core/AIAgentCLIRelay.hpp>
#include <zisla/core/AIAgentChatRequestPlanner.hpp>

#include <rpc.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cstdint>
#include <iterator>
#include <limits>
#include <stdexcept>
#include <system_error>
#include <string_view>
#include <type_traits>
#include <utility>
#include <variant>

namespace winrt::Zisla {
namespace {

using zisla::core::AIAgentWorkspaceState;
using zisla::core::AgentWorkspaceMessage;
using zisla::core::AgentWorkspaceMessageCommand;
using zisla::core::AgentWorkspaceMessageRole;
using zisla::core::AgentWorkspaceProject;
using zisla::core::AgentWorkspaceSetGoalPromptCommand;
using zisla::core::AgentWorkspaceSetModeCommand;
using zisla::core::AgentWorkspaceThread;

std::string api_secret_reference_for_account(std::string_view account_id) {
    return "ai-agent-api-key-" + std::string(account_id);
}

class SensitiveString {
public:
    explicit SensitiveString(std::string& value) noexcept : value_(value) {}

    ~SensitiveString() {
        if (!value_.empty()) {
            SecureZeroMemory(value_.data(), value_.size());
        }
    }

    SensitiveString(const SensitiveString&) = delete;
    SensitiveString& operator=(const SensitiveString&) = delete;

private:
    std::string& value_;
};

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::string trim_ascii(std::string_view value) {
    const auto is_space = [](unsigned char character) noexcept {
        return character == ' ' || character == '\t' || character == '\n'
            || character == '\r' || character == '\f' || character == '\v';
    };
    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return std::string(value);
}

std::filesystem::path path_from_utf8(std::string_view value) {
    if (value.empty() || value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return {};
    }
    const auto length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) {
        return {};
    }
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length) != length) {
        return {};
    }
    return std::filesystem::path{result};
}

void append_hex(std::string& target, std::uint64_t value, std::size_t digits) {
    constexpr char hex[] = "0123456789abcdef";
    for (std::size_t index = digits; index > 0; --index) {
        const auto shift = static_cast<unsigned>((index - 1) * 4U);
        target.push_back(hex[(value >> shift) & 0x0FU]);
    }
}

std::string make_identifier(std::string_view prefix) {
    UUID uuid{};
    const auto status = UuidCreate(&uuid);
    if (status != RPC_S_OK && status != RPC_S_UUID_LOCAL_ONLY) {
        throw std::runtime_error("无法生成 AI Agent 工作区标识");
    }

    std::string result{prefix};
    result.push_back('-');
    result.reserve(result.size() + 36);
    append_hex(result, uuid.Data1, 8);
    result.push_back('-');
    append_hex(result, uuid.Data2, 4);
    result.push_back('-');
    append_hex(result, uuid.Data3, 4);
    result.push_back('-');
    append_hex(result, uuid.Data4[0], 2);
    append_hex(result, uuid.Data4[1], 2);
    result.push_back('-');
    for (std::size_t index = 2; index < std::size(uuid.Data4); ++index) {
        append_hex(result, uuid.Data4[index], 2);
    }
    return result;
}

AgentWorkspaceThread* find_thread(
    AIAgentWorkspaceState& state,
    std::string_view id) {
    const auto found = std::find_if(
        state.threads.begin(),
        state.threads.end(),
        [id](const AgentWorkspaceThread& thread) { return thread.id == id; });
    return found == state.threads.end() ? nullptr : &*found;
}

const AgentWorkspaceProject* find_project(
    const AIAgentWorkspaceState& state,
    const std::optional<std::string>& id) {
    if (!id) {
        return nullptr;
    }
    const auto found = std::find_if(
        state.projects.begin(),
        state.projects.end(),
        [id](const AgentWorkspaceProject& project) { return project.id == *id; });
    return found == state.projects.end() ? nullptr : &*found;
}

const zisla::core::AgentAccount* find_account(
    const zisla::core::AIAgentRoutingState& state,
    std::string_view id) {
    const auto found = std::find_if(
        state.accounts.begin(),
        state.accounts.end(),
        [id](const zisla::core::AgentAccount& account) { return account.id == id; });
    return found == state.accounts.end() ? nullptr : &*found;
}

const zisla::core::AgentChannel* find_channel(
    const zisla::core::AIAgentRoutingState& state,
    std::string_view id) {
    const auto found = std::find_if(
        state.channels.begin(),
        state.channels.end(),
        [id](const zisla::core::AgentChannel& channel) { return channel.id == id; });
    return found == state.channels.end() ? nullptr : &*found;
}

std::vector<std::string> parse_base_urls(std::string_view value) {
    std::vector<std::string> urls;
    while (!value.empty()) {
        const auto delimiter = value.find_first_of(",\n\r");
        urls.push_back(trim_ascii(value.substr(0, delimiter)));
        if (delimiter == std::string_view::npos) {
            break;
        }
        value.remove_prefix(delimiter + 1);
    }
    urls = zisla::core::AgentEndpointGroup::normalize_base_urls(std::move(urls));
    if (urls.empty()) {
        throw std::runtime_error("请填写至少一个 AI Agent Base URL");
    }
    return urls;
}

int parse_endpoint_priority(std::string_view value) {
    const auto trimmed = trim_ascii(value);
    if (trimmed.empty()) {
        return 0;
    }
    int priority = 0;
    const auto [end, error] = std::from_chars(
        trimmed.data(), trimmed.data() + trimmed.size(), priority);
    if (error != std::errc{} || end != trimmed.data() + trimmed.size()
        || priority < -99 || priority > 99) {
        throw std::runtime_error("端点优先级必须是 -99 到 99 之间的整数");
    }
    return priority;
}

struct APIConnectionTarget {
    const zisla::core::AgentEndpointGroup* endpoint_group{nullptr};
    const zisla::core::AgentAccount* account{nullptr};
};

std::optional<APIConnectionTarget> api_connection_target(
    const zisla::core::AIAgentRoutingState& state,
    const zisla::core::AgentChannel& channel) {
    for (const auto& group : channel.endpoint_groups) {
        if (group.base_urls.empty()) {
            continue;
        }
        for (const auto& account_id : group.account_ids) {
            const auto* account = find_account(state, account_id);
            if (account
                && account->credential_kind
                    == zisla::core::AgentAccountCredentialKind::api_key) {
                return APIConnectionTarget{&group, account};
            }
        }
    }
    return std::nullopt;
}

const zisla::core::AgentChannelModelCatalog* model_catalog_for(
    const zisla::core::AIAgentRoutingState& state,
    const zisla::core::AgentChannel& channel,
    const zisla::core::AgentEndpointGroup& group) {
    if (group.base_urls.empty()) {
        return nullptr;
    }
    const auto found = std::find_if(
        state.model_catalogs.begin(),
        state.model_catalogs.end(),
        [&channel, &group](const zisla::core::AgentChannelModelCatalog& catalog) {
            return catalog.channel_id == channel.id
                && catalog.endpoint_group_id == group.id
                && catalog.base_url == group.base_urls.front();
        });
    return found == state.model_catalogs.end() ? nullptr : &*found;
}

std::optional<zisla::core::AgentRoute> route_for_account(
    const zisla::core::AIAgentRoutingState& state,
    std::string_view account_id) {
    for (const auto& channel : state.channels) {
        for (const auto& group : channel.endpoint_groups) {
            const auto account = std::find(
                group.account_ids.begin(), group.account_ids.end(), account_id);
            if (account != group.account_ids.end() && !group.base_urls.empty()) {
                return zisla::core::AgentRoute{
                    .channel_id = channel.id,
                    .endpoint_group_id = group.id,
                    .account_id = std::string(account_id),
                    .base_url = group.base_urls.front(),
                    .protocol_kind = channel.protocol_kind,
                    .model = channel.default_model,
                };
            }
        }
    }
    return std::nullopt;
}

std::optional<zisla::core::AgentRoute> route_for_channel(
    const zisla::core::AIAgentRoutingState& state,
    std::string_view channel_id) {
    const auto* channel = find_channel(state, channel_id);
    if (!channel) {
        return std::nullopt;
    }
    for (const auto& group : channel->endpoint_groups) {
        if (group.base_urls.empty()) {
            continue;
        }
        for (const auto& account_id : group.account_ids) {
            const auto* account = find_account(state, account_id);
            if (account
                && account->credential_kind == zisla::core::AgentAccountCredentialKind::api_key) {
                return zisla::core::AgentRoute{
                    .channel_id = channel->id,
                    .endpoint_group_id = group.id,
                    .account_id = account->id,
                    .base_url = group.base_urls.front(),
                    .protocol_kind = channel->protocol_kind,
                    .model = channel->default_model,
                };
            }
        }
    }
    return std::nullopt;
}

std::optional<std::string> goal_title(
    const AgentWorkspaceThread& thread,
    const AIAgentWorkspaceState& state) {
    if (thread.goal_prompt && !thread.goal_prompt->empty()) {
        return thread.goal_prompt;
    }
    if (!thread.goal_id) {
        return std::nullopt;
    }
    const auto goal = std::find_if(
        state.goals.begin(),
        state.goals.end(),
        [&thread](const zisla::core::AgentWorkspaceGoal& value) {
            return value.id == *thread.goal_id;
        });
    return goal == state.goals.end()
        ? std::nullopt
        : std::optional<std::string>{goal->title};
}

std::runtime_error command_error(const zisla::core::AgentWorkspaceParseError& error) {
    switch (error.code()) {
    case zisla::core::AgentWorkspaceParseErrorCode::missing_skill_name:
        return std::runtime_error("请在 /skill 后指定一个可用 Skill");
    case zisla::core::AgentWorkspaceParseErrorCode::unavailable_skill:
        return std::runtime_error(error.subject().empty()
            ? "所选 Skill 不可用"
            : "所选 Skill 不可用：" + error.subject());
    }
    return std::runtime_error("AI Agent 命令无效");
}

void append_user_message(
    zisla::core::AIAgentWorkspaceRepository& repository,
    const AgentWorkspaceThread& thread,
    const AIAgentWorkspaceState& state,
    std::string content,
    std::vector<zisla::core::AgentWorkspaceSkillReference> skill_references,
    std::int64_t now_unix_ms) {
    if (content.empty()) {
        throw std::runtime_error("请在命令后输入需要保存的消息");
    }
    repository.append_message({
        .id = make_identifier("message"),
        .thread_id = thread.id,
        .role = AgentWorkspaceMessageRole::user,
        .content = std::move(content),
        .skill_references = std::move(skill_references),
        .mode = thread.mode,
        .goal_title = goal_title(thread, state),
        .created_at_unix_ms = now_unix_ms,
    });
}

void update_thread_activity(
    zisla::core::AIAgentWorkspaceRepository& repository,
    AgentWorkspaceThread thread,
    std::int64_t now_unix_ms) {
    thread.updated_at_unix_ms = now_unix_ms;
    repository.upsert_thread(std::move(thread));
}

}  // namespace

AIAgentWorkspaceService::AIAgentWorkspaceService(std::filesystem::path state_directory)
    : repository_(std::move(state_directory)),
      routing_repository_(repository_.directory()),
      snapshot_(std::make_shared<const AIAgentWorkspaceServiceSnapshot>()) {}

AIAgentWorkspaceService::~AIAgentWorkspaceService() {
    stop();
}

bool AIAgentWorkspaceService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || thread_.joinable() || !target || changed_message == 0
        || repository_.directory().empty()) {
        return false;
    }

    commands_.clear();
    loading_ = true;
    revision_ = 0;
    cli_cancellation_requested_.store(false, std::memory_order_release);
    cli_cancellable_.store(false, std::memory_order_release);
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    snapshot_.store(
        std::make_shared<const AIAgentWorkspaceServiceSnapshot>(
            AIAgentWorkspaceServiceSnapshot{.loading = true}),
        std::memory_order_release);
    commands_.push_back({.kind = CommandKind::reload});
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void AIAgentWorkspaceService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    cli_cancellation_requested_.store(true, std::memory_order_release);
    cli_runner_.cancel();
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

void AIAgentWorkspaceService::reload() {
    enqueue({.kind = CommandKind::reload});
}

void AIAgentWorkspaceService::createThread() {
    enqueue({.kind = CommandKind::create_thread});
}

void AIAgentWorkspaceService::removeThread(std::string thread_id) {
    if (!thread_id.empty()) {
        enqueue({
            .kind = CommandKind::remove_thread,
            .thread_id = std::move(thread_id),
        });
    }
}

void AIAgentWorkspaceService::submitMessage(
    std::string thread_id,
    std::string content,
    std::vector<zisla::core::AgentSkill> skills,
    std::optional<zisla::core::AgentCLIKind> cli_kind,
    std::optional<std::string> channel_id) {
    if (!thread_id.empty()) {
        enqueue({
            .kind = CommandKind::submit_message,
            .thread_id = std::move(thread_id),
            .channel_id = std::move(channel_id).value_or(std::string{}),
            .content = std::move(content),
            .skills = std::move(skills),
            .cli_kind = cli_kind,
        });
    }
}

void AIAgentWorkspaceService::cancelActiveRequest() noexcept {
    if (!cli_cancellable_.load(std::memory_order_acquire)) {
        return;
    }
    cli_cancellation_requested_.store(true, std::memory_order_release);
    cli_runner_.cancel();
}

void AIAgentWorkspaceService::refreshAccountBalance(std::string account_id) {
    if (!account_id.empty()) {
        enqueue({
            .kind = CommandKind::refresh_account_balance,
            .account_id = std::move(account_id),
        });
    }
}

void AIAgentWorkspaceService::refreshChannelModels(std::string channel_id) {
    if (!channel_id.empty()) {
        enqueue({
            .kind = CommandKind::refresh_channel_models,
            .channel_id = std::move(channel_id),
        });
    }
}

void AIAgentWorkspaceService::configureAPIConnection(
    std::optional<std::string> channel_id,
    zisla::core::AgentChannelProtocol protocol,
    std::string name,
    std::string base_url,
    std::string model,
    std::string endpoint_priority,
    std::string api_key,
    std::optional<zisla::core::AgentBalanceProbe> balance_probe) {
    enqueue({
        .kind = CommandKind::configure_api_connection,
        .channel_id = std::move(channel_id).value_or(std::string{}),
        .protocol = protocol,
        .connection_name = std::move(name),
        .base_url = std::move(base_url),
        .model = std::move(model),
        .endpoint_priority = std::move(endpoint_priority),
        .api_key = std::move(api_key),
        .balance_probe = std::move(balance_probe),
    });
}

void AIAgentWorkspaceService::removeAPIConnection(std::string channel_id) {
    if (!channel_id.empty()) {
        enqueue({
            .kind = CommandKind::remove_api_connection,
            .channel_id = std::move(channel_id),
        });
    }
}

std::shared_ptr<const AIAgentWorkspaceServiceSnapshot>
AIAgentWorkspaceService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void AIAgentWorkspaceService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        if (command.kind == CommandKind::reload) {
            std::erase_if(commands_, [](const Command& pending) {
                return pending.kind == CommandKind::reload;
            });
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void AIAgentWorkspaceService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (!running_) {
                commands_.clear();
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        try {
            loading_ = true;
            publish(std::nullopt);
            const auto preferred_thread_id = execute(std::move(command));
            loading_ = false;
            publish(preferred_thread_id);
        } catch (const std::exception& error) {
            loading_ = false;
            publishError(error.what());
        } catch (...) {
            loading_ = false;
            publishError("AI Agent 工作区操作失败");
        }
    }
}

std::optional<std::string> AIAgentWorkspaceService::execute(Command command) {
    switch (command.kind) {
    case CommandKind::reload:
        return std::nullopt;
    case CommandKind::create_thread: {
        const auto now_unix_ms = now_unix_milliseconds();
        AgentWorkspaceThread thread{
            .id = make_identifier("thread"),
            .title = "新对话",
            .created_at_unix_ms = now_unix_ms,
            .updated_at_unix_ms = now_unix_ms,
        };
        const auto routing = routing_repository_.load();
        if (const auto channel_id = zisla::core::AIAgentChatRequestPlanner::
                default_api_channel_id(routing)) {
            thread.channel_id = *channel_id;
            if (const auto* channel = find_channel(routing, *channel_id)) {
                thread.selected_model = channel->default_model;
            }
        }
        repository_.upsert_thread(thread);
        return thread.id;
    }
    case CommandKind::remove_thread:
        (void)repository_.remove_thread(command.thread_id);
        return std::nullopt;
    case CommandKind::configure_api_connection:
        configureAPIConnection(command);
        return std::nullopt;
    case CommandKind::remove_api_connection:
        removeAPIConnection(command);
        return std::nullopt;
    case CommandKind::refresh_account_balance:
        refreshAccountBalance(command);
        return std::nullopt;
    case CommandKind::refresh_channel_models:
        refreshChannelModels(command);
        return std::nullopt;
    case CommandKind::submit_message:
        break;
    }

    auto state = repository_.load();
    auto* thread = find_thread(state, command.thread_id);
    if (!thread) {
        throw std::runtime_error("AI Agent 会话不存在");
    }

    zisla::core::AgentWorkspaceCommand parsed;
    try {
        parsed = zisla::core::AgentWorkspaceCommandParser::parse(command.content, command.skills);
    } catch (const zisla::core::AgentWorkspaceParseError& error) {
        throw command_error(error);
    }

    const auto now_unix_ms = now_unix_milliseconds();
    const auto requested_channel_id = command.channel_id.empty()
        ? std::optional<std::string>{}
        : std::optional<std::string>{command.channel_id};
    if (thread->cli_kind != command.cli_kind
        || (!command.cli_kind && thread->channel_id != requested_channel_id)) {
        thread->cli_kind = command.cli_kind;
        thread->account_id.reset();
        if (thread->cli_kind) {
            thread->channel_id.reset();
        } else {
            thread->channel_id = requested_channel_id;
        }
        update_thread_activity(repository_, *thread, now_unix_ms);
    }
    bool should_request_completion = false;
    std::visit(
        [this, &state, thread, now_unix_ms, &should_request_completion](const auto& value) {
            using CommandType = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<CommandType, AgentWorkspaceSetModeCommand>) {
                thread->mode = value.mode;
                if (thread->goal_prompt && !value.content.empty()) {
                    thread->goal_prompt = value.content;
                }
                update_thread_activity(repository_, *thread, now_unix_ms);
                if (!value.content.empty()) {
                    append_user_message(
                        repository_,
                        *thread,
                        state,
                        value.content,
                        {},
                        now_unix_ms);
                    should_request_completion = true;
                }
            } else if constexpr (std::is_same_v<CommandType, AgentWorkspaceSetGoalPromptCommand>) {
                thread->goal_prompt = value.content;
                update_thread_activity(repository_, *thread, now_unix_ms);
                if (!value.content.empty()) {
                    append_user_message(
                        repository_,
                        *thread,
                        state,
                        value.content,
                        {},
                        now_unix_ms);
                    should_request_completion = true;
                }
            } else if constexpr (std::is_same_v<CommandType, AgentWorkspaceMessageCommand>) {
                if (thread->goal_prompt && !value.content.empty()) {
                    thread->goal_prompt = value.content;
                    update_thread_activity(repository_, *thread, now_unix_ms);
                }
                append_user_message(
                    repository_,
                    *thread,
                    state,
                    value.content,
                    value.skill_references,
                    now_unix_ms);
                should_request_completion = !value.content.empty();
                if (!thread->goal_prompt || value.content.empty()) {
                    update_thread_activity(repository_, *thread, now_unix_ms);
                }
            }
        },
        parsed);
    if (should_request_completion) {
        auto updated_state = repository_.load();
        auto* updated_thread = find_thread(updated_state, command.thread_id);
        if (!updated_thread) {
            throw std::runtime_error("AI Agent 会话不存在");
        }
        requestCompletion(
            updated_state,
            *updated_thread,
            now_unix_ms);
    }
    return command.thread_id;
}

void AIAgentWorkspaceService::configureAPIConnection(Command& command) {
    const auto name = trim_ascii(command.connection_name);
    const auto model = trim_ascii(command.model);
    if (model.empty()) {
        throw std::runtime_error("请填写模型名称");
    }
    const auto base_urls = parse_base_urls(command.base_url);
    const auto endpoint_priority = parse_endpoint_priority(command.endpoint_priority);
    try {
        for (const auto& base_url : base_urls) {
            AIAgentHTTPClient::validateBaseUrl(command.protocol, base_url, model);
        }
    } catch (...) {
        throw std::runtime_error("AI Agent Base URL、协议或模型无效或不安全");
    }

    const auto routing = routing_repository_.load();
    const auto* existing_channel = command.channel_id.empty()
        ? nullptr
        : find_channel(routing, command.channel_id);
    if (!command.channel_id.empty() && !existing_channel) {
        throw std::runtime_error("所选 AI Agent 渠道已不存在");
    }
    const auto target = existing_channel
        ? api_connection_target(routing, *existing_channel)
        : std::optional<APIConnectionTarget>{};
    const auto channel_id = existing_channel ? existing_channel->id : make_identifier("channel");
    const auto account_id = target ? target->account->id : make_identifier("account");
    const auto secret_reference = target
        ? target->account->secret_reference
        : api_secret_reference_for_account(account_id);
    if (!command.api_key.empty()) {
        [[maybe_unused]] SensitiveString api_key_clearer(command.api_key);
        if (!credential_store_.write(secret_reference, command.api_key)) {
            throw std::runtime_error("无法保存 API Key 到 Windows Credential Manager");
        }
    } else {
        auto existing_key = credential_store_.read(secret_reference);
        if (!existing_key) {
            throw std::runtime_error("请填写 API Key");
        }
        [[maybe_unused]] SensitiveString existing_key_clearer(*existing_key);
    }

    const std::string display_name = name.empty() ? "AI API" : name;
    auto account = target ? *target->account : zisla::core::AgentAccount{};
    if (account.balance_probe != command.balance_probe) {
        account.balance.reset();
    }
    account.id = account_id;
    account.name = display_name;
    account.provider = display_name;
    account.secret_reference = secret_reference;
    account.credential_kind = zisla::core::AgentAccountCredentialKind::api_key;
    account.cli_profile.reset();
    account.is_enabled = true;
    account.balance_probe = command.balance_probe;
    account.consecutive_failures = 0;
    account.disabled_until_unix_ms.reset();
    routing_repository_.upsert_account(account);
    auto endpoint_groups = existing_channel
        ? existing_channel->endpoint_groups
        : std::vector<zisla::core::AgentEndpointGroup>{};
    if (target) {
        const auto group = std::find_if(
            endpoint_groups.begin(), endpoint_groups.end(), [target](const auto& value) {
                return value.id == target->endpoint_group->id;
            });
        if (group == endpoint_groups.end()) {
            throw std::runtime_error("所选 AI Agent 端点组已不存在");
        }
        *group = zisla::core::AgentEndpointGroup::make(
            group->id,
            group->name.empty() ? display_name : group->name,
            base_urls,
            group->account_ids,
            true,
            endpoint_priority);
    } else if (endpoint_groups.empty()) {
        endpoint_groups.push_back(zisla::core::AgentEndpointGroup::make(
            make_identifier("endpoint"),
            display_name,
            base_urls,
            {account.id},
            true,
            endpoint_priority));
    } else {
        auto& group = endpoint_groups.front();
        auto account_ids = group.account_ids;
        if (std::find(account_ids.begin(), account_ids.end(), account.id) == account_ids.end()) {
            account_ids.push_back(account.id);
        }
        group = zisla::core::AgentEndpointGroup::make(
            group.id,
            group.name.empty() ? display_name : group.name,
            base_urls,
            account_ids,
            true,
            endpoint_priority);
    }
    routing_repository_.upsert_channel({
        .id = channel_id,
        .name = display_name,
        .protocol_kind = command.protocol,
        .default_model = model,
        .endpoint_groups = std::move(endpoint_groups),
        .is_enabled = true,
    });
    route_router_.reset_channel(channel_id);
    preferred_connection_channel_id_ = channel_id;
}

void AIAgentWorkspaceService::removeAPIConnection(Command& command) {
    if (!routing_repository_.remove_channel(command.channel_id)) {
        throw std::runtime_error("所选 AI Agent 渠道已不存在");
    }
    route_router_.reset_channel(command.channel_id);
    if (preferred_connection_channel_id_ == command.channel_id) {
        preferred_connection_channel_id_.reset();
    }
}

void AIAgentWorkspaceService::refreshAccountBalance(Command& command) {
    const auto routing = routing_repository_.load();
    const auto* account = find_account(routing, command.account_id);
    if (!account || !account->balance_probe) {
        throw std::runtime_error("所选 AI Agent 账号未配置余额检测");
    }
    if (account->credential_kind != zisla::core::AgentAccountCredentialKind::api_key) {
        throw std::runtime_error("CLI 账号不支持 API 余额检测");
    }
    const auto route = route_for_account(routing, account->id);
    if (!route) {
        throw std::runtime_error("所选 AI Agent 账号没有可用端点");
    }
    auto api_key = credential_store_.read(account->secret_reference);
    if (!api_key) {
        throw std::runtime_error("所选 AI Agent 账号未配置 API Key");
    }
    [[maybe_unused]] SensitiveString api_key_clearer(*api_key);
    const auto now_unix_ms = now_unix_milliseconds();
    const auto balance = http_client_.checkBalance(
        *account->balance_probe, *route, *api_key, now_unix_ms);
    if (!routing_repository_.record_balance(account->id, balance)) {
        throw std::runtime_error("AI Agent 账号已不存在");
    }
}

void AIAgentWorkspaceService::refreshChannelModels(Command& command) {
    const auto routing = routing_repository_.load();
    const auto route = route_for_channel(routing, command.channel_id);
    if (!route) {
        throw std::runtime_error("所选 AI Agent 渠道没有 API Key 账号或端点");
    }
    const auto* account = find_account(routing, route->account_id);
    if (!account) {
        throw std::runtime_error("AI Agent 路由账号不可用");
    }
    auto api_key = credential_store_.read(account->secret_reference);
    if (!api_key) {
        throw std::runtime_error("所选 AI Agent 账号未配置 API Key");
    }
    [[maybe_unused]] SensitiveString api_key_clearer(*api_key);
    const auto now_unix_ms = now_unix_milliseconds();
    const auto probe = http_client_.probe(*route, *api_key, now_unix_ms);
    routing_repository_.replace_channel_probe(probe);
    const auto catalog = http_client_.fetchModelCatalog(*route, *api_key, now_unix_ms);
    if (catalog.detail) {
        throw std::runtime_error("无法获取 AI Agent 模型目录");
    }
    routing_repository_.replace_model_catalog(catalog);
}

void AIAgentWorkspaceService::requestCompletion(
    zisla::core::AIAgentWorkspaceState& state,
    zisla::core::AgentWorkspaceThread& thread,
    std::int64_t now_unix_ms) {
    if (thread.cli_kind) {
        requestCLICompletion(state, thread);
        return;
    }
    requestAPICompletion(state, thread, now_unix_ms);
}

void AIAgentWorkspaceService::requestCLICompletion(
    zisla::core::AIAgentWorkspaceState& state,
    zisla::core::AgentWorkspaceThread& thread) {
    if (!thread.cli_kind) {
        throw std::logic_error("AI Agent CLI 类型缺失");
    }
    const auto* project = find_project(state, thread.project_id);
    const auto project_context = project
        ? std::optional<zisla::core::AgentCLIRelayProjectContext>{
            zisla::core::AgentCLIRelayProjectContext{
                .name = project->name,
                .instructions = project->instructions,
            }}
        : std::nullopt;

    zisla::core::AgentCLIRelayCommand command;
    try {
        command = zisla::core::AIAgentCLIRelay::make_command(
            *thread.cli_kind,
            state.messages,
            thread,
            project_context);
    } catch (const std::length_error&) {
        throw std::runtime_error("AI Agent CLI 转发内容超过大小限制");
    } catch (const std::invalid_argument&) {
        throw std::runtime_error("AI Agent CLI 没有可转发的消息");
    }

    cli_cancellation_requested_.store(false, std::memory_order_release);
    cli_cancellable_.store(true, std::memory_order_release);
    struct CancellationReset {
        std::atomic_bool& cancellation_requested;
        std::atomic_bool& cancellable;

        ~CancellationReset() {
            cancellation_requested.store(false, std::memory_order_release);
            cancellable.store(false, std::memory_order_release);
        }
    };
    [[maybe_unused]] CancellationReset cancellation_reset{
        cli_cancellation_requested_,
        cli_cancellable_};
    publish(thread.id);

    const auto working_directory = project
        ? path_from_utf8(project->directory_path)
        : std::filesystem::path{};
    const auto result = cli_runner_.run(
        command,
        working_directory,
        cli_cancellation_requested_);
    if (result.cancelled) {
        return;
    }
    if (result.timed_out) {
        throw std::runtime_error("AI Agent CLI 请求超时，请检查 CLI 状态后重试");
    }
    if (result.output_limit_exceeded) {
        throw std::runtime_error("AI Agent CLI 输出超过安全上限");
    }
    if (result.exit_code != 0) {
        throw std::runtime_error(
            "AI Agent CLI 执行失败（退出码 " + std::to_string(result.exit_code)
            + "）。请在终端检查登录和配置。");
    }

    std::string assistant_content;
    try {
        assistant_content = zisla::core::AIAgentCLIRelay::response_from_stdout(
            result.standard_output);
    } catch (const std::length_error&) {
        throw std::runtime_error("AI Agent CLI 输出超过安全上限");
    }
    if (assistant_content.empty()) {
        throw std::runtime_error("AI Agent CLI 没有返回消息");
    }
    const auto account_id = "cli:" + std::string(zisla::core::agent_cli_kind_token(*thread.cli_kind));
    repository_.append_message({
        .id = make_identifier("message"),
        .thread_id = thread.id,
        .role = AgentWorkspaceMessageRole::assistant,
        .content = std::move(assistant_content),
        .account_id = account_id,
        .mode = thread.mode,
        .goal_title = goal_title(thread, state),
        .created_at_unix_ms = now_unix_milliseconds(),
    });
    thread.channel_id.reset();
    thread.account_id = account_id;
    update_thread_activity(repository_, thread, now_unix_milliseconds());
}

void AIAgentWorkspaceService::requestAPICompletion(
    zisla::core::AIAgentWorkspaceState& state,
    zisla::core::AgentWorkspaceThread& thread,
    std::int64_t now_unix_ms) {
    const auto routing = routing_repository_.load();
    zisla::core::AIAgentChatRequestPlan plan;
    try {
        plan = zisla::core::AIAgentChatRequestPlanner::make_plan(
            state,
            thread,
            routing,
            route_router_,
            now_unix_ms);
    } catch (...) {
        throw std::runtime_error("没有可用的 AI Agent API 渠道或路由");
    }
    const auto* account = find_account(routing, plan.route.account_id);
    if (!account) {
        throw std::runtime_error("AI Agent 路由账号不可用");
    }

    auto api_key = credential_store_.read(account->secret_reference);
    if (!api_key) {
        throw std::runtime_error("所选 AI Agent 账号未配置 API Key");
    }
    [[maybe_unused]] SensitiveString api_key_clearer(*api_key);

    std::string assistant_content;
    try {
        assistant_content = http_client_.complete(
            plan.route,
            *api_key,
            plan.request);
    } catch (...) {
        try {
            (void)routing_repository_.record_route_failure(
                account->id,
                now_unix_ms);
        } catch (...) {
        }
        throw std::runtime_error(
            "AI Agent 请求失败。请检查渠道地址、模型、API Key、网络和配额。");
    }

    repository_.append_message({
        .id = make_identifier("message"),
        .thread_id = thread.id,
        .role = AgentWorkspaceMessageRole::assistant,
        .content = std::move(assistant_content),
        .account_id = account->id,
        .mode = thread.mode,
        .goal_title = goal_title(thread, state),
        .created_at_unix_ms = now_unix_milliseconds(),
    });
    thread.channel_id = plan.route.channel_id;
    thread.account_id = account->id;
    thread.selected_model = plan.route.model;
    update_thread_activity(repository_, thread, now_unix_milliseconds());
    (void)routing_repository_.record_route_success(account->id);
}

std::vector<AIAgentAPIConnectionSummary> AIAgentWorkspaceService::connectionSummaries(
    const zisla::core::AIAgentRoutingState& routing) {
    std::vector<AIAgentAPIConnectionSummary> result;
    result.reserve(routing.channels.size());
    for (const auto& channel : routing.channels) {
        AIAgentAPIConnectionSummary summary{
            .channel_id = channel.id,
            .name = channel.name,
            .model = channel.default_model,
            .protocol = channel.protocol_kind,
        };
        const auto target = api_connection_target(routing, channel);
        const auto* group = target ? target->endpoint_group : nullptr;
        if (!group) {
            const auto found = std::find_if(
                channel.endpoint_groups.begin(),
                channel.endpoint_groups.end(), [](const auto& value) {
                    return !value.base_urls.empty();
                });
            group = found == channel.endpoint_groups.end() ? nullptr : &*found;
        }
        if (group) {
            summary.base_urls = group->base_urls;
            summary.endpoint_priority = group->priority;
            if (const auto* catalog = model_catalog_for(routing, channel, *group)) {
                summary.model_catalog = catalog->models;
            }
        }
        if (target) {
            summary.account_id = target->account->id;
            summary.balance_probe = target->account->balance_probe;
            summary.balance = target->account->balance;
            summary.is_configured = channel.is_enabled && group && group->is_enabled
                && target->account->is_enabled;
            auto api_key = credential_store_.read(target->account->secret_reference);
            if (api_key) {
                [[maybe_unused]] SensitiveString api_key_clearer(*api_key);
                summary.has_stored_api_key = true;
            }
        }
        result.push_back(std::move(summary));
    }
    return result;
}

void AIAgentWorkspaceService::publish(
    std::optional<std::string> preferred_thread_id) {
    auto state = repository_.load();
    auto routing = routing_repository_.load();
    auto next = std::make_shared<const AIAgentWorkspaceServiceSnapshot>(
        AIAgentWorkspaceServiceSnapshot{
            .state = std::move(state),
            .routing = routing,
            .preferred_thread_id = std::move(preferred_thread_id),
            .preferred_connection_channel_id = preferred_connection_channel_id_,
            .connections = connectionSummaries(routing),
            .loading = loading_,
            .can_cancel = cli_cancellable_.load(std::memory_order_acquire),
            .revision = ++revision_,
        });
    snapshot_.store(std::move(next), std::memory_order_release);
    notify();
}

void AIAgentWorkspaceService::publishError(std::string error) noexcept {
    try {
        const auto current = snapshot();
        auto state = current ? current->state : AIAgentWorkspaceState{};
        auto routing = current ? current->routing : zisla::core::AIAgentRoutingState{};
        auto connections = current
            ? current->connections
            : std::vector<AIAgentAPIConnectionSummary>{};
        try {
            state = repository_.load();
        } catch (...) {
        }
        try {
            routing = routing_repository_.load();
        } catch (...) {
        }
        try {
            connections = connectionSummaries(routing);
        } catch (...) {
        }
        auto next = std::make_shared<const AIAgentWorkspaceServiceSnapshot>(
            AIAgentWorkspaceServiceSnapshot{
                .state = std::move(state),
                .routing = std::move(routing),
                .preferred_connection_channel_id = preferred_connection_channel_id_,
                .connections = std::move(connections),
                .error = std::move(error),
                .loading = false,
                .can_cancel = cli_cancellable_.load(std::memory_order_acquire),
                .revision = ++revision_,
            });
        snapshot_.store(std::move(next), std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void AIAgentWorkspaceService::notify() noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
