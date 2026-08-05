#include "pch.h"
#include "PowerRequestService.h"

namespace winrt::Zisla {

PowerRequestService::~PowerRequestService() {
    if (request_ != INVALID_HANDLE_VALUE) {
        CloseHandle(request_);
        request_ = INVALID_HANDLE_VALUE;
    }
}

bool PowerRequestService::acquire(
    zisla::core::PowerRequestKind kind) noexcept {
    return ensureHandle()
        && PowerSetRequest(request_, nativeType(kind)) != FALSE;
}

bool PowerRequestService::release(
    zisla::core::PowerRequestKind kind) noexcept {
    return request_ != INVALID_HANDLE_VALUE
        && PowerClearRequest(request_, nativeType(kind)) != FALSE;
}

bool PowerRequestService::ensureHandle() noexcept {
    if (request_ != INVALID_HANDLE_VALUE) {
        return true;
    }

    static constexpr wchar_t reason[] = L"Zisla 保持亮屏与防止空闲休眠";
    REASON_CONTEXT context{};
    context.Version = POWER_REQUEST_CONTEXT_VERSION;
    context.Flags = POWER_REQUEST_CONTEXT_SIMPLE_STRING;
    context.Reason.SimpleReasonString = const_cast<wchar_t*>(reason);
    request_ = PowerCreateRequest(&context);
    return request_ != INVALID_HANDLE_VALUE;
}

POWER_REQUEST_TYPE PowerRequestService::nativeType(
    zisla::core::PowerRequestKind kind) noexcept {
    return kind == zisla::core::PowerRequestKind::display_required
        ? PowerRequestDisplayRequired
        : PowerRequestSystemRequired;
}

}
