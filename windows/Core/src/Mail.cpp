#include "zisla/core/Mail.hpp"

#include <yyjson.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>

namespace zisla::core {
namespace {

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

constexpr std::string_view graph_api_prefix = "https://graph.microsoft.com/v1.0/";
constexpr std::string_view graph_mail_messages_url =
    "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages"
    "?$select=id,subject,from,body,receivedDateTime,isRead&$top=50";
constexpr std::string_view graph_mail_message_url =
    "https://graph.microsoft.com/v1.0/me/messages/";
constexpr std::string_view graph_send_mail_url =
    "https://graph.microsoft.com/v1.0/me/sendMail";
constexpr std::string_view graph_mail_scope =
    "https://graph.microsoft.com/Mail.ReadWrite "
    "https://graph.microsoft.com/Mail.Send offline_access";

bool contains_control(std::string_view value) noexcept {
    return std::any_of(value.begin(), value.end(), [](unsigned char character) {
        return character < 0x20U || character == 0x7fU;
    });
}

bool ascii_case_equal(std::string_view left, std::string_view right) noexcept {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0; index < left.size(); ++index) {
        auto first = left[index];
        auto second = right[index];
        if (first >= 'A' && first <= 'Z') {
            first = static_cast<char>(first - 'A' + 'a');
        }
        if (second >= 'A' && second <= 'Z') {
            second = static_cast<char>(second - 'A' + 'a');
        }
        if (first != second) {
            return false;
        }
    }
    return true;
}

bool is_safe_graph_url(std::string_view value) noexcept {
    if (value.size() <= graph_api_prefix.size()
        || !ascii_case_equal(value.substr(0, graph_api_prefix.size()), graph_api_prefix)
        || contains_control(value)) {
        return false;
    }
    const auto authority_end = value.find_first_of("/?#", std::string_view{"https://"}.size());
    return authority_end != std::string_view::npos
        && ascii_case_equal(
            value.substr(std::string_view{"https://"}.size(),
                authority_end - std::string_view{"https://"}.size()),
            "graph.microsoft.com");
}

bool is_safe_message_id(std::string_view value) noexcept {
    return !value.empty()
        && value.size() <= GraphMailRequestBuilder::maximum_message_id_bytes
        && !contains_control(value);
}

bool is_safe_recipient(std::string_view value) noexcept {
    if (value.empty() || value.size() > 320 || contains_control(value)) {
        return false;
    }
    const auto at = value.find('@');
    return at != std::string_view::npos && at > 0 && at + 1 < value.size()
        && value.find_first_of(" \t\r\n") == std::string_view::npos;
}

std::string percent_encode(std::string_view value) {
    constexpr char hex[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(value.size() * 3);
    for (const auto byte : value) {
        const auto character = static_cast<unsigned char>(byte);
        if ((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '-' || character == '.' || character == '_' || character == '~') {
            result.push_back(static_cast<char>(character));
            continue;
        }
        result.push_back('%');
        result.push_back(hex[character >> 4U]);
        result.push_back(hex[character & 0x0fU]);
    }
    return result;
}

std::string json_string(std::string_view value) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(value.size() + 2);
    result.push_back('"');
    for (const auto byte : value) {
        const auto character = static_cast<unsigned char>(byte);
        switch (character) {
        case '"':
            result.append("\\\"");
            break;
        case '\\':
            result.append("\\\\");
            break;
        case '\b':
            result.append("\\b");
            break;
        case '\f':
            result.append("\\f");
            break;
        case '\n':
            result.append("\\n");
            break;
        case '\r':
            result.append("\\r");
            break;
        case '\t':
            result.append("\\t");
            break;
        default:
            if (character < 0x20U) {
                result.append("\\u00");
                result.push_back(hex[character >> 4U]);
                result.push_back(hex[character & 0x0fU]);
            } else {
                result.push_back(static_cast<char>(character));
            }
            break;
        }
    }
    result.push_back('"');
    return result;
}

void require_message_id(std::string_view value) {
    if (!is_safe_message_id(value)) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_message_id,
            "邮件标识无效");
    }
}

void require_body_size(std::string_view value) {
    if (value.size() > GraphMailRequestBuilder::maximum_body_bytes) {
        throw MailRequestError(
            MailRequestErrorCode::request_too_large,
            "邮件正文超过大小限制");
    }
}

