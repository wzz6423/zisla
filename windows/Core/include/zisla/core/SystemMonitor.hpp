#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace zisla::core {

struct CpuTimes {
    std::uint64_t idle{0};
    std::uint64_t kernel{0};
    std::uint64_t user{0};

    friend bool operator==(const CpuTimes&, const CpuTimes&) = default;
};

struct CpuMetrics {
    double usage{0};
    double user_fraction{0};
    double system_fraction{0};
    double idle_fraction{1};

    friend bool operator==(const CpuMetrics&, const CpuMetrics&) = default;
};

struct MemoryMetrics {
    std::uint64_t total_bytes{0};
    std::uint64_t used_bytes{0};
    std::uint64_t available_bytes{0};
    bool available{false};
    double usage_fraction{0};

    friend bool operator==(const MemoryMetrics&, const MemoryMetrics&) = default;
};

struct DiskMetrics {
    std::uint64_t total_bytes{0};
    std::uint64_t used_bytes{0};
    std::uint64_t free_bytes{0};
    bool available{false};
    double usage_fraction{0};
    std::optional<double> read_bytes_per_second;
    std::optional<double> write_bytes_per_second;
    std::string volume_name;
    std::string volume_path;

    friend bool operator==(const DiskMetrics&, const DiskMetrics&) = default;
};

struct NetworkCounters {
    std::uint64_t received_bytes{0};
    std::uint64_t sent_bytes{0};

    friend bool operator==(const NetworkCounters&, const NetworkCounters&) = default;
};

struct NetworkMetrics {
    std::uint64_t received_bytes{0};
    std::uint64_t sent_bytes{0};
    bool available{false};
    double receive_bytes_per_second{0};
    double send_bytes_per_second{0};
    std::string private_ip_address;
    std::string public_ip_address;

    friend bool operator==(const NetworkMetrics&, const NetworkMetrics&) = default;
};

struct GpuMetrics {
    double usage_fraction{0};
    std::string detail;

    friend bool operator==(const GpuMetrics&, const GpuMetrics&) = default;
};

struct TemperatureMetric {
    std::optional<double> celsius;
    std::string unavailable_reason;

    friend bool operator==(const TemperatureMetric&, const TemperatureMetric&) = default;
};

struct FanMetrics {
    std::vector<double> rpm;
    std::string unavailable_reason;

    friend bool operator==(const FanMetrics&, const FanMetrics&) = default;
};

enum class PowerSource {
    unknown,
    ac,
    battery,
};

struct BatteryMetrics {
    bool present{false};
    std::optional<std::uint8_t> percent;
    PowerSource power_source{PowerSource::unknown};
    bool charging{false};
    bool battery_saver{false};
    std::optional<std::uint64_t> remaining_seconds;

    friend bool operator==(const BatteryMetrics&, const BatteryMetrics&) = default;
};

struct SystemHardwareInfo {
    std::string cpu_name;
    std::string gpu_name;
    std::uint32_t logical_processor_count{0};

    friend bool operator==(const SystemHardwareInfo&, const SystemHardwareInfo&) = default;
};

struct SystemMonitorSnapshot {
    std::int64_t sampled_at_unix_ms{0};
    SystemHardwareInfo hardware;
    std::optional<CpuMetrics> cpu;
    MemoryMetrics memory;
    // `disk` is an aggregate maintained for compact status consumers.
    DiskMetrics disk;
    std::vector<DiskMetrics> disks;
    NetworkMetrics network;
    std::optional<GpuMetrics> gpu;
    TemperatureMetric cpu_temperature;
    TemperatureMetric gpu_temperature;
    TemperatureMetric disk_temperature;
    FanMetrics fan;
    std::optional<BatteryMetrics> battery;
    std::uint64_t uptime_seconds{0};

    friend bool operator==(const SystemMonitorSnapshot&, const SystemMonitorSnapshot&) = default;
};

class SystemMonitorMath {
public:
    [[nodiscard]] static double clamp_fraction(double value) noexcept;
    [[nodiscard]] static std::optional<CpuMetrics> cpu_metrics(
        CpuTimes previous,
        CpuTimes current) noexcept;
    [[nodiscard]] static double counter_rate(
        std::uint64_t previous,
        std::uint64_t current,
        double elapsed_seconds) noexcept;
    [[nodiscard]] static NetworkMetrics network_metrics(
        NetworkCounters previous,
        NetworkCounters current,
        double elapsed_seconds) noexcept;
    [[nodiscard]] static MemoryMetrics memory_metrics(
        std::uint64_t total_bytes,
        std::uint64_t available_bytes) noexcept;
    [[nodiscard]] static DiskMetrics disk_metrics(
        std::uint64_t total_bytes,
        std::uint64_t free_bytes) noexcept;
};

class SystemMetricHistory {
public:
    explicit SystemMetricHistory(std::size_t capacity = 60);

    void append(const SystemMonitorSnapshot& snapshot);
    void clear() noexcept;

    [[nodiscard]] std::size_t capacity() const noexcept;
    [[nodiscard]] const std::vector<double>& cpu_usage() const noexcept;
    [[nodiscard]] const std::vector<double>& cpu_user() const noexcept;
    [[nodiscard]] const std::vector<double>& cpu_system() const noexcept;
    [[nodiscard]] const std::vector<double>& cpu_idle() const noexcept;
    [[nodiscard]] const std::vector<double>& gpu_usage() const noexcept;
    [[nodiscard]] const std::vector<double>& network_download() const noexcept;
    [[nodiscard]] const std::vector<double>& network_upload() const noexcept;

private:
    void append_value(std::vector<double>& values, double value);

    std::size_t capacity_{60};
    std::vector<double> cpu_usage_;
    std::vector<double> cpu_user_;
    std::vector<double> cpu_system_;
    std::vector<double> cpu_idle_;
    std::vector<double> gpu_usage_;
    std::vector<double> network_download_;
    std::vector<double> network_upload_;
};

class SystemMonitorFormat {
public:
    [[nodiscard]] static std::string bytes(std::uint64_t value);
    [[nodiscard]] static std::string rate(double bytes_per_second);
    [[nodiscard]] static std::string uptime(std::uint64_t seconds);
};

}  // namespace zisla::core
