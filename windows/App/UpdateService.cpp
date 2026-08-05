#include "pch.h"
#include "UpdateService.h"
#include "WinHttpRequest.h"

#include <algorithm>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

struct SourceResult {
    std::optional<zisla::core::ReleaseInfo> release;
    std::string error;
};

SourceResult fetch_release(zisla::core::ReleaseSource source,
    zisla::core::UpdateChannel channel,
    WinHttpCancellation& cancellation) {
    const auto url = zisla::core::release_endpoint(source, channel);
    const auto headers = source == zisla::core::ReleaseSource::github
        ? std::wstring_view{
            L"Accept: application/vnd.github+json\r\n"
            L"X-GitHub-Api-Version: 2022-11-28\r\n"}
        : std::wstring_view{L"Accept: application/json\r\n"};
    try {
        const auto response = WinHttpRequest::send(
            "GET",
            url,
            headers,
            {},
            cancellation);
        if (response.status != 200) {
            return {.error = "更新服务返回 HTTP " + std::to_string(response.status)};
        }
        return {.release = zisla::core::ReleaseResponseParser::parse(response.body)};
    } catch (const std::exception& error) {
        return {.error = error.what()};
    } catch (...) {
        return {.error = "更新服务请求失败"};
    }
}

}  // namespace

UpdateService::UpdateService(std::string current_version)
    : current_version_(std::move(current_version)),
      snapshot_(std::make_shared<const UpdateServiceSnapshot>()) {}

UpdateService::~UpdateService() {
    stop();
}

bool UpdateService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    cancellation_.reset();
    running_ = true;
    commands_.push_back({.channel = zisla::core::UpdateChannel::release});
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void UpdateService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
        commands_.clear();
    }
    cancellation_.cancel();
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    target_ = nullptr;
    changed_message_ = 0;
}

void UpdateService::check(zisla::core::UpdateChannel channel) {
    enqueue({.channel = channel});
}

std::shared_ptr<const UpdateServiceSnapshot>
UpdateService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void UpdateService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.clear();
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void UpdateService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }
        try {
            execute(command);
        } catch (const std::exception& error) {
            if (!cancellation_.cancelled()) {
                publish_error(command.channel, error.what());
            }
        } catch (...) {
            if (!cancellation_.cancelled()) {
                publish_error(command.channel, "更新服务发生未知错误");
            }
        }
    }
}

void UpdateService::execute(Command command) {
    publish({
        .phase = UpdateServicePhase::checking,
        .channel = command.channel,
        .message = "正在检查更新",
    });

    const auto gitee = fetch_release(
        zisla::core::ReleaseSource::gitee,
        command.channel,
        cancellation_);
    if (cancellation_.cancelled()) {
        return;
    }

    std::optional<SourceResult> github;
    if (zisla::core::UpdateSourceQueryPolicy::should_query_github(
            current_version_,
            gitee.release,
            command.channel)) {
        github = fetch_release(
            zisla::core::ReleaseSource::github,
            command.channel,
            cancellation_);
    }
    if (cancellation_.cancelled()) {
        return;
    }

    if (!gitee.release && (!github || !github->release)) {
        const auto message = (github && !github->error.empty())
            ? github->error
            : gitee.error;
        throw std::runtime_error(message.empty() ? "无法连接更新服务" : message);
    }

    const auto selected = zisla::core::UpdateSelector::select(
        current_version_,
        gitee.release,
        github ? github->release : std::nullopt,
        command.channel);
    if (selected) {
        publish({
            .phase = UpdateServicePhase::available,
            .channel = command.channel,
            .update = selected,
            .message = "发现可用更新",
        });
    } else {
        publish({
            .phase = UpdateServicePhase::up_to_date,
            .channel = command.channel,
            .message = "当前已是最新版本",
        });
    }
}

void UpdateService::publish(UpdateServiceSnapshot snapshot) noexcept {
    try {
        snapshot_.store(
            std::make_shared<const UpdateServiceSnapshot>(std::move(snapshot)),
            std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void UpdateService::publish_error(
    zisla::core::UpdateChannel channel,
    std::string message) noexcept {
    publish({
        .phase = UpdateServicePhase::failed,
        .channel = channel,
        .message = std::move(message),
    });
}

void UpdateService::notify() noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
