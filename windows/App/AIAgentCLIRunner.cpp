#include "pch.h"
#include "AIAgentCLIRunner.h"

#include <zisla/core/Download.hpp>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cwctype>
#include <exception>
#include <functional>
#include <limits>
#include <optional>
#include <span>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace winrt::Zisla {
namespace {

class UniqueHandle {
public:
    UniqueHandle() = default;
    explicit UniqueHandle(HANDLE value) noexcept : value_(value) {}
    ~UniqueHandle() {
        reset();
    }

    UniqueHandle(const UniqueHandle&) = delete;
    UniqueHandle& operator=(const UniqueHandle&) = delete;

    UniqueHandle(UniqueHandle&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}

    UniqueHandle& operator=(UniqueHandle&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }

    void reset(HANDLE value = nullptr) noexcept {
        if (value_ && value_ != INVALID_HANDLE_VALUE) {
            CloseHandle(value_);
        }
        value_ = value;
    }

    [[nodiscard]] HANDLE get() const noexcept {
        return value_;
    }

    [[nodiscard]] HANDLE release() noexcept {
        return std::exchange(value_, nullptr);
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return value_ && value_ != INVALID_HANDLE_VALUE;
    }

private:
    HANDLE value_{nullptr};
};

class AttributeList {
public:
    explicit AttributeList(std::span<const HANDLE> inherited_handles) {
        SIZE_T bytes = 0;
        (void)InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
        if (bytes == 0) {
            throw std::runtime_error("无法准备 AI Agent CLI 进程句柄列表");
        }
        storage_.resize(bytes);
        value_ = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage_.data());
        if (!InitializeProcThreadAttributeList(value_, 1, 0, &bytes)
            || !UpdateProcThreadAttribute(
                value_,
                0,
                PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                const_cast<HANDLE*>(inherited_handles.data()),
                inherited_handles.size_bytes(),
                nullptr,
                nullptr)) {
            const auto error = GetLastError();
            if (value_) {
                DeleteProcThreadAttributeList(value_);
                value_ = nullptr;
            }
            throw std::runtime_error(
                "无法限制 AI Agent CLI 进程继承句柄（Windows 错误 "
                + std::to_string(error) + "）");
        }
    }

    ~AttributeList() {
        if (value_) {
            DeleteProcThreadAttributeList(value_);
        }
    }

    AttributeList(const AttributeList&) = delete;
    AttributeList& operator=(const AttributeList&) = delete;

    [[nodiscard]] LPPROC_THREAD_ATTRIBUTE_LIST get() const noexcept {
        return value_;
    }

private:
    std::vector<std::byte> storage_;
    LPPROC_THREAD_ATTRIBUTE_LIST value_{nullptr};
};

std::runtime_error windows_error(std::string_view operation, DWORD code) {
    return std::runtime_error(
        std::string(operation) + "（Windows 错误 " + std::to_string(code) + "）");
}

std::wstring wide_from_utf8(std::string_view value) {
    if (value.empty()) {
        return {};
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        throw std::runtime_error("AI Agent CLI 参数过长");
    }
    const auto length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) {
        throw windows_error("AI Agent CLI 参数包含无效 UTF-8", GetLastError());
    }
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length) != length) {
        throw windows_error("无法转换 AI Agent CLI 参数", GetLastError());
    }
    return result;
}

bool is_valid_utf8(std::string_view value) noexcept {
    if (value.empty()) {
        return true;
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return false;
    }
    return MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0) > 0;
}

std::wstring environment_value(const wchar_t* name) {
    const auto required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required == 0) {
        return {};
    }
    std::wstring result(required, L'\0');
    const auto written = GetEnvironmentVariableW(name, result.data(), required);
    if (written == 0 || written >= required) {
        return {};
    }
    result.resize(written);
    return result;
}

void append_search_directory(
    std::vector<std::filesystem::path>& directories,
    std::filesystem::path directory) {
    if (!directory.empty()
        && std::find(directories.begin(), directories.end(), directory) == directories.end()) {
        directories.push_back(std::move(directory));
    }
}

