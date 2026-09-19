#pragma once

#include <zisla/core/PowerRequests.hpp>

#include <windows.h>

namespace winrt::Zisla {

class PowerRequestService final : public zisla::core::PowerRequestBackend {
public:
    PowerRequestService() = default;
    ~PowerRequestService() override;

    PowerRequestService(const PowerRequestService&) = delete;
    PowerRequestService& operator=(const PowerRequestService&) = delete;

    [[nodiscard]] bool acquire(zisla::core::PowerRequestKind kind) noexcept override;
    [[nodiscard]] bool release(zisla::core::PowerRequestKind kind) noexcept override;

private:
    [[nodiscard]] bool ensureHandle() noexcept;
    [[nodiscard]] static POWER_REQUEST_TYPE nativeType(
        zisla::core::PowerRequestKind kind) noexcept;

    HANDLE request_{INVALID_HANDLE_VALUE};
};

}
