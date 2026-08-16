#pragma once

#include "App.xaml.g.h"

namespace winrt::Zisla::implementation {

struct App : ::winrt::Zisla::implementation::AppT<App> {
    App();

    void OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const&);
};

}
