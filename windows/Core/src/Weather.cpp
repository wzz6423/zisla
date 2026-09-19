#include "zisla/core/Weather.hpp"

#include "FileReplacement.hpp"

#include <yyjson.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <limits>
#include <memory>
#include <random>
#include <string_view>
#include <utility>

namespace zisla::core {
namespace {

constexpr std::size_t maximum_response_bytes = 1U * 1024U * 1024U;
constexpr double coordinate_tolerance = 0.001;

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;
using MutableJsonDocument =
    std::unique_ptr<yyjson_mut_doc, decltype(&yyjson_mut_doc_free)>;

[[noreturn]] void throw_parse(
    WeatherParseErrorCode code,
    std::string message) {
    throw WeatherParseError(code, std::move(message));
}

JsonDocument read_json(std::string_view source) {
    if (source.size() > maximum_response_bytes) {
        throw_parse(
            WeatherParseErrorCode::response_too_large,
            "天气响应超过大小限制");
    }
    auto document = JsonDocument(
        yyjson_read(source.data(), source.size(), YYJSON_READ_NOFLAG),
        yyjson_doc_free);
    if (!document) {
        throw_parse(
            WeatherParseErrorCode::invalid_json,
            "天气服务返回了无效 JSON");
    }
    return document;
}

yyjson_val* object_value(yyjson_val* parent, const char* key) {
    auto* value = parent ? yyjson_obj_get(parent, key) : nullptr;
    if (!yyjson_is_obj(value)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            std::string("天气 JSON 缺少对象字段：") + key);
    }
    return value;
}

yyjson_val* array_value(yyjson_val* parent, const char* key) {
    auto* value = parent ? yyjson_obj_get(parent, key) : nullptr;
    if (!yyjson_is_arr(value)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            std::string("天气 JSON 缺少数组字段：") + key);
    }
    return value;
}

std::optional<std::string> optional_string(yyjson_val* value) {
    if (!value || yyjson_is_null(value)) {
        return std::nullopt;
    }
    if (!yyjson_is_str(value)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "天气 JSON 字符串字段类型错误");
    }
    return std::string(yyjson_get_str(value), yyjson_get_len(value));
}

std::string required_string(yyjson_val* parent, const char* key) {
    const auto value = optional_string(parent ? yyjson_obj_get(parent, key) : nullptr);
    if (!value || value->empty()) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            std::string("天气 JSON 缺少字符串字段：") + key);
    }
    return *value;
}

std::optional<double> optional_number(yyjson_val* value) {
    if (!value || yyjson_is_null(value)) {
        return std::nullopt;
    }
    if (!yyjson_is_num(value)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "天气 JSON 数字字段类型错误");
    }
    const auto result = yyjson_get_num(value);
    if (!std::isfinite(result)) {
        throw_parse(
            WeatherParseErrorCode::invalid_value,
            "天气 JSON 包含非有限数字");
    }
    return result;
}

double required_number(yyjson_val* parent, const char* key) {
    const auto value = optional_number(parent ? yyjson_obj_get(parent, key) : nullptr);
    if (!value) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            std::string("天气 JSON 缺少数字字段：") + key);
    }
    return *value;
}

int required_integer(yyjson_val* parent, const char* key) {
    const auto number = required_number(parent, key);
    const auto rounded = std::round(number);
    if (rounded < static_cast<double>(std::numeric_limits<int>::min())
        || rounded > static_cast<double>(std::numeric_limits<int>::max())
        || std::abs(number - rounded) > 0.000'001) {
        throw_parse(
            WeatherParseErrorCode::invalid_value,
            std::string("天气 JSON 整数字段无效：") + key);
    }
    return static_cast<int>(rounded);
}

bool required_day_flag(yyjson_val* parent, const char* key) {
    auto* value = parent ? yyjson_obj_get(parent, key) : nullptr;
    if (!value || yyjson_is_null(value)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            std::string("天气 JSON 缺少昼夜字段：") + key);
    }
    if (yyjson_is_bool(value)) {
        return yyjson_get_bool(value);
    }
    return required_integer(parent, key) != 0;
}

std::string first_string(yyjson_val* parent, const char* key) {
    auto* array = array_value(parent, key);
    if (auto* item = yyjson_arr_get_first(array)) {
        const auto value = optional_string(item);
        if (value && !value->empty()) {
            return *value;
        }
    }
    throw_parse(
        WeatherParseErrorCode::invalid_shape,
        std::string("天气 JSON 数组为空：") + key);
}

