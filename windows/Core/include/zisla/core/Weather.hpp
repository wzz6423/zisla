#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

inline constexpr std::string_view weather_current_location_id =
    "weather-location-current";

struct GeoCoordinate {
    double latitude{0};
    double longitude{0};

    [[nodiscard]] bool valid() const noexcept;

    friend bool operator==(const GeoCoordinate&, const GeoCoordinate&) = default;
};

enum class WeatherLocationKind {
    current,
    saved,
};

struct WeatherLocation {
    std::string id;
    WeatherLocationKind kind{WeatherLocationKind::current};
    std::string display_name;
    std::optional<GeoCoordinate> coordinate;

    [[nodiscard]] static WeatherLocation current(
        std::string display_name = "当前位置",
        std::optional<GeoCoordinate> coordinate = std::nullopt);
    [[nodiscard]] static WeatherLocation saved(
        std::string display_name,
        GeoCoordinate coordinate,
        std::string id = {});

    friend bool operator==(const WeatherLocation&, const WeatherLocation&) = default;
};

struct WeatherLocationSearchResult {
    std::string display_name;
    std::string country;
    std::string administrative_area;
    GeoCoordinate coordinate;

    friend bool operator==(
        const WeatherLocationSearchResult&,
        const WeatherLocationSearchResult&) = default;
};

enum class WeatherAlertSeverity {
    minor,
    moderate,
    severe,
    extreme,
};

struct WeatherAlert {
    std::string id;
    WeatherAlertSeverity severity{WeatherAlertSeverity::minor};
    std::string source;
    std::string summary;
    std::string region;
    std::string details_url;
    std::int64_t updated_at_unix_ms{0};
    std::optional<std::int64_t> expires_at_unix_ms;

    friend bool operator==(const WeatherAlert&, const WeatherAlert&) = default;
};

struct WeatherSnapshot {
    std::string location_id;
    std::string location_name;
    GeoCoordinate coordinate;
    double temperature{0};
    double apparent_temperature{0};
    int weather_code{0};
    bool is_day{true};
    double current_precipitation{0};
    std::string sunrise;
    std::string sunset;
    int precipitation_probability{0};
    double precipitation_sum{0};
    std::vector<WeatherAlert> official_alerts;
    std::optional<std::string> alert_error;
    std::string timezone;
    std::int64_t fetched_at_unix_ms{0};

    friend bool operator==(const WeatherSnapshot&, const WeatherSnapshot&) = default;
};

enum class WeatherParseErrorCode {
    invalid_json,
    invalid_shape,
    invalid_value,
    response_too_large,
};

class WeatherParseError : public std::runtime_error {
public:
    WeatherParseError(WeatherParseErrorCode code, std::string message);

    [[nodiscard]] WeatherParseErrorCode code() const noexcept;

private:
    WeatherParseErrorCode code_;
};

class WeatherParser {
public:
    [[nodiscard]] static WeatherSnapshot parse_open_meteo(
        std::string_view json,
        GeoCoordinate coordinate,
        std::string location_id,
        std::string location_name,
        std::int64_t fetched_at_unix_ms);

    [[nodiscard]] static std::vector<WeatherLocationSearchResult>
        parse_geocoding(std::string_view json);

    [[nodiscard]] static std::optional<std::string> parse_china_station_id(
        std::string_view response,
        std::string_view query,
        std::string_view location_name);

    [[nodiscard]] static std::vector<WeatherAlert> parse_china_alerts(
        std::string_view response,
        std::string_view station_id,
        std::string_view region,
        std::int64_t fallback_updated_at_unix_ms);

    [[nodiscard]] static std::vector<WeatherAlert> parse_nws_alerts(
        std::string_view response,
        std::int64_t fallback_updated_at_unix_ms);

    [[nodiscard]] static std::string condition_summary(int weather_code);
};

class WeatherLocationRepositoryError : public std::runtime_error {
public:
    explicit WeatherLocationRepositoryError(std::string message);
};

class WeatherLocationRepository {
public:
    explicit WeatherLocationRepository(
        std::filesystem::path path,
        std::size_t max_saved = 6);

    [[nodiscard]] const std::filesystem::path& path() const noexcept;
    [[nodiscard]] std::size_t max_saved() const noexcept;
    [[nodiscard]] std::vector<WeatherLocation> load() const;
    void save(std::span<const WeatherLocation> locations) const;
    void add_saved(std::string name, GeoCoordinate coordinate) const;
    void update_current(
        std::string name,
        std::optional<GeoCoordinate> coordinate) const;
    [[nodiscard]] bool remove(std::string_view id) const;
    [[nodiscard]] bool move_saved(
        std::string_view id,
        std::string_view destination_id) const;

    [[nodiscard]] static std::vector<WeatherLocation> normalize(
        std::span<const WeatherLocation> locations,
        std::size_t max_saved);
    [[nodiscard]] static bool coordinates_equal_approximately(
        std::optional<GeoCoordinate> lhs,
        GeoCoordinate rhs) noexcept;

private:
    std::filesystem::path path_;
    std::size_t max_saved_;
};

}  // namespace zisla::core
