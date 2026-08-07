#include "pch.h"
#include "DownloadService.h"
#include "BilibiliDownloadClient.h"
#include "MediaFoundationMuxer.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <climits>
#include <cwctype>
#include <exception>
#include <span>
#include <stdexcept>
#include <string_view>
#include <utility>

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
            throw std::runtime_error("无法准备下载进程句柄列表");
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
                "无法限制下载进程继承句柄（Windows 错误 "
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

class TaskDirectory {
public:
    explicit TaskDirectory(std::filesystem::path path)
        : path_(std::move(path)) {}

    ~TaskDirectory() {
        std::error_code ignored;
        std::filesystem::remove_all(path_, ignored);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

std::runtime_error windows_error(std::string_view operation, DWORD code) {
    return std::runtime_error(
        std::string(operation) + "（Windows 错误 " + std::to_string(code) + "）");
}

std::optional<std::wstring> wide_from_utf8(std::string_view value) noexcept {
    if (value.empty()) {
        return std::wstring{};
    }
    if (value.size() > static_cast<std::size_t>(INT_MAX)) {
        return std::nullopt;
    }
    const auto length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) {
        return std::nullopt;
    }
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length) != length) {
        return std::nullopt;
    }
    return result;
}

bool starts_with_case_insensitive(
    std::wstring_view value,
    std::wstring_view prefix) noexcept {
    return value.size() >= prefix.size()
        && std::equal(
            prefix.begin(),
            prefix.end(),
            value.begin(),
            [](wchar_t left, wchar_t right) {
                return std::towupper(left) == std::towupper(right);
            });
}

std::vector<wchar_t> sanitized_environment() {
    const auto raw = GetEnvironmentStringsW();
    if (!raw) {
        throw windows_error("无法读取下载进程环境", GetLastError());
    }

    std::vector<wchar_t> result;
    for (const wchar_t* entry = raw; *entry != L'\0';) {
        const std::wstring_view value{entry};
        entry += value.size() + 1;
        const auto separator = value.find(L'=', value.starts_with(L'=') ? 1 : 0);
        const auto key = value.substr(0, separator);
        if (starts_with_case_insensitive(key, L"PYTHON")
            || starts_with_case_insensitive(key, L"PYINSTALLER")) {
            continue;
        }
        result.insert(result.end(), value.begin(), value.end());
        result.push_back(L'\0');
    }
    FreeEnvironmentStringsW(raw);
    result.push_back(L'\0');
    return result;
}

bool trusted_executable(const std::filesystem::path& path) noexcept {
    if (path.empty() || !path.is_absolute()) {
        return false;
    }
    const auto attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0
        && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

std::filesystem::path make_task_directory(
    const std::filesystem::path& root) {
    std::error_code error;
    std::filesystem::create_directories(root, error);
    if (error || !std::filesystem::is_directory(root, error) || error) {
        throw std::runtime_error("无法创建下载临时目录");
    }

    for (int attempt = 0; attempt < 8; ++attempt) {
        GUID identifier{};
        if (FAILED(CoCreateGuid(&identifier))) {
            break;
        }
        std::array<wchar_t, 40> text{};
        const auto length = StringFromGUID2(
                identifier,
                text.data(),
                static_cast<int>(text.size()));
        if (length <= 3) {
            continue;
        }
        std::wstring name{text.data() + 1, static_cast<std::size_t>(length - 3)};
        auto candidate = root / name;
        if (std::filesystem::create_directory(candidate, error)) {
            return candidate;
        }
        if (error) {
            error.clear();
        }
    }
    throw std::runtime_error("无法分配独立下载临时目录");
}

std::string combined_diagnostic(
    std::string_view standard_output,
    std::string_view standard_error) {
    zisla::core::DownloadProcessOutputBuffer buffer;
    if (!standard_error.empty()) {
        (void)buffer.append(standard_error);
    }
    if (!standard_error.empty() && !standard_output.empty()) {
        (void)buffer.append("\n");
    }
    if (!standard_output.empty()) {
        (void)buffer.append(standard_output);
    }
    return buffer.diagnostic();
}

std::string move_file_without_overwrite(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) {
    if (MoveFileExW(
            source.c_str(),
            destination.c_str(),
            MOVEFILE_COPY_ALLOWED | MOVEFILE_WRITE_THROUGH)) {
        return {};
    }
    return "无法保存下载文件（Windows 错误 "
        + std::to_string(GetLastError()) + "）";
}

}  // namespace

