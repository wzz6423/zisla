#pragma once

#include "AIAgentCredentialStore.h"

#include <zisla/core/Mail.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct MailConnectionSettings {
    std::string tenant{"common"};
    std::string client_id;
    std::string account_name;

    friend bool operator==(const MailConnectionSettings&, const MailConnectionSettings&) = default;
};

enum class MailServicePhase {
    not_configured,
    idle,
    loading,
    authorization_required,
    ready,
    failed,
};

struct MailServiceSnapshot {
    MailServicePhase phase{MailServicePhase::not_configured};
    MailConnectionSettings connection;
    std::vector<zisla::core::MailMessage> messages;
    std::optional<zisla::core::GraphDeviceCode> device_code;
    std::string message;
};

class MailService {
public:
    struct TokenState {
        std::string access_token;
        std::string refresh_token;
        std::int64_t expires_at_unix_seconds{0};
    };

    explicit MailService(MailConnectionSettings settings = {});
    ~MailService();

    MailService(const MailService&) = delete;
    MailService& operator=(const MailService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    void configure(MailConnectionSettings settings);
    void refresh();
    void begin_authorization();
    void mark_read(std::string message_id);
    void move_to_junk(std::string message_id);
    void move_to_deleted(std::string message_id);
    void send(
        std::vector<zisla::core::MailRecipient> recipients,
        std::string subject,
        std::string body);
    void reply(std::string message_id, std::string body);

    [[nodiscard]] std::shared_ptr<const MailServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        configure,
        refresh,
        authorize,
        mark_read,
        move_to_junk,
        move_to_deleted,
        send,
        reply,
    };

    struct Command {
        CommandKind kind{CommandKind::refresh};
        MailConnectionSettings settings;
        std::string message_id;
        std::vector<zisla::core::MailRecipient> recipients;
        std::string subject;
        std::string body;
        bool clear_credentials{false};
    };

    void enqueue(Command command);
    void run() noexcept;
    void execute(Command command);
    void refresh_inbox(const MailConnectionSettings& settings);
    void mutate(
        const MailConnectionSettings& settings,
        zisla::core::GraphMailRequest request);
    void authorize(const MailConnectionSettings& settings);
    [[nodiscard]] MailConnectionSettings configuration() const;
    [[nodiscard]] TokenState access_token(const MailConnectionSettings& settings);
    [[nodiscard]] std::optional<TokenState> stored_token();
    void store_token(const zisla::core::GraphToken& token);
    void clear_token() noexcept;
    [[nodiscard]] static std::string graph_request(
        const zisla::core::GraphMailRequest& request,
        std::string_view access_token);
    [[nodiscard]] static std::string token_request(
        std::string_view url,
        std::string_view body);
    [[nodiscard]] bool wait_for_authorization_interval(std::uint32_t seconds) noexcept;
    void publish(MailServiceSnapshot snapshot) noexcept;
    void publish_error(std::string message) noexcept;
    void notify() noexcept;

    CredentialStore credential_store_{CredentialNamespace::mail};
    std::atomic<std::shared_ptr<const MailServiceSnapshot>> snapshot_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    MailConnectionSettings settings_;
    bool running_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
