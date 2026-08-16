#include "zisla/core/CLIParser.hpp"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace zisla::core {

CLIParseError::CLIParseError(
    CLIParseErrorCode code,
    std::string subject,
    std::string message)
    : std::runtime_error(std::move(message)),
      code_(code),
      subject_(std::move(subject)) {}

CLIParseErrorCode CLIParseError::code() const noexcept {
    return code_;
}

const std::string& CLIParseError::subject() const noexcept {
    return subject_;
}

namespace {

struct Option {
    std::string_view name;
    std::string_view value;
};

using Options = std::vector<Option>;

[[noreturn]] void fail(CLIParseErrorCode code, std::string_view subject) {
    std::string message;
    switch (code) {
    case CLIParseErrorCode::missing_subcommand:
        message = "missing subcommand";
        break;
    case CLIParseErrorCode::unknown_subcommand:
        message = "unknown subcommand: ";
        break;
    case CLIParseErrorCode::unexpected_argument:
        message = "unexpected argument: ";
        break;
    case CLIParseErrorCode::unknown_option:
        message = "unknown option: ";
        break;
    case CLIParseErrorCode::missing_option:
        message = "missing required option: ";
        break;
    case CLIParseErrorCode::invalid_value:
        message = "invalid option value: ";
        break;
    case CLIParseErrorCode::progress_out_of_range:
        message = "progress is outside 0-100: ";
        break;
    case CLIParseErrorCode::unknown_provider:
        message = "unknown provider: ";
        break;
    case CLIParseErrorCode::unknown_notice_kind:
        message = "unknown notice kind: ";
        break;
    case CLIParseErrorCode::unknown_notice_side:
        message = "unknown notice side: ";
        break;
    }
    message.append(subject);
    throw CLIParseError(code, std::string(subject), std::move(message));
}

bool starts_with_option_prefix(std::string_view value) noexcept {
    return value.starts_with("--");
}

bool allowed_option(
    std::span<const std::string_view> allowed,
    std::string_view option) noexcept {
    return std::find(allowed.begin(), allowed.end(), option) != allowed.end();
}

Options parse_options(
    std::span<const std::string_view> tokens,
    std::span<const std::string_view> allowed) {
    Options result;
    for (std::size_t index = 0; index < tokens.size();) {
        const auto token = tokens[index];
        if (!starts_with_option_prefix(token)) {
            fail(CLIParseErrorCode::unexpected_argument, token);
        }
        if (!allowed_option(allowed, token)) {
            fail(CLIParseErrorCode::unknown_option, token);
        }

        std::string_view value;
        if (index + 1 < tokens.size()
            && !starts_with_option_prefix(tokens[index + 1])) {
            value = tokens[index + 1];
            index += 2;
        } else {
            ++index;
        }

        const auto existing = std::find_if(
            result.begin(),
            result.end(),
            [token](const Option& option) {
                return option.name == token;
            });
        if (existing == result.end()) {
            result.push_back({token, value});
        } else {
            existing->value = value;
        }
    }
    return result;
}

std::optional<std::string_view> find_option(
    const Options& options,
    std::string_view name) noexcept {
    const auto found = std::find_if(
        options.begin(),
        options.end(),
        [name](const Option& option) {
            return option.name == name;
        });
    if (found == options.end()) {
        return std::nullopt;
    }
    return found->value;
}

std::string require_option(const Options& options, std::string_view name) {
    const auto value = find_option(options, name);
    if (!value || value->empty()) {
        fail(CLIParseErrorCode::missing_option, name);
    }
    return std::string(*value);
}

std::optional<std::string> optional_string(
    const Options& options,
    std::string_view name) {
    const auto value = find_option(options, name);
    return value ? std::optional<std::string>(std::string(*value)) : std::nullopt;
}

std::optional<double> parse_double(std::string_view value) noexcept {
    double result = 0.0;
    const auto parsed = std::from_chars(
        value.data(),
        value.data() + value.size(),
        result,
        std::chars_format::general);
    if (parsed.ec != std::errc{}
        || parsed.ptr != value.data() + value.size()
        || !std::isfinite(result)) {
        return std::nullopt;
    }
    return result;
}

std::optional<std::uint64_t> parse_unsigned(std::string_view value) noexcept {
    if (value.empty() || value.front() == '-') {
        return std::nullopt;
    }
    std::uint64_t result = 0;
    const auto parsed = std::from_chars(
        value.data(), value.data() + value.size(), result, 10);
    if (parsed.ec != std::errc{}
        || parsed.ptr != value.data() + value.size()) {
        return std::nullopt;
    }
    return result;
}

std::uint64_t require_unsigned(const Options& options, std::string_view name) {
    const auto raw = require_option(options, name);
    const auto parsed = parse_unsigned(raw);
    if (!parsed
        || *parsed > static_cast<std::uint64_t>(
            std::numeric_limits<std::int64_t>::max())) {
        fail(CLIParseErrorCode::invalid_value, name);
    }
    return *parsed;
}

AIProvider require_provider(const Options& options) {
    const auto raw = require_option(options, "--provider");
    const auto provider = parse_ai_provider(raw);
    if (!provider) {
        fail(CLIParseErrorCode::unknown_provider, raw);
    }
    return *provider;
}

std::int64_t unix_milliseconds(std::string_view raw) {
    const auto seconds = parse_double(raw);
    if (!seconds) {
        fail(CLIParseErrorCode::invalid_value, "--timestamp");
    }
    const auto milliseconds = static_cast<long double>(*seconds) * 1'000.0L;
    if (milliseconds < static_cast<long double>(std::numeric_limits<std::int64_t>::min())
        || milliseconds > static_cast<long double>(std::numeric_limits<std::int64_t>::max())) {
        fail(CLIParseErrorCode::invalid_value, "--timestamp");
    }
    return static_cast<std::int64_t>(std::round(milliseconds));
}

std::optional<std::string> normalized_optional_identifier(
    const Options& options,
    std::string_view name) {
    const auto value = find_option(options, name);
    if (!value) {
        return std::nullopt;
    }
    const auto first = value->find_first_not_of(" \t\n\r\f\v");
    if (first == std::string_view::npos) {
        return std::nullopt;
    }
    const auto last = value->find_last_not_of(" \t\n\r\f\v");
    return std::string(value->substr(first, last - first + 1));
}

CLICommand parse_update(const Options& options, std::int64_t now_unix_ms) {
    std::optional<double> progress;
    if (const auto raw = find_option(options, "--progress")) {
        const auto percent = parse_double(*raw);
        if (!percent) {
            fail(CLIParseErrorCode::invalid_value, "--progress");
        }
        if (*percent < 0.0 || *percent > 100.0) {
            fail(CLIParseErrorCode::progress_out_of_range, *raw);
        }
        progress = *percent / 100.0;
    }

    AIProgressStatus status = find_option(options, "--queued")
        ? AIProgressStatus::queued
        : AIProgressStatus::running;
    if (const auto raw = find_option(options, "--status")) {
        const auto parsed = parse_ai_progress_status(*raw);
        if (!parsed || !is_active(*parsed)) {
            fail(CLIParseErrorCode::invalid_value, "--status");
        }
        status = *parsed;
    }

    return CLIUpdateCommand{.task = {
        .id = require_option(options, "--id"),
        .provider = require_provider(options),
        .title = require_option(options, "--title"),
        .detail = optional_string(options, "--detail"),
        .progress = progress,
        .status = status,
        .updated_at_unix_ms = now_unix_ms,
    }};
}

CLICommand parse_finish(const Options& options) {
    bool failed = false;
    if (const auto raw = find_option(options, "--failed")) {
        if (raw->empty() || *raw == "true") {
            failed = true;
        } else if (*raw != "false") {
            fail(CLIParseErrorCode::invalid_value, "--failed");
        }
    }
    return CLIFinishCommand{
        .id = require_option(options, "--id"),
        .failed = failed,
        .detail = optional_string(options, "--detail"),
    };
}

CLICommand parse_usage(const Options& options, std::int64_t now_unix_ms) {
    std::optional<double> cost;
    if (const auto raw = find_option(options, "--cost")) {
        cost = parse_double(*raw);
        if (!cost) {
            fail(CLIParseErrorCode::invalid_value, "--cost");
        }
    }

    auto timestamp = now_unix_ms;
    if (const auto raw = find_option(options, "--timestamp")) {
        timestamp = unix_milliseconds(*raw);
    }
    return CLIUsageCommand{.sample = {
        .provider = require_provider(options),
        .timestamp_unix_ms = timestamp,
        .input_tokens = require_unsigned(options, "--input-tokens"),
        .output_tokens = require_unsigned(options, "--output-tokens"),
        .cost_usd = cost,
        .model = optional_string(options, "--model"),
    }};
}

CLICommand parse_notify(
    const Options& options,
    std::int64_t now_unix_ms,
    std::string generated_id) {
    auto kind = NoticeKind::info;
    if (const auto raw = find_option(options, "--kind")) {
        const auto parsed = parse_notice_kind(*raw);
        if (!parsed) {
            fail(CLIParseErrorCode::unknown_notice_kind, *raw);
        }
        kind = *parsed;
    }

    auto side = NoticeSide::right;
    if (const auto raw = find_option(options, "--side")) {
        const auto parsed = parse_notice_side(*raw);
        if (!parsed) {
            fail(CLIParseErrorCode::unknown_notice_side, *raw);
        }
        side = *parsed;
    }
    return CLINotifyCommand{.notice = {
        .id = std::move(generated_id),
        .title = require_option(options, "--title"),
        .detail = optional_string(options, "--detail"),
        .kind = kind,
        .side = side,
        .created_at_unix_ms = now_unix_ms,
    }};
}

CLICommand parse_message(
    const Options& options,
    std::int64_t now_unix_ms,
    std::string generated_id) {
    return CLIMessageCommand{.message = {
        .app_name = require_option(options, "--app"),
        .sender = require_option(options, "--sender"),
        .content = MessageNotification::normalize_content(
            require_option(options, "--content")),
        .app_bundle_identifier = normalized_optional_identifier(
            options, "--app-bundle-id"),
        .created_at_unix_ms = now_unix_ms,
        .pair_id = std::move(generated_id),
    }};
}

}  // namespace

