#include "pch.h"
#include "WeatherService.h"

#include <winhttp.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cctype>
#include <limits>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr std::size_t maximum_response_bytes = 1U * 1024U * 1024U;
constexpr int resolve_timeout_ms = 5'000;
constexpr int connect_timeout_ms = 5'000;
constexpr int send_timeout_ms = 12'000;
constexpr int receive_timeout_ms = 20'000;

class InternetHandle {
public:
    InternetHandle() = default;
    explicit InternetHandle(HINTERNET value) noexcept : value_(value) {}

    ~InternetHandle() {
        reset();
    }

    InternetHandle(const InternetHandle&) = delete;
    InternetHandle& operator=(const InternetHandle&) = delete;

    InternetHandle(InternetHandle&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}

    InternetHandle& operator=(InternetHandle&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }

    [[nodiscard]] HINTERNET get() const noexcept {
        return value_;
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return value_ != nullptr;
    }

    void reset(HINTERNET value = nullptr) noexcept {
        if (value_) {
            WinHttpCloseHandle(value_);
        }
        value_ = value;
    }

private:
    HINTERNET value_{nullptr};
};

std::int64_t nowUnixMilliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::string trimAscii(std::string_view value) {
    std::size_t begin = 0;
    while (begin < value.size()
        && std::isspace(static_cast<unsigned char>(value[begin]))) {
        ++begin;
    }
    std::size_t end = value.size();
    while (end > begin
        && std::isspace(static_cast<unsigned char>(value[end - 1]))) {
        --end;
    }
    return std::string(value.substr(begin, end - begin));
}

std::string percentEncode(std::string_view value) {
    constexpr char hexadecimal[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(value.size() * 3);
    for (const auto byte : value) {
        const auto character = static_cast<unsigned char>(byte);
        if ((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '-' || character == '.'
            || character == '_' || character == '~') {
            result.push_back(static_cast<char>(character));
        } else {
            result.push_back('%');
            result.push_back(hexadecimal[character >> 4U]);
            result.push_back(hexadecimal[character & 0x0fU]);
        }
    }
    return result;
}

std::wstring widenAscii(std::string_view value) {
    std::wstring result;
    result.reserve(value.size());
    for (const auto character : value) {
        if (static_cast<unsigned char>(character) > 0x7fU) {
            throw std::runtime_error("天气请求路径编码无效");
        }
        result.push_back(static_cast<wchar_t>(character));
    }
    return result;
}

std::string formatNumber(double value) {
    if (!std::isfinite(value)) {
        throw std::runtime_error("天气位置坐标无效");
    }
    std::array<char, 64> buffer{};
    const auto result = std::to_chars(
        buffer.data(),
        buffer.data() + buffer.size(),
        value,
        std::chars_format::general,
        std::numeric_limits<double>::max_digits10);
    if (result.ec != std::errc{}) {
        throw std::runtime_error("无法编码天气位置坐标");
    }
    return {buffer.data(), result.ptr};
}

std::string request(
    HINTERNET session,
    const wchar_t* host,
    std::string_view path,
    const wchar_t* headers = L"Accept: application/json\r\n") {
    InternetHandle connection{WinHttpConnect(
        session,
        host,
        INTERNET_DEFAULT_HTTPS_PORT,
        0)};
    if (!connection) {
        throw std::runtime_error("无法连接天气服务");
    }

    const auto wide_path = widenAscii(path);
    InternetHandle request_handle{WinHttpOpenRequest(
        connection.get(),
        L"GET",
        wide_path.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE)};
    if (!request_handle) {
        throw std::runtime_error("无法创建天气请求");
    }
    if (!WinHttpSendRequest(
            request_handle.get(),
            headers,
            static_cast<DWORD>(-1L),
            WINHTTP_NO_REQUEST_DATA,
            0,
            0,
            0)
        || !WinHttpReceiveResponse(request_handle.get(), nullptr)) {
        throw std::runtime_error("天气服务请求失败");
    }

    DWORD status = 0;
    DWORD status_size = sizeof(status);
    if (!WinHttpQueryHeaders(
            request_handle.get(),
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &status,
            &status_size,
            WINHTTP_NO_HEADER_INDEX)
        || status != 200) {
        throw std::runtime_error(
            "天气服务返回 HTTP " + std::to_string(status));
    }

    std::string body;
    while (true) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request_handle.get(), &available)) {
            throw std::runtime_error("无法读取天气服务响应");
        }
        if (available == 0) {
            break;
        }
        if (body.size() > maximum_response_bytes
            || available > maximum_response_bytes - body.size()) {
            throw std::runtime_error("天气响应超过大小限制");
        }
        const auto offset = body.size();
        body.resize(offset + available);
        DWORD read = 0;
        if (!WinHttpReadData(
                request_handle.get(),
                body.data() + offset,
                available,
                &read)) {
            throw std::runtime_error("无法读取天气服务响应");
        }
        body.resize(offset + read);
        if (read == 0) {
            break;
        }
    }
    return body;
}