std::vector<std::filesystem::path> executable_search_directories() {
    std::vector<std::filesystem::path> directories;
    const auto path = environment_value(L"PATH");
    std::size_t begin = 0;
    while (begin <= path.size()) {
        const auto end = path.find(L';', begin);
        auto value = path.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin);
        if (value.size() >= 2 && value.front() == L'"' && value.back() == L'"') {
            value = value.substr(1, value.size() - 2);
        }
        append_search_directory(directories, std::filesystem::path{std::move(value)});
        if (end == std::wstring::npos) {
            break;
        }
        begin = end + 1;
    }

    const auto app_data = environment_value(L"APPDATA");
    const auto local_app_data = environment_value(L"LOCALAPPDATA");
    const auto user_profile = environment_value(L"USERPROFILE");
    if (!app_data.empty()) {
        append_search_directory(directories, std::filesystem::path{app_data} / L"npm");
    }
    if (!local_app_data.empty()) {
        append_search_directory(directories, std::filesystem::path{local_app_data} / L"pnpm");
    }
    if (!user_profile.empty()) {
        const std::filesystem::path profile{user_profile};
        append_search_directory(directories, profile / L".volta" / L"bin");
        append_search_directory(directories, profile / L".bun" / L"bin");
    }
    return directories;
}

bool is_absolute_regular_file(const std::filesystem::path& path) noexcept {
    if (path.empty() || !path.is_absolute()) {
        return false;
    }
    const auto attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::optional<std::filesystem::path> find_executable(zisla::core::AgentCLIKind cli_kind) {
    const auto name = wide_from_utf8(zisla::core::agent_cli_kind_token(cli_kind));
    const std::array<std::wstring_view, 3> suffixes{L".exe", L".cmd", L".bat"};
    for (const auto& directory : executable_search_directories()) {
        for (const auto suffix : suffixes) {
            const auto candidate = directory / (name + std::wstring(suffix));
            if (is_absolute_regular_file(candidate)) {
                return candidate;
            }
        }
    }
    return std::nullopt;
}

bool is_command_script(const std::filesystem::path& path) noexcept {
    const auto extension = path.extension().wstring();
    if (extension.size() != 4 || extension.front() != L'.') {
        return false;
    }
    const auto first = static_cast<wchar_t>(std::towlower(extension[1]));
    const auto second = static_cast<wchar_t>(std::towlower(extension[2]));
    const auto third = static_cast<wchar_t>(std::towlower(extension[3]));
    return (first == L'c' && second == L'm' && third == L'd')
        || (first == L'b' && second == L'a' && third == L't');
}

std::filesystem::path command_interpreter() {
    std::array<wchar_t, MAX_PATH> buffer{};
    auto length = GetSystemDirectoryW(buffer.data(), static_cast<UINT>(buffer.size()));
    if (length == 0) {
        throw windows_error("无法定位 Windows 命令解释器", GetLastError());
    }
    std::wstring directory;
    if (length < buffer.size()) {
        directory.assign(buffer.data(), length);
    } else {
        std::wstring expanded(static_cast<std::size_t>(length) + 1U, L'\0');
        length = GetSystemDirectoryW(
            expanded.data(),
            static_cast<UINT>(expanded.size()));
        if (length == 0 || length >= expanded.size()) {
            throw windows_error("无法读取 Windows 命令解释器目录", GetLastError());
        }
        directory.assign(expanded.data(), length);
    }
    const auto result = std::filesystem::path{directory} / L"cmd.exe";
    if (!is_absolute_regular_file(result)) {
        throw std::runtime_error("Windows 命令解释器不可用");
    }
    return result;
}

std::filesystem::path working_directory(const std::filesystem::path& requested) {
    std::error_code error;
    if (!requested.empty()
        && requested.is_absolute()
        && std::filesystem::is_directory(requested, error)
        && !error) {
        return requested;
    }
    const auto profile = environment_value(L"USERPROFILE");
    if (!profile.empty()) {
        const std::filesystem::path result{profile};
        if (std::filesystem::is_directory(result, error) && !error) {
            return result;
        }
    }
    throw std::runtime_error("无法确定 AI Agent CLI 的工作目录");
}

void write_standard_input(HANDLE pipe, std::string_view input) noexcept {
    std::size_t offset = 0;
    while (offset < input.size()) {
        const auto remaining = input.size() - offset;
        const auto count = static_cast<DWORD>(std::min<std::size_t>(
            remaining,
            std::numeric_limits<DWORD>::max()));
        DWORD written = 0;
        if (!WriteFile(pipe, input.data() + offset, count, &written, nullptr) || written == 0) {
            break;
        }
        offset += written;
    }
    CloseHandle(pipe);
}

void drain_pipe(
    HANDLE pipe,
    std::string* retained_output,
    HANDLE job,
    std::atomic_bool& output_limit_exceeded,
    std::atomic_bool& read_failed) noexcept {
    std::array<char, 32U * 1024U> buffer{};
    std::size_t total = 0;
    for (;;) {
        DWORD read = 0;
        if (!ReadFile(
                pipe,
                buffer.data(),
                static_cast<DWORD>(buffer.size()),
                &read,
                nullptr)) {
            if (GetLastError() != ERROR_BROKEN_PIPE) {
                read_failed.store(true, std::memory_order_release);
                (void)TerminateJobObject(job, ERROR_READ_FAULT);
            }
            return;
        }
        if (read == 0) {
            return;
        }
        if (static_cast<std::size_t>(read)
            > zisla::core::AIAgentCLIRelay::maximum_response_bytes - total) {
            output_limit_exceeded.store(true, std::memory_order_release);
            (void)TerminateJobObject(job, ERROR_BUFFER_OVERFLOW);
            return;
        }
        total += read;
        if (retained_output) {
            retained_output->append(buffer.data(), read);
        }
    }
}

DWORD wait_timeout_milliseconds(std::chrono::seconds timeout) noexcept {
    if (timeout <= std::chrono::seconds::zero()) {
        return 0;
    }
    constexpr auto maximum = static_cast<long long>(std::numeric_limits<DWORD>::max());
    const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(timeout);
    return milliseconds.count() >= maximum
        ? std::numeric_limits<DWORD>::max()
        : static_cast<DWORD>(milliseconds.count());
}

}  // namespace

