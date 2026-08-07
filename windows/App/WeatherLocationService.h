#pragma once

#include <winrt/Windows.Devices.Geolocation.h>
#include <winrt/Windows.Foundation.h>

namespace winrt::Zisla {

class WeatherLocationService {
public:
    [[nodiscard]] static Windows::Foundation::IAsyncOperation<
        Windows::Devices::Geolocation::Geoposition> currentPosition();
};

}