std::string normalizedPlaceName(std::string_view value) {
    auto result = trimAscii(value);
    for (const auto token : {"特别行政区", "自治区", "省", "市"}) {
        std::size_t position = 0;
        while ((position = result.find(token, position)) != std::string::npos) {
            result.erase(position, std::char_traits<char>::length(token));
        }
    }
    return result;
}

std::vector<std::string> chinaSearchQueries(std::string_view location_name) {
    std::vector<std::string> candidates{std::string(location_name)};
    for (const auto separator : {"特别行政区", "自治区", "省"}) {
        if (const auto position = location_name.find(separator);
            position != std::string_view::npos) {
            candidates.emplace_back(location_name.substr(
                position + std::char_traits<char>::length(separator)));
        }
    }
    if (const auto position = location_name.find("市");
        position != std::string_view::npos) {
        candidates.emplace_back(location_name.substr(0, position));
    }

    std::vector<std::string> result;
    for (const auto& candidate : candidates) {
        auto normalized = normalizedPlaceName(candidate);
        if (!normalized.empty()
            && std::find(result.begin(), result.end(), normalized) == result.end()) {
            result.push_back(std::move(normalized));
        }
    }
    return result;
}

bool isChina(zisla::core::GeoCoordinate coordinate) noexcept {
    return coordinate.latitude >= 18.0 && coordinate.latitude <= 54.0
        && coordinate.longitude >= 73.0 && coordinate.longitude <= 135.0;
}

bool isUnitedStates(zisla::core::GeoCoordinate coordinate) noexcept {
    const bool contiguous = coordinate.latitude >= 24.0
        && coordinate.latitude <= 50.0
        && coordinate.longitude >= -125.0
        && coordinate.longitude <= -66.0;
    const bool alaska = coordinate.latitude >= 51.0
        && coordinate.latitude <= 72.0
        && coordinate.longitude >= -180.0
        && coordinate.longitude <= -129.0;
    const bool hawaii = coordinate.latitude >= 18.0
        && coordinate.latitude <= 23.0
        && coordinate.longitude >= -161.0
        && coordinate.longitude <= -154.0;
    return contiguous || alaska || hawaii;
}

