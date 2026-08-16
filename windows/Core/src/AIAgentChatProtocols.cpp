#include "zisla/core/AIAgentChatProtocols.hpp"

#include <yyjson.h>

#include <cstdlib>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>
#include <string_view>

namespace zisla::core {
namespace {

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;
using MutableJsonDocument = std::unique_ptr<
    yyjson_mut_doc,
    decltype(&yyjson_mut_doc_free)>;
using JsonText = std::unique_ptr<char, decltype(&std::free)>;

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

void require_json(bool value) {
    if (!value) {
        throw std::bad_alloc();
    }
}

void add_string(
    yyjson_mut_doc* document,
    yyjson_mut_val* object,
    const char* key,
    std::string_view value) {
    require_json(yyjson_mut_obj_add_strncpy(
        document,
        object,
        key,
        value.data(),
        value.size()));
}

yyjson_mut_val* add_text_part(
    yyjson_mut_doc* document,
    yyjson_mut_val* parts,
    std::string_view value) {
    auto* part = yyjson_mut_arr_add_obj(document, parts);
    if (!part) {
        throw std::bad_alloc();
    }
    add_string(document, part, "text", value);
    return part;
}

std::string require_model(const OpenAIChatCompletionRequest& request, std::string_view protocol) {
    const auto model = trim_ascii(request.model);
    if (model.empty()) {
        throw std::invalid_argument(std::string(protocol) + " chat model is required");
    }
    return model;
}

std::string_view anthropic_role(AgentWorkspaceMessageRole role) {
    switch (role) {
    case AgentWorkspaceMessageRole::user: return "user";
    case AgentWorkspaceMessageRole::assistant: return "assistant";
    case AgentWorkspaceMessageRole::system: break;
    }
    throw std::invalid_argument("Anthropic Messages history cannot contain a system message");
}

std::string_view gemini_role(AgentWorkspaceMessageRole role) {
    switch (role) {
    case AgentWorkspaceMessageRole::user: return "user";
    case AgentWorkspaceMessageRole::assistant: return "model";
    case AgentWorkspaceMessageRole::system: break;
    }
    throw std::invalid_argument("Gemini history cannot contain a system message");
}

std::optional<std::string> text_member(yyjson_val* object, const char* key) {
    auto* value = yyjson_is_obj(object) ? yyjson_obj_get(object, key) : nullptr;
    if (!yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto* text = yyjson_get_str(value);
    return text ? std::optional<std::string>{std::string(text, yyjson_get_len(value))}
                : std::nullopt;
}

void append_text(std::string& result, std::string_view text) {
    result.append(text.data(), text.size());
}

}  // namespace

std::string AnthropicMessagesProtocol::make_request_body(
    const OpenAIChatCompletionRequest& request) {
    const auto model = require_model(request, "Anthropic Messages");
    MutableJsonDocument document{
        yyjson_mut_doc_new(nullptr),
        &yyjson_mut_doc_free,
    };
    if (!document) {
        throw std::bad_alloc();
    }
    auto* root = yyjson_mut_obj(document.get());
    if (!root) {
        throw std::bad_alloc();
    }
    yyjson_mut_doc_set_root(document.get(), root);
    add_string(document.get(), root, "model", model);
    require_json(yyjson_mut_obj_add_uint(
        document.get(), root, "max_tokens", maximum_output_tokens));
    if (!request.system_prompt.empty()) {
        add_string(document.get(), root, "system", request.system_prompt);
    }
    auto* messages = yyjson_mut_obj_add_arr(document.get(), root, "messages");
    if (!messages) {
        throw std::bad_alloc();
    }
    for (const auto& message : request.messages) {
        if (message.content.empty()) {
            continue;
        }
        auto* encoded = yyjson_mut_arr_add_obj(document.get(), messages);
        if (!encoded) {
            throw std::bad_alloc();
        }
        add_string(document.get(), encoded, "role", anthropic_role(message.role));
        add_string(document.get(), encoded, "content", message.content);
    }

    std::size_t length = 0;
    JsonText text{
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        &std::free,
    };
    if (!text) {
        throw std::runtime_error("Unable to encode Anthropic Messages request");
    }
    return {text.get(), length};
}

std::optional<std::string> AnthropicMessagesProtocol::parse_response(std::string_view body) {
    JsonDocument document{
        yyjson_read(body.data(), body.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    auto* content = yyjson_is_obj(root) ? yyjson_obj_get(root, "content") : nullptr;
    if (!yyjson_is_arr(content)) {
        return std::nullopt;
    }

    std::string result;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* part = nullptr;
    yyjson_arr_foreach(content, index, maximum, part) {
        if (!yyjson_is_obj(part)) {
            continue;
        }
        const auto type = text_member(part, "type");
        const auto text = text_member(part, "text");
        if (type && *type == "text" && text) {
            append_text(result, *text);
        }
    }
    const auto text = trim_ascii(result);
    return text.empty() ? std::nullopt : std::optional<std::string>{text};
}

std::string GeminiGenerateContentProtocol::make_request_body(
    const OpenAIChatCompletionRequest& request) {
    (void)require_model(request, "Gemini generateContent");
    MutableJsonDocument document{
        yyjson_mut_doc_new(nullptr),
        &yyjson_mut_doc_free,
    };
    if (!document) {
        throw std::bad_alloc();
    }
    auto* root = yyjson_mut_obj(document.get());
    if (!root) {
        throw std::bad_alloc();
    }
    yyjson_mut_doc_set_root(document.get(), root);
    if (!request.system_prompt.empty()) {
        auto* instruction = yyjson_mut_obj_add_obj(document.get(), root, "systemInstruction");
        if (!instruction) {
            throw std::bad_alloc();
        }
        auto* parts = yyjson_mut_obj_add_arr(document.get(), instruction, "parts");
        if (!parts) {
            throw std::bad_alloc();
        }
        (void)add_text_part(document.get(), parts, request.system_prompt);
    }
    auto* contents = yyjson_mut_obj_add_arr(document.get(), root, "contents");
    if (!contents) {
        throw std::bad_alloc();
    }
    for (const auto& message : request.messages) {
        if (message.content.empty()) {
            continue;
        }
        auto* content = yyjson_mut_arr_add_obj(document.get(), contents);
        if (!content) {
            throw std::bad_alloc();
        }
        add_string(document.get(), content, "role", gemini_role(message.role));
        auto* parts = yyjson_mut_obj_add_arr(document.get(), content, "parts");
        if (!parts) {
            throw std::bad_alloc();
        }
        (void)add_text_part(document.get(), parts, message.content);
    }

    std::size_t length = 0;
    JsonText text{
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        &std::free,
    };
    if (!text) {
        throw std::runtime_error("Unable to encode Gemini generateContent request");
    }
    return {text.get(), length};
}

std::optional<std::string> GeminiGenerateContentProtocol::parse_response(std::string_view body) {
    JsonDocument document{
        yyjson_read(body.data(), body.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    auto* candidates = yyjson_is_obj(root) ? yyjson_obj_get(root, "candidates") : nullptr;
    auto* candidate = yyjson_arr_get_first(candidates);
    auto* content = yyjson_is_obj(candidate) ? yyjson_obj_get(candidate, "content") : nullptr;
    auto* parts = yyjson_is_obj(content) ? yyjson_obj_get(content, "parts") : nullptr;
    if (!yyjson_is_arr(parts)) {
        return std::nullopt;
    }

    std::string result;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* part = nullptr;
    yyjson_arr_foreach(parts, index, maximum, part) {
        if (const auto text = text_member(part, "text")) {
            append_text(result, *text);
        }
    }
    const auto text = trim_ascii(result);
    return text.empty() ? std::nullopt : std::optional<std::string>{text};
}

}  // namespace zisla::core
