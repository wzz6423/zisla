#include "zisla/core/CLIApplication.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <Windows.h>
#include <objbase.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <climits>
#include <cstdint>
#include <cwctype>
#include <filesystem>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::string wide_to_utf8(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }
    if (value.size() > static_cast<std::size_t>(INT_MAX)) {
        throw std::runtime_error("command-line argument is too long");
    }
    const auto length = static_cast<int>(value.size());
    const auto required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        length,
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) {
        throw std::runtime_error("unable to encode command-line argument as UTF-8");
    }
    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            length,
            result.data(),
            required,
            nullptr,
            nullptr) != required) {
        throw std::runtime_error("unable to encode command-line argument as UTF-8");
    }
    return result;
}

std::wstring utf8_to_wide(std::string_view value) {
    if (value.empty()) {
        return {};
    }
    if (value.size() > static_cast<std::size_t>(INT_MAX)) {
        throw std::runtime_error("output is too long");
    }
    const auto length = static_cast<int>(value.size());
    const auto required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        length,
        nullptr,
        0);
    if (required <= 0) {
        throw std::runtime_error("unable to decode UTF-8 output");
    }
    std::wstring result(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            length,
            result.data(),
            required) != required) {
        throw std::runtime_error("unable to decode UTF-8 output");
    }
    return result;
}

void write_utf8(DWORD stream, std::string_view value) noexcept {
    if (value.empty()) {
        return;
    }
    const auto handle = GetStdHandle(stream);
    if (!handle || handle == INVALID_HANDLE_VALUE) {
        return;
    }

    DWORD mode = 0;
    if (GetConsoleMode(handle, &mode)) {
        try {
            const auto wide = utf8_to_wide(value);
            std::size_t offset = 0;
            while (offset < wide.size()) {
                const auto remaining = wide.size() - offset;
                const auto count = static_cast<DWORD>(std::min<std::size_t>(
                    remaining,
                    std::numeric_limits<DWORD>::max()));
                DWORD written = 0;
                if (!WriteConsoleW(handle, wide.data() + offset, count, &written, nullptr)
                    || written == 0) {
                    return;
                }
                offset += written;
            }
        } catch (...) {
        }
        return;
    }

    std::size_t offset = 0;
    while (offset < value.size()) {
        const auto remaining = value.size() - offset;
        const auto count = static_cast<DWORD>(std::min<std::size_t>(
            remaining,
            std::numeric_limits<DWORD>::max()));
        DWORD written = 0;
        if (!WriteFile(handle, value.data() + offset, count, &written, nullptr)
            || written == 0) {
            return;
        }
        offset += written;
    }
}

std::filesystem::path state_directory() {
    PWSTR raw_path = nullptr;
    const auto result = SHGetKnownFolderPath(
        FOLDERID_LocalAppData,
        KF_FLAG_NO_PACKAGE_REDIRECTION,
        nullptr,
        &raw_path);
    if (FAILED(result) || !raw_path) {
        CoTaskMemFree(raw_path);
        throw std::runtime_error("unable to locate LocalAppData");
    }
    const std::filesystem::path path(raw_path);
    CoTaskMemFree(raw_path);
    return path / L"zisla";
}

std::string generated_id() {
    GUID guid{};
    if (FAILED(CoCreateGuid(&guid))) {
        throw std::runtime_error("unable to generate notification identifier");
    }
    std::array<wchar_t, 39> buffer{};
    const auto length = StringFromGUID2(guid, buffer.data(), static_cast<int>(buffer.size()));
    if (length <= 2) {
        throw std::runtime_error("unable to format notification identifier");
    }
    std::wstring value(buffer.data() + 1, static_cast<std::size_t>(length - 3));
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t character) {
        return static_cast<wchar_t>(std::towlower(character));
    });
    return wide_to_utf8(value);
}

std::int64_t current_unix_milliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
    try {
        std::vector<std::string> encoded_arguments;
        encoded_arguments.reserve(argc > 1 ? static_cast<std::size_t>(argc - 1) : 0);
        for (int index = 1; index < argc; ++index) {
            encoded_arguments.push_back(wide_to_utf8(argv[index]));
        }
        std::vector<std::string_view> arguments;
        arguments.reserve(encoded_arguments.size());
        for (const auto& argument : encoded_arguments) {
            arguments.push_back(argument);
        }

        const auto result = zisla::core::run_cli(
            arguments,
            state_directory(),
            current_unix_milliseconds(),
            generated_id());
        write_utf8(STD_OUTPUT_HANDLE, result.output);
        write_utf8(STD_ERROR_HANDLE, result.error);
        return result.exit_code;
    } catch (const std::exception& error) {
        write_utf8(
            STD_ERROR_HANDLE,
            "错误：zislactl 启动失败：" + std::string(error.what()) + "\n");
        return 70;
    }
}
