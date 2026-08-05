#include "pch.h"
#include "SystemMonitorService.h"

#include <dxgi1_6.h>
#include <iphlpapi.h>
#include <pdh.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <string_view>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace winrt::Zisla {
namespace {

using SteadyClock = std::chrono::steady_clock;

constexpr auto sampling_interval = std::chrono::milliseconds{1'500};
constexpr auto disk_capacity_interval = std::chrono::minutes{3};
constexpr auto address_refresh_interval = std::chrono::seconds{30};
constexpr auto public_ip_refresh_interval = std::chrono::minutes{10};
constexpr std::size_t maximum_public_ip_bytes = 128;

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::optional<std::string> utf8(std::wstring_view value) {
    if (value.empty()) {
        return std::string{};
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }
    const auto input_size = static_cast<int>(value.size());
    const auto required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        input_size,
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) {
        return std::nullopt;
    }
    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            input_size,
            result.data(),
            required,
            nullptr,
            nullptr) != required) {
        return std::nullopt;
    }
    return result;
}

std::uint64_t file_time_value(const FILETIME& value) noexcept {
    ULARGE_INTEGER result{};
    result.LowPart = value.dwLowDateTime;
    result.HighPart = value.dwHighDateTime;
    return result.QuadPart;
}

std::optional<zisla::core::CpuTimes> cpu_times() noexcept {
    FILETIME idle{};
    FILETIME kernel{};
    FILETIME user{};
    if (!GetSystemTimes(&idle, &kernel, &user)) {
        return std::nullopt;
    }
    return zisla::core::CpuTimes{
        .idle = file_time_value(idle),
        .kernel = file_time_value(kernel),
        .user = file_time_value(user),
    };
}

zisla::core::MemoryMetrics memory_metrics() noexcept {
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) {
        return {};
    }
    return zisla::core::SystemMonitorMath::memory_metrics(
        status.ullTotalPhys,
        status.ullAvailPhys);
}

std::wstring system_volume_path() {
    std::array<wchar_t, MAX_PATH> windows_directory{};
    const auto length = GetWindowsDirectoryW(
        windows_directory.data(),
        static_cast<UINT>(windows_directory.size()));
    if (length == 0 || length >= windows_directory.size()) {
        return L"C:\\";
    }

    std::array<wchar_t, MAX_PATH> volume{};
    if (!GetVolumePathNameW(
            windows_directory.data(),
            volume.data(),
            static_cast<DWORD>(volume.size()))) {
        return L"C:\\";
    }
    return volume.data();
}

zisla::core::DiskMetrics disk_capacity(std::wstring_view volume) {
    ULARGE_INTEGER available{};
    ULARGE_INTEGER total{};
    ULARGE_INTEGER free{};
    if (!GetDiskFreeSpaceExW(
            std::wstring(volume).c_str(),
            &available,
            &total,
            &free)) {
        return {};
    }
    (void)available;

    auto result = zisla::core::SystemMonitorMath::disk_metrics(
        total.QuadPart,
        free.QuadPart);
    std::array<wchar_t, MAX_PATH + 1> name{};
    if (GetVolumeInformationW(
            std::wstring(volume).c_str(),
            name.data(),
            static_cast<DWORD>(name.size()),
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0)) {
        result.volume_name = utf8(name.data()).value_or(std::string{});
    }
    if (result.volume_name.empty()) {
        result.volume_name = utf8(volume).value_or(std::string{});
    }
    return result;
}

class MibTable {
public:
    MibTable() = default;

    ~MibTable() {
        if (value_) {
            FreeMibTable(value_);
        }
    }

    MibTable(const MibTable&) = delete;
    MibTable& operator=(const MibTable&) = delete;

    [[nodiscard]] PMIB_IF_TABLE2* put() noexcept {
        return &value_;
    }

    [[nodiscard]] PMIB_IF_TABLE2 get() const noexcept {
        return value_;
    }

private:
    PMIB_IF_TABLE2 value_{nullptr};
};