int first_integer(yyjson_val* parent, const char* key) {
    auto* array = array_value(parent, key);
    if (auto* item = yyjson_arr_get_first(array)) {
        const auto value = optional_number(item);
        if (value) {
            const auto rounded = std::round(*value);
            if (std::abs(*value - rounded) <= 0.000'001
                && rounded >= static_cast<double>(std::numeric_limits<int>::min())
                && rounded <= static_cast<double>(std::numeric_limits<int>::max())) {
                return static_cast<int>(rounded);
            }
        }
    }
    throw_parse(
        WeatherParseErrorCode::invalid_shape,
        std::string("天气 JSON 整数数组无效：") + key);
}

double first_number(yyjson_val* parent, const char* key) {
    auto* array = array_value(parent, key);
    if (auto* item = yyjson_arr_get_first(array)) {
        if (const auto value = optional_number(item)) {
            return *value;
        }
    }
    throw_parse(
        WeatherParseErrorCode::invalid_shape,
        std::string("天气 JSON 数组为空：") + key);
}

std::string trim_ascii(std::string_view value) {
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

std::string normalized_place_name(std::string_view value) {
    auto result = trim_ascii(value);
    for (const auto suffix : {"特别行政区", "自治区", "省", "市"}) {
        std::size_t position = 0;
        while ((position = result.find(suffix, position)) != std::string::npos) {
            result.erase(position, std::char_traits<char>::length(suffix));
        }
    }
    return result;
}

bool contains_text(std::string_view value, std::string_view part) noexcept {
    return !part.empty() && value.find(part) != std::string_view::npos;
}

std::string generated_id() {
    static std::atomic<std::uint64_t> counter{0};
    const auto sequence = counter.fetch_add(1, std::memory_order_relaxed);
    std::uint64_t random = 0;
    try {
        random = static_cast<std::uint64_t>(std::random_device{}())
            << 32U
            ^ static_cast<std::uint64_t>(std::random_device{}());
    } catch (...) {
        random = static_cast<std::uint64_t>(
            std::chrono::steady_clock::now().time_since_epoch().count());
    }
    return "weather-location-" + std::to_string(random) + "-"
        + std::to_string(sequence);
}

std::string alert_id(
    std::string_view url,
    std::string_view source,
    std::string_view summary,
    std::optional<std::int64_t> expires_at) {
    std::string result;
    result.reserve(url.size() + source.size() + summary.size() + 32);
    result.append(url);
    result.push_back('|');
    result.append(source);
    result.push_back('|');
    result.append(summary);
    result.push_back('|');
    if (expires_at) {
        result.append(std::to_string(*expires_at));
    }
    return result;
}

std::int64_t unix_ms_from_components(
    int year,
    unsigned month,
    unsigned day,
    int hour,
    int minute,
    int second,
    int offset_minutes) noexcept {
    using namespace std::chrono;
    const year_month_day date{
        std::chrono::year{year},
        std::chrono::month{month},
        std::chrono::day{day}};
    if (!date.ok() || hour < 0 || hour > 23 || minute < 0 || minute > 59
        || second < 0 || second > 60) {
        return 0;
    }
    const auto time = sys_days{date} + hours{hour} + minutes{minute}
        + seconds{second} - minutes{offset_minutes};
    return duration_cast<milliseconds>(time.time_since_epoch()).count();
}

std::optional<std::int64_t> parse_compact_time(std::string_view value) noexcept {
    std::string digits;
    digits.reserve(value.size());
    for (const auto character : value) {
        if (character >= '0' && character <= '9') {
            digits.push_back(character);
        }
    }
    if (digits.size() < 12) {
        return std::nullopt;
    }
    const auto number = [&digits](std::size_t offset, std::size_t count) {
        int result = 0;
        for (std::size_t index = 0; index < count; ++index) {
            result = result * 10 + digits[offset + index] - '0';
        }
        return result;
    };
    const auto result = unix_ms_from_components(
        number(0, 4),
        static_cast<unsigned>(number(4, 2)),
        static_cast<unsigned>(number(6, 2)),
        number(8, 2),
        number(10, 2),
        digits.size() >= 14 ? number(12, 2) : 0,
        8 * 60);
    return result == 0 ? std::nullopt : std::optional{result};
}

std::optional<std::int64_t> parse_iso8601(std::string_view value) noexcept {
    if (value.size() < 19) {
        return std::nullopt;
    }
    const auto digit = [&value](std::size_t index) -> int {
        const auto character = value[index];
        return character >= '0' && character <= '9' ? character - '0' : -1;
    };
    const auto part = [&digit](std::size_t offset, std::size_t count) -> int {
        int result = 0;
        for (std::size_t index = 0; index < count; ++index) {
            const auto value = digit(offset + index);
            if (value < 0) {
                return -1;
            }
            result = result * 10 + value;
        }
        return result;
    };
    const auto year = part(0, 4);
    const auto month = part(5, 2);
    const auto day = part(8, 2);
    const auto hour = part(11, 2);
    const auto minute = part(14, 2);
    const auto second = part(17, 2);
    if (year < 0 || month < 0 || day < 0 || hour < 0 || minute < 0 || second < 0
        || value[4] != '-' || value[7] != '-' || value[10] != 'T'
        || value[13] != ':' || value[16] != ':') {
        return std::nullopt;
    }
    int offset_minutes = 0;
    if (value.size() == 19 || value[19] == 'Z' || value[19] == 'z') {
        offset_minutes = 0;
    } else {
        if (value.size() < 25 || (value[19] != '+' && value[19] != '-')
            || value[22] != ':') {
            return std::nullopt;
        }
        const auto offset_hour = part(20, 2);
        const auto offset_minute = part(23, 2);
        if (offset_hour < 0 || offset_minute < 0 || offset_hour > 23
            || offset_minute > 59) {
            return std::nullopt;
        }
        offset_minutes = offset_hour * 60 + offset_minute;
        if (value[19] == '-') {
            offset_minutes = -offset_minutes;
        }
    }
    const auto result = unix_ms_from_components(
        year,
        static_cast<unsigned>(month),
        static_cast<unsigned>(day),
        hour,
        minute,
        second,
        offset_minutes);
    return result == 0 ? std::nullopt : std::optional{result};
}

WeatherAlertSeverity china_severity(std::string_view value) noexcept {
    if (contains_text(value, "红") || value == "04") {
        return WeatherAlertSeverity::extreme;
    }
    if (contains_text(value, "橙") || value == "03") {
        return WeatherAlertSeverity::severe;
    }
    if (contains_text(value, "黄") || value == "02") {
        return WeatherAlertSeverity::moderate;
    }
    return WeatherAlertSeverity::minor;
}

WeatherAlertSeverity nws_severity(std::string_view value) noexcept {
    std::string normalized;
    normalized.reserve(value.size());
    for (const auto character : value) {
        normalized.push_back(static_cast<char>(std::tolower(
            static_cast<unsigned char>(character))));
    }
    if (normalized == "extreme") {
        return WeatherAlertSeverity::extreme;
    }
    if (normalized == "severe") {
        return WeatherAlertSeverity::severe;
    }
    if (normalized == "moderate") {
        return WeatherAlertSeverity::moderate;
    }
    return WeatherAlertSeverity::minor;
}

std::string extract_assigned_object(std::string_view source, std::string_view name) {
    const auto variable = source.find(name);
    if (variable == std::string_view::npos) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "中国天气网响应缺少预警对象");
    }
    const auto start = source.find('{', variable + name.size());
    if (start == std::string_view::npos) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "中国天气网预警对象无效");
    }
    int depth = 0;
    bool in_string = false;
    bool escaped = false;
    for (std::size_t index = start; index < source.size(); ++index) {
        const auto character = source[index];
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (character == '\\') {
                escaped = true;
            } else if (character == '"') {
                in_string = false;
            }
            continue;
        }
        if (character == '"') {
            in_string = true;
        } else if (character == '{') {
            ++depth;
        } else if (character == '}') {
            --depth;
            if (depth == 0) {
                return std::string(source.substr(start, index - start + 1));
            }
        }
    }
    throw_parse(
        WeatherParseErrorCode::invalid_shape,
        "中国天气网预警对象未闭合");
}

