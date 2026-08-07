#include "pch.h"
#include "App.xaml.h"
#include "AppHost.h"

namespace winrt::Zisla::implementation {

App::App() {
    InitializeComponent();
}

void App::OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const&) {
    AppHost::instance().start();
}

}
