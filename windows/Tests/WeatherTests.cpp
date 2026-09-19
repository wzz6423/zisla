#include "zisla/core/Weather.hpp"

#include <chrono>
#include <cmath>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

template <typename Function>
void expectParseError(
    Function&& function,
    WeatherParseErrorCode code,
    std::string_view message) {
    try {
        function();
    } catch (const WeatherParseError& error) {
        expect(error.code() == code, message);
        return;
    }
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-weather-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

void openMeteoParsesFloatingDailySummary() {
    constexpr std::string_view response = R"json({
        "current": {
            "temperature_2m": 23.4,
            "apparent_temperature": 24.1,
            "weather_code": 999,
            "is_day": 1,
            "precipitation": 0.2
        },
        "daily": {
            "precipitation_probability_max": [70],
            "sunrise": ["2026-07-31T05:00"],
            "sunset": ["2026-07-31T19:00"],
            "precipitation_sum": [18.5]
        },
        "timezone": "Asia/Shanghai"
    })json";

    const auto snapshot = WeatherParser::parse_open_meteo(
        response,
        {31.2304, 121.4737},
        "saved-shanghai",
        "上海",
        1'234);

    expect(snapshot.location_id == "saved-shanghai"
            && snapshot.location_name == "上海"
            && snapshot.coordinate == GeoCoordinate{31.2304, 121.4737},
        "天气快照应保留地点标识和坐标");
    expect(std::abs(snapshot.temperature - 23.4) < 0.000'001
            && std::abs(snapshot.apparent_temperature - 24.1) < 0.000'001
            && std::abs(snapshot.current_precipitation - 0.2) < 0.000'001
            && std::abs(snapshot.precipitation_sum - 18.5) < 0.000'001,
        "天气快照应正确解析浮点温度和降水量");
    expect(snapshot.precipitation_probability == 70
            && snapshot.weather_code == 999
            && snapshot.is_day
            && snapshot.timezone == "Asia/Shanghai"
            && snapshot.fetched_at_unix_ms == 1'234,
        "天气快照应正确解析当前状态");
    expect(WeatherParser::condition_summary(999) == "天气未知",
        "未知天气编码应有稳定的降级文案");
}

void openMeteoRejectsInvalidResponses() {
    expectParseError(
        [] {
            (void)WeatherParser::parse_open_meteo(
                "not-json", {31, 121}, "id", "地点", 0);
        },
        WeatherParseErrorCode::invalid_json,
        "无效 JSON 应被拒绝");
    expectParseError(
        [] {
            (void)WeatherParser::parse_open_meteo(
                "{}", {31, 121}, "id", "地点", 0);
        },
        WeatherParseErrorCode::invalid_shape,
        "缺少天气字段的 JSON 应被拒绝");
    expectParseError(
        [] {
            (void)WeatherParser::parse_open_meteo(
                "{}", {91, 121}, "id", "地点", 0);
        },
        WeatherParseErrorCode::invalid_value,
        "越界坐标应被拒绝");

    const std::string oversized(1U * 1024U * 1024U + 1U, 'x');
    expectParseError(
        [&oversized] {
            (void)WeatherParser::parse_geocoding(oversized);
        },
        WeatherParseErrorCode::response_too_large,
        "超大天气响应应被拒绝");
}

void geocodingKeepsValidResultsAndAddsAdministrativeNames() {
    constexpr std::string_view response = R"json({
        "results": [
            {"name":"上海","latitude":31.2304,"longitude":121.4737,"admin1":"上海市","country":"中国"},
            {"name":"坏地点","latitude":100,"longitude":181},
            {"name":"缺坐标","latitude":30}
        ]
    })json";

    const auto results = WeatherParser::parse_geocoding(response);
    expect(results.size() == 1, "地区搜索应过滤无效结果");
    expect(results.front().display_name == "上海市上海"
            && results.front().country == "中国"
            && results.front().administrative_area == "上海市"
            && results.front().coordinate == GeoCoordinate{31.2304, 121.4737},
        "地区搜索结果应包含行政区和坐标");
    expect(WeatherParser::parse_geocoding("{}").empty(),
        "无搜索结果的响应应返回空列表");
}

void chinaStationSearchDisambiguatesSameNamedCities() {
    constexpr std::string_view response = R"json(([
        {"ref":"101010100~x~朝阳~x~x~x~x~x~北京市"},
        {"ref":"101020100~x~朝阳~x~x~x~x~x~上海市"}
    ]))json";

    const auto station = WeatherParser::parse_china_station_id(
        response,
        "朝阳市",
        "北京市朝阳区");
    expect(station && *station == "101010100",
        "中国天气网地点搜索应优先匹配省级行政区");
    expect(!WeatherParser::parse_china_station_id(
        response,
        "不存在",
        "北京市"),
        "不存在的地点应返回空站点");
}

