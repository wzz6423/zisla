#pragma once

#include <filesystem>
#include <system_error>

namespace zisla::core::detail {

[[nodiscard]] std::error_code replace_file_atomically(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) noexcept;

}
