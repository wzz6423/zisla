#include <zisla/core/AIAgentChatProtocols.hpp>

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

OpenAIChatCompletionRequest request() {
    return {
        .model = "  selected-model  ",
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
    };
}

void anthropicMessagesSerializeAndParse() {
    const auto body = AnthropicMessagesProtocol::make_request_body(request());
    expect(body.find("\"model\":\"selected-model\"") != std::string::npos,
        "Anthropic request should trim the selected model");
    expect(body.find("\"max_tokens\":4096") != std::string::npos,
        "Anthropic request should include a bounded output token limit");
    expect(body.find("\"system\":\"System prompt\"") != std::string::npos,
        "Anthropic request should send the system prompt in the dedicated field");
    expect(body.find("\"role\":\"user\"") != std::string::npos
            && body.find("\"role\":\"assistant\"") != std::string::npos,
        "Anthropic request should preserve user and assistant roles");
    expect(body.find("\"content\":\"\"") == std::string::npos,
        "empty Anthropic history entries should not consume context");

    const auto response = AnthropicMessagesProtocol::parse_response(
        R"({"content":[{"type":"thinking","thinking":"hidden"},{"type":"text","text":"  Done"},{"type":"text","text":".  "}]})");
    expect(response && *response == "Done.",
        "Anthropic parser should concatenate only text blocks and trim the result");
    expect(!AnthropicMessagesProtocol::parse_response("{}").has_value(),
        "Anthropic responses without content blocks should be rejected");
    expect(!AnthropicMessagesProtocol::parse_response(
                R"({"content":[{"type":"thinking","thinking":"hidden"}]})").has_value(),
        "Anthropic responses without assistant text should be rejected");
}

void geminiGenerateContentSerializesAndParses() {
    const auto body = GeminiGenerateContentProtocol::make_request_body(request());
    expect(body.find("\"systemInstruction\"") != std::string::npos
            && body.find("\"text\":\"System prompt\"") != std::string::npos,
        "Gemini request should use the systemInstruction field");
    expect(body.find("\"role\":\"user\"") != std::string::npos
            && body.find("\"role\":\"model\"") != std::string::npos,
        "Gemini request should map assistant history to the model role");
    expect(body.find("Line one\\nquoted: \\\"value\\\"") != std::string::npos,
        "Gemini text parts should be JSON escaped");

    const auto response = GeminiGenerateContentProtocol::parse_response(
        R"({"candidates":[{"content":{"parts":[{"text":"  Answer"},{"functionCall":{"name":"skip"}},{"text":".\n"}]}}]})");
    expect(response && *response == "Answer.",
        "Gemini parser should concatenate text parts and ignore function calls");
    expect(!GeminiGenerateContentProtocol::parse_response(
                R"({"candidates":[{"content":{}}]})").has_value(),
        "Gemini responses without parts should be rejected");
    expect(!GeminiGenerateContentProtocol::parse_response(
                R"({"candidates":[{"content":{"parts":[{"functionCall":{"name":"skip"}}]}}]})").has_value(),
        "Gemini responses without assistant text should be rejected");
}

void invalidProtocolHistoryAndModelsAreRejected() {
    auto invalid_history = request();
    invalid_history.messages.front().role = AgentWorkspaceMessageRole::system;
    bool anthopic_rejected = false;
    try {
        (void)AnthropicMessagesProtocol::make_request_body(invalid_history);
    } catch (const std::invalid_argument&) {
        anthopic_rejected = true;
    }
    expect(anthopic_rejected, "Anthropic protocol should reject a system history item");

    bool gemini_rejected = false;
    try {
        invalid_history.model = " \t";
        (void)GeminiGenerateContentProtocol::make_request_body(invalid_history);
    } catch (const std::invalid_argument&) {
        gemini_rejected = true;
    }
    expect(gemini_rejected, "Gemini protocol should reject a missing model");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"Anthropic Messages serializes and parses", anthropicMessagesSerializeAndParse},
        {"Gemini generateContent serializes and parses", geminiGenerateContentSerializesAndParses},
        {"invalid protocol history and models are rejected", invalidProtocolHistoryAndModelsAreRejected},
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