std::optional<zisla::core::NetworkCounters> network_counters() noexcept {
    MibTable table;
    if (GetIfTable2(table.put()) != NO_ERROR || !table.get()) {
        return std::nullopt;
    }

    zisla::core::NetworkCounters counters;
    for (ULONG index = 0; index < table.get()->NumEntries; ++index) {
        const auto& row = table.get()->Table[index];
        if (row.OperStatus != IfOperStatusUp
            || row.Type == IF_TYPE_SOFTWARE_LOOPBACK
            || row.Type == IF_TYPE_TUNNEL) {
            continue;
        }
        const auto next_received = counters.received_bytes + row.InOctets;
        const auto next_sent = counters.sent_bytes + row.OutOctets;
        counters.received_bytes = next_received < counters.received_bytes
            ? std::numeric_limits<std::uint64_t>::max()
            : next_received;
        counters.sent_bytes = next_sent < counters.sent_bytes
            ? std::numeric_limits<std::uint64_t>::max()
            : next_sent;
    }
    return counters;
}

class AdapterAddresses {
public:
    [[nodiscard]] bool load() {
        ULONG size = 16 * 1024;
        for (int attempt = 0; attempt < 3; ++attempt) {
            buffer_.resize(size);
            auto* addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer_.data());
            const auto result = GetAdaptersAddresses(
                AF_INET,
                GAA_FLAG_SKIP_ANYCAST
                    | GAA_FLAG_SKIP_MULTICAST
                    | GAA_FLAG_SKIP_DNS_SERVER,
                nullptr,
                addresses,
                &size);
            if (result == NO_ERROR) {
                value_ = addresses;
                return true;
            }
            if (result != ERROR_BUFFER_OVERFLOW) {
                break;
            }
        }
        value_ = nullptr;
        return false;
    }

    [[nodiscard]] PIP_ADAPTER_ADDRESSES get() const noexcept {
        return value_;
    }

private:
    std::vector<std::byte> buffer_;
    PIP_ADAPTER_ADDRESSES value_{nullptr};
};

bool usable_private_address(const IN_ADDR& address) noexcept {
    const auto host = ntohl(address.S_un.S_addr);
    const auto first = static_cast<unsigned>((host >> 24U) & 0xffU);
    const auto first_two = static_cast<unsigned>((host >> 16U) & 0xffffU);
    return host != 0 && first != 127U && first_two != 0xa9feU;
}

std::string private_ipv4_address() {
    AdapterAddresses addresses;
    if (!addresses.load()) {
        return {};
    }

    for (auto* adapter = addresses.get(); adapter; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp
            || adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK
            || adapter->IfType == IF_TYPE_TUNNEL) {
            continue;
        }
        for (auto* unicast = adapter->FirstUnicastAddress;
             unicast;
             unicast = unicast->Next) {
            if (!unicast->Address.lpSockaddr
                || unicast->Address.lpSockaddr->sa_family != AF_INET) {
                continue;
            }
            const auto* address = reinterpret_cast<const sockaddr_in*>(
                unicast->Address.lpSockaddr);
            if (!usable_private_address(address->sin_addr)) {
                continue;
            }
            std::array<char, INET_ADDRSTRLEN> text{};
            if (InetNtopA(
                    AF_INET,
                    &address->sin_addr,
                    text.data(),
                    static_cast<DWORD>(text.size()))) {
                return text.data();
            }
        }
    }
    return {};
}

std::string cpu_name() {
    HKEY raw_key = nullptr;
    if (RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
            0,
            KEY_QUERY_VALUE,
            &raw_key) != ERROR_SUCCESS) {
        return {};
    }
    struct KeyCloser {
        void operator()(HKEY key) const noexcept {
            if (key) {
                RegCloseKey(key);
            }
        }
    };
    std::unique_ptr<std::remove_pointer_t<HKEY>, KeyCloser> key(raw_key);

    std::array<wchar_t, 256> value{};
    DWORD type = 0;
    DWORD bytes = static_cast<DWORD>(value.size() * sizeof(wchar_t));
    if (RegQueryValueExW(
            key.get(),
            L"ProcessorNameString",
            nullptr,
            &type,
            reinterpret_cast<BYTE*>(value.data()),
            &bytes) != ERROR_SUCCESS
        || (type != REG_SZ && type != REG_EXPAND_SZ)) {
        return {};
    }
    value.back() = L'\0';
    std::wstring_view text{value.data()};
    while (!text.empty() && text.front() == L' ') {
        text.remove_prefix(1);
    }
    while (!text.empty() && text.back() == L' ') {
        text.remove_suffix(1);
    }
    return utf8(text).value_or(std::string{});
}