struct ChinaStation {
    std::string id;
    std::string city;
    std::string province;
};

std::optional<ChinaStation> china_station(yyjson_val* value) {
    const auto ref = optional_string(value ? yyjson_obj_get(value, "ref") : nullptr);
    if (!ref) {
        return std::nullopt;
    }
    std::vector<std::string_view> fields;
    std::size_t begin = 0;
    while (begin <= ref->size()) {
        const auto end = ref->find('~', begin);
        fields.emplace_back(
            ref->data() + begin,
            (end == std::string::npos ? ref->size() : end) - begin);
        if (end == std::string::npos) {
            break;
        }
        begin = end + 1;
    }
    if (fields.size() < 9 || fields[0].size() != 9
        || !std::all_of(fields[0].begin(), fields[0].end(), [](char value) {
            return value >= '0' && value <= '9';
        })) {
        return std::nullopt;
    }
    return ChinaStation{
        .id = std::string(fields[0]),
        .city = std::string(fields[2]),
        .province = std::string(fields[8]),
    };
}

bool add_string(
    yyjson_mut_doc* document,
    yyjson_mut_val* object,
    const char* key,
    std::string_view value) {
    return yyjson_mut_obj_add_strncpy(
        document,
        object,
        key,
        value.data(),
        value.size());
}