CLICommand CLIParser::parse(
    std::span<const std::string_view> arguments,
    std::int64_t now_unix_ms,
    std::string generated_id) {
    if (arguments.empty()) {
        fail(CLIParseErrorCode::missing_subcommand, {});
    }

    const auto subcommand = arguments.front();
    const auto tokens = arguments.subspan(1);
    if (subcommand == "update") {
        constexpr auto allowed = std::to_array<std::string_view>({
            "--id", "--provider", "--title", "--progress", "--detail",
            "--status", "--queued",
        });
        return parse_update(parse_options(tokens, allowed), now_unix_ms);
    }
    if (subcommand == "finish") {
        constexpr auto allowed = std::to_array<std::string_view>({
            "--id", "--failed", "--detail",
        });
        return parse_finish(parse_options(tokens, allowed));
    }
    if (subcommand == "remove") {
        constexpr auto allowed = std::to_array<std::string_view>({"--id"});
        const auto options = parse_options(tokens, allowed);
        return CLIRemoveCommand{.id = require_option(options, "--id")};
    }
    if (subcommand == "clear") {
        constexpr std::array<std::string_view, 0> allowed{};
        (void)parse_options(tokens, allowed);
        return CLIClearCommand{};
    }
    if (subcommand == "list") {
        constexpr std::array<std::string_view, 0> allowed{};
        (void)parse_options(tokens, allowed);
        return CLIListCommand{};
    }
    if (subcommand == "usage") {
        constexpr auto allowed = std::to_array<std::string_view>({
            "--provider", "--input-tokens", "--output-tokens", "--cost",
            "--model", "--timestamp",
        });
        return parse_usage(parse_options(tokens, allowed), now_unix_ms);
    }
    if (subcommand == "notify") {
        constexpr auto allowed = std::to_array<std::string_view>({
            "--title", "--detail", "--kind", "--side",
        });
        return parse_notify(
            parse_options(tokens, allowed),
            now_unix_ms,
            std::move(generated_id));
    }
    if (subcommand == "message") {
        constexpr auto allowed = std::to_array<std::string_view>({
            "--app", "--sender", "--content", "--app-bundle-id",
        });
        return parse_message(
            parse_options(tokens, allowed),
            now_unix_ms,
            std::move(generated_id));
    }
    if (subcommand == "help" || subcommand == "--help" || subcommand == "-h") {
        constexpr std::array<std::string_view, 0> allowed{};
        (void)parse_options(tokens, allowed);
        return CLIHelpCommand{};
    }
    fail(CLIParseErrorCode::unknown_subcommand, subcommand);
}

}  // namespace zisla::core