std::string gpu_name() {
    try {
        com_ptr<IDXGIFactory1> factory;
        check_hresult(CreateDXGIFactory1(
            __uuidof(IDXGIFactory1),
            factory.put_void()));
        for (UINT index = 0;; ++index) {
            com_ptr<IDXGIAdapter1> adapter;
            const auto result = factory->EnumAdapters1(index, adapter.put());
            if (result == DXGI_ERROR_NOT_FOUND) {
                break;
            }
            if (FAILED(result)) {
                return {};
            }
            DXGI_ADAPTER_DESC1 description{};
            if (SUCCEEDED(adapter->GetDesc1(&description))
                && (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) == 0) {
                return utf8(description.Description).value_or(std::string{});
            }
        }
    } catch (...) {
    }
    return {};
}

zisla::core::SystemHardwareInfo hardware_info() {
    return {
        .cpu_name = cpu_name(),
        .gpu_name = gpu_name(),
        .logical_processor_count = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS),
    };
}

std::optional<zisla::core::BatteryMetrics> battery_metrics() noexcept {
    SYSTEM_POWER_STATUS status{};
    if (!GetSystemPowerStatus(&status)) {
        return std::nullopt;
    }

    zisla::core::BatteryMetrics result;
    result.power_source = status.ACLineStatus == 1
        ? zisla::core::PowerSource::ac
        : status.ACLineStatus == 0
            ? zisla::core::PowerSource::battery
            : zisla::core::PowerSource::unknown;
    if (status.BatteryFlag == 128) {
        return result;
    }

    result.present = true;
    if (status.BatteryLifePercent <= 100) {
        result.percent = status.BatteryLifePercent;
    }
    if (status.BatteryFlag != 255) {
        result.charging = (status.BatteryFlag & 8U) != 0;
    }
    result.battery_saver = status.SystemStatusFlag != 0;
    if (status.BatteryLifeTime != std::numeric_limits<DWORD>::max()) {
        result.remaining_seconds = status.BatteryLifeTime;
    }
    return result;
}

class PdhQuery {
public:
    PdhQuery() {
        open();
    }

    ~PdhQuery() {
        close();
    }

    PdhQuery(const PdhQuery&) = delete;
    PdhQuery& operator=(const PdhQuery&) = delete;

    void reset() noexcept {
        close();
        open();
    }

    struct Sample {
        std::optional<double> gpu_usage_fraction;
        std::optional<double> disk_read_bytes_per_second;
        std::optional<double> disk_write_bytes_per_second;
    };

    [[nodiscard]] Sample sample() noexcept {
        Sample result;
        if (!query_ || PdhCollectQueryData(query_) != ERROR_SUCCESS) {
            return result;
        }
        result.gpu_usage_fraction = gpu_usage();
        result.disk_read_bytes_per_second = formatted_value(disk_read_);
        result.disk_write_bytes_per_second = formatted_value(disk_write_);
        return result;
    }

private:
    void open() noexcept {
        if (PdhOpenQueryW(nullptr, 0, &query_) != ERROR_SUCCESS) {
            query_ = nullptr;
            return;
        }
        (void)PdhAddEnglishCounterW(
            query_,
            L"\\GPU Engine(*)\\Utilization Percentage",
            0,
            &gpu_usage_);
        (void)PdhAddEnglishCounterW(
            query_,
            L"\\PhysicalDisk(_Total)\\Disk Read Bytes/sec",
            0,
            &disk_read_);
        (void)PdhAddEnglishCounterW(
            query_,
            L"\\PhysicalDisk(_Total)\\Disk Write Bytes/sec",
            0,
            &disk_write_);
        (void)PdhCollectQueryData(query_);
    }

    void close() noexcept {
        if (query_) {
            PdhCloseQuery(query_);
        }
        query_ = nullptr;
        gpu_usage_ = nullptr;
        disk_read_ = nullptr;
        disk_write_ = nullptr;
    }

    [[nodiscard]] static std::optional<double> formatted_value(
        HCOUNTER counter) noexcept {
        if (!counter) {
            return std::nullopt;
        }
        PDH_FMT_COUNTERVALUE value{};
        if (PdhGetFormattedCounterValue(
                counter,
                PDH_FMT_DOUBLE | PDH_FMT_NOCAP100,
                nullptr,
                &value) != ERROR_SUCCESS
            || (value.CStatus != ERROR_SUCCESS
                && value.CStatus != PDH_CSTATUS_NEW_DATA)
            || !std::isfinite(value.doubleValue)
            || value.doubleValue < 0) {
            return std::nullopt;
        }
        return value.doubleValue;
    }