void require_request_size(std::string_view value) {
    if (value.size() > GraphMailRequestBuilder::maximum_request_bytes) {
        throw MailRequestError(
            MailRequestErrorCode::request_too_large,
            "邮件请求超过大小限制");
    }
}

std::optional<std::string> string_member(yyjson_val* object, const char* name) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    auto* value = yyjson_obj_get(object, name);
    if (!yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto* text = yyjson_get_str(value);
    return text ? std::optional<std::string>{std::string(text, yyjson_get_len(value))}
                : std::nullopt;
}

std::optional<std::uint32_t> unsigned_member(yyjson_val* object, const char* name) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    auto* value = yyjson_obj_get(object, name);
    if (!yyjson_is_num(value)) {
        return std::nullopt;
    }
    const auto number = yyjson_get_num(value);
    if (number < 0 || number > std::numeric_limits<std::uint32_t>::max()
        || static_cast<double>(static_cast<std::uint32_t>(number)) != number) {
        return std::nullopt;
    }
    return static_cast<std::uint32_t>(number);
}

std::string sender_name(yyjson_val* item) {
    auto* from = yyjson_obj_get(item, "from");
    auto* email_address = from ? yyjson_obj_get(from, "emailAddress") : nullptr;
    const auto name = string_member(email_address, "name");
    const auto address = string_member(email_address, "address");
    return name && !name->empty() ? *name : address.value_or(std::string{});
}

std::string sender_address(yyjson_val* item) {
    auto* from = yyjson_obj_get(item, "from");
    auto* email_address = from ? yyjson_obj_get(from, "emailAddress") : nullptr;
    return string_member(email_address, "address").value_or(std::string{});
}

std::string message_body(yyjson_val* item) {
    auto* body = yyjson_obj_get(item, "body");
    return string_member(body, "content").value_or(std::string{});
}

bool valid_tenant(std::string_view tenant) noexcept {
    return !tenant.empty()
        && tenant.size() <= 128
        && std::all_of(tenant.begin(), tenant.end(), [](unsigned char character) {
            return (character >= 'a' && character <= 'z')
                || (character >= 'A' && character <= 'Z')
                || (character >= '0' && character <= '9')
                || character == '-' || character == '.';
        });
}

void require_client_id(std::string_view value) {
    if (value.empty() || value.size() > GraphOAuthRequestBuilder::maximum_client_id_bytes
        || contains_control(value)) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_oauth_configuration,
            "Microsoft Graph 客户端标识无效");
    }
}

std::string oauth_url(std::string_view tenant, std::string_view suffix) {
    if (!valid_tenant(tenant)) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_oauth_configuration,
            "Microsoft Graph 租户标识无效");
    }
    return "https://login.microsoftonline.com/" + std::string(tenant)
        + "/oauth2/v2.0/" + std::string(suffix);
}

JsonDocument parse_document(std::string_view response, std::size_t limit) {
    if (response.size() > limit) {
        throw MailResponseError(
            MailResponseErrorCode::response_too_large,
            "邮件服务响应超过大小限制");
    }
    JsonDocument document{
        yyjson_read(response.data(), response.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        throw MailResponseError(
            MailResponseErrorCode::invalid_json,
            "邮件服务返回了无效 JSON");
    }
    return document;
}

}  // namespace

