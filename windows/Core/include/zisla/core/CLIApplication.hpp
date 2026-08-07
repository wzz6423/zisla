#pragma once

#include <cstdint>
#include <filesystem>
#include <span>
#include <string>
#include <string_view>

namespace zisla::core {

struct CLIResult {
    int exit_code{0};
    std::string output;
    std::string error;

    friend bool operator==(const CLIResult&, const CLIResult&) = default;
};

[[nodiscard]] CLIResult run_cli(
    std::span<const std::string_view> arguments,
    const std::filesystem::path& state_directory,
    std::int64_t now_unix_ms,
    std::string generated_id);

}  // namespace zisla::core
