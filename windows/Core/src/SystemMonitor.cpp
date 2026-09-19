#include "zisla/core/SystemMonitor.hpp"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>

namespace zisla::core {
namespace {

std::optional<std::uint64_t> counter_delta(
    std::uint64_t previous,
    std::uint64_t current) noexcept {
    if (current < previous) {
        return std::nullopt;
    }
    return current - previous;
}

std::string scaled_bytes(long double value, std::string_view suffix) {
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << std::fixed << std::setprecision(1)
           << static_cast<double>(value) << ' ' << suffix;
    return stream.str();
}

}  // namespace

double SystemMonitorMath::clamp_fraction(double value) noexcept {
    if (!std::isfinite(value)) {
        return 0;
    }
    return std::clamp(value, 0.0, 1.0);
}

std::optional<CpuMetrics> SystemMonitorMath::cpu_metrics(
    CpuTimes previous,
    CpuTimes current) noexcept {
    const auto idle = counter_delta(previous.idle, current.idle);
    const auto kernel = counter_delta(previous.kernel, current.kernel);
    const auto user = counter_delta(previous.user, current.user);
    if (!idle || !kernel || !user || *kernel < *idle) {
        return std::nullopt;
    }

    const auto system = *kernel - *idle;
    const long double total = static_cast<long double>(*kernel)
        + static_cast<long double>(*user);
    if (total <= 0) {
        return std::nullopt;
    }

    CpuMetrics result;
    result.user_fraction = clamp_fraction(static_cast<double>(
        static_cast<long double>(*user) / total));
    result.system_fraction = clamp_fraction(static_cast<double>(
        static_cast<long double>(system) / total));
    result.idle_fraction = clamp_fraction(static_cast<double>(
        static_cast<long double>(*idle) / total));
    result.usage = clamp_fraction(result.user_fraction + result.system_fraction);
    return result;
}

double SystemMonitorMath::counter_rate(
    std::uint64_t previous,
    std::uint64_t current,
    double elapsed_seconds) noexcept {
    if (!std::isfinite(elapsed_seconds) || elapsed_seconds <= 0) {
        return 0;
    }
    const auto delta = counter_delta(previous, current);
    if (!delta) {
        return 0;
    }
    const long double rate = static_cast<long double>(*delta)
        / static_cast<long double>(elapsed_seconds);
    if (!std::isfinite(rate)
        || rate > static_cast<long double>(std::numeric_limits<double>::max())) {
        return 0;
    }
    return std::max(0.0, static_cast<double>(rate));
}

NetworkMetrics SystemMonitorMath::network_metrics(
    NetworkCounters previous,
    NetworkCounters current,
    double elapsed_seconds) noexcept {
    return {
        .received_bytes = current.received_bytes,
        .sent_bytes = current.sent_bytes,
        .available = true,
        .receive_bytes_per_second = counter_rate(
            previous.received_bytes,
            current.received_bytes,
            elapsed_seconds),
        .send_bytes_per_second = counter_rate(
            previous.sent_bytes,
            current.sent_bytes,
            elapsed_seconds),
    };
}

MemoryMetrics SystemMonitorMath::memory_metrics(
    std::uint64_t total_bytes,
    std::uint64_t available_bytes) noexcept {
    const auto available = std::min(total_bytes, available_bytes);
    const auto used = total_bytes - available;
    const auto fraction = total_bytes == 0
        ? 0.0
        : static_cast<double>(static_cast<long double>(used)
            / static_cast<long double>(total_bytes));
    return {
        .total_bytes = total_bytes,
        .used_bytes = used,
        .available_bytes = available,
        .available = total_bytes > 0,
        .usage_fraction = clamp_fraction(fraction),
    };
}

DiskMetrics SystemMonitorMath::disk_metrics(
    std::uint64_t total_bytes,
    std::uint64_t free_bytes) noexcept {
    const auto free = std::min(total_bytes, free_bytes);
    const auto used = total_bytes - free;
    const auto fraction = total_bytes == 0
        ? 0.0
        : static_cast<double>(static_cast<long double>(used)
            / static_cast<long double>(total_bytes));
    return {
        .total_bytes = total_bytes,
        .used_bytes = used,
        .free_bytes = free,
        .available = total_bytes > 0,
        .usage_fraction = clamp_fraction(fraction),
    };
}

SystemMetricHistory::SystemMetricHistory(std::size_t capacity)
    : capacity_(std::max<std::size_t>(1, capacity)) {}

void SystemMetricHistory::append(const SystemMonitorSnapshot& snapshot) {
    if (snapshot.cpu) {
        append_value(cpu_usage_, snapshot.cpu->usage);
        append_value(cpu_user_, snapshot.cpu->user_fraction);
        append_value(cpu_system_, snapshot.cpu->system_fraction);
        append_value(cpu_idle_, snapshot.cpu->idle_fraction);
    }
    if (snapshot.gpu) {
        append_value(gpu_usage_, snapshot.gpu->usage_fraction);
    }
    if (snapshot.network.available) {
        append_value(
            network_download_,
            std::max(0.0, snapshot.network.receive_bytes_per_second));
        append_value(
            network_upload_,
            std::max(0.0, snapshot.network.send_bytes_per_second));
    }
}

void SystemMetricHistory::clear() noexcept {
    cpu_usage_.clear();
    cpu_user_.clear();
    cpu_system_.clear();
    cpu_idle_.clear();
    gpu_usage_.clear();
    network_download_.clear();
    network_upload_.clear();
}

std::size_t SystemMetricHistory::capacity() const noexcept {
    return capacity_;
}

const std::vector<double>& SystemMetricHistory::cpu_usage() const noexcept {
    return cpu_usage_;
}

const std::vector<double>& SystemMetricHistory::cpu_user() const noexcept {
    return cpu_user_;
}

const std::vector<double>& SystemMetricHistory::cpu_system() const noexcept {
    return cpu_system_;
}

const std::vector<double>& SystemMetricHistory::cpu_idle() const noexcept {
    return cpu_idle_;
}

const std::vector<double>& SystemMetricHistory::gpu_usage() const noexcept {
    return gpu_usage_;
}

const std::vector<double>& SystemMetricHistory::network_download() const noexcept {
    return network_download_;
}

const std::vector<double>& SystemMetricHistory::network_upload() const noexcept {
    return network_upload_;
}

void SystemMetricHistory::append_value(
    std::vector<double>& values,
    double value) {
    values.push_back(std::isfinite(value) ? std::max(0.0, value) : 0.0);
    if (values.size() > capacity_) {
        values.erase(values.begin(), values.begin()
            + static_cast<std::ptrdiff_t>(values.size() - capacity_));
    }
}

std::string SystemMonitorFormat::bytes(std::uint64_t value) {
    static constexpr std::string_view suffixes[]{
        "B", "KiB", "MiB", "GiB", "TiB", "PiB",
    };
    long double scaled = static_cast<long double>(value);
    std::size_t suffix = 0;
    while (scaled >= 1024.0L && suffix + 1 < std::size(suffixes)) {
        scaled /= 1024.0L;
        ++suffix;
    }
    if (suffix == 0) {
        return std::to_string(value) + " B";
    }
    return scaled_bytes(scaled, suffixes[suffix]);
}

std::string SystemMonitorFormat::rate(double bytes_per_second) {
    if (!std::isfinite(bytes_per_second) || bytes_per_second < 0) {
        bytes_per_second = 0;
    }
    const auto bounded = std::min<long double>(
        bytes_per_second,
        static_cast<long double>(std::numeric_limits<std::uint64_t>::max()));
    return bytes(static_cast<std::uint64_t>(std::llround(bounded))) + "/s";
}

std::string SystemMonitorFormat::uptime(std::uint64_t seconds) {
    const auto total_minutes = seconds / 60;
    const auto days = total_minutes / (24 * 60);
    const auto hours = (total_minutes % (24 * 60)) / 60;
    const auto minutes = total_minutes % 60;
    return std::to_string(days) + "\xE5\xA4\xA9 "
        + std::to_string(hours) + "\xE5\xB0\x8F\xE6\x97\xB6 "
        + std::to_string(minutes) + "\xE5\x88\x86\xE9\x92\x9F";
}

}  // namespace zisla::core
