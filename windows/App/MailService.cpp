#include "pch.h"
#include "MailService.h"
#include "WinHttpRequest.h"

#include <chrono>
#include <charconv>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr std::string_view credential_reference = "graph";
constexpr std::int64_t refresh_leeway_seconds = 60;

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

class SensitiveWideString {
public:
    explicit SensitiveWideString(std::wstring& value) noexcept : value_(value) {}

    ~SensitiveWideString() {
        if (!value_.empty()) {
            SecureZeroMemory(value_.data(), value_.size() * sizeof(wchar_t));
        }
    }

    SensitiveWideString(const SensitiveWideString&) = delete;
    SensitiveWideString& operator=(const SensitiveWideString&) = delete;

private:
    std::wstring& value_;
};

std::int64_t unix_seconds() noexcept {
    return std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

bool contains_control(std::string_view value) noexcept {
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        if (byte < 0x20U || byte == 0x7fU) {
            return true;
        }
    }
    return false;
}

std::optional<std::wstring> wide_from_utf8(std::string_view value) {
    if (value.empty()) {
        return std::wstring{};
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }
    const auto length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) {
        return std::nullopt;
    }
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length) != length) {
        return std::nullopt;
    }
    return result;
}

std::optional<MailService::TokenState> parse_stored_token(std::string_view value) {
    const auto first = value.find('\n');
    const auto second = first == std::string_view::npos
        ? std::string_view::npos
        : value.find('\n', first + 1);
    if (first == std::string_view::npos || second == std::string_view::npos
        || value.find('\n', second + 1) != std::string_view::npos) {
        return std::nullopt;
    }
    const auto access = value.substr(0, first);
    const auto refresh = value.substr(first + 1, second - first - 1);
    const auto expiry = value.substr(second + 1);
    if (access.empty() || refresh.empty() || expiry.empty()
        || contains_control(access) || contains_control(refresh)) {
        return std::nullopt;
    }
    std::int64_t expires_at = 0;
    const auto [parsed_end, error] = std::from_chars(
        expiry.data(),
        expiry.data() + expiry.size(),
        expires_at);
    if (error != std::errc{} || parsed_end != expiry.data() + expiry.size()
        || expires_at <= 0) {
        return std::nullopt;
    }
    return MailService::TokenState{
        .access_token = std::string(access),
        .refresh_token = std::string(refresh),
        .expires_at_unix_seconds = expires_at,
    };
}

std::string token_secret(const zisla::core::GraphToken& token) {
    if (token.access_token.empty() || token.refresh_token.empty()
        || contains_control(token.access_token) || contains_control(token.refresh_token)) {
        throw std::runtime_error("Microsoft Graph 返回了无效令牌");
    }
    const auto now = unix_seconds();
    const auto lifetime = std::max<std::int64_t>(
        1,
        static_cast<std::int64_t>(token.expires_in_seconds));
    if (now > std::numeric_limits<std::int64_t>::max() - lifetime) {
        throw std::runtime_error("Microsoft Graph 令牌过期时间无效");
    }
    return token.access_token + "\n" + token.refresh_token + "\n"
        + std::to_string(now + lifetime);
}

void require_configured(const MailConnectionSettings& settings) {
    if (settings.client_id.empty()) {
        throw std::runtime_error("请先在设置中填写 Microsoft Graph 客户端标识");
    }
    (void)zisla::core::GraphOAuthRequestBuilder::device_code_url(settings.tenant);
    (void)zisla::core::GraphOAuthRequestBuilder::device_code_body(settings.client_id);
}

}  // namespace

MailService::MailService(MailConnectionSettings settings)
    : snapshot_(std::make_shared<const MailServiceSnapshot>()),
      settings_(std::move(settings)) {}

MailService::~MailService() {
    stop();
}

bool MailService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    commands_.push_back({.kind = CommandKind::configure, .settings = settings_});
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

void MailService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_all();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

void MailService::configure(MailConnectionSettings settings) {
    bool clear_credentials = false;
    {
        std::lock_guard lock(mutex_);
        clear_credentials = settings_.tenant != settings.tenant
            || settings_.client_id != settings.client_id;
        settings_ = std::move(settings);
    }
    enqueue({
        .kind = CommandKind::configure,
        .settings = configuration(),
        .clear_credentials = clear_credentials,
    });
}

void MailService::refresh() {
    enqueue({.kind = CommandKind::refresh});
}

void MailService::begin_authorization() {
    enqueue({.kind = CommandKind::authorize});
}

void MailService::mark_read(std::string message_id) {
    enqueue({.kind = CommandKind::mark_read, .message_id = std::move(message_id)});
}

void MailService::move_to_junk(std::string message_id) {
    enqueue({.kind = CommandKind::move_to_junk, .message_id = std::move(message_id)});
}

void MailService::move_to_deleted(std::string message_id) {
    enqueue({.kind = CommandKind::move_to_deleted, .message_id = std::move(message_id)});
}

