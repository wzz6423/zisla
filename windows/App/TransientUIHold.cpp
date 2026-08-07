#include "pch.h"
#include "TransientUIHold.h"

#include "AppHost.h"

#include <shobjidl_core.h>

namespace winrt::Zisla {

TransientUIHold::TransientUIHold() {
    AppHost::instance().dispatchPresentationAction(
        zisla::core::PresentationAction::holdChanged(
            zisla::core::PresentationHold::transient_ui,
            true));
}

TransientUIHold::~TransientUIHold() noexcept {
    try {
        AppHost::instance().dispatchPresentationAction(
            zisla::core::PresentationAction::holdChanged(
                zisla::core::PresentationHold::transient_ui,
                false));
    } catch (...) {
    }
}

void initializePicker(Windows::Foundation::IInspectable const& picker) {
    const auto hwnd = AppHost::instance().overlayWindowHandle();
    if (!hwnd) {
        throw hresult_error(E_HANDLE);
    }
    check_hresult(picker.as<::IInitializeWithWindow>()->Initialize(hwnd));
}

}  // namespace winrt::Zisla
