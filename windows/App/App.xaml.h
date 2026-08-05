#pragma once

#include "App.xaml.g.h"

namespace winrt::Zisla::implementation {

struct App : AppT<App> {
    App();

    void OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const&);
};

}

namespace winrt::Zisla::factory_implementation {

struct App : AppT<App, implementation::App> {};

}