std::string encode_locations(std::span<const WeatherLocation> locations) {
    MutableJsonDocument document(yyjson_mut_doc_new(nullptr), yyjson_mut_doc_free);
    if (!document) {
        throw WeatherLocationRepositoryError("无法分配天气地点 JSON");
    }
    auto* root = yyjson_mut_arr(document.get());
    yyjson_mut_doc_set_root(document.get(), root);
    if (!root) {
        throw WeatherLocationRepositoryError("无法创建天气地点 JSON 数组");
    }
    for (const auto& location : locations) {
        auto* object = yyjson_mut_obj(document.get());
        if (!object
            || !add_string(document.get(), object, "id", location.id)
            || !add_string(
                document.get(),
                object,
                "kind",
                location.kind == WeatherLocationKind::current ? "current" : "saved")
            || !add_string(document.get(), object, "displayName", location.display_name)
            || !yyjson_mut_arr_add_val(root, object)) {
            throw WeatherLocationRepositoryError("无法编码天气地点 JSON");
        }
        if (location.coordinate) {
            if (!yyjson_mut_obj_add_real(
                    document.get(), object, "latitude", location.coordinate->latitude)
                || !yyjson_mut_obj_add_real(
                    document.get(), object, "longitude", location.coordinate->longitude)) {
                throw WeatherLocationRepositoryError("无法编码天气地点坐标");
            }
        }
    }
    std::size_t length = 0;
    std::unique_ptr<char, decltype(&std::free)> json(
        yyjson_mut_write(document.get(), YYJSON_WRITE_NOFLAG, &length),
        std::free);
    if (!json) {
        throw WeatherLocationRepositoryError("无法序列化天气地点 JSON");
    }
    return {json.get(), length};
}

std::vector<WeatherLocation> decode_locations(std::string_view source) {
    if (source.size() > maximum_response_bytes) {
        throw WeatherLocationRepositoryError("天气地点文件超过大小限制");
    }
    JsonDocument document(
        yyjson_read(source.data(), source.size(), YYJSON_READ_NOFLAG),
        yyjson_doc_free);
    auto* root = document ? yyjson_doc_get_root(document.get()) : nullptr;
    if (!yyjson_is_arr(root)) {
        throw WeatherLocationRepositoryError("天气地点文件格式无效");
    }
    std::vector<WeatherLocation> locations;
    yyjson_val* item = nullptr;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_arr_foreach(root, index, maximum, item) {
        if (!yyjson_is_obj(item)) {
            throw WeatherLocationRepositoryError("天气地点项目格式无效");
        }
        const auto id = optional_string(yyjson_obj_get(item, "id"));
        const auto kind = optional_string(yyjson_obj_get(item, "kind"));
        const auto display_name = optional_string(yyjson_obj_get(item, "displayName"));
        if (!id || !kind || !display_name || id->empty() || display_name->empty()) {
            throw WeatherLocationRepositoryError("天气地点缺少必要字段");
        }
        WeatherLocationKind location_kind;
        if (*kind == "saved") {
            location_kind = WeatherLocationKind::saved;
        } else if (*kind == "current") {
            location_kind = WeatherLocationKind::current;
        } else {
            throw WeatherLocationRepositoryError("天气地点类型无效");
        }
        WeatherLocation location{
            .id = *id,
            .kind = location_kind,
            .display_name = *display_name,
        };
        const auto latitude = optional_number(yyjson_obj_get(item, "latitude"));
        const auto longitude = optional_number(yyjson_obj_get(item, "longitude"));
        if (latitude.has_value() != longitude.has_value()) {
            throw WeatherLocationRepositoryError("天气地点坐标不完整");
        }
        if (latitude && longitude) {
            location.coordinate = GeoCoordinate{*latitude, *longitude};
            if (!location.coordinate->valid()) {
                throw WeatherLocationRepositoryError("天气地点坐标无效");
            }
        }
        locations.push_back(std::move(location));
    }
    return locations;
}

void write_atomic_file(const std::filesystem::path& path, std::string_view data) {
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error) {
        throw WeatherLocationRepositoryError("无法创建天气地点目录");
    }
    auto temporary = path;
    temporary += ".tmp";
    {
        std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
        stream.write(data.data(), static_cast<std::streamsize>(data.size()));
        stream.flush();
        if (!stream) {
            throw WeatherLocationRepositoryError("无法写入天气地点文件");
        }
    }
    error = detail::replace_file_atomically(temporary, path);
    if (error) {
        std::filesystem::remove(temporary, error);
        throw WeatherLocationRepositoryError("无法替换天气地点文件");
    }
}

}  // namespace

