#include "LocalOfficeAdapter.hpp"

#include <zisla/core/PDFProcessing.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <optional>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace zisla::pdf {
namespace {

namespace fs = std::filesystem;

constexpr std::array<std::string_view, 16> supported_extensions{
    "doc", "docx", "dot", "dotx", "rtf", "odt",
    "ppt", "pptx", "pps", "ppsx", "odp",
    "xls", "xlsx", "xlsm", "ods", "csv",
};

[[noreturn]] void fail(LocalOfficeAdapterErrorCode code, std::string message) {
    throw LocalOfficeAdapterError(code, std::move(message));
}

std::string path_as_utf8(const fs::path& path) {
    const auto encoded = path.u8string();
    std::string result;
    result.reserve(encoded.size());
    for (const auto character : encoded) {
        result.push_back(static_cast<char>(character));
    }
    return result;
}

std::string lower_ascii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

std::string display_name(const fs::path& path) {
    const auto name = path.filename();
    return path_as_utf8(name.empty() ? path : name);
}

fs::path normalized_path(const fs::path& path, LocalOfficeAdapterErrorCode code) {
    if (path.empty()) {
        fail(code, "文件路径不能为空");
    }
    std::error_code error;
    const auto absolute = fs::absolute(path, error);
    if (error) {
        fail(code, "文件路径无效");
    }
    const auto canonical = fs::weakly_canonical(absolute, error);
    return error ? absolute.lexically_normal() : canonical.lexically_normal();
}

bool is_unreserved_uri_character(unsigned char character) noexcept {
    return (character >= 'A' && character <= 'Z')
        || (character >= 'a' && character <= 'z')
        || (character >= '0' && character <= '9')
        || character == '-' || character == '.' || character == '_' || character == '~'
        || character == '/' || character == ':';
}

std::string file_uri(const fs::path& directory) {
    const auto normalized = normalized_path(
        directory,
        LocalOfficeAdapterErrorCode::cannot_prepare_directory);
    const auto generic = normalized.generic_u8string();
    std::string result = !generic.empty() && generic.front() == u8'/'
        ? "file://"
        : "file:///";
    result.reserve(result.size() + generic.size() * 3U + 1U);
    constexpr char hex[] = "0123456789ABCDEF";
    for (const auto character : generic) {
        const auto byte = static_cast<unsigned char>(character);
        if (is_unreserved_uri_character(byte)) {
            result.push_back(static_cast<char>(byte));
        } else {
            result.push_back('%');
            result.push_back(hex[byte >> 4U]);
            result.push_back(hex[byte & 0x0fU]);
        }
    }
    if (result.back() != '/') {
        result.push_back('/');
    }
    return result;
}

class TemporaryDirectory {
public:
    explicit TemporaryDirectory(fs::path path)
        : path_(std::move(path)) {}

