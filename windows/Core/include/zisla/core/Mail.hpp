#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct MailRecipient {
    std::string email_address;
    std::string display_name;

    friend bool operator==(const MailRecipient&, const MailRecipient&) = default;
};

struct MailMessage {
    std::string id;
    std::string sender;
    std::string sender_address;
    std::string subject;
    std::string body;
    std::string received_at;
    bool is_read{false};

    friend bool operator==(const MailMessage&, const MailMessage&) = default;
};

struct MailSnapshot {
    std::vector<MailMessage> messages;
    std::optional<std::string> next_link;

    friend bool operator==(const MailSnapshot&, const MailSnapshot&) = default;
};

struct GraphMailRequest {
    std::string method;
    std::string url;
    std::string body;

    friend bool operator==(const GraphMailRequest&, const GraphMailRequest&) = default;
};

enum class MailRequestErrorCode {
    invalid_message_id,
    invalid_recipient,
    invalid_continuation_url,
    invalid_oauth_configuration,
    request_too_large,
};

class MailRequestError : public std::runtime_error {
public:
    MailRequestError(MailRequestErrorCode code, std::string message);

    [[nodiscard]] MailRequestErrorCode code() const noexcept;

private:
    MailRequestErrorCode code_;
};

class GraphMailRequestBuilder {
public:
    static constexpr std::size_t maximum_message_id_bytes = 1'024;
    static constexpr std::size_t maximum_recipients = 50;
    static constexpr std::size_t maximum_subject_bytes = 4'096;
    static constexpr std::size_t maximum_body_bytes = 512U * 1024U;
    static constexpr std::size_t maximum_request_bytes = 1U * 1024U * 1024U;

    [[nodiscard]] static GraphMailRequest inbox(
        std::optional<std::string_view> continuation_url = std::nullopt);
    [[nodiscard]] static GraphMailRequest mark_read(std::string_view message_id);
    [[nodiscard]] static GraphMailRequest move_to_junk(std::string_view message_id);
    [[nodiscard]] static GraphMailRequest move_to_deleted(std::string_view message_id);
    [[nodiscard]] static GraphMailRequest send(
        std::span<const MailRecipient> recipients,
        std::string_view subject,
        std::string_view body);
    [[nodiscard]] static GraphMailRequest reply(
        std::string_view message_id,
        std::string_view body);
};

enum class MailResponseErrorCode {
    invalid_json,
    invalid_shape,
    invalid_value,
    response_too_large,
};

class MailResponseError : public std::runtime_error {
public:
    MailResponseError(MailResponseErrorCode code, std::string message);

    [[nodiscard]] MailResponseErrorCode code() const noexcept;

private:
    MailResponseErrorCode code_;
};

class GraphMailResponseParser {
public:
    static constexpr std::size_t maximum_response_bytes = 1U * 1024U * 1024U;
    static constexpr std::size_t maximum_messages = 50;

    [[nodiscard]] static MailSnapshot parse_inbox(std::string_view response);
};

struct GraphDeviceCode {
    std::string device_code;
    std::string user_code;
    std::string verification_uri;
    std::uint32_t expires_in_seconds{0};
    std::uint32_t interval_seconds{5};

    friend bool operator==(const GraphDeviceCode&, const GraphDeviceCode&) = default;
};

struct GraphToken {
    std::string access_token;
    std::string refresh_token;
    std::uint32_t expires_in_seconds{0};

    friend bool operator==(const GraphToken&, const GraphToken&) = default;
};

struct GraphTokenResponse {
    std::optional<GraphToken> token;
    std::string error;
    std::string error_description;

    friend bool operator==(const GraphTokenResponse&, const GraphTokenResponse&) = default;
};

class GraphOAuthRequestBuilder {
public:
    static constexpr std::size_t maximum_client_id_bytes = 128;
    static constexpr std::size_t maximum_refresh_token_bytes = 8U * 1024U;

    [[nodiscard]] static std::string device_code_url(std::string_view tenant);
    [[nodiscard]] static std::string token_url(std::string_view tenant);
    [[nodiscard]] static std::string device_code_body(std::string_view client_id);
    [[nodiscard]] static std::string token_poll_body(
        std::string_view client_id,
        std::string_view device_code);
    [[nodiscard]] static std::string refresh_token_body(
        std::string_view client_id,
        std::string_view refresh_token);
};

class GraphOAuthResponseParser {
public:
    static constexpr std::size_t maximum_response_bytes = 128U * 1024U;

    [[nodiscard]] static GraphDeviceCode parse_device_code(std::string_view response);
    [[nodiscard]] static GraphTokenResponse parse_token(std::string_view response);
};

}  // namespace zisla::core
