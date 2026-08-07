#include "pch.h"
#include "WeatherLocationService.h"

#include <chrono>

namespace winrt::Zisla {

Windows::Foundation::IAsyncOperation<
    Windows::Devices::Geolocation::Geoposition>
WeatherLocationService::currentPosition() {
    using namespace Windows::Devices::Geolocation;

    const auto access = co_await Geolocator::RequestAccessAsync();
    if (access != GeolocationAccessStatus::Allowed) {
        throw hresult_error(
            E_ACCESSDENIED,
            L"定位权限被拒绝，请在 Windows 设置中允许访问位置");
    }

    Geolocator locator;
    locator.DesiredAccuracy(PositionAccuracy::Default);
    co_return co_await locator.GetGeopositionAsync(
        std::chrono::minutes{15},
        std::chrono::seconds{15});
}

}