std::vector<zisla::core::WeatherAlert> fetchChinaAlerts(
    HINTERNET session,
    const zisla::core::WeatherLocation& location,
    std::int64_t now_unix_ms) {
    static constexpr wchar_t headers[] =
        L"Accept: application/json\r\n"
        L"Referer: https://www.weather.com.cn/\r\n";

    for (const auto& query : chinaSearchQueries(location.display_name)) {
        const auto search_response = request(
            session,
            L"toy1.weather.com.cn",
            "/search?cityname=" + percentEncode(query),
            headers);
        const auto station = zisla::core::WeatherParser::parse_china_station_id(
            search_response,
            query,
            location.display_name);
        if (!station) {
            continue;
        }
        const auto alert_response = request(
            session,
            L"d1.weather.com.cn",
            "/dingzhi/" + *station + ".html?_="
                + std::to_string(now_unix_ms / 1'000),
            headers);
        return zisla::core::WeatherParser::parse_china_alerts(
            alert_response,
            *station,
            location.display_name,
            now_unix_ms);
    }
    throw std::runtime_error("未找到中国天气网站点");
}

std::vector<zisla::core::WeatherAlert> fetchNwsAlerts(
    HINTERNET session,
    zisla::core::GeoCoordinate coordinate,
    std::int64_t now_unix_ms) {
    static constexpr wchar_t headers[] =
        L"Accept: application/geo+json\r\n";
    const auto point = formatNumber(coordinate.latitude) + ","
        + formatNumber(coordinate.longitude);
    const auto response = request(
        session,
        L"api.weather.gov",
        "/alerts/active?point=" + percentEncode(point),
        headers);
    return zisla::core::WeatherParser::parse_nws_alerts(response, now_unix_ms);
}

zisla::core::WeatherSnapshot fetchWeather(
    HINTERNET session,
    const zisla::core::WeatherLocation& location) {
    if (!location.coordinate || !location.coordinate->valid()) {
        throw std::runtime_error("天气地点缺少有效坐标");
    }
    const auto coordinate = *location.coordinate;
    const auto path = "/v1/forecast?latitude=" + formatNumber(coordinate.latitude)
        + "&longitude=" + formatNumber(coordinate.longitude)
        + "&current=temperature_2m%2Capparent_temperature%2Cweather_code%2Cis_day%2Cprecipitation"
        + "&daily=sunrise%2Csunset%2Cprecipitation_probability_max%2Cprecipitation_sum"
        + "&timezone=auto";
    const auto now_unix_ms = nowUnixMilliseconds();
    auto snapshot = zisla::core::WeatherParser::parse_open_meteo(
        request(session, L"api.open-meteo.com", path),
        coordinate,
        location.id,
        location.display_name,
        now_unix_ms);
    try {
        if (isChina(coordinate)) {
            snapshot.official_alerts = fetchChinaAlerts(
                session,
                location,
                now_unix_ms);
        } else if (isUnitedStates(coordinate)) {
            snapshot.official_alerts = fetchNwsAlerts(
                session,
                coordinate,
                now_unix_ms);
        } else {
            snapshot.alert_error = "当前地区暂无支持的官方预警源";
        }
    } catch (const std::exception& error) {
        snapshot.alert_error = "无法读取官方天气预警：" + std::string(error.what());
    }
    return snapshot;
}

std::shared_ptr<const WeatherServiceSnapshot> performRefresh(
    HINTERNET session,
    const std::vector<zisla::core::WeatherLocation>& locations,
    std::string initial_error,
    std::uint64_t generation) {
    auto result = std::make_shared<WeatherServiceSnapshot>();
    result->operation = WeatherServiceOperation::refresh;
    result->phase = WeatherServicePhase::ready;
    result->generation = generation;
    std::string first_error = std::move(initial_error);
    for (const auto& location : locations) {
        if (!location.coordinate) {
            if (first_error.empty()) {
                first_error = location.kind == zisla::core::WeatherLocationKind::current
                    ? "无法获取当前位置"
                    : "天气地点缺少坐标";
            }
            continue;
        }
        try {
            result->weather.push_back(fetchWeather(session, location));
        } catch (const std::exception& error) {
            if (first_error.empty()) {
                first_error = error.what();
            }
        }
    }
    if (result->weather.empty()) {
        result->phase = WeatherServicePhase::failed;
        result->message = first_error.empty()
            ? "没有可用的天气数据"
            : std::move(first_error);
    } else if (!first_error.empty()) {
        result->message = std::move(first_error);
    } else {
        result->message = std::to_string(result->weather.size()) + " 个地点";
    }
    return result;
}

std::shared_ptr<const WeatherServiceSnapshot> performSearch(
    HINTERNET session,
    std::string_view search_query,
    std::uint64_t generation,
    std::vector<zisla::core::WeatherSnapshot> weather) {
    auto result = std::make_shared<WeatherServiceSnapshot>();
    result->operation = WeatherServiceOperation::search;
    result->phase = WeatherServicePhase::ready;
    result->weather = std::move(weather);
    result->generation = generation;
    const auto query = trimAscii(search_query);
    if (query.empty()) {
        result->phase = WeatherServicePhase::failed;
        result->message = "请输入要查询的地区名称";
        return result;
    }
    const auto response = request(
        session,
        L"geocoding-api.open-meteo.com",
        "/v1/search?name=" + percentEncode(query)
            + "&count=10&language=zh&format=json");
    result->search_results = zisla::core::WeatherParser::parse_geocoding(response);
    if (result->search_results.empty()) {
        result->phase = WeatherServicePhase::failed;
        result->message = "未找到匹配的地区";
    } else {
        result->message = std::to_string(result->search_results.size()) + " 个结果";
    }
    return result;
}

}

WeatherService::WeatherService() {
    snapshot_.store(
        std::make_shared<const WeatherServiceSnapshot>(),
        std::memory_order_release);
}

WeatherService::~WeatherService() {
    stop();
}

