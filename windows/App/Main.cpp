#include "pch.h"
#include "App.xaml.h"
#include "AppHost.h"

#include <winrt/Microsoft.Windows.AppLifecycle.h>

#include <atomic>
#include <memory>

namespace {

struct RedirectState {
    winrt::handle completed;
    std::atomic<HRESULT> result{E_PENDING};
};

winrt::fire_and_forget redirectActivation(
    winrt::Microsoft::Windows::AppLifecycle::AppInstance instance,
    winrt::Microsoft::Windows::AppLifecycle::AppActivationArguments args,
    std::shared_ptr<RedirectState> state) {
    try {
        co_await instance.RedirectActivationToAsync(args);
        state->result.store(S_OK, std::memory_order_release);
    } catch (...) {
        state->result.store(winrt::to_hresult(), std::memory_order_release);
    }
    (void)SetEvent(state->completed.get());
}

void redirectActivationAndWait(
    const winrt::Microsoft::Windows::AppLifecycle::AppInstance& instance,
    const winrt::Microsoft::Windows::AppLifecycle::AppActivationArguments& args) {
    auto state = std::make_shared<RedirectState>();
    state->completed.attach(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    winrt::check_pointer(state->completed.get());

    redirectActivation(instance, args, state);
    HANDLE completed = state->completed.get();
    DWORD completed_index = 0;
    winrt::check_hresult(CoWaitForMultipleHandles(
        COWAIT_DISPATCH_CALLS | COWAIT_DISPATCH_WINDOW_MESSAGES,
        INFINITE,
        1,
        &completed,
        &completed_index));
    winrt::check_hresult(state->result.load(std::memory_order_acquire));
}

}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    winrt::init_apartment(winrt::apartment_type::single_threaded);

    const auto key = L"Zisla-E3C8C887-1E41-4E59-9B4C-26D3546C82D4";
    const auto instance = winrt::Microsoft::Windows::AppLifecycle::AppInstance::FindOrRegisterForKey(key);
    if (!instance) {
        return 1;
    }
    if (!instance.IsCurrent()) {
        const auto current = winrt::Microsoft::Windows::AppLifecycle::AppInstance::GetCurrent();
        if (!current) {
            return 1;
        }
        const auto activation_args = current.GetActivatedEventArgs();
        if (!activation_args) {
            return 1;
        }
        redirectActivationAndWait(instance, activation_args);
        return 0;
    }

    const auto activation_token = instance.Activated([](auto&&, auto&&) {
        winrt::Zisla::AppHost::instance().requestExternalActivation();
    });
    winrt::Zisla::AppHost::loadSettings();
    winrt::Microsoft::UI::Xaml::Application::Start(
        [](auto&&) {
            winrt::make<winrt::Zisla::implementation::App>();
        });
    instance.Activated(activation_token);
    return 0;
}