    [[nodiscard]] std::optional<double> gpu_usage() const noexcept {
        if (!gpu_usage_) {
            return std::nullopt;
        }
        DWORD bytes = 0;
        DWORD count = 0;
        const auto sizing = PdhGetFormattedCounterArrayW(
            gpu_usage_,
            PDH_FMT_DOUBLE | PDH_FMT_NOCAP100,
            &bytes,
            &count,
            nullptr);
        if (sizing != PDH_MORE_DATA || bytes == 0 || count == 0) {
            return std::nullopt;
        }

        std::vector<std::byte> buffer(bytes);
        auto* values = reinterpret_cast<PPDH_FMT_COUNTERVALUE_ITEM_W>(
            buffer.data());
        if (PdhGetFormattedCounterArrayW(
                gpu_usage_,
                PDH_FMT_DOUBLE | PDH_FMT_NOCAP100,
                &bytes,
                &count,
                values) != ERROR_SUCCESS) {
            return std::nullopt;
        }

        std::unordered_map<std::wstring, double> engines;
        for (DWORD index = 0; index < count; ++index) {
            const auto& item = values[index];
            if (!item.szName
                || (item.FmtValue.CStatus != ERROR_SUCCESS
                    && item.FmtValue.CStatus != PDH_CSTATUS_NEW_DATA)
                || !std::isfinite(item.FmtValue.doubleValue)
                || item.FmtValue.doubleValue < 0) {
                continue;
            }
            std::wstring name{item.szName};
            const auto engine = name.find(L"_luid_");
            if (engine != std::wstring::npos) {
                name.erase(0, engine);
            }
            engines[name] += item.FmtValue.doubleValue;
        }

        double busiest = -1;
        for (const auto& [name, usage] : engines) {
            (void)name;
            busiest = std::max(busiest, usage);
        }
        if (busiest < 0) {
            return std::nullopt;
        }
        return zisla::core::SystemMonitorMath::clamp_fraction(busiest / 100.0);
    }

    HQUERY query_{nullptr};
    HCOUNTER gpu_usage_{nullptr};
    HCOUNTER disk_read_{nullptr};
    HCOUNTER disk_write_{nullptr};
};

class InternetHandle {
public:
    InternetHandle() = default;
    explicit InternetHandle(HINTERNET value) noexcept : value_(value) {}
    ~InternetHandle() {
        if (value_) {
            WinHttpCloseHandle(value_);
        }
    }

    InternetHandle(const InternetHandle&) = delete;
    InternetHandle& operator=(const InternetHandle&) = delete;

    [[nodiscard]] HINTERNET get() const noexcept {
        return value_;
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return value_ != nullptr;
    }

private:
    HINTERNET value_{nullptr};
};

std::optional<std::string> public_ip_address() noexcept {
    InternetHandle session{WinHttpOpen(
        L"Zisla/0.1.2",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0)};
    if (!session) {
        return std::nullopt;
    }
    WinHttpSetTimeouts(session.get(), 3'000, 3'000, 5'000, 5'000);

    InternetHandle connection{WinHttpConnect(
        session.get(),
        L"api64.ipify.org",
        INTERNET_DEFAULT_HTTPS_PORT,
        0)};
    if (!connection) {
        return std::nullopt;
    }
    InternetHandle request{WinHttpOpenRequest(
        connection.get(),
        L"GET",
        L"/",
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE)};
    if (!request
        || !WinHttpSendRequest(
            request.get(),
            L"Accept: text/plain\r\n",
            static_cast<DWORD>(-1L),
            WINHTTP_NO_REQUEST_DATA,
            0,
            0,
            0)
        || !WinHttpReceiveResponse(request.get(), nullptr)) {
        return std::nullopt;
    }

    DWORD status = 0;
    DWORD status_bytes = sizeof(status);
    if (!WinHttpQueryHeaders(
            request.get(),
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &status,
            &status_bytes,
            WINHTTP_NO_HEADER_INDEX)
        || status != 200) {
        return std::nullopt;
    }

    std::string body;
    while (true) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.get(), &available)) {
            return std::nullopt;
        }
        if (available == 0) {
            break;
        }
        if (body.size() > maximum_public_ip_bytes
            || available > maximum_public_ip_bytes - body.size()) {
            return std::nullopt;
        }
        const auto offset = body.size();
        body.resize(offset + available);
        DWORD read = 0;
        if (!WinHttpReadData(
                request.get(),
                body.data() + offset,
                available,
                &read)) {
            return std::nullopt;
        }
        body.resize(offset + read);
    }
    while (!body.empty()
        && (body.back() == '\r' || body.back() == '\n'
            || body.back() == ' ' || body.back() == '\t')) {
        body.pop_back();
    }
    std::size_t first = 0;
    while (first < body.size()
        && (body[first] == ' ' || body[first] == '\t')) {
        ++first;
    }
    body.erase(0, first);
    if (body.empty()) {
        return std::nullopt;
    }

    IN_ADDR ipv4{};
    IN6_ADDR ipv6{};
    if (InetPtonA(AF_INET, body.c_str(), &ipv4) != 1
        && InetPtonA(AF_INET6, body.c_str(), &ipv6) != 1) {
        return std::nullopt;
    }
    return body;
}