bool GeoCoordinate::valid() const noexcept {
    return std::isfinite(latitude) && std::isfinite(longitude)
        && latitude >= -90.0 && latitude <= 90.0
        && longitude >= -180.0 && longitude <= 180.0;
}

WeatherLocation WeatherLocation::current(
    std::string display_name,
    std::optional<GeoCoordinate> coordinate) {
    if (display_name.empty()) {
        display_name = "当前位置";
    }
    return {
        .id = std::string(weather_current_location_id),
        .kind = WeatherLocationKind::current,
        .display_name = std::move(display_name),
        .coordinate = coordinate,
    };
}

WeatherLocation WeatherLocation::saved(
    std::string display_name,
    GeoCoordinate coordinate,
    std::string id) {
    if (display_name.empty()) {
        display_name = "未命名地点";
    }
    if (id.empty()) {
        id = generated_id();
    }
    return {
        .id = std::move(id),
        .kind = WeatherLocationKind::saved,
        .display_name = std::move(display_name),
        .coordinate = coordinate,
    };
}

WeatherParseError::WeatherParseError(
    WeatherParseErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

WeatherParseErrorCode WeatherParseError::code() const noexcept {
    return code_;
}

WeatherSnapshot WeatherParser::parse_open_meteo(
    std::string_view json,
    GeoCoordinate coordinate,
    std::string location_id,
    std::string location_name,
    std::int64_t fetched_at_unix_ms) {
    if (!coordinate.valid()) {
        throw_parse(
            WeatherParseErrorCode::invalid_value,
            "天气位置坐标无效");
    }
    JsonDocument document = read_json(json);
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "天气 JSON 根节点不是对象");
    }
    auto* current = object_value(root, "current");
    auto* daily = object_value(root, "daily");
    const auto weather_code = required_integer(current, "weather_code");
    const auto precipitation_probability = first_integer(
        daily,
        "precipitation_probability_max");
    if (precipitation_probability < 0 || precipitation_probability > 100) {
        throw_parse(
            WeatherParseErrorCode::invalid_value,
            "降水概率超出范围");
    }
    WeatherSnapshot snapshot{
        .location_id = std::move(location_id),
        .location_name = std::move(location_name),
        .coordinate = coordinate,
        .temperature = required_number(current, "temperature_2m"),
        .apparent_temperature = required_number(current, "apparent_temperature"),
        .weather_code = weather_code,
        .is_day = required_day_flag(current, "is_day"),
        .current_precipitation = optional_number(
            yyjson_obj_get(current, "precipitation")).value_or(0.0),
        .sunrise = first_string(daily, "sunrise"),
        .sunset = first_string(daily, "sunset"),
        .precipitation_probability = precipitation_probability,
        .precipitation_sum = first_number(daily, "precipitation_sum"),
        .timezone = required_string(root, "timezone"),
        .fetched_at_unix_ms = fetched_at_unix_ms,
    };
    if (!std::isfinite(snapshot.current_precipitation)
        || snapshot.current_precipitation < 0
        || !std::isfinite(snapshot.precipitation_sum)
        || snapshot.precipitation_sum < 0) {
        throw_parse(
            WeatherParseErrorCode::invalid_value,
            "降水量无效");
    }
    return snapshot;
}

std::vector<WeatherLocationSearchResult> WeatherParser::parse_geocoding(
    std::string_view json) {
    JsonDocument document = read_json(json);
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "地区搜索 JSON 根节点不是对象");
    }
    auto* results = yyjson_obj_get(root, "results");
    if (!results || yyjson_is_null(results)) {
        return {};
    }
    if (!yyjson_is_arr(results)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "地区搜索 JSON 结果字段类型错误");
    }
    std::vector<WeatherLocationSearchResult> output;
    yyjson_val* item = nullptr;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_arr_foreach(results, index, maximum, item) {
        if (!yyjson_is_obj(item)) {
            continue;
        }
        const auto name = optional_string(yyjson_obj_get(item, "name"));
        const auto latitude = optional_number(yyjson_obj_get(item, "latitude"));
        const auto longitude = optional_number(yyjson_obj_get(item, "longitude"));
        if (!name || !latitude || !longitude) {
            continue;
        }
        const auto admin = optional_string(yyjson_obj_get(item, "admin1"));
        const auto country = optional_string(yyjson_obj_get(item, "country"));
        std::string display_name = *name;
        if (admin && !admin->empty() && *admin != *name) {
            display_name = *admin + *name;
        }
        const GeoCoordinate coordinate{*latitude, *longitude};
        if (!coordinate.valid()) {
            continue;
        }
        output.push_back({
            .display_name = std::move(display_name),
            .country = country.value_or(std::string{}),
            .administrative_area = admin.value_or(std::string{}),
            .coordinate = coordinate,
        });
        if (output.size() >= 16) {
            break;
        }
    }
    return output;
}

