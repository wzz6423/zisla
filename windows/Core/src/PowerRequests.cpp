#include "zisla/core/PowerRequests.hpp"

namespace zisla::core {

PowerRequestController::PowerRequestController(PowerRequestBackend& backend) noexcept
    : backend_(backend) {}

PowerRequestController::~PowerRequestController() {
    release_all();
}

PowerRequestSnapshot PowerRequestController::snapshot() const noexcept {
    return snapshot_;
}

bool PowerRequestController::set_keep_display_awake(bool enabled) noexcept {
    if (snapshot_.keep_display_awake == enabled) {
        return true;
    }

    if (enabled) {
        if (!backend_.acquire(PowerRequestKind::system_required)) {
            return false;
        }
        if (!backend_.acquire(PowerRequestKind::display_required)) {
            (void)backend_.release(PowerRequestKind::system_required);
            return false;
        }
        snapshot_.keep_display_awake = true;
        return true;
    }

    if (!backend_.release(PowerRequestKind::system_required)) {
        return false;
    }
    if (!backend_.release(PowerRequestKind::display_required)) {
        (void)backend_.acquire(PowerRequestKind::system_required);
        return false;
    }
    snapshot_.keep_display_awake = false;
    return true;
}

bool PowerRequestController::set_prevent_idle_system_sleep(bool enabled) noexcept {
    if (snapshot_.prevent_idle_system_sleep == enabled) {
        return true;
    }

    const bool succeeded = enabled
        ? backend_.acquire(PowerRequestKind::system_required)
        : backend_.release(PowerRequestKind::system_required);
    if (succeeded) {
        snapshot_.prevent_idle_system_sleep = enabled;
    }
    return succeeded;
}

void PowerRequestController::release_all() noexcept {
    if (snapshot_.keep_display_awake) {
        (void)backend_.release(PowerRequestKind::display_required);
        (void)backend_.release(PowerRequestKind::system_required);
    }
    if (snapshot_.prevent_idle_system_sleep) {
        (void)backend_.release(PowerRequestKind::system_required);
    }
    snapshot_ = {};
}

}  // namespace zisla::core