DownloadService::DownloadService(
    std::filesystem::path yt_dlp_executable,
    std::optional<std::filesystem::path> ffmpeg_executable,
    std::filesystem::path temporary_root)
    : yt_dlp_executable_(std::move(yt_dlp_executable)),
      ffmpeg_executable_(std::move(ffmpeg_executable)),
      temporary_root_(std::move(temporary_root)),
      bilibili_client_(std::make_unique<BilibiliDownloadClient>(
          [this] { return cancellation_requested(); },
          [this](double fraction, std::string speed) {
              update_bilibili_progress(fraction, std::move(speed));
          })),
      media_muxer_(std::make_unique<MediaFoundationMuxer>(
          [this] { return cancellation_requested(); })),
      snapshot_(std::make_shared<const zisla::core::DownloadSnapshot>()) {}

DownloadService::~DownloadService() {
    stop();
}

bool DownloadService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || thread_.joinable() || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void DownloadService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
        pending_request_.reset();
        if (state_.snapshot().active()) {
            (void)state_.request_cancel();
            cancel_requested_ = true;
            publish_locked();
        }
        if (active_job_) {
            (void)TerminateJobObject(active_job_, ERROR_CANCELLED);
        }
        if (bilibili_client_) {
            bilibili_client_->cancel();
        }
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    if (state_.snapshot().active()) {
        state_.cancel();
        publish_locked();
    }
    active_job_ = nullptr;
    completed_file_.reset();
    components_.clear();
    target_ = nullptr;
    changed_message_ = 0;
    cancel_requested_ = false;
}

bool DownloadService::start_download(zisla::core::DownloadRequest request) {
    const auto normalized =
        zisla::core::DownloadRequestValidator::normalized_url(request.url);
    if (normalized) {
        request.url = *normalized;
    }
    const auto validation = zisla::core::DownloadRequestValidator::validate(request);

    {
        std::lock_guard lock(mutex_);
        if (!running_ || task_in_progress_ || pending_request_
            || !state_.begin(request)) {
            return false;
        }
        cancel_requested_ = false;
        completed_file_.reset();
        components_.clear();
        if (validation != zisla::core::DownloadRequestValidation::valid) {
            state_.fail(validation
                    == zisla::core::DownloadRequestValidation::unsupported_url
                ? "仅支持包含有效主机名的 HTTP 或 HTTPS 链接"
                : "请选择一个存在的下载目录");
            publish_locked();
            return false;
        }
        pending_request_ = std::move(request);
        publish_locked();
    }
    condition_.notify_one();
    return true;
}

void DownloadService::cancel() {
    std::lock_guard lock(mutex_);
    if (!state_.request_cancel()) {
        return;
    }
    cancel_requested_ = true;
    const bool pending_only = pending_request_.has_value() && !task_in_progress_;
    pending_request_.reset();
    publish_locked();
    if (active_job_) {
        (void)TerminateJobObject(active_job_, ERROR_CANCELLED);
    }
    if (bilibili_client_) {
        bilibili_client_->cancel();
    }
    if (pending_only) {
        state_.cancel();
        publish_locked();
    }
    condition_.notify_one();
}

std::shared_ptr<const zisla::core::DownloadSnapshot>
DownloadService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void DownloadService::run() noexcept {
    while (true) {
        std::optional<zisla::core::DownloadRequest> request;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !running_ || pending_request_.has_value();
            });
            if (!running_ && !pending_request_) {
                break;
            }
            request = std::move(pending_request_);
            pending_request_.reset();
            task_in_progress_ = request.has_value();
        }

        if (!request) {
            continue;
        }
        try {
            execute(std::move(*request));
        } catch (const std::exception& error) {
            fail(error.what());
        } catch (...) {
            fail("下载发生未知错误");
        }
        {
            std::lock_guard lock(mutex_);
            task_in_progress_ = false;
        }
    }
}

