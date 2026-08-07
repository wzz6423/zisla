#pragma once

#include "zisla/core/AIAgentWorkspace.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

struct OpenAIChatCompletionMessage {
    AgentWorkspaceMessageRole role{AgentWorkspaceMessageRole::user};
    std::string content;

    friend bool operator==(const OpenAIChatCompletionMessage&,
                           const OpenAIChatCompletionMessage&) = default;
};

struct OpenAIChatCompletionRequest {
    std::string model;
    std::string system_prompt;
    std::vector<OpenAIChatCompletionMessage> messages;

    friend bool operator==(const OpenAIChatCompletionRequest&,
                           const OpenAIChatCompletionRequest&) = default;
};

/// Pure JSON protocol support for non-streaming OpenAI-compatible chat endpoints.
class OpenAIChatCompletionsProtocol {
public:
    [[nodiscard]] static std::string make_request_body(
        const OpenAIChatCompletionRequest& request);
    [[nodiscard]] static std::optional<std::string> parse_response(
        std::string_view body);
};

}  // namespace zisla::core
