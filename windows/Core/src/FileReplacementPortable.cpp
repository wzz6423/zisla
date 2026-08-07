#include "FileReplacement.hpp"

namespace zisla::core::detail {

std::error_code replace_file_atomically(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) noexcept {
    std::error_code error;
    std::filesystem::rename(source, destination, error);
    return error;
}

}