void MailService::send(
    std::vector<zisla::core::MailRecipient> recipients,
    std::string subject,
    std::string body) {
    enqueue({
        .kind = CommandKind::send,
        .recipients = std::move(recipients),
        .subject = std::move(subject),
        .body = std::move(body),
    });
}

void MailService::reply(std::string message_id, std::string body) {
    enqueue({
        .kind = CommandKind::reply,
        .message_id = std::move(message_id),
        .body = std::move(body),
    });
}

std::shared_ptr<const MailServiceSnapshot> MailService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void MailService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        if (command.kind == CommandKind::refresh) {
            commands_.erase(
                std::remove_if(
                    commands_.begin(),
                    commands_.end(),
                    [](const Command& pending) {
                        return pending.kind == CommandKind::refresh;
                    }),
                commands_.end());
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void MailService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }
        try {
            execute(std::move(command));
        } catch (const std::exception& error) {
            publish_error(error.what());
        } catch (...) {
            publish_error("邮件服务发生未知错误");
        }
    }
}

void MailService::execute(Command command) {
    const auto settings = command.kind == CommandKind::configure
        ? command.settings
        : configuration();
    switch (command.kind) {
    case CommandKind::configure:
        if (command.clear_credentials) {
            clear_token();
        }
        publish({
            .phase = settings.client_id.empty()
                ? MailServicePhase::not_configured
                : MailServicePhase::idle,
            .connection = settings,
            .message = settings.client_id.empty()
                ? "请在设置中连接 Microsoft Graph 邮箱"
                : "Microsoft Graph 邮箱已配置",
        });
        return;
    case CommandKind::refresh:
        refresh_inbox(settings);
        return;
    case CommandKind::authorize:
        authorize(settings);
        return;
    case CommandKind::mark_read:
        mutate(settings, zisla::core::GraphMailRequestBuilder::mark_read(command.message_id));
        return;
    case CommandKind::move_to_junk:
        mutate(settings, zisla::core::GraphMailRequestBuilder::move_to_junk(command.message_id));
        return;
    case CommandKind::move_to_deleted:
        mutate(settings, zisla::core::GraphMailRequestBuilder::move_to_deleted(command.message_id));
        return;
    case CommandKind::send:
        mutate(settings, zisla::core::GraphMailRequestBuilder::send(
            command.recipients,
            command.subject,
            command.body));
        return;
    case CommandKind::reply:
        mutate(settings, zisla::core::GraphMailRequestBuilder::reply(
            command.message_id,
            command.body));
        return;
    }
}

void MailService::refresh_inbox(const MailConnectionSettings& settings) {
    require_configured(settings);
    publish({
        .phase = MailServicePhase::loading,
        .connection = settings,
        .message = "正在读取收件箱",
    });
    auto token = access_token(settings);
    SensitiveString access_token_clearer(token.access_token);
    SensitiveString refresh_token_clearer(token.refresh_token);
    const auto response = graph_request(
        zisla::core::GraphMailRequestBuilder::inbox(),
        token.access_token);
    const auto inbox = zisla::core::GraphMailResponseParser::parse_inbox(response);
    publish({
        .phase = MailServicePhase::ready,
        .connection = settings,
        .messages = inbox.messages,
        .message = inbox.messages.empty() ? "收件箱没有可显示的邮件" : "收件箱已更新",
    });
}

void MailService::mutate(
    const MailConnectionSettings& settings,
    zisla::core::GraphMailRequest request) {
    require_configured(settings);
    publish({
        .phase = MailServicePhase::loading,
        .connection = settings,
        .message = "正在更新邮件",
    });
    auto token = access_token(settings);
    SensitiveString access_token_clearer(token.access_token);
    SensitiveString refresh_token_clearer(token.refresh_token);
    (void)graph_request(request, token.access_token);
    refresh_inbox(settings);
}

void MailService::authorize(const MailConnectionSettings& settings) {
    require_configured(settings);
    const auto device_response = token_request(
        zisla::core::GraphOAuthRequestBuilder::device_code_url(settings.tenant),
        zisla::core::GraphOAuthRequestBuilder::device_code_body(settings.client_id));
    const auto device_code = zisla::core::GraphOAuthResponseParser::parse_device_code(device_response);
    publish({
        .phase = MailServicePhase::authorization_required,
        .connection = settings,
        .device_code = device_code,
        .message = "请在浏览器中完成 Microsoft 登录",
    });

    const auto deadline = std::chrono::steady_clock::now()
        + std::chrono::seconds(device_code.expires_in_seconds);
    auto interval = device_code.interval_seconds;
    while (std::chrono::steady_clock::now() < deadline) {
        if (!wait_for_authorization_interval(interval)) {
            return;
        }
        const auto token_response = token_request(
            zisla::core::GraphOAuthRequestBuilder::token_url(settings.tenant),
            zisla::core::GraphOAuthRequestBuilder::token_poll_body(
                settings.client_id,
                device_code.device_code));
        const auto parsed = zisla::core::GraphOAuthResponseParser::parse_token(token_response);
        if (parsed.token) {
            store_token(*parsed.token);
            refresh_inbox(settings);
            return;
        }
        if (parsed.error == "authorization_pending") {
            continue;
        }
        if (parsed.error == "slow_down") {
            interval = std::min<std::uint32_t>(interval + 5, 60);
            continue;
        }
        throw std::runtime_error(parsed.error_description.empty()
            ? "Microsoft Graph 登录失败"
            : parsed.error_description);
    }
    throw std::runtime_error("Microsoft Graph 登录超时，请重新开始");
}

