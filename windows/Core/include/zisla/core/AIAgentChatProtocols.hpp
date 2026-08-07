#pragma once

#include "zisla/core/OpenAIChatCompletions.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace zisla::core {

/// Pure JSON support for non-streaming Anthropic Messages requests.
class AnthropicMessagesProtocol {
public:
    static constexpr std::uint32_t maximum_output_tokens = 4'096;

    [[nodiscard]] static std::string make_request_body(
        const OpenAIChatCompletionRequest& request);
    [[nodiscard]] static std::optional<std::string> parse_response(
        std::string_view body);
};

/// Pure JSON support for non-streaming Gemini generateContent requests.
class GeminiGenerateContentProtocol {
public:
    [[nodiscard]] static std::string make_request_body(
        const OpenAIChatCompletionRequest& request);
    [[nodiscard]] static std::optional<std::string> parse_response(
        std::string_view body);
};

}  // namespace zisla::core