    ~TemporaryDirectory() {
        std::error_code error;
        fs::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const fs::path& path() const noexcept {
        return path_;
    }

private:
    fs::path path_;
};

fs::path make_temporary_directory() {
    std::error_code error;
    const auto root = fs::temp_directory_path(error);
    if (error) {
        fail(LocalOfficeAdapterErrorCode::cannot_prepare_directory, "无法定位临时目录");
    }
    static std::atomic_uint64_t sequence{0};
    const auto suffix = std::to_string(
        std::chrono::steady_clock::now().time_since_epoch().count())
        + "-" + std::to_string(sequence.fetch_add(1, std::memory_order_relaxed));
    const auto directory = root / "Zisla" / "OfficeConversion" / suffix;
    fs::create_directories(directory, error);
    if (error || !fs::is_directory(directory, error) || error) {
        fail(
            LocalOfficeAdapterErrorCode::cannot_prepare_directory,
            "无法创建 LibreOffice 临时目录");
    }
    return directory;
}

void validate_output(const fs::path& input, const fs::path& output) {
    const std::array inputs{input};
    const std::array outputs{output};
    const auto validation = zisla::core::PDFProcessing::validate_outputs(inputs, outputs);
    if (validation != zisla::core::PDFOutputValidationError::none) {
        fail(
            LocalOfficeAdapterErrorCode::output_validation,
            validation == zisla::core::PDFOutputValidationError::output_already_exists
                ? "输出文件已存在，未覆盖：" + display_name(output)
                : "Office 转 PDF 输出路径无效");
    }
}

std::optional<fs::path> available_executable(
    const std::vector<fs::path>& candidates) {
    std::error_code error;
    for (const auto& candidate : candidates) {
        if (fs::is_regular_file(candidate, error) && !error) {
            return candidate;
        }
        error.clear();
    }
    return std::nullopt;
}

#ifdef _WIN32

std::wstring utf8_to_wide(std::string_view value) {
    if (value.empty()) {
        return {};
    }
    const auto required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (required <= 0) {
        fail(LocalOfficeAdapterErrorCode::launch_failed, "LibreOffice 参数编码无效");
    }
    std::wstring converted(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            converted.data(),
            required) != required) {
        fail(LocalOfficeAdapterErrorCode::launch_failed, "LibreOffice 参数编码无效");
    }
    return converted;
}

std::wstring quote_windows_argument(std::wstring_view value) {
    std::wstring result{L"\""};
    std::size_t slash_count = 0;
    for (const auto character : value) {
        if (character == L'\\') {
            ++slash_count;
            continue;
        }
        if (character == L'\"') {
            result.append(slash_count * 2U + 1U, L'\\');
            result.push_back(character);
            slash_count = 0;
            continue;
        }
        result.append(slash_count, L'\\');
        slash_count = 0;
        result.push_back(character);
    }
    result.append(slash_count * 2U, L'\\');
    result.push_back(L'\"');
    return result;
}

std::string last_error_message(DWORD error) {
    const std::error_code code{static_cast<int>(error), std::system_category()};
    return code.message();
}

void run_converter(
    const fs::path& executable,
    const std::vector<std::string>& arguments,
    const fs::path& working_directory) {
    std::wstring command_line = quote_windows_argument(executable.wstring());
    for (const auto& argument : arguments) {
        command_line.push_back(L' ');
        command_line.append(quote_windows_argument(utf8_to_wide(argument)));
    }
    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            executable.c_str(),
            mutable_command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            working_directory.c_str(),
            &startup,
            &process)) {
        fail(
            LocalOfficeAdapterErrorCode::launch_failed,
            "无法启动 LibreOffice：" + last_error_message(GetLastError()));
    }

    const auto close_handles = [&process] {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    };
    const auto wait_result = WaitForSingleObject(process.hProcess, 5U * 60U * 1000U);
    if (wait_result == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, 1);
        close_handles();
        fail(LocalOfficeAdapterErrorCode::conversion_failed, "LibreOffice 转换超时");
    }
    if (wait_result != WAIT_OBJECT_0) {
        const auto error = GetLastError();
        close_handles();
        fail(
            LocalOfficeAdapterErrorCode::conversion_failed,
            "无法等待 LibreOffice 转换完成：" + last_error_message(error));
    }
    DWORD exit_code = 1;
    const auto has_exit_code = GetExitCodeProcess(process.hProcess, &exit_code) != FALSE;
    close_handles();
    if (!has_exit_code || exit_code != 0) {
        fail(
            LocalOfficeAdapterErrorCode::conversion_failed,
            "LibreOffice 转换失败，退出码：" + std::to_string(exit_code));
    }
}

#endif

}  // namespace

LocalOfficeAdapterError::LocalOfficeAdapterError(
    LocalOfficeAdapterErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)),
      code_(code) {}

LocalOfficeAdapterErrorCode LocalOfficeAdapterError::code() const noexcept {
    return code_;
}

LocalOfficeAdapter::LocalOfficeAdapter()
    : LocalOfficeAdapter(default_executable_candidates()) {}

LocalOfficeAdapter::LocalOfficeAdapter(std::vector<fs::path> executable_candidates)
    : executable_candidates_(std::move(executable_candidates)) {}