MailConnectionSettings MailService::configuration() const {
    std::lock_guard lock(mutex_);
    return settings_;
}

MailService::TokenState MailService::access_token(const MailConnectionSettings& settings) {
    auto stored = stored_token();
    if (!stored) {
        throw std::runtime_error("请先在设置中完成 Microsoft Graph 登录");
    }
    if (stored->expires_at_unix_seconds > unix_seconds() + refresh_leeway_seconds) {
        return *stored;
    }

    SensitiveString refresh_token_clearer(stored->refresh_token);
    const auto response = token_request(
        zisla::core::GraphOAuthRequestBuilder::token_url(settings.tenant),
        zisla::core::GraphOAuthRequestBuilder::refresh_token_body(
            settings.client_id,
            stored->refresh_token));
    const auto parsed = zisla::core::GraphOAuthResponseParser::parse_token(response);
    if (!parsed.token) {
        clear_token();
        throw std::runtime_error(parsed.error_description.empty()
            ? "Microsoft Graph 登录已失效，请重新登录"
            : parsed.error_description);
    }
    store_token(*parsed.token);
    auto refreshed = stored_token();
    if (!refreshed) {
        throw std::runtime_error("无法保存 Microsoft Graph 登录状态");
    }
    return *refreshed;
}

std::optional<MailService::TokenState> MailService::stored_token() {
    auto secret = credential_store_.read(credential_reference);
    if (!secret) {
        return std::nullopt;
    }
    SensitiveString clearer(*secret);
    return parse_stored_token(*secret);
}

void MailService::store_token(const zisla::core::GraphToken& token) {
    auto secret = token_secret(token);
    SensitiveString clearer(secret);
    if (!credential_store_.write(credential_reference, secret)) {
        throw std::runtime_error(credential_store_.last_error().empty()
            ? "无法保存 Microsoft Graph 登录状态"
            : credential_store_.last_error());
    }
}

void MailService::clear_token() noexcept {
    (void)credential_store_.erase(credential_reference);
}

std::string MailService::graph_request(
    const zisla::core::GraphMailRequest& request,
    std::string_view access_token) {
    if (access_token.empty() || access_token.size() > 16U * 1024U
        || contains_control(access_token)) {
        throw std::runtime_error("Microsoft Graph 访问令牌无效");
    }
    const auto wide_token = wide_from_utf8(access_token);
    if (!wide_token) {
        throw std::runtime_error("Microsoft Graph 访问令牌无效");
    }
    std::wstring headers = L"Authorization: Bearer ";
    headers.append(*wide_token);
    headers.append(L"\r\nAccept: application/json\r\n");
    if (!request.body.empty()) {
        headers.append(L"Content-Type: application/json\r\n");
    }
    SensitiveWideString headers_clearer(headers);
    const auto response = WinHttpRequest::send(
        request.method,
        request.url,
        headers,
        request.body,
        zisla::core::GraphMailResponseParser::maximum_response_bytes);
    if (response.status < 200 || response.status >= 300) {
        throw std::runtime_error("Microsoft Graph 返回 HTTP " + std::to_string(response.status));
    }
    return response.body;
}

std::string MailService::token_request(
    std::string_view url,
    std::string_view body) {
    const auto response = WinHttpRequest::send(
        "POST",
        url,
        L"Accept: application/json\r\n"
        L"Content-Type: application/x-www-form-urlencoded\r\n",
        body,
        zisla::core::GraphOAuthResponseParser::maximum_response_bytes);
    if ((response.status < 200 || response.status >= 300) && response.status != 400) {
        throw std::runtime_error("Microsoft Graph 授权服务返回 HTTP "
            + std::to_string(response.status));
    }
    return response.body;
}

bool MailService::wait_for_authorization_interval(std::uint32_t seconds) noexcept {
    std::unique_lock lock(mutex_);
    return !condition_.wait_for(
        lock,
        std::chrono::seconds(seconds),
        [this] { return !running_; });
}

void MailService::publish(MailServiceSnapshot snapshot) noexcept {
    try {
        snapshot_.store(
            std::make_shared<const MailServiceSnapshot>(std::move(snapshot)),
            std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void MailService::publish_error(std::string message) noexcept {
    auto current = snapshot();
    publish({
        .phase = MailServicePhase::failed,
        .connection = current ? current->connection : configuration(),
        .messages = current ? current->messages : std::vector<zisla::core::MailMessage>{},
        .message = std::move(message),
    });
}

void MailService::notify() noexcept {
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