void DownloadService::execute(zisla::core::DownloadRequest request) {
    if (cancellation_requested()) {
        std::lock_guard lock(mutex_);
        state_.cancel();
        publish_locked();
        return;
    }
    TaskDirectory task_directory{make_task_directory(temporary_root_)};
    if (!trusted_executable(yt_dlp_executable_)) {
        if (request.mode == zisla::core::DownloadMode::video
            && zisla::core::DownloadFailureDiagnostics::is_bilibili_url(
                request.url)) {
            try {
                execute_bilibili(request, task_directory.path());
                return;
            } catch (const std::exception& error) {
                if (cancellation_requested()) {
                    throw;
                }
                throw std::runtime_error(
                    "下载组件 yt-dlp 不可用；B站备用下载也失败："
                    + std::string(error.what()));
            }
        }
        throw std::runtime_error("下载组件 yt-dlp 不可用，请重新安装 Zisla");
    }

    std::optional<std::filesystem::path> ffmpeg;
    if (ffmpeg_executable_ && trusted_executable(*ffmpeg_executable_)) {
        ffmpeg = *ffmpeg_executable_;
    }
    const zisla::core::DownloadCapabilities capabilities{
        .has_ffmpeg = ffmpeg.has_value(),
    };
    const auto strategy = zisla::core::YTDLPArgumentBuilder::strategy(
        request,
        capabilities);
    std::vector<std::wstring> arguments;
    arguments.push_back(yt_dlp_executable_.wstring());
    for (const auto& argument : zisla::core::YTDLPArgumentBuilder::arguments(
             request,
             capabilities,
             task_directory.path(),
             ffmpeg)) {
        const auto wide = wide_from_utf8(argument);
        if (!wide) {
            throw std::runtime_error("下载参数包含无效 UTF-8 文本");
        }
        arguments.push_back(*wide);
    }
    auto command_line = zisla::core::WindowsCommandLine::build(arguments);
    auto environment = sanitized_environment();

    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;

    UniqueHandle stdin_read{CreateFileW(
        L"NUL",
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        &security,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr)};
    if (!stdin_read) {
        throw windows_error("无法打开下载进程标准输入", GetLastError());
    }

    HANDLE stdout_read_raw = nullptr;
    HANDLE stdout_write_raw = nullptr;
    if (!CreatePipe(&stdout_read_raw, &stdout_write_raw, &security, 0)) {
        throw windows_error("无法创建下载输出管道", GetLastError());
    }
    UniqueHandle stdout_read{stdout_read_raw};
    UniqueHandle stdout_write{stdout_write_raw};

    HANDLE stderr_read_raw = nullptr;
    HANDLE stderr_write_raw = nullptr;
    if (!CreatePipe(&stderr_read_raw, &stderr_write_raw, &security, 0)) {
        throw windows_error("无法创建下载错误管道", GetLastError());
    }
    UniqueHandle stderr_read{stderr_read_raw};
    UniqueHandle stderr_write{stderr_write_raw};
    if (!SetHandleInformation(stdout_read.get(), HANDLE_FLAG_INHERIT, 0)
        || !SetHandleInformation(stderr_read.get(), HANDLE_FLAG_INHERIT, 0)) {
        throw windows_error("无法限制下载管道继承", GetLastError());
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
        throw windows_error("无法创建下载进程组", GetLastError());
    }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(
            job.get(),
            JobObjectExtendedLimitInformation,
            &limits,
            sizeof(limits))) {
        throw windows_error("无法配置下载进程组", GetLastError());
    }

    PROCESS_INFORMATION process_info{};
    if (!CreateProcessW(
            yt_dlp_executable_.c_str(),
            command_line.data(),
            nullptr,
            nullptr,
            TRUE,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW
                | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT,
            environment.data(),
            task_directory.path().c_str(),
            &startup.StartupInfo,
            &process_info)) {
        throw windows_error("无法启动下载组件", GetLastError());
    }
    UniqueHandle process{process_info.hProcess};
    UniqueHandle process_thread{process_info.hThread};
    stdout_write.reset();
    stderr_write.reset();

    if (!AssignProcessToJobObject(job.get(), process.get())) {
        const auto error = GetLastError();
        (void)TerminateProcess(process.get(), error);
        throw windows_error("无法约束下载进程树", error);
    }

    bool cancelled_before_resume = false;
    {
        std::lock_guard lock(mutex_);
        active_job_ = job.get();
        cancelled_before_resume = cancel_requested_ || !running_;
        if (cancelled_before_resume) {
            (void)TerminateJobObject(job.get(), ERROR_CANCELLED);
        }
    }
    if (!cancelled_before_resume
        && ResumeThread(process_thread.get()) == static_cast<DWORD>(-1)) {
        const auto error = GetLastError();
        (void)TerminateJobObject(job.get(), error);
        {
            std::lock_guard lock(mutex_);
            active_job_ = nullptr;
        }
        throw windows_error("无法恢复下载进程", error);
    }

    PipeResult stdout_result;
    PipeResult stderr_result;
    std::exception_ptr stdout_failure;
    std::exception_ptr stderr_failure;
    std::thread stdout_thread;
    std::thread stderr_thread;
    const auto drain = [this, job_handle = job.get()](
                           HANDLE pipe,
                           PipeResult* result,
                           std::exception_ptr* failure) noexcept {
        try {
            *result = drain_pipe(pipe);
        } catch (...) {
            *failure = std::current_exception();
            (void)TerminateJobObject(job_handle, ERROR_READ_FAULT);
        }
    };
    try {
        stdout_thread = std::thread(
            drain,
            stdout_read.get(),
            &stdout_result,
            &stdout_failure);
        stderr_thread = std::thread(
            drain,
            stderr_read.get(),
            &stderr_result,
            &stderr_failure);
    } catch (...) {
        (void)TerminateJobObject(job.get(), ERROR_CANCELLED);
        if (stdout_thread.joinable()) {
            stdout_thread.join();
        }
        if (stderr_thread.joinable()) {
            stderr_thread.join();
        }
        {
            std::lock_guard lock(mutex_);
            active_job_ = nullptr;
        }
        throw;
    }

    const auto wait_result = WaitForSingleObject(process.get(), INFINITE);
    const auto wait_error = wait_result == WAIT_FAILED ? GetLastError() : ERROR_SUCCESS;
    DWORD exit_code = 0;
    const bool exit_available = wait_result == WAIT_OBJECT_0
        && GetExitCodeProcess(process.get(), &exit_code);
    if (!exit_available) {
        (void)TerminateJobObject(job.get(), ERROR_CANCELLED);
    }
    stdout_thread.join();
    stderr_thread.join();

    bool cancelled = false;
    {
        std::lock_guard lock(mutex_);
        active_job_ = nullptr;
        cancelled = cancel_requested_ || !running_;
    }
    if (cancelled) {
        std::lock_guard lock(mutex_);
        state_.cancel();
        publish_locked();
        return;
    }
    if (stdout_failure || stderr_failure) {
        try {
            std::rethrow_exception(stdout_failure ? stdout_failure : stderr_failure);
        } catch (const std::exception& error) {
            throw std::runtime_error(
                std::string{"读取下载输出失败："} + error.what());
        } catch (...) {
            throw std::runtime_error("读取下载输出失败");
        }
    }
    if (!exit_available) {
        throw windows_error("无法等待下载进程结束", wait_error);
    }
    if (exit_code != 0) {
        const auto diagnostic = combined_diagnostic(
            stdout_result.diagnostic,
            stderr_result.diagnostic);
        if (request.mode == zisla::core::DownloadMode::video
            && zisla::core::DownloadFailureDiagnostics::should_use_bilibili_fallback(
                diagnostic,
                request.url)) {
            try {
                execute_bilibili(request, task_directory.path());
                return;
            } catch (const std::exception& error) {
                if (cancellation_requested()) {
                    throw;
                }
                throw std::runtime_error(
                    zisla::core::DownloadFailureDiagnostics::actionable_message(
                        diagnostic,
                        request.url)
                    + "\nB站原生备用下载失败：" + error.what());
            }
        }
        throw std::runtime_error(
            zisla::core::DownloadFailureDiagnostics::actionable_message(
                diagnostic,
                request.url));
    }

    if (strategy == zisla::core::DownloadExecutionStrategy::direct) {
        finish_direct(request);
    } else {
        finish_native_packaging(request, task_directory.path());
    }
}

