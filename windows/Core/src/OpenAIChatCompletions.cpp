#include "zisla/core/OpenAIChatCompletions.hpp"

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

void append_message(
    yyjson_mut_doc* document,
    yyjson_mut_val* messages,
    AgentWorkspaceMessageRole role,
    std::string_view content) {
    const auto role_token = agent_workspace_message_role_token(role);
    if (role_token.empty()) {
        throw std::invalid_argument("OpenAI-compatible chat message role is invalid");
    }
    auto* message = yyjson_mut_arr_add_obj(document, messages);
    if (!message) {
        throw std::bad_alloc();
    }
    require_json(yyjson_mut_obj_add_strncpy(
        document,
        message,
        "role",
        role_token.data(),
        role_token.size()));
    require_json(yyjson_mut_obj_add_strncpy(
        document,
        message,
        "content",
        content.data(),
        content.size()));
}

}  // namespace

std::string OpenAIChatCompletionsProtocol::make_request_body(
    const OpenAIChatCompletionRequest& request) {
    const auto model = trim_ascii(request.model);
    if (model.empty()) {
        throw std::invalid_argument("OpenAI-compatible chat model is required");
    }

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
    require_json(yyjson_mut_obj_add_strcpy(document.get(), root, "model", model.c_str()));
    require_json(yyjson_mut_obj_add_bool(document.get(), root, "stream", false));
    auto* messages = yyjson_mut_obj_add_arr(document.get(), root, "messages");
    if (!messages) {
        throw std::bad_alloc();
    }
    if (!request.system_prompt.empty()) {
        append_message(
            document.get(),
            messages,
            AgentWorkspaceMessageRole::system,
            request.system_prompt);
    }
    for (const auto& message : request.messages) {
        if (message.content.empty()) {
            continue;
        }
        append_message(document.get(), messages, message.role, message.content);
    }

    std::size_t length = 0;
    JsonText text{
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        &std::free,
    };
    if (!text) {
        throw std::runtime_error("Unable to encode OpenAI-compatible chat request");
    }
    return {text.get(), length};
}

std::optional<std::string> OpenAIChatCompletionsProtocol::parse_response(
    std::string_view body) {
    JsonDocument document{
        yyjson_read(body.data(), body.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        return std::nullopt;
    }
    auto* choices = yyjson_obj_get(root, "choices");
    auto* choice = yyjson_arr_get_first(choices);
    if (!yyjson_is_obj(choice)) {
        return std::nullopt;
    }
    auto* message = yyjson_obj_get(choice, "message");
    if (!yyjson_is_obj(message)) {
        return std::nullopt;
    }
    auto* content = yyjson_obj_get(message, "content");
    if (!content || yyjson_is_null(content)) {
        return std::string{};
    }
    if (!yyjson_is_str(content)) {
        return std::nullopt;
    }
    const auto* value = yyjson_get_str(content);
    if (!value) {
        return std::nullopt;
    }
    return trim_ascii({value, yyjson_get_len(content)});
}

}  // namespace zisla::core