class WinsockSession {
public:
    WinsockSession() noexcept {
        WSADATA data{};
        active_ = WSAStartup(MAKEWORD(2, 2), &data) == 0;
    }

    ~WinsockSession() {
        if (active_) {
            WSACleanup();
        }
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return active_;
    }

private:
    bool active_{false};
};

class SystemSampler {
public:
    SystemSampler()
        : volume_path_(system_volume_path()),
          hardware_(hardware_info()) {}

    void reset_baselines() noexcept {
        previous_cpu_.reset();
        previous_network_.reset();
        previous_sample_time_.reset();
        counters_.reset();
    }

    [[nodiscard]] zisla::core::SystemMonitorSnapshot sample() {
        const auto now = SteadyClock::now();
        zisla::core::SystemMonitorSnapshot result;
        result.sampled_at_unix_ms = now_unix_milliseconds();
        result.hardware = hardware_;

        const auto current_cpu = cpu_times();
        if (previous_cpu_ && current_cpu) {
            result.cpu = zisla::core::SystemMonitorMath::cpu_metrics(
                *previous_cpu_,
                *current_cpu);
        }
        previous_cpu_ = current_cpu;
        result.memory = memory_metrics();

        if (!last_disk_capacity_sample_
            || now - *last_disk_capacity_sample_ >= disk_capacity_interval) {
            cached_disk_ = disk_capacity(volume_path_);
            last_disk_capacity_sample_ = now;
        }
        result.disk = cached_disk_;

        const auto performance = counters_.sample();
        result.disk.read_bytes_per_second = performance.disk_read_bytes_per_second;
        result.disk.write_bytes_per_second = performance.disk_write_bytes_per_second;
        if (performance.gpu_usage_fraction) {
            result.gpu = zisla::core::GpuMetrics{
                .usage_fraction = *performance.gpu_usage_fraction,
                .detail = hardware_.gpu_name,
            };
        }

        const auto current_network = network_counters();
        if (current_network && previous_network_ && previous_sample_time_) {
            const auto elapsed = std::chrono::duration<double>(
                now - *previous_sample_time_).count();
            result.network = zisla::core::SystemMonitorMath::network_metrics(
                *previous_network_,
                *current_network,
                elapsed);
        } else if (current_network) {
            result.network.received_bytes = current_network->received_bytes;
            result.network.sent_bytes = current_network->sent_bytes;
            result.network.available = true;
        }
        if (current_network) {
            previous_network_ = current_network;
            previous_sample_time_ = now;
        } else {
            previous_network_.reset();
            previous_sample_time_.reset();
        }

        if (!last_address_sample_
            || now - *last_address_sample_ >= address_refresh_interval) {
            cached_private_ip_ = private_ipv4_address();
            last_address_sample_ = now;
        }
        result.network.private_ip_address = cached_private_ip_;
        result.network.public_ip_address = cached_public_ip_;

        result.cpu_temperature.unavailable_reason =
            "Windows 未提供统一可靠的 CPU 温度接口";
        result.gpu_temperature.unavailable_reason =
            "Windows 未提供统一可靠的 GPU 温度接口";
        result.disk_temperature.unavailable_reason =
            "Windows 未提供统一可靠的磁盘温度接口";
        result.fan.unavailable_reason =
            "Windows 未提供统一可靠的风扇转速接口";
        result.battery = battery_metrics();
        result.uptime_seconds = GetTickCount64() / 1'000;
        return result;
    }

    [[nodiscard]] bool public_ip_due() const noexcept {
        return !last_public_ip_attempt_
            || SteadyClock::now() - *last_public_ip_attempt_
                >= public_ip_refresh_interval;
    }