bool WeatherService::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0) {
        return false;
    }
    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    wake_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!stop_event_ || !wake_event_) {
        if (stop_event_) {
            CloseHandle(stop_event_);
            stop_event_ = nullptr;
        }
        if (wake_event_) {
            CloseHandle(wake_event_);
            wake_event_ = nullptr;
        }
        return false;
    }

    target_ = target;
    changed_message_ = changed_message;
    running_.store(true, std::memory_order_release);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_.store(false, std::memory_order_release);
        CloseHandle(stop_event_);
        CloseHandle(wake_event_);
        stop_event_ = nullptr;
        wake_event_ = nullptr;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void WeatherService::stop() noexcept {
    if (stop_event_) {
        (void)SetEvent(stop_event_);
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    if (stop_event_) {
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
    }
    if (wake_event_) {
        CloseHandle(wake_event_);
        wake_event_ = nullptr;
    }
    {
        const std::scoped_lock lock(command_mutex_);
        commands_.clear();
    }
    running_.store(false, std::memory_order_release);
    target_ = nullptr;
    changed_message_ = 0;
}

bool WeatherService::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const WeatherServiceSnapshot>
WeatherService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

bool WeatherService::requestRefresh(
    std::vector<zisla::core::WeatherLocation> locations,
    std::string initial_error) noexcept {
    return request({
        .kind = CommandKind::refresh,
        .locations = std::move(locations),
        .initial_error = std::move(initial_error),
    });
}

bool WeatherService::requestSearch(std::string query) noexcept {
    return request({
        .kind = CommandKind::search,
        .query = std::move(query),
    });
}

bool WeatherService::request(Command command) noexcept {
    if (!running()) {
        return false;
    }
    try {
        command.generation = latest_generation_.fetch_add(
            1,
            std::memory_order_acq_rel) + 1;
        {
            const std::scoped_lock lock(command_mutex_);
            commands_.clear();
            commands_.push_back(command);
        }
        const auto current = snapshot();
        auto pending = std::make_shared<WeatherServiceSnapshot>();
        pending->operation = command.kind == CommandKind::refresh
            ? WeatherServiceOperation::refresh
            : WeatherServiceOperation::search;
        pending->phase = WeatherServicePhase::loading;
        pending->weather = current ? current->weather
            : std::vector<zisla::core::WeatherSnapshot>{};
        pending->message = command.kind == CommandKind::refresh
            ? "正在刷新天气"
            : "正在搜索地区";
        pending->generation = command.generation;
        publish(std::move(pending));
        wake();
        return true;
    } catch (...) {
        return false;
    }
}

void WeatherService::run() noexcept {
    InternetHandle session{WinHttpOpen(
        L"zisla/0.1.2 (+https://github.com/wzz6423/zisla)",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0)};
    if (session) {
        (void)WinHttpSetTimeouts(
            session.get(),
            resolve_timeout_ms,
            connect_timeout_ms,
            send_timeout_ms,
            receive_timeout_ms);
    }

    const HANDLE events[] = {stop_event_, wake_event_};
    while (session) {
        const auto wait_result = WaitForMultipleObjects(
            static_cast<DWORD>(std::size(events)),
            events,
            FALSE,
            INFINITE);
        if (wait_result == WAIT_OBJECT_0) {
            break;
        }
        if (wait_result != WAIT_OBJECT_0 + 1) {
            break;
        }
        while (const auto command = takeLatestCommand()) {
            try {
                const auto current = snapshot();
                auto result = command->kind == CommandKind::refresh
                    ? performRefresh(
                        session.get(),
                        command->locations,
                        command->initial_error,
                        command->generation)
                    : performSearch(
                        session.get(),
                        command->query,
                        command->generation,
                        current ? current->weather
                            : std::vector<zisla::core::WeatherSnapshot>{});
                publishIfCurrent(command->generation, std::move(result));
            } catch (const std::exception& error) {
                auto failure = std::make_shared<WeatherServiceSnapshot>();
                failure->operation = command->kind == CommandKind::refresh
                    ? WeatherServiceOperation::refresh
                    : WeatherServiceOperation::search;
                failure->phase = WeatherServicePhase::failed;
                failure->message = error.what();
                failure->generation = command->generation;
                if (const auto current = snapshot()) {
                    failure->weather = current->weather;
                }
                publishIfCurrent(command->generation, std::move(failure));
            }
        }
    }

    if (!session && latest_generation_.load(std::memory_order_acquire) != 0) {
        auto failure = std::make_shared<WeatherServiceSnapshot>();
        failure->phase = WeatherServicePhase::failed;
        failure->message = "无法初始化 Windows 网络服务";
        failure->generation = latest_generation_.load(std::memory_order_acquire);
        publish(std::move(failure));
    }
    running_.store(false, std::memory_order_release);
}

void WeatherService::wake() noexcept {
    if (wake_event_) {
        (void)SetEvent(wake_event_);
    }
}

void WeatherService::notifyChanged() const noexcept {
    if (target_ && changed_message_ != 0) {
        (void)PostMessageW(target_, changed_message_, 0, 0);
    }
}

std::optional<WeatherService::Command>
WeatherService::takeLatestCommand() noexcept {
    const std::scoped_lock lock(command_mutex_);
    if (commands_.empty()) {
        return std::nullopt;
    }
    auto command = std::move(commands_.back());
    commands_.clear();
    return command;
}

void WeatherService::publish(
    std::shared_ptr<const WeatherServiceSnapshot> snapshot) noexcept {
    snapshot_.store(std::move(snapshot), std::memory_order_release);
    notifyChanged();
}

void WeatherService::publishIfCurrent(
    std::uint64_t generation,
    std::shared_ptr<const WeatherServiceSnapshot> snapshot) noexcept {
    if (generation == latest_generation_.load(std::memory_order_acquire)) {
        publish(std::move(snapshot));
    }
}

}
