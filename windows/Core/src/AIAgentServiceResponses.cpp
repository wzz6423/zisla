#include "zisla/core/AIAgentServiceResponses.hpp"

#include <yyjson.h>

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace zisla::core {
namespace {

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

std::optional<double> number_value(yyjson_val* value) {
    if (!value || yyjson_is_null(value)) {
        return std::nullopt;
    }
    if (yyjson_is_num(value)) {
        const auto number = yyjson_get_num(value);
        return std::isfinite(number) ? std::optional<double>{number} : std::nullopt;
    }
    if (!yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto* text = yyjson_get_str(value);
    if (!text) {
        return std::nullopt;
    }
    std::string copy(text, yyjson_get_len(value));
    char* end = nullptr;
    errno = 0;
    const auto number = std::strtod(copy.c_str(), &end);
    return errno == 0 && end == copy.c_str() + copy.size() && std::isfinite(number)
        ? std::optional<double>{number}
        : std::nullopt;
}

std::optional<double> first_number(yyjson_val* object, std::initializer_list<const char*> keys) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    for (const auto* key : keys) {
        if (const auto number = number_value(yyjson_obj_get(object, key))) {
            return number;
        }
    }
    return std::nullopt;
}

double sum_numbers_named(yyjson_val* value, std::string_view name) {
    if (yyjson_is_obj(value)) {
        double result = 0;
        std::size_t index = 0;
        std::size_t maximum = 0;
        yyjson_val* key = nullptr;
        yyjson_val* item = nullptr;
        yyjson_obj_foreach(value, index, maximum, key, item) {
            if (yyjson_is_str(key)) {
                const auto* key_text = yyjson_get_str(key);
                if (key_text
                    && std::string_view(key_text, yyjson_get_len(key)) == name) {
                    result += number_value(item).value_or(0.0);
                }
            }
            result += sum_numbers_named(item, name);
        }
        return result;
    }
    if (yyjson_is_arr(value)) {
        double result = 0;
        std::size_t index = 0;
        std::size_t maximum = 0;
        yyjson_val* item = nullptr;
        yyjson_arr_foreach(value, index, maximum, item) {
            result += sum_numbers_named(item, name);
        }
        return result;
    }
    return 0;
}

std::optional<AgentBalanceSnapshot> parse_openai_credits(
    yyjson_val* root,
    std::int64_t checked_at_unix_ms) {
    if (!yyjson_is_obj(root)) {
        return std::nullopt;
    }
    const auto total = first_number(root, {"total_available", "total_granted"});
    const auto used = first_number(root, {"total_used"});
    const auto available = first_number(root, {"total_available"})
        ? first_number(root, {"total_available"})
        : total ? std::optional<double>{*total - used.value_or(0.0)} : std::nullopt;
    return AgentBalanceSnapshot{
        .available = available,
        .used = used,
        .currency = "USD",
        .checked_at_unix_ms = checked_at_unix_ms,
        .detail = std::nullopt,
    };
}

std::optional<AgentBalanceSnapshot> parse_anthropic_usage(
    yyjson_val* root,
    std::int64_t checked_at_unix_ms) {
    if (!yyjson_is_obj(root)) {
        return std::nullopt;
    }
    const auto used = sum_numbers_named(root, "input_tokens")
        + sum_numbers_named(root, "output_tokens");
    return AgentBalanceSnapshot{
        .available = std::nullopt,
        .used = used == 0.0 ? std::nullopt : std::optional<double>{used},
        .currency = "tokens",
        .checked_at_unix_ms = checked_at_unix_ms,
        .detail = "Anthropic usage for the last 24 hours; balance unavailable",
    };
}

std::optional<AgentBalanceSnapshot> parse_new_api_quota(
    yyjson_val* root,
    std::int64_t checked_at_unix_ms) {
    if (!yyjson_is_obj(root)) {
        return std::nullopt;
    }
    auto* data = yyjson_obj_get(root, "data");
    if (!yyjson_is_obj(data)) {
        data = root;
    }
    const auto quota = first_number(data, {"quota", "balance", "available_quota"});
    const auto used = first_number(data, {"used_quota", "used", "consumed_quota"});
    const auto has_available = yyjson_obj_get(data, "balance") != nullptr
        || yyjson_obj_get(data, "available_quota") != nullptr;
    const auto available = has_available
        ? quota
        : quota ? std::optional<double>{*quota - used.value_or(0.0)} : std::nullopt;
    if (!available && !used) {
        return std::nullopt;
    }
    return AgentBalanceSnapshot{
        .available = available,
        .used = used,
        .currency = "quota",
        .checked_at_unix_ms = checked_at_unix_ms,
        .detail = "Provider quota unit",
    };
}

std::optional<std::string> model_name(yyjson_val* value) {
    if (!yyjson_is_obj(value)) {
        return std::nullopt;
    }
    auto* name = yyjson_obj_get(value, "id");
    if (!yyjson_is_str(name)) {
        name = yyjson_obj_get(value, "name");
    }
    if (!yyjson_is_str(name)) {
        return std::nullopt;
    }
    const auto* text = yyjson_get_str(name);
    if (!text || yyjson_get_len(name) == 0) {
        return std::nullopt;
    }
    std::string result(text, yyjson_get_len(name));
    constexpr std::string_view prefix = "models/";
    if (result.starts_with(prefix)) {
        result.erase(0, prefix.size());
    }
    return result.empty() ? std::nullopt : std::optional<std::string>{std::move(result)};
}

}  // namespace

std::optional<AgentBalanceSnapshot> AIAgentBalanceResponseParser::parse(
    AgentBalanceProbeKind kind,
    std::string_view body,
    std::int64_t checked_at_unix_ms) {
    JsonDocument document{
        yyjson_read(body.data(), body.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        return std::nullopt;
    }
    auto* root = yyjson_doc_get_root(document.get());
    switch (kind) {
    case AgentBalanceProbeKind::openai_credits:
        return parse_openai_credits(root, checked_at_unix_ms);
    case AgentBalanceProbeKind::anthropic_usage:
        return parse_anthropic_usage(root, checked_at_unix_ms);
    case AgentBalanceProbeKind::new_api_quota:
        return parse_new_api_quota(root, checked_at_unix_ms);
    case AgentBalanceProbeKind::custom_script:
        return std::nullopt;
    }
    return std::nullopt;
}

std::optional<std::vector<std::string>> AIAgentModelCatalogResponseParser::parse(
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
    auto* models = yyjson_obj_get(root, "data");
    if (!yyjson_is_arr(models)) {
        models = yyjson_obj_get(root, "models");
    }
    if (!yyjson_is_arr(models)) {
        return std::nullopt;
    }
    std::vector<std::string> values;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* item = nullptr;
    yyjson_arr_foreach(models, index, maximum, item) {
        if (const auto name = model_name(item)) {
            values.push_back(*name);
        }
    }
    auto normalized = AgentChannelModelCatalog::normalize_models(std::move(values));
    return normalized.empty()
        ? std::nullopt
        : std::optional<std::vector<std::string>>{std::move(normalized)};
}

AgentChannelHealth agent_channel_health_for_http_status(std::uint32_t status) noexcept {
    if (status >= 200 && status < 300) {
        return AgentChannelHealth::healthy;
    }
    if (status == 401 || status == 403 || status == 429) {
        return AgentChannelHealth::degraded;
    }
    return AgentChannelHealth::unavailable;
}

}  // namespace zisla::core
