#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstdint>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>

namespace zisla::core {

struct CLIUpdateCommand {
    AIProgressTask task;
    friend bool operator==(const CLIUpdateCommand&, const CLIUpdateCommand&) = default;
};

struct CLIFinishCommand {
    std::string id;
    bool failed{false};
    std::optional<std::string> detail;
    friend bool operator==(const CLIFinishCommand&, const CLIFinishCommand&) = default;
};

struct CLIRemoveCommand {
    std::string id;
    friend bool operator==(const CLIRemoveCommand&, const CLIRemoveCommand&) = default;
};

struct CLIClearCommand {
    friend bool operator==(const CLIClearCommand&, const CLIClearCommand&) = default;
};

struct CLIListCommand {
    friend bool operator==(const CLIListCommand&, const CLIListCommand&) = default;
};

struct CLIUsageCommand {
    AIUsageSample sample;
    friend bool operator==(const CLIUsageCommand&, const CLIUsageCommand&) = default;
};

struct CLINotifyCommand {
    IslandNotice notice;
    friend bool operator==(const CLINotifyCommand&, const CLINotifyCommand&) = default;
};

struct CLIMessageCommand {
    MessageNotification message;
    friend bool operator==(const CLIMessageCommand&, const CLIMessageCommand&) = default;
};

struct CLIHelpCommand {
    friend bool operator==(const CLIHelpCommand&, const CLIHelpCommand&) = default;
};

using CLICommand = std::variant<
    CLIUpdateCommand,
    CLIFinishCommand,
    CLIRemoveCommand,
    CLIClearCommand,
    CLIListCommand,
    CLIUsageCommand,
    CLINotifyCommand,
    CLIMessageCommand,
    CLIHelpCommand>;

enum class CLIParseErrorCode {
    missing_subcommand,
    unknown_subcommand,
    unexpected_argument,
    unknown_option,
    missing_option,
    invalid_value,
    progress_out_of_range,
    unknown_provider,
    unknown_notice_kind,
    unknown_notice_side,
};

class CLIParseError : public std::runtime_error {
public:
    CLIParseError(
        CLIParseErrorCode code,
        std::string subject,
        std::string message);

    [[nodiscard]] CLIParseErrorCode code() const noexcept;
    [[nodiscard]] const std::string& subject() const noexcept;

private:
    CLIParseErrorCode code_;
    std::string subject_;
};

class CLIParser {
public:
    [[nodiscard]] static CLICommand parse(
        std::span<const std::string_view> arguments,
        std::int64_t now_unix_ms,
        std::string generated_id);
};

}  // namespace zisla::core