AIAgentCLIRunner::~AIAgentCLIRunner() {
    cancel();
}

AIAgentCLIProcessResult AIAgentCLIRunner::run(
    const zisla::core::AgentCLIRelayCommand& command,
    const std::filesystem::path& requested_working_directory,
    std::atomic_bool& cancellation_requested,
    std::chrono::seconds timeout) {
    const auto executable = find_executable(command.cli_kind);
    if (!executable) {
        throw std::runtime_error(
            "未找到 " + std::string(zisla::core::agent_cli_kind_token(command.cli_kind))
            + " 官方 CLI。请先在用户 PATH 中安装并完成登录。");
    }
    if (command.standard_input.size() > zisla::core::AIAgentCLIRelay::maximum_prompt_bytes) {
        throw std::length_error("AI Agent CLI 输入超过安全上限");
    }

    std::vector<std::wstring> executable_arguments;
    executable_arguments.reserve(command.arguments.size() + 1U);
    executable_arguments.push_back(executable->wstring());
    for (const auto& argument : command.arguments) {
        executable_arguments.push_back(wide_from_utf8(argument));
    }

    std::filesystem::path application_name = *executable;
    std::vector<std::wstring> launch_arguments = executable_arguments;
    if (is_command_script(*executable)) {
        application_name = command_interpreter();
        std::wstring script_command{L"call "};
        script_command.append(zisla::core::WindowsCommandLine::build(executable_arguments));
        launch_arguments = {
            application_name.wstring(),
            L"/d",
            L"/s",
            L"/c",
            std::move(script_command),
        };
    }
    auto command_line = zisla::core::WindowsCommandLine::build(launch_arguments);

    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;

    HANDLE stdin_read_raw = nullptr;
    HANDLE stdin_write_raw = nullptr;
    if (!CreatePipe(&stdin_read_raw, &stdin_write_raw, &security, 0)) {
        throw windows_error("无法创建 AI Agent CLI 输入管道", GetLastError());
    }
    UniqueHandle stdin_read{stdin_read_raw};
    UniqueHandle stdin_write{stdin_write_raw};

    HANDLE stdout_read_raw = nullptr;
    HANDLE stdout_write_raw = nullptr;
    if (!CreatePipe(&stdout_read_raw, &stdout_write_raw, &security, 0)) {
        throw windows_error("无法创建 AI Agent CLI 输出管道", GetLastError());
    }
    UniqueHandle stdout_read{stdout_read_raw};
    UniqueHandle stdout_write{stdout_write_raw};

    HANDLE stderr_read_raw = nullptr;
    HANDLE stderr_write_raw = nullptr;
    if (!CreatePipe(&stderr_read_raw, &stderr_write_raw, &security, 0)) {
        throw windows_error("无法创建 AI Agent CLI 错误管道", GetLastError());
    }
    UniqueHandle stderr_read{stderr_read_raw};
    UniqueHandle stderr_write{stderr_write_raw};

    if (!SetHandleInformation(stdin_write.get(), HANDLE_FLAG_INHERIT, 0)
        || !SetHandleInformation(stdout_read.get(), HANDLE_FLAG_INHERIT, 0)
        || !SetHandleInformation(stderr_read.get(), HANDLE_FLAG_INHERIT, 0)) {
        throw windows_error("无法限制 AI Agent CLI 管道继承", GetLastError());
    }

    const std::array<HANDLE, 3> inherited{
        stdin_read.get(),
        stdout_write.get(),
        stderr_write.get(),
    };
    AttributeList attributes{inherited};
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = stdin_read.get();
    startup.StartupInfo.hStdOutput = stdout_write.get();
    startup.StartupInfo.hStdError = stderr_write.get();
    startup.lpAttributeList = attributes.get();

    UniqueHandle job{CreateJobObjectW(nullptr, nullptr)};
    if (!job) {
        throw windows_error("无法创建 AI Agent CLI 进程组", GetLastError());
    }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(
            job.get(),
            JobObjectExtendedLimitInformation,
            &limits,
            sizeof(limits))) {
        throw windows_error("无法配置 AI Agent CLI 进程组", GetLastError());
    }

    PROCESS_INFORMATION process_info{};
    const auto directory = working_directory(requested_working_directory);
    if (!CreateProcessW(
            application_name.c_str(),
            command_line.data(),
            nullptr,
            nullptr,
            TRUE,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW | CREATE_SUSPENDED,
            nullptr,
            directory.c_str(),
            &startup.StartupInfo,
            &process_info)) {
        throw windows_error("无法启动 AI Agent CLI", GetLastError());
    }
    UniqueHandle process{process_info.hProcess};
    UniqueHandle process_thread{process_info.hThread};
    stdin_read.reset();
    stdout_write.reset();
    stderr_write.reset();

    if (!AssignProcessToJobObject(job.get(), process.get())) {
        const auto error = GetLastError();
        (void)TerminateProcess(process.get(), error);
        throw windows_error("无法约束 AI Agent CLI 进程树", error);
    }

    {
        std::lock_guard lock(mutex_);
        if (active_job_) {
            (void)TerminateProcess(process.get(), ERROR_BUSY);
            throw std::logic_error("AI Agent CLI 请求已在执行");
        }
        active_job_ = job.get();
        if (cancellation_requested.load(std::memory_order_acquire)) {
            (void)TerminateJobObject(job.get(), ERROR_CANCELLED);
        }
    }

    std::string standard_output;
    std::atomic_bool output_limit_exceeded{false};
    std::atomic_bool read_failed{false};
    std::thread stdout_thread;
    std::thread stderr_thread;
    std::thread stdin_thread;
    try {
        stdout_thread = std::thread(
            drain_pipe,
            stdout_read.get(),
            &standard_output,
            job.get(),
            std::ref(output_limit_exceeded),
            std::ref(read_failed));
        stderr_thread = std::thread(
            drain_pipe,
            stderr_read.get(),
            nullptr,
            job.get(),
            std::ref(output_limit_exceeded),
            std::ref(read_failed));
        stdin_thread = std::thread(
            [pipe = std::move(stdin_write), input = std::string_view{command.standard_input}]() mutable {
                write_standard_input(pipe.release(), input);
            });
    } catch (...) {
        (void)TerminateJobObject(job.get(), ERROR_CANCELLED);
        if (stdout_thread.joinable()) {
            stdout_thread.join();
        }
        if (stderr_thread.joinable()) {
            stderr_thread.join();
        }
        if (stdin_thread.joinable()) {
            stdin_thread.join();
        }
        {
            std::lock_guard lock(mutex_);
            active_job_ = nullptr;
        }
        throw;
    }

    const auto resume_result = cancellation_requested.load(std::memory_order_acquire)
        ? 0
        : ResumeThread(process_thread.get());
    if (resume_result == static_cast<DWORD>(-1)
        && !cancellation_requested.load(std::memory_order_acquire)) {
        const auto error = GetLastError();
        (void)TerminateJobObject(job.get(), error);
        (void)WaitForSingleObject(process.get(), INFINITE);
        stdout_thread.join();
        stderr_thread.join();
        stdin_thread.join();
        {
            std::lock_guard lock(mutex_);
            active_job_ = nullptr;
        }
        throw windows_error("无法恢复 AI Agent CLI 进程", error);
    }

    const auto wait_result = WaitForSingleObject(process.get(), wait_timeout_milliseconds(timeout));
    const auto wait_error = wait_result == WAIT_FAILED ? GetLastError() : ERROR_SUCCESS;
    const bool timed_out = wait_result == WAIT_TIMEOUT;
    if (timed_out || wait_result == WAIT_FAILED) {
        (void)TerminateJobObject(job.get(), timed_out ? ERROR_TIMEOUT : ERROR_CANCELLED);
        (void)WaitForSingleObject(process.get(), INFINITE);
    }

    DWORD exit_code = 0;
    const bool exit_available = GetExitCodeProcess(process.get(), &exit_code) != FALSE;
    stdout_thread.join();
    stderr_thread.join();
    stdin_thread.join();
    {
        std::lock_guard lock(mutex_);
        active_job_ = nullptr;
    }

    const bool cancelled = cancellation_requested.load(std::memory_order_acquire);
    if (read_failed.load(std::memory_order_acquire) && !cancelled) {
        throw std::runtime_error("读取 AI Agent CLI 输出失败");
    }
    if (wait_result == WAIT_FAILED && !cancelled) {
        throw windows_error("无法等待 AI Agent CLI 结束", wait_error);
    }
    if (!exit_available && !cancelled) {
        throw windows_error("无法读取 AI Agent CLI 退出状态", GetLastError());
    }
    if (!cancelled && !output_limit_exceeded.load(std::memory_order_acquire)
        && !is_valid_utf8(standard_output)) {
        throw std::runtime_error("AI Agent CLI 返回了无效 UTF-8 文本");
    }
    return {
        .standard_output = std::move(standard_output),
        .exit_code = exit_code,
        .cancelled = cancelled,
        .timed_out = timed_out,
        .output_limit_exceeded = output_limit_exceeded.load(std::memory_order_acquire),
    };
}

void AIAgentCLIRunner::cancel() noexcept {
    std::lock_guard lock(mutex_);
    if (active_job_) {
        (void)TerminateJobObject(active_job_, ERROR_CANCELLED);
    }
}

}