std::optional<std::string> WeatherParser::parse_china_station_id(
    std::string_view response,
    std::string_view query,
    std::string_view location_name) {
    const auto source = trim_ascii(response);
    if (source.size() < 2 || source.front() != '(' || source.back() != ')') {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "中国天气网地区响应格式无效");
    }
    JsonDocument document = read_json(
        std::string_view{source}.substr(1, source.size() - 2));
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_arr(root)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "中国天气网地区响应不是数组");
    }
    const auto normalized_query = normalized_place_name(query);
    std::vector<ChinaStation> matches;
    yyjson_val* item = nullptr;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_arr_foreach(root, index, maximum, item) {
        if (const auto station = china_station(item);
            station && normalized_place_name(station->city) == normalized_query) {
            matches.push_back(*station);
        }
    }
    for (const auto& station : matches) {
        if (contains_text(location_name, station.province)) {
            return station.id;
        }
    }
    if (!matches.empty()) {
        return matches.front().id;
    }
    return std::nullopt;
}

std::vector<WeatherAlert> WeatherParser::parse_china_alerts(
    std::string_view response,
    std::string_view station_id,
    std::string_view region,
    std::int64_t fallback_updated_at_unix_ms) {
    const auto json = extract_assigned_object(response, "alarmDZ");
    JsonDocument document = read_json(json);
    auto* root = yyjson_doc_get_root(document.get());
    auto* values = array_value(root, "w");
    std::vector<WeatherAlert> alerts;
    yyjson_val* item = nullptr;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_arr_foreach(values, index, maximum, item) {
        if (!yyjson_is_obj(item)) {
            continue;
        }
        const auto type = optional_string(yyjson_obj_get(item, "w5"));
        const auto level = optional_string(yyjson_obj_get(item, "w7"));
        const auto publication = optional_string(yyjson_obj_get(item, "w8"));
        const auto file = optional_string(yyjson_obj_get(item, "w11"));
        const auto summary_value = optional_string(yyjson_obj_get(item, "w13"));
        const auto summary = summary_value.value_or(
            (type.value_or(std::string{}) + " " + level.value_or(std::string{})));
        if (summary.empty()) {
            continue;
        }
        const auto url = file && !file->empty()
            ? "https://www.weather.com.cn/alarm/newalarmcontent.shtml?file=" + *file
            : "https://www.weather.com.cn/weather1d/" + std::string(station_id) + ".shtml";
        const auto updated = publication
            ? parse_compact_time(*publication).value_or(fallback_updated_at_unix_ms)
            : fallback_updated_at_unix_ms;
        const auto severity = china_severity(level.value_or(std::string{}));
        alerts.push_back({
            .id = alert_id(url, "中国天气网（中国气象局）", summary, std::nullopt),
            .severity = severity,
            .source = "中国天气网（中国气象局）",
            .summary = summary,
            .region = std::string(region),
            .details_url = url,
            .updated_at_unix_ms = updated,
            .expires_at_unix_ms = std::nullopt,
        });
    }
    return alerts;
}