    [[nodiscard]] std::optional<std::string> refresh_public_ip() noexcept {
        last_public_ip_attempt_ = SteadyClock::now();
        if (const auto address = public_ip_address()) {
            cached_public_ip_ = *address;
            return address;
        }
        return std::nullopt;
    }

private:
    std::wstring volume_path_;
    zisla::core::SystemHardwareInfo hardware_;
    PdhQuery counters_;
    std::optional<zisla::core::CpuTimes> previous_cpu_;
    std::optional<zisla::core::NetworkCounters> previous_network_;
    std::optional<SteadyClock::time_point> previous_sample_time_;
    std::optional<SteadyClock::time_point> last_disk_capacity_sample_;
    std::optional<SteadyClock::time_point> last_address_sample_;
    std::optional<SteadyClock::time_point> last_public_ip_attempt_;
    zisla::core::DiskMetrics cached_disk_;
    std::string cached_private_ip_;
    std::string cached_public_ip_;
};

}  // namespace

SystemMonitorService::SystemMonitorService()
    : snapshot_(std::make_shared<const SystemMonitorServiceSnapshot>()) {}

SystemMonitorService::~SystemMonitorService() {
    stop();
}

bool SystemMonitorService::start(HWND target, UINT changed_message) {
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

void SystemMonitorService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
        active_ = false;
        refresh_requested_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    target_ = nullptr;
    changed_message_ = 0;
}

void SystemMonitorService::set_active(bool active) noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ || active_ == active) {
            return;
        }
        active_ = active;
        refresh_requested_ = active;
        reset_baselines_ = true;
    }
    condition_.notify_one();
}

void SystemMonitorService::refresh() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ || !active_) {
            return;
        }
        refresh_requested_ = true;
    }
    condition_.notify_one();
}

bool SystemMonitorService::running() const noexcept {
    std::lock_guard lock(mutex_);
    return running_;
}

bool SystemMonitorService::active() const noexcept {
    std::lock_guard lock(mutex_);
    return active_;
}

std::shared_ptr<const SystemMonitorServiceSnapshot>
SystemMonitorService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void SystemMonitorService::run() noexcept {
    const WinsockSession winsock;
    (void)winsock;
    try {
        SystemSampler sampler;
        auto next_sample = SteadyClock::now();
        while (true) {
            bool reset_baselines = false;
            {
                std::unique_lock lock(mutex_);
                condition_.wait_until(lock, next_sample, [this] {
                    return !running_ || !active_ || refresh_requested_;
                });
                if (!running_) {
                    break;
                }
                if (!active_) {
                    condition_.wait(lock, [this] {
                        return !running_ || active_;
                    });
                    if (!running_) {
                        break;
                    }
                }
                reset_baselines = std::exchange(reset_baselines_, false);
                refresh_requested_ = false;
            }

            if (reset_baselines) {
                sampler.reset_baselines();
            }

            try {
                auto current = snapshot();
                SystemMonitorServiceSnapshot next = current
                    ? *current
                    : SystemMonitorServiceSnapshot{};
                next.active = true;
                next.loading = false;
                next.error.clear();
                next.metrics = sampler.sample();
                next.history.append(next.metrics);
                publish(std::move(next));

                if (sampler.public_ip_due()) {
                    if (const auto address = sampler.refresh_public_ip()) {
                        auto refreshed = snapshot();
                        if (refreshed) {
                            auto with_public_ip = *refreshed;
                            with_public_ip.metrics.network.public_ip_address = *address;
                            publish(std::move(with_public_ip));
                        }
                    }
                }
            } catch (const std::exception& error) {
                publish_error(error.what());
            } catch (...) {
                publish_error("系统监控采样发生未知错误");
            }
            next_sample = SteadyClock::now() + sampling_interval;
        }
    } catch (const std::exception& error) {
        publish_error(error.what());
    } catch (...) {
        publish_error("系统监控采样发生未知错误");
    }
    std::lock_guard lock(mutex_);
    running_ = false;
    active_ = false;
}

void SystemMonitorService::publish(
    SystemMonitorServiceSnapshot snapshot) noexcept {
    try {
        snapshot_.store(
            std::make_shared<const SystemMonitorServiceSnapshot>(
                std::move(snapshot)),
            std::memory_order_release);
        notify_changed();
    } catch (...) {
    }
}

void SystemMonitorService::publish_error(std::string error) noexcept {
    try {
        const auto current = snapshot();
        auto next = current ? *current : SystemMonitorServiceSnapshot{};
        next.loading = false;
        next.error = std::move(error);
        publish(std::move(next));
    } catch (...) {
    }
}

void SystemMonitorService::notify_changed() const noexcept {
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
