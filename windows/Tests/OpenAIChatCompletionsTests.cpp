#include <zisla/core/OpenAIChatCompletions.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void requestBodyIncludesSystemHistoryAndEscapesContent() {
    const auto body = OpenAIChatCompletionsProtocol::make_request_body({
        .model = "  gpt-test  ",
        .system_prompt = "System prompt",
        .messages = {
            {
                .role = AgentWorkspaceMessageRole::user,
                .content = "Line one\nquoted: \"value\"",
            },
            {
                .role = AgentWorkspaceMessageRole::assistant,
                .content = "Previous reply",
            },
            {
                .role = AgentWorkspaceMessageRole::user,
                .content = "",
            },
        },
    });

    expect(body.find("\"model\":\"gpt-test\"") != std::string::npos,
        "request should trim and encode the selected model");
    expect(body.find("\"stream\":false") != std::string::npos,
        "request should explicitly disable streaming");
    const auto system = body.find("\"role\":\"system\"");
    const auto user = body.find("\"role\":\"user\"");
    const auto assistant = body.find("\"role\":\"assistant\"");
    expect(system != std::string::npos && user != std::string::npos
            && assistant != std::string::npos && system < user && user < assistant,
        "system prompt and retained history should keep their protocol order");
    expect(body.find("Line one\\nquoted: \\\"value\\\"") != std::string::npos,
        "message content should be JSON escaped");
    expect(body.find("\"content\":\"\"") == std::string::npos,
        "empty retained messages should not consume context");
}

void responseParserMatchesMacCompletionContract() {
    const auto response = OpenAIChatCompletionsProtocol::parse_response(
        R"({"choices":[{"message":{"content":"  Done.\n"}}]})");
    expect(response && *response == "Done.",
        "first assistant completion should be trimmed like the macOS client");

    const auto empty = OpenAIChatCompletionsProtocol::parse_response(
        R"({"choices":[{"message":{"content":null}}]})");
    expect(empty && empty->empty(),
        "a null completion content should remain a valid empty response");

    expect(!OpenAIChatCompletionsProtocol::parse_response("{}").has_value(),
        "responses without a first choice should be rejected");
    expect(!OpenAIChatCompletionsProtocol::parse_response(
                R"({"choices":[{"message":{"content":3}}]})").has_value(),
        "non-string completion content should be rejected");
    expect(!OpenAIChatCompletionsProtocol::parse_response("not-json").has_value(),
        "malformed response JSON should be rejected");
}

void missingModelIsRejected() {
    try {
        (void)OpenAIChatCompletionsProtocol::make_request_body({
            .model = " \t\n ",
        });
        throw std::runtime_error("missing model should throw");
    } catch (const std::invalid_argument&) {
    }
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"request body serializes history", requestBodyIncludesSystemHistoryAndEscapesContent},
        {"response parser matches macOS", responseParserMatchesMacCompletionContract},
        {"missing model is rejected", missingModelIsRejected},
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
