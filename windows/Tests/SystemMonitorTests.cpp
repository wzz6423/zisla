#include "zisla/core/SystemMonitor.hpp"

#include <cmath>
#include <exception>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void expectNear(double actual, double expected, std::string_view message) {
    if (std::abs(actual - expected) > 0.000001) {
        throw std::runtime_error(std::string(message));
    }
}

void cpuFractionsUseWindowsKernelSemantics() {
    const auto metrics = SystemMonitorMath::cpu_metrics(
        {.idle = 100, .kernel = 300, .user = 200},
        {.idle = 160, .kernel = 400, .user = 260});

    expect(metrics.has_value(), "valid CPU deltas should produce metrics");
    expectNear(metrics->idle_fraction, 0.375, "idle fraction should use total time");
    expectNear(metrics->system_fraction, 0.25, "kernel time must exclude idle time");
    expectNear(metrics->user_fraction, 0.375, "user fraction should use total time");
    expectNear(metrics->usage, 0.625, "usage should combine user and system time");
}

void cpuRejectsCounterResetAndZeroElapsedTime() {
    expect(!SystemMonitorMath::cpu_metrics(
            {.idle = 100, .kernel = 300, .user = 200},
            {.idle = 90, .kernel = 400, .user = 260}),
        "a reset counter must not create a usage spike");
    expect(!SystemMonitorMath::cpu_metrics(
            {.idle = 100, .kernel = 300, .user = 200},
            {.idle = 100, .kernel = 300, .user = 200}),
        "a zero CPU interval should remain unavailable");
}

void counterRatesRejectInvalidIntervalsAndResets() {
    expectNear(SystemMonitorMath::counter_rate(100, 400, 1.5), 200,
        "counter rate should divide the delta by elapsed time");
    expectNear(SystemMonitorMath::counter_rate(400, 100, 1.5), 0,
        "counter reset should report zero instead of underflowing");
    expectNear(SystemMonitorMath::counter_rate(100, 400, 0), 0,
        "zero elapsed time should report zero");
    expectNear(SystemMonitorMath::counter_rate(
            100,
            400,
            std::numeric_limits<double>::quiet_NaN()),
        0,
        "non-finite elapsed time should report zero");
}

void capacityMetricsClampImpossibleAvailableValues() {
    const auto memory = SystemMonitorMath::memory_metrics(1'000, 1'500);
    expect(memory.available_bytes == 1'000 && memory.used_bytes == 0,
        "memory availability should not exceed capacity");
    expect(memory.available, "non-zero memory capacity should be available");
    expectNear(memory.usage_fraction, 0, "empty memory should have zero usage");

    const auto disk = SystemMonitorMath::disk_metrics(1'000, 250);
    expect(disk.used_bytes == 750 && disk.free_bytes == 250,
        "disk used bytes should be derived safely");
    expect(disk.available, "non-zero disk capacity should be available");
    expectNear(disk.usage_fraction, 0.75, "disk usage should be normalized");
}

void clampFractionRejectsNonFiniteValues() {
    expectNear(SystemMonitorMath::clamp_fraction(-1), 0,
        "negative fractions should clamp to zero");
    expectNear(SystemMonitorMath::clamp_fraction(2), 1,
        "large fractions should clamp to one");
    expectNear(SystemMonitorMath::clamp_fraction(
            std::numeric_limits<double>::infinity()),
        0,
        "non-finite fractions should become zero");
}

void historyIsBoundedAndSkipsUnavailableGpuSamples() {
    SystemMetricHistory history{3};
    for (int index = 0; index < 5; ++index) {
        SystemMonitorSnapshot snapshot;
        snapshot.cpu = CpuMetrics{.usage = index / 10.0};
        snapshot.network.receive_bytes_per_second = index * 100.0;
        snapshot.network.send_bytes_per_second = index * 50.0;
        snapshot.network.available = true;
        if (index != 2) {
            snapshot.gpu = GpuMetrics{.usage_fraction = index / 20.0};
        }
        history.append(snapshot);
    }

    expect(history.cpu_usage().size() == 3,
        "CPU history should retain only its configured capacity");
    expectNear(history.cpu_usage().front(), 0.2,
        "history should discard the oldest CPU samples");
    expect(history.gpu_usage().size() == 3,
        "GPU history should skip unavailable samples and remain bounded");
    expectNear(history.network_download().back(), 400,
        "network history should retain the newest rate");
}

void zeroHistoryCapacityStillRetainsOneValue() {
    SystemMetricHistory history{0};
    SystemMonitorSnapshot snapshot;
    snapshot.network.available = true;
    history.append(snapshot);
    history.append(snapshot);

    expect(history.capacity() == 1 && history.network_download().size() == 1,
        "zero capacity should resolve to a one-sample history");
}

void byteAndRateFormattingUseIecUnits() {
    expect(SystemMonitorFormat::bytes(999) == "999 B",
        "small byte values should stay in bytes");
    expect(SystemMonitorFormat::bytes(1'536) == "1.5 KiB",
        "byte values should use IEC scaling");
    expect(SystemMonitorFormat::rate(1'048'576) == "1.0 MiB/s",
        "rates should include the per-second suffix");
    expect(SystemMonitorFormat::rate(-1) == "0 B/s",
        "negative rates should format as zero");
}

void uptimeFormattingMatchesTheProductClock() {
    expect(SystemMonitorFormat::uptime(2 * 86'400 + 3 * 3'600 + 4 * 60)
            == "2\xE5\xA4\xA9 3\xE5\xB0\x8F\xE6\x97\xB6 4\xE5\x88\x86\xE9\x92\x9F",
        "uptime should expose days, hours, and minutes");
}

void batteryStateKeepsUnknownValuesExplicit() {
    const BatteryMetrics desktop{
        .present = false,
        .power_source = PowerSource::ac,
    };
    expect(!desktop.percent && !desktop.remaining_seconds,
        "desktop battery values must remain unknown rather than fabricated");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"CPU fractions use Windows semantics", cpuFractionsUseWindowsKernelSemantics},
        {"CPU rejects resets and empty intervals", cpuRejectsCounterResetAndZeroElapsedTime},
        {"counter rates reject invalid samples", counterRatesRejectInvalidIntervalsAndResets},
        {"capacity metrics clamp availability", capacityMetricsClampImpossibleAvailableValues},
        {"fraction clamp rejects non-finite values", clampFractionRejectsNonFiniteValues},
        {"history remains bounded", historyIsBoundedAndSkipsUnavailableGpuSamples},
        {"zero history capacity resolves safely", zeroHistoryCapacityStillRetainsOneValue},
        {"byte and rate formatting use IEC units", byteAndRateFormattingUseIecUnits},
        {"uptime formatting matches product", uptimeFormattingMatchesTheProductClock},
        {"battery unknowns remain explicit", batteryStateKeepsUnknownValuesExplicit},
    };

    std::size_t failed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failed;
            std::cerr << "FAIL: " << name << " - " << error.what() << '\n';
        }
    }

    if (failed != 0) {
        std::cerr << failed << " test(s) failed\n";
        return 1;
    }
    return 0;
}