MailRequestError::MailRequestError(MailRequestErrorCode code, std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

MailRequestErrorCode MailRequestError::code() const noexcept {
    return code_;
}

GraphMailRequest GraphMailRequestBuilder::inbox(
    std::optional<std::string_view> continuation_url) {
    if (continuation_url) {
        if (!is_safe_graph_url(*continuation_url)) {
            throw MailRequestError(
                MailRequestErrorCode::invalid_continuation_url,
                "邮件分页地址无效");
        }
        return {
            .method = "GET",
            .url = std::string(*continuation_url),
        };
    }
    return {
        .method = "GET",
        .url = std::string(graph_mail_messages_url),
    };
}

GraphMailRequest GraphMailRequestBuilder::mark_read(std::string_view message_id) {
    require_message_id(message_id);
    return {
        .method = "PATCH",
        .url = std::string(graph_mail_message_url) + percent_encode(message_id),
        .body = "{\"isRead\":true}",
    };
}

GraphMailRequest GraphMailRequestBuilder::move_to_junk(std::string_view message_id) {
    require_message_id(message_id);
    return {
        .method = "POST",
        .url = std::string(graph_mail_message_url) + percent_encode(message_id) + "/move",
        .body = "{\"destinationId\":\"junkemail\"}",
    };
}

GraphMailRequest GraphMailRequestBuilder::move_to_deleted(std::string_view message_id) {
    require_message_id(message_id);
    return {
        .method = "POST",
        .url = std::string(graph_mail_message_url) + percent_encode(message_id) + "/move",
        .body = "{\"destinationId\":\"deleteditems\"}",
    };
}

GraphMailRequest GraphMailRequestBuilder::send(
    std::span<const MailRecipient> recipients,
    std::string_view subject,
    std::string_view body) {
    if (recipients.empty() || recipients.size() > maximum_recipients) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_recipient,
            "请填写 1 到 50 个收件人");
    }
    if (subject.size() > maximum_subject_bytes) {
        throw MailRequestError(
            MailRequestErrorCode::request_too_large,
            "邮件主题超过大小限制");
    }
    require_body_size(body);

    std::string request = "{\"message\":{\"subject\":" + json_string(subject)
        + ",\"body\":{\"contentType\":\"Text\",\"content\":"
        + json_string(body) + "},\"toRecipients\":[";
    for (std::size_t index = 0; index < recipients.size(); ++index) {
        const auto& recipient = recipients[index];
        if (!is_safe_recipient(recipient.email_address)) {
            throw MailRequestError(
                MailRequestErrorCode::invalid_recipient,
                "收件人地址无效");
        }
        if (index > 0) {
            request.push_back(',');
        }
        request.append("{\"emailAddress\":{\"address\":");
        request.append(json_string(recipient.email_address));
        if (!recipient.display_name.empty()) {
            request.append(",\"name\":");
            request.append(json_string(recipient.display_name));
        }
        request.append("}}");
    }
    request.append("]},\"saveToSentItems\":true}");
    require_request_size(request);
    return {
        .method = "POST",
        .url = std::string(graph_send_mail_url),
        .body = std::move(request),
    };
}

GraphMailRequest GraphMailRequestBuilder::reply(
    std::string_view message_id,
    std::string_view body) {
    require_message_id(message_id);
    require_body_size(body);
    const auto request = "{\"comment\":" + json_string(body) + "}";
    require_request_size(request);
    return {
        .method = "POST",
        .url = std::string(graph_mail_message_url) + percent_encode(message_id) + "/reply",
        .body = request,
    };
}

MailResponseError::MailResponseError(MailResponseErrorCode code, std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

MailResponseErrorCode MailResponseError::code() const noexcept {
    return code_;
}

MailSnapshot GraphMailResponseParser::parse_inbox(std::string_view response) {
    auto document = parse_document(response, maximum_response_bytes);
    auto* root = yyjson_doc_get_root(document.get());
    auto* values = root ? yyjson_obj_get(root, "value") : nullptr;
    if (!yyjson_is_obj(root) || !yyjson_is_arr(values)) {
        throw MailResponseError(
            MailResponseErrorCode::invalid_shape,
            "邮件服务返回了无效收件箱数据");
    }

    MailSnapshot result;
    if (const auto next_link = string_member(root, "@odata.nextLink")) {
        if (!is_safe_graph_url(*next_link)) {
            throw MailResponseError(
                MailResponseErrorCode::invalid_value,
                "邮件分页地址无效");
        }
        result.next_link = *next_link;
    }

    std::unordered_set<std::string> seen_ids;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* item = nullptr;
    yyjson_arr_foreach(values, index, maximum, item) {
        if (result.messages.size() >= maximum_messages || !yyjson_is_obj(item)) {
            break;
        }
        const auto id = string_member(item, "id");
        if (!id || !is_safe_message_id(*id) || !seen_ids.insert(*id).second) {
            continue;
        }
        auto* read_value = yyjson_obj_get(item, "isRead");
        if (!yyjson_is_bool(read_value)) {
            continue;
        }
        result.messages.push_back({
            .id = *id,
            .sender = sender_name(item),
            .sender_address = sender_address(item),
            .subject = string_member(item, "subject").value_or(std::string{}),
            .body = message_body(item),
            .received_at = string_member(item, "receivedDateTime").value_or(std::string{}),
            .is_read = yyjson_get_bool(read_value),
        });
    }
    std::sort(
        result.messages.begin(),
        result.messages.end(),
        [](const MailMessage& left, const MailMessage& right) {
            if (left.received_at != right.received_at) {
                return left.received_at > right.received_at;
            }
            return left.id < right.id;
        });
    return result;
}

std::string GraphOAuthRequestBuilder::device_code_url(std::string_view tenant) {
    return oauth_url(tenant, "devicecode");
}

std::string GraphOAuthRequestBuilder::token_url(std::string_view tenant) {
    return oauth_url(tenant, "token");
}

std::string GraphOAuthRequestBuilder::device_code_body(std::string_view client_id) {
    require_client_id(client_id);
    return "client_id=" + percent_encode(client_id) + "&scope="
        + percent_encode(graph_mail_scope);
}

std::string GraphOAuthRequestBuilder::token_poll_body(
    std::string_view client_id,
    std::string_view device_code) {
    require_client_id(client_id);
    if (device_code.empty() || device_code.size() > maximum_refresh_token_bytes
        || contains_control(device_code)) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_oauth_configuration,
            "Microsoft Graph 设备代码无效");
    }
    return "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id="
        + percent_encode(client_id) + "&device_code=" + percent_encode(device_code);
}