void chinaAlertsParseOfficialRedAlertWithoutExpiry() {
    constexpr std::string_view response = R"json(
        var alarmDZ={"w":[{
            "w5":"暴雨",
            "w7":"红色",
            "w8":"20260731120000",
            "w11":"20260731120000.html",
            "w13":"北京市暴雨红色预警"
        }]};
    )json";

    const auto alerts = WeatherParser::parse_china_alerts(
        response,
        "101010100",
        "北京市",
        5'000);
    expect(alerts.size() == 1, "中国天气网预警应解析一条有效记录");
    expect(alerts.front().severity == WeatherAlertSeverity::extreme
            && alerts.front().source == "中国天气网（中国气象局）"
            && alerts.front().summary == "北京市暴雨红色预警"
            && alerts.front().region == "北京市"
            && !alerts.front().expires_at_unix_ms
            && alerts.front().details_url.find("newalarmcontent")
                != std::string::npos,
        "中国天气网红色预警应保留官方来源和详情链接");
    expect(alerts.front().updated_at_unix_ms > 0,
        "中国天气网紧凑时间应转换为 Unix 毫秒");
}

void nwsAlertsParseSeverityAndExpiry() {
    constexpr std::string_view response = R"json({
        "features": [{
            "id":"https://api.weather.gov/alerts/1",
            "properties": {
                "headline":"Severe storm warning",
                "event":"Storm",
                "senderName":"National Weather Service",
                "areaDesc":"Austin",
                "severity":"Severe",
                "effective":"2026-07-31T12:00:00-05:00",
                "expires":"2026-07-31T18:00:00-05:00"
            }
        }]
    })json";

    const auto alerts = WeatherParser::parse_nws_alerts(response, 7'000);
    expect(alerts.size() == 1, "NWS 预警应解析一条有效记录");
    expect(alerts.front().severity == WeatherAlertSeverity::severe
            && alerts.front().source == "National Weather Service"
            && alerts.front().region == "Austin"
            && alerts.front().summary == "Severe storm warning"
            && alerts.front().expires_at_unix_ms.has_value()
            && alerts.front().updated_at_unix_ms != 7'000,
        "NWS 预警应解析等级、区域和有效期");
}

void locationRepositoryPersistsCurrentSavedLocationsAndCapacity() {
    TemporaryDirectory temporary;
    WeatherLocationRepository repository(temporary.path() / "weather.json", 6);

    const auto initial = repository.load();
    expect(initial.size() == 1
            && initial.front().kind == WeatherLocationKind::current
            && initial.front().id == weather_current_location_id,
        "首次读取应提供默认当前位置");

    repository.update_current("上海", GeoCoordinate{31.2304, 121.4737});
    for (int index = 0; index < 8; ++index) {
        repository.add_saved(
            "地点" + std::to_string(index),
            GeoCoordinate{20.0 + index, 100.0 + index});
    }
    const auto locations = repository.load();
    expect(locations.size() == 7
            && locations.front().display_name == "上海",
        "地点仓库应保留当前位置和最多六个保存地点");
    expect(locations[1].display_name == "地点2"
            && locations.back().display_name == "地点7",
        "超过容量时应保留最近加入的六个地点");

    repository.add_saved("更新后的地点", {22.0005, 102.0005});
    const auto deduplicated = repository.load();
    expect(deduplicated.size() == 7
            && deduplicated[1].display_name == "更新后的地点",
        "近似相同坐标应更新而不是重复保存");

    const auto saved_id = deduplicated[1].id;
    expect(repository.remove(saved_id), "保存地点应可删除");
    expect(!repository.remove(weather_current_location_id),
        "当前位置不可删除");
}

void locationRepositoryMovesSavedLocationsAndProtectsCorruptFiles() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "weather.json";
    WeatherLocationRepository repository(state);
    repository.add_saved("甲", {10, 10});
    repository.add_saved("乙", {20, 20});
    repository.add_saved("丙", {30, 30});
    auto locations = repository.load();
    const auto first = locations[1].id;
    const auto second = locations[2].id;
    const auto third = locations[3].id;

    expect(repository.move_saved(third, first), "保存地点应支持向前重排");
    locations = repository.load();
    expect(locations[1].id == third && locations[2].id == first
            && locations[3].id == second,
        "向前重排应将源地点放到目标地点位置");
    expect(repository.move_saved(third, second), "保存地点应支持向后重排");
    locations = repository.load();
    expect(locations[1].id == first && locations[2].id == third
            && locations[3].id == second,
        "向后重排应将源地点放到目标地点位置");

    {
        std::ofstream stream(state, std::ios::binary | std::ios::trunc);
        stream << "not-json";
    }
    bool failed = false;
    try {
        (void)repository.load();
    } catch (const WeatherLocationRepositoryError&) {
        failed = true;
    }
    expect(failed, "损坏的地点文件应报告错误而不是静默覆盖");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"Open-Meteo parses floating summaries", openMeteoParsesFloatingDailySummary},
        {"Open-Meteo rejects invalid responses", openMeteoRejectsInvalidResponses},
        {"geocoding filters invalid results", geocodingKeepsValidResultsAndAddsAdministrativeNames},
        {"China station search disambiguates", chinaStationSearchDisambiguatesSameNamedCities},
        {"China alerts parse official red alert", chinaAlertsParseOfficialRedAlertWithoutExpiry},
        {"NWS alerts parse severity and expiry", nwsAlertsParseSeverityAndExpiry},
        {"location repository persists and caps", locationRepositoryPersistsCurrentSavedLocationsAndCapacity},
        {"location repository reorders and protects files", locationRepositoryMovesSavedLocationsAndProtectsCorruptFiles},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