std::vector<WeatherAlert> WeatherParser::parse_nws_alerts(
    std::string_view response,
    std::int64_t fallback_updated_at_unix_ms) {
    JsonDocument document = read_json(response);
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        throw_parse(
            WeatherParseErrorCode::invalid_shape,
            "美国国家气象局响应根节点无效");
    }
    auto* features = array_value(root, "features");
    std::vector<WeatherAlert> alerts;
    yyjson_val* feature = nullptr;
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_arr_foreach(features, index, maximum, feature) {
        if (!yyjson_is_obj(feature)) {
            continue;
        }
        auto* properties = object_value(feature, "properties");
        const auto details = optional_string(yyjson_obj_get(feature, "id"));
        const auto headline = optional_string(yyjson_obj_get(properties, "headline"));
        const auto event = optional_string(yyjson_obj_get(properties, "event"));
        const auto summary = headline && !headline->empty()
            ? *headline
            : event.value_or(std::string{});
        if (summary.empty()) {
            continue;
        }
        const auto source = optional_string(yyjson_obj_get(properties, "senderName"))
            .value_or("美国国家气象局");
        const auto region = optional_string(yyjson_obj_get(properties, "areaDesc"))
            .value_or(std::string{});
        const auto severity = nws_severity(optional_string(
            yyjson_obj_get(properties, "severity")).value_or(std::string{}));
        const auto effective = optional_string(yyjson_obj_get(properties, "effective"));
        const auto expires = optional_string(yyjson_obj_get(properties, "expires"));
        const auto updated = effective
            ? parse_iso8601(*effective).value_or(fallback_updated_at_unix_ms)
            : fallback_updated_at_unix_ms;
        const auto expires_at = expires ? parse_iso8601(*expires) : std::nullopt;
        const auto url = details.value_or("https://www.weather.gov/alerts");
        alerts.push_back({
            .id = alert_id(url, source, summary, expires_at),
            .severity = severity,
            .source = source,
            .summary = summary,
            .region = region,
            .details_url = url,
            .updated_at_unix_ms = updated,
            .expires_at_unix_ms = expires_at,
        });
    }
    return alerts;
}

std::string WeatherParser::condition_summary(int weather_code) {
    switch (weather_code) {
    case 0:
        return "晴";
    case 1:
        return "晴间少云";
    case 2:
        return "多云";
    case 3:
        return "阴";
    case 45:
    case 48:
        return "雾";
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
        return "毛毛雨";
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
        return "雨";
    case 71:
    case 73:
    case 75:
    case 77:
        return "雪";
    case 80:
    case 81:
    case 82:
        return "阵雨";
    case 85:
    case 86:
        return "阵雪";
    case 95:
    case 96:
    case 99:
        return "雷阵雨";
    default:
        return "天气未知";
    }
}

WeatherLocationRepositoryError::WeatherLocationRepositoryError(std::string message)
    : std::runtime_error(std::move(message)) {}

WeatherLocationRepository::WeatherLocationRepository(
    std::filesystem::path path,
    std::size_t max_saved)
    : path_(std::move(path)), max_saved_(std::max<std::size_t>(1, max_saved)) {}

const std::filesystem::path& WeatherLocationRepository::path() const noexcept {
    return path_;
}

std::size_t WeatherLocationRepository::max_saved() const noexcept {
    return max_saved_;
}

std::vector<WeatherLocation> WeatherLocationRepository::load() const {
    std::error_code error;
    if (!std::filesystem::exists(path_, error)) {
        return {WeatherLocation::current()};
    }
    const auto size = std::filesystem::file_size(path_, error);
    if (error || size > maximum_response_bytes) {
        throw WeatherLocationRepositoryError("无法读取天气地点文件");
    }
    std::ifstream stream(path_, std::ios::binary);
    if (!stream) {
        throw WeatherLocationRepositoryError("无法打开天气地点文件");
    }
    std::string source(
        std::istreambuf_iterator<char>{stream},
        std::istreambuf_iterator<char>{});
    if (!stream.good() && !stream.eof()) {
        throw WeatherLocationRepositoryError("无法读取天气地点文件");
    }
    return normalize(decode_locations(source), max_saved_);
}

void WeatherLocationRepository::save(
    std::span<const WeatherLocation> locations) const {
    const auto normalized = normalize(locations, max_saved_);
    write_atomic_file(path_, encode_locations(normalized));
}

void WeatherLocationRepository::add_saved(
    std::string name,
    GeoCoordinate coordinate) const {
    if (!coordinate.valid()) {
        throw WeatherLocationRepositoryError("保存的天气地点坐标无效");
    }
    auto locations = load();
    const auto trimmed = trim_ascii(name);
    const auto display_name = trimmed.empty() ? "未命名地点" : trimmed;
    const auto duplicate = std::find_if(
        locations.begin(),
        locations.end(),
        [coordinate](const auto& location) {
            return location.kind == WeatherLocationKind::saved
                && coordinates_equal_approximately(location.coordinate, coordinate);
        });
    if (duplicate != locations.end()) {
        duplicate->display_name = display_name;
        duplicate->coordinate = coordinate;
    } else {
        locations.push_back(WeatherLocation::saved(display_name, coordinate));
    }
    save(locations);
}

