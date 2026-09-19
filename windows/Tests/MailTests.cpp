#include <zisla/core/Mail.hpp>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

void require(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void graphRequestsUseOnlyTheExpectedEndpointsAndEscaping() {
    using zisla::core::GraphMailRequestBuilder;
    using zisla::core::MailRecipient;

    const auto inbox = GraphMailRequestBuilder::inbox();
    require(inbox.method == "GET", "inbox should use GET");
    require(inbox.url.starts_with("https://graph.microsoft.com/v1.0/"),
        "inbox must use Graph HTTPS");

    const auto read = GraphMailRequestBuilder::mark_read("A/B+");
    require(read.method == "PATCH", "mark-read should use PATCH");
    require(read.url.ends_with("A%2FB%2B"), "message identifier must be encoded");
    require(read.body == "{\"isRead\":true}", "mark-read body should be stable");

    const std::array recipients{
        MailRecipient{.email_address = "alice@example.com", .display_name = "Alice"},
        MailRecipient{.email_address = "bob@example.com"},
    };
    const auto sent = GraphMailRequestBuilder::send(recipients, "主题 \"A\"", "第一行\n第二行");
    require(sent.method == "POST", "send should use POST");
    require(sent.url == "https://graph.microsoft.com/v1.0/me/sendMail",
        "send endpoint should be fixed");
    require(sent.body.find("\\\"A\\\"") != std::string::npos,
        "subject should be JSON escaped");
    require(sent.body.find("第一行\\n第二行") != std::string::npos,
        "body newlines should be JSON escaped");
    require(sent.body.find("alice@example.com") != std::string::npos,
        "first recipient should be present");
    require(sent.body.find("bob@example.com") != std::string::npos,
        "second recipient should be present");
}

void graphRequestsRejectUnsafeUserInputAndContinuationLinks() {
    using zisla::core::GraphMailRequestBuilder;
    using zisla::core::MailRequestError;
    using zisla::core::MailRequestErrorCode;
    using zisla::core::MailRecipient;

    bool rejected_message_id = false;
    try {
        (void)GraphMailRequestBuilder::reply("bad\nidentifier", "hello");
    } catch (const MailRequestError& error) {
        rejected_message_id = error.code() == MailRequestErrorCode::invalid_message_id;
    }
    require(rejected_message_id, "control characters must reject message identifiers");

    const std::array recipients{MailRecipient{.email_address = "not-an-address"}};
    bool rejected_recipient = false;
    try {
        (void)GraphMailRequestBuilder::send(recipients, "subject", "body");
    } catch (const MailRequestError& error) {
        rejected_recipient = error.code() == MailRequestErrorCode::invalid_recipient;
    }
    require(rejected_recipient, "invalid recipient must be rejected");

    bool rejected_link = false;
    try {
        (void)GraphMailRequestBuilder::inbox("https://example.invalid/next");
    } catch (const MailRequestError& error) {
        rejected_link = error.code() == MailRequestErrorCode::invalid_continuation_url;
    }
    require(rejected_link, "continuation links must stay on Graph HTTPS");
}

void inboxResponseKeepsSafeMessagesAndOrdersNewestFirst() {
    using zisla::core::GraphMailResponseParser;

    const auto snapshot = GraphMailResponseParser::parse_inbox(R"json(
        {
          "@odata.nextLink":"https://graph.microsoft.com/v1.0/me/messages?$skiptoken=next",
          "value":[
            {
              "id":"older",
              "subject":"旧邮件",
              "from":{"emailAddress":{"name":"Old sender","address":"old@example.com"}},
              "body":{"contentType":"text","content":"旧正文"},
              "receivedDateTime":"2026-08-01T08:00:00Z",
              "isRead":true
            },
            {"id":"missing-read","subject":"忽略"},
            {
              "id":"newer",
              "subject":"新邮件",
              "from":{"emailAddress":{"address":"new@example.com"}},
              "body":{"contentType":"html","content":"新正文"},
              "receivedDateTime":"2026-08-02T08:00:00Z",
              "isRead":false
            }
          ]
        }
    )json");

    require(snapshot.messages.size() == 2, "invalid message rows should be skipped");
    require(snapshot.messages[0].id == "newer", "newest message should be first");
    require(snapshot.messages[0].sender == "new@example.com",
        "address should be used when sender name is unavailable");
    require(snapshot.messages[1].is_read, "read state should be retained");
    require(snapshot.next_link.has_value(), "safe Graph next link should be retained");
}

void oauthRequestsAndResponsesAreBoundedAndExplicit() {
    using zisla::core::GraphOAuthRequestBuilder;
    using zisla::core::GraphOAuthResponseParser;

    require(
        GraphOAuthRequestBuilder::device_code_url("common")
            == "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode",
        "device-code endpoint should be deterministic");
    const auto request = GraphOAuthRequestBuilder::device_code_body("client-id");
    require(request.find("client_id=client-id") != std::string::npos,
        "client id should be form encoded");
    require(request.find("Mail.ReadWrite%20https%3A%2F%2Fgraph.microsoft.com%2FMail.Send")
            != std::string::npos,
        "scope separators and URL characters must be form encoded");

    const auto device = GraphOAuthResponseParser::parse_device_code(R"json(
        {"device_code":"device","user_code":"ABCD-EFGH",
         "verification_uri":"https://microsoft.com/devicelogin","expires_in":900,"interval":3}
    )json");
    require(device.interval_seconds == 3, "server polling interval should be retained");

    const auto pending = GraphOAuthResponseParser::parse_token(R"json(
        {"error":"authorization_pending","error_description":"waiting"}
    )json");
    require(!pending.token && pending.error == "authorization_pending",
        "OAuth error responses should remain inspectable");

    const auto token = GraphOAuthResponseParser::parse_token(R"json(
        {"access_token":"access","refresh_token":"refresh","expires_in":3600}
    )json");
    require(token.token && token.token->access_token == "access",
        "OAuth token responses should retain secrets only for caller storage");
}

}  // namespace

int main() {
    const std::array tests{
        std::pair{"Graph 请求使用固定端点与转义", graphRequestsUseOnlyTheExpectedEndpointsAndEscaping},
        std::pair{"Graph 请求拒绝危险输入", graphRequestsRejectUnsafeUserInputAndContinuationLinks},
        std::pair{"收件箱响应安全解析与排序", inboxResponseKeepsSafeMessagesAndOrdersNewestFirst},
        std::pair{"OAuth 请求与响应边界", oauthRequestsAndResponsesAreBoundedAndExplicit},
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
    std::cout << passed << '/' << tests.size() << " tests passed\n";
    return passed == tests.size() ? EXIT_SUCCESS : EXIT_FAILURE;
}