void DownloadService::execute_bilibili(
    const zisla::core::DownloadRequest& request,
    const std::filesystem::path& task_directory) {
    if (!bilibili_client_) {
        throw std::runtime_error("B站备用下载组件不可用");
    }
    auto components = bilibili_client_->download(request.url, task_directory);
    {
        std::lock_guard lock(mutex_);
        components_ = std::move(components);
    }
    finish_native_packaging(request, task_directory);
}

DownloadService::PipeResult DownloadService::drain_pipe(HANDLE pipe) {
    zisla::core::DownloadProcessOutputBuffer output;
    std::array<char, 32U * 1024U> buffer{};
    for (;;) {
        DWORD read = 0;
        if (!ReadFile(
                pipe,
                buffer.data(),
                static_cast<DWORD>(buffer.size()),
                &read,
                nullptr)) {
            const auto error = GetLastError();
            if (error != ERROR_BROKEN_PIPE) {
                const auto message = "\n读取下载输出失败（Windows 错误 "
                    + std::to_string(error) + "）";
                (void)output.append(message);
            }
            break;
        }
        if (read == 0) {
            break;
        }
        for (auto& line : output.append(
                 std::string_view{buffer.data(), read})) {
            if (auto event = zisla::core::YTDLPOutputParser::parse(line)) {
                accept_event(std::move(*event));
            }
        }
    }
    if (auto line = output.finish()) {
        if (auto event = zisla::core::YTDLPOutputParser::parse(*line)) {
            accept_event(std::move(*event));
        }
    }
    return {.diagnostic = output.diagnostic()};
}