void WeatherLocationRepository::update_current(
    std::string name,
    std::optional<GeoCoordinate> coordinate) const {
    if (coordinate && !coordinate->valid()) {
        throw WeatherLocationRepositoryError("当前位置坐标无效");
    }
    auto locations = load();
    const auto display_name = trim_ascii(name).empty()
        ? "当前位置"
        : trim_ascii(name);
    auto current = std::find_if(
        locations.begin(),
        locations.end(),
        [](const auto& location) {
            return location.kind == WeatherLocationKind::current;
        });
    if (current == locations.end()) {
        locations.insert(
            locations.begin(),
            WeatherLocation::current(display_name, coordinate));
    } else {
        current->id = std::string(weather_current_location_id);
        current->kind = WeatherLocationKind::current;
        current->display_name = display_name;
        current->coordinate = coordinate;
    }
    save(locations);
}

bool WeatherLocationRepository::remove(std::string_view id) const {
    if (id == weather_current_location_id) {
        return false;
    }
    auto locations = load();
    const auto before = locations.size();
    std::erase_if(locations, [id](const auto& location) {
        return location.kind == WeatherLocationKind::saved && location.id == id;
    });
    if (locations.size() == before) {
        return false;
    }
    save(locations);
    return true;
}

bool WeatherLocationRepository::move_saved(
    std::string_view id,
    std::string_view destination_id) const {
    if (id == destination_id) {
        return false;
    }
    auto locations = load();
    const auto source = std::find_if(
        locations.begin(),
        locations.end(),
        [id](const auto& location) {
            return location.kind == WeatherLocationKind::saved && location.id == id;
        });
    const auto destination = std::find_if(
        locations.begin(),
        locations.end(),
        [destination_id](const auto& location) {
            return location.kind == WeatherLocationKind::saved
                && location.id == destination_id;
        });
    if (source == locations.end() || destination == locations.end()) {
        return false;
    }
    const auto source_index = static_cast<std::size_t>(
        std::distance(locations.begin(), source));
    auto destination_index = static_cast<std::size_t>(
        std::distance(locations.begin(), destination));
    auto moved = *source;
    locations.erase(source);
    if (source_index < destination_index) {
        --destination_index;
    }
    locations.insert(locations.begin() + static_cast<std::ptrdiff_t>(destination_index), moved);
    save(locations);
    return true;
}

std::vector<WeatherLocation> WeatherLocationRepository::normalize(
    std::span<const WeatherLocation> locations,
    std::size_t max_saved) {
    max_saved = std::max<std::size_t>(1, max_saved);
    WeatherLocation current = WeatherLocation::current();
    for (const auto& location : locations) {
        if (location.kind == WeatherLocationKind::current) {
            current = location;
            break;
        }
    }
    current.id = std::string(weather_current_location_id);
    current.kind = WeatherLocationKind::current;
    if (current.display_name.empty()) {
        current.display_name = "当前位置";
    }
    if (current.coordinate && !current.coordinate->valid()) {
        current.coordinate.reset();
    }

    std::vector<WeatherLocation> saved;
    std::vector<std::string> ids;
    for (const auto& location : locations) {
        if (location.kind != WeatherLocationKind::saved
            || !location.coordinate || !location.coordinate->valid()) {
            continue;
        }
        const auto duplicate = std::find_if(
            saved.begin(),
            saved.end(),
            [&location](const auto& existing) {
                return coordinates_equal_approximately(
                    existing.coordinate,
                    *location.coordinate);
            });
        if (duplicate != saved.end()) {
            duplicate->display_name = location.display_name.empty()
                ? "未命名地点"
                : location.display_name;
            duplicate->coordinate = location.coordinate;
            continue;
        }
        auto copy = location;
        copy.kind = WeatherLocationKind::saved;
        if (copy.id.empty() || copy.id == weather_current_location_id
            || std::find(ids.begin(), ids.end(), copy.id) != ids.end()) {
            copy.id = generated_id();
        }
        if (copy.display_name.empty()) {
            copy.display_name = "未命名地点";
        }
        ids.push_back(copy.id);
        saved.push_back(std::move(copy));
    }
    if (saved.size() > max_saved) {
        saved.erase(saved.begin(), saved.end() - static_cast<std::ptrdiff_t>(max_saved));
    }
    std::vector<WeatherLocation> result;
    result.reserve(saved.size() + 1);
    result.push_back(std::move(current));
    result.insert(
        result.end(),
        std::make_move_iterator(saved.begin()),
        std::make_move_iterator(saved.end()));
    return result;
}

bool WeatherLocationRepository::coordinates_equal_approximately(
    std::optional<GeoCoordinate> lhs,
    GeoCoordinate rhs) noexcept {
    return lhs && std::abs(lhs->latitude - rhs.latitude) <= coordinate_tolerance
        && std::abs(lhs->longitude - rhs.longitude) <= coordinate_tolerance;
}

}  // namespace zisla::core