std::string GraphOAuthRequestBuilder::refresh_token_body(
    std::string_view client_id,
    std::string_view refresh_token) {
    require_client_id(client_id);
    if (refresh_token.empty() || refresh_token.size() > maximum_refresh_token_bytes
        || contains_control(refresh_token)) {
        throw MailRequestError(
            MailRequestErrorCode::invalid_oauth_configuration,
            "Microsoft Graph 刷新令牌无效");
    }
    return "grant_type=refresh_token&client_id=" + percent_encode(client_id)
        + "&refresh_token=" + percent_encode(refresh_token)
        + "&scope=" + percent_encode(graph_mail_scope);
}

GraphDeviceCode GraphOAuthResponseParser::parse_device_code(std::string_view response) {
    auto document = parse_document(response, maximum_response_bytes);
    auto* root = yyjson_doc_get_root(document.get());
    const auto device_code = string_member(root, "device_code");
    const auto user_code = string_member(root, "user_code");
    const auto verification_uri = string_member(root, "verification_uri");
    const auto expires_in = unsigned_member(root, "expires_in");
    const auto interval = unsigned_member(root, "interval");
    if (!yyjson_is_obj(root) || !device_code || device_code->empty() || !user_code
        || user_code->empty() || !verification_uri
        || !verification_uri->starts_with("https://") || !expires_in || *expires_in == 0) {
        throw MailResponseError(
            MailResponseErrorCode::invalid_shape,
            "Microsoft Graph 授权响应无效");
    }
    return {
        .device_code = *device_code,
        .user_code = *user_code,
        .verification_uri = *verification_uri,
        .expires_in_seconds = *expires_in,
        .interval_seconds = interval && *interval > 0 ? *interval : 5,
    };
}

GraphTokenResponse GraphOAuthResponseParser::parse_token(std::string_view response) {
    auto document = parse_document(response, maximum_response_bytes);
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        throw MailResponseError(
            MailResponseErrorCode::invalid_shape,
            "Microsoft Graph 令牌响应无效");
    }
    if (const auto error = string_member(root, "error")) {
        return {
            .error = *error,
            .error_description = string_member(root, "error_description")
                .value_or(std::string{}),
        };
    }
    const auto access_token = string_member(root, "access_token");
    const auto refresh_token = string_member(root, "refresh_token");
    const auto expires_in = unsigned_member(root, "expires_in");
    if (!access_token || access_token->empty() || !refresh_token || refresh_token->empty()
        || !expires_in || *expires_in == 0) {
        throw MailResponseError(
            MailResponseErrorCode::invalid_shape,
            "Microsoft Graph 令牌响应无效");
    }
    return {
        .token = GraphToken{
            .access_token = *access_token,
            .refresh_token = *refresh_token,
            .expires_in_seconds = *expires_in,
        },
    };
}

}  // namespace zisla::core