void DownloadService::accept_event(zisla::core::YTDLPEvent event) {
    std::lock_guard lock(mutex_);
    if (cancel_requested_) {
        return;
    }
    switch (event.kind) {
    case zisla::core::YTDLPEventKind::progress:
        state_.update_progress(
            event.fraction,
            std::move(event.speed),
            std::move(event.eta));
        publish_locked();
        break;
    case zisla::core::YTDLPEventKind::completed_file:
        completed_file_ = std::move(event.path);
        break;
    case zisla::core::YTDLPEventKind::completed_component:
        if (event.component) {
            components_.push_back(std::move(*event.component));
        }
        break;
    }
}

void DownloadService::update_bilibili_progress(
    double fraction,
    std::string speed) noexcept {
    try {
        std::lock_guard lock(mutex_);
        if (cancel_requested_ || !running_) {
            return;
        }
        state_.update_progress(fraction, std::move(speed), {});
        publish_locked();
    } catch (...) {
    }
}

void DownloadService::finish_direct(
    const zisla::core::DownloadRequest& request) {
    std::optional<std::filesystem::path> reported;
    {
        std::lock_guard lock(mutex_);
        reported = completed_file_;
    }
    if (!reported) {
        throw std::runtime_error("下载进程没有报告完成文件");
    }
    const auto completed = zisla::core::DownloadOutputPathValidator::normalized_file(
        *reported,
        request.output_directory);
    if (!completed) {
        throw std::runtime_error("下载组件报告了不安全或不存在的完成文件");
    }

    std::lock_guard lock(mutex_);
    if (cancel_requested_) {
        state_.cancel();
    } else {
        state_.complete(*completed);
    }
    publish_locked();
}

