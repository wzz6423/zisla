#include "FileReplacement.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace zisla::core::detail {

std::error_code replace_file_atomically(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) noexcept {
    if (MoveFileExW(
            source.c_str(),
            destination.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        return {};
    }
    return {
        static_cast<int>(GetLastError()),
        std::system_category(),
    };
}

}