bool LocalOfficeAdapter::supports(const fs::path& input) {
    const auto extension = lower_ascii(path_as_utf8(input.extension()));
    if (extension.size() < 2U || extension.front() != '.') {
        return false;
    }
    const auto name = std::string_view{extension}.substr(1U);
    return std::find(supported_extensions.begin(), supported_extensions.end(), name)
        != supported_extensions.end();
}

std::vector<fs::path> LocalOfficeAdapter::default_executable_candidates() {
#ifdef _WIN32
    std::vector<fs::path> candidates{
        LR"(C:\Program Files\LibreOffice\program\soffice.exe)",
        LR"(C:\Program Files (x86)\LibreOffice\program\soffice.exe)",
    };
    if (const auto* local_app_data = std::getenv("LOCALAPPDATA"); local_app_data
        && *local_app_data != '\0') {
        candidates.emplace_back(
            fs::path{local_app_data} / "Programs" / "LibreOffice" / "program" / "soffice.exe");
    }
    return candidates;
#else
    return {};
#endif
}

std::vector<std::string> LocalOfficeAdapter::conversion_arguments(
    const fs::path& input,
    const fs::path& output_directory,
    const fs::path& profile_directory) {
    return {
        "-env:UserInstallation=" + file_uri(profile_directory),
        "--headless",
        "--convert-to",
        "pdf",
        "--outdir",
        path_as_utf8(output_directory),
        path_as_utf8(input),
    };
}

void LocalOfficeAdapter::convert_to_pdf(
    const fs::path& input,
    const fs::path& output) const {
    const auto source = normalized_path(input, LocalOfficeAdapterErrorCode::invalid_input);
    std::error_code error;
    if (!supports(source) || !fs::is_regular_file(source, error) || error) {
        fail(
            LocalOfficeAdapterErrorCode::invalid_input,
            "不支持的 Office 文件：" + display_name(source));
    }
    const auto destination = normalized_path(output, LocalOfficeAdapterErrorCode::output_validation);
    validate_output(source, destination);
    const auto executable = available_executable(executable_candidates_);
    if (!executable) {
        fail(
            LocalOfficeAdapterErrorCode::converter_not_installed,
            "未找到 LibreOffice；请安装 LibreOffice 后重试");
    }

    const auto temporary_path = make_temporary_directory();
    const TemporaryDirectory temporary{temporary_path};
    const auto profile_directory = temporary.path() / "LibreOfficeProfile";
    fs::create_directories(profile_directory, error);
    if (error || !fs::is_directory(profile_directory, error) || error) {
        fail(
            LocalOfficeAdapterErrorCode::cannot_prepare_directory,
            "无法创建 LibreOffice 配置目录");
    }
    error.clear();
    fs::create_directories(destination.parent_path(), error);
    if (error || !fs::is_directory(destination.parent_path(), error) || error) {
        fail(
            LocalOfficeAdapterErrorCode::cannot_prepare_directory,
            "无法创建 PDF 输出目录");
    }

#ifdef _WIN32
    run_converter(
        *executable,
        conversion_arguments(source, temporary.path(), profile_directory),
        temporary.path());
#else
    (void)executable;
    fail(
        LocalOfficeAdapterErrorCode::unsupported_platform,
        "Office 转 PDF 只能在 Windows 上调用本机 LibreOffice");
#endif

    auto converted_name = source.filename();
    converted_name.replace_extension(".pdf");
    const auto converted = temporary.path() / converted_name;
    if (!fs::is_regular_file(converted, error) || error) {
        fail(
            LocalOfficeAdapterErrorCode::missing_output,
            "LibreOffice 没有生成 PDF 文件");
    }
    fs::copy_file(converted, destination, fs::copy_options::none, error);
    if (error) {
        fail(
            LocalOfficeAdapterErrorCode::conversion_failed,
            "无法保存 LibreOffice 转换结果：" + error.message());
    }
}

}  // namespace zisla::pdf