void DownloadService::finish_native_packaging(
    const zisla::core::DownloadRequest& request,
    const std::filesystem::path& task_directory) {
    std::vector<zisla::core::DownloadedMediaComponent> components;
    {
        std::lock_guard lock(mutex_);
        components = components_;
    }
    for (auto& component : components) {
        const auto normalized =
            zisla::core::DownloadOutputPathValidator::normalized_file(
                component.path,
                task_directory);
        if (!normalized) {
            throw std::runtime_error("下载组件报告了不安全或不存在的媒体轨道");
        }
        component.path = *normalized;
    }

    const auto combined = std::find_if(
        components.rbegin(),
        components.rend(),
        [](const auto& component) {
            return component.kind == zisla::core::DownloadedMediaKind::combined;
        });
    std::filesystem::path packaged_file;
    const zisla::core::DownloadedMediaComponent* output_component = nullptr;
    if (combined != components.rend()) {
        packaged_file = combined->path;
        output_component = &*combined;
    } else {
        const auto video = std::find_if(
            components.rbegin(),
            components.rend(),
            [](const auto& component) {
                return component.kind == zisla::core::DownloadedMediaKind::video;
            });
        const auto audio = std::find_if(
            components.rbegin(),
            components.rend(),
            [](const auto& component) {
                return component.kind == zisla::core::DownloadedMediaKind::audio;
            });
        if (video == components.rend() || audio == components.rend()) {
            throw std::runtime_error("下载组件中缺少可封装的视频轨或音频轨");
        }
        if (!media_muxer_) {
            throw std::runtime_error("Windows 原生媒体封装组件不可用");
        }
        packaged_file = task_directory / L"zisla-native-packaged.mp4";
        {
            std::lock_guard lock(mutex_);
            if (!cancel_requested_) {
                state_.update_progress(0.96, {}, {});
                publish_locked();
            }
        }
        media_muxer_->mux(video->path, audio->path, packaged_file);
        const auto normalized =
            zisla::core::DownloadOutputPathValidator::normalized_file(
                packaged_file,
                task_directory);
        if (!normalized) {
            throw std::runtime_error("无法验证 Windows 原生封装结果");
        }
        packaged_file = *normalized;
        output_component = &*video;
    }
    const auto desired = zisla::core::DownloadOutputPathBuilder::destination(
        *output_component,
        request.output_directory,
        combined == components.rend()
            ? std::optional<std::string_view>{"mp4"}
            : std::nullopt);
    const auto destination =
        zisla::core::DownloadOutputPathBuilder::available_destination(desired);
    if (!destination) {
        throw std::runtime_error("无法为下载文件分配安全的输出名称");
    }
    if (const auto error = move_file_without_overwrite(
            packaged_file,
            *destination);
        !error.empty()) {
        throw std::runtime_error(error);
    }
    const auto completed = zisla::core::DownloadOutputPathValidator::normalized_file(
        *destination,
        request.output_directory);
    if (!completed) {
        throw std::runtime_error("无法验证已保存的下载文件");
    }

    std::lock_guard lock(mutex_);
    if (cancel_requested_) {
        std::error_code ignored;
        std::filesystem::remove(*completed, ignored);
        state_.cancel();
    } else {
        state_.complete(*completed);
    }
    publish_locked();
}

void DownloadService::fail(std::string message) noexcept {
    try {
        std::lock_guard lock(mutex_);
        if (cancel_requested_ || !running_) {
            state_.cancel();
        } else {
            state_.fail(std::move(message));
        }
        publish_locked();
    } catch (...) {
    }
}

void DownloadService::publish_locked() noexcept {
    try {
        snapshot_.store(
            std::make_shared<const zisla::core::DownloadSnapshot>(state_.snapshot()),
            std::memory_order_release);
        notify_changed();
    } catch (...) {
    }
}

void DownloadService::notify_changed() const noexcept {
    if (target_ && changed_message_ != 0) {
        (void)PostMessageW(target_, changed_message_, 0, 0);
    }
}

bool DownloadService::cancellation_requested() const noexcept {
    std::lock_guard lock(mutex_);
    return cancel_requested_ || !running_;
}

}
