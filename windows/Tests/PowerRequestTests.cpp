#include "zisla/core/PowerRequests.hpp"

#include <array>
#include <cstddef>
#include <exception>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

enum class BackendOperation {
    acquire,
    release,
};

class FakePowerRequestBackend final : public PowerRequestBackend {
public:
    bool acquire(PowerRequestKind kind) noexcept override {
        calls.emplace_back(BackendOperation::acquire, kind);
        if (failing_acquire == kind) {
            failing_acquire.reset();
            return false;
        }
        ++counts[index(kind)];
        return true;
    }

    bool release(PowerRequestKind kind) noexcept override {
        calls.emplace_back(BackendOperation::release, kind);
        if (failing_release == kind) {
            failing_release.reset();
            return false;
        }
        if (counts[index(kind)] == 0) {
            return false;
        }
        --counts[index(kind)];
        return true;
    }

    [[nodiscard]] std::size_t count(PowerRequestKind kind) const noexcept {
        return counts[index(kind)];
    }

    std::optional<PowerRequestKind> failing_acquire;
    std::optional<PowerRequestKind> failing_release;
    std::vector<std::pair<BackendOperation, PowerRequestKind>> calls;

private:
    [[nodiscard]] static constexpr std::size_t index(PowerRequestKind kind) noexcept {
        return kind == PowerRequestKind::display_required ? 0U : 1U;
    }

    std::array<std::size_t, 2> counts{};
};

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void displayAndSystemTogglesShareSystemRequestCounts() {
    FakePowerRequestBackend backend;
    PowerRequestController controller{backend};

    expect(controller.set_keep_display_awake(true),
        "display mode should acquire its requests");
    expect(backend.count(PowerRequestKind::display_required) == 1,
        "display mode should acquire a display request");
    expect(backend.count(PowerRequestKind::system_required) == 1,
        "display mode should also acquire a system request");

    expect(controller.set_prevent_idle_system_sleep(true),
        "system mode should acquire its independent system request");
    expect(backend.count(PowerRequestKind::system_required) == 2,
        "both product toggles should retain separate system request counts");

    expect(controller.set_keep_display_awake(false),
        "display mode should release both of its contributions");
    expect(backend.count(PowerRequestKind::display_required) == 0,
        "display request should be released");
    expect(backend.count(PowerRequestKind::system_required) == 1,
        "the explicit system toggle should remain active");
    expect(controller.snapshot() == PowerRequestSnapshot{
            .prevent_idle_system_sleep = true,
        },
        "controller state should preserve the independent system toggle");
}

void repeatedValuesAreIdempotent() {
    FakePowerRequestBackend backend;
    PowerRequestController controller{backend};

    expect(controller.set_prevent_idle_system_sleep(false),
        "repeating the default off state should succeed");
    expect(controller.set_keep_display_awake(true),
        "display mode should enable");
    const auto calls_after_enable = backend.calls.size();
    expect(controller.set_keep_display_awake(true),
        "repeating an enabled state should succeed");
    expect(backend.calls.size() == calls_after_enable,
        "repeating an enabled state must not increment OS request counts");
}

void displayAcquireFailureRollsBackSystemContribution() {
    FakePowerRequestBackend backend;
    backend.failing_acquire = PowerRequestKind::display_required;
    PowerRequestController controller{backend};

    expect(!controller.set_keep_display_awake(true),
        "display mode should fail when the display request fails");
    expect(controller.snapshot() == PowerRequestSnapshot{},
        "a partial acquire must not enable the product toggle");
    expect(backend.count(PowerRequestKind::system_required) == 0,
        "a partial acquire should roll back its system request");
}

void systemAcquireFailureDoesNotAttemptDisplayRequest() {
    FakePowerRequestBackend backend;
    backend.failing_acquire = PowerRequestKind::system_required;
    PowerRequestController controller{backend};

    expect(!controller.set_keep_display_awake(true),
        "display mode should fail when its required system request fails");
    expect(backend.calls.size() == 1,
        "display request should not be attempted after system failure");
    expect(backend.count(PowerRequestKind::display_required) == 0,
        "display request count should remain zero");
}

void releaseFailureKeepsTheProductToggleEnabled() {
    FakePowerRequestBackend backend;
    PowerRequestController controller{backend};
    (void)controller.set_keep_display_awake(true);
    backend.failing_release = PowerRequestKind::system_required;

    expect(!controller.set_keep_display_awake(false),
        "a failed system release should be reported");
    expect(controller.snapshot().keep_display_awake,
        "the UI state must not claim the request was released");
    expect(backend.count(PowerRequestKind::display_required) == 1
            && backend.count(PowerRequestKind::system_required) == 1,
        "a failed first release should leave both requests active");
}

void releaseAllClearsBothProductStatesAndCounts() {
    FakePowerRequestBackend backend;
    PowerRequestController controller{backend};
    (void)controller.set_keep_display_awake(true);
    (void)controller.set_prevent_idle_system_sleep(true);

    controller.release_all();

    expect(controller.snapshot() == PowerRequestSnapshot{},
        "release_all should clear the product state");
    expect(backend.count(PowerRequestKind::display_required) == 0
            && backend.count(PowerRequestKind::system_required) == 0,
        "release_all should balance every acquired backend request");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"toggles share system request counts", displayAndSystemTogglesShareSystemRequestCounts},
        {"repeated values are idempotent", repeatedValuesAreIdempotent},
        {"display failure rolls back system", displayAcquireFailureRollsBackSystemContribution},
        {"system failure skips display", systemAcquireFailureDoesNotAttemptDisplayRequest},
        {"release failure preserves state", releaseFailureKeepsTheProductToggleEnabled},
        {"release all balances counts", releaseAllClearsBothProductStatesAndCounts},
    };

    std::size_t failed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failed;
            std::cerr << "FAIL: " << name << " - " << error.what() << '\n';
        }
    }

    if (failed != 0) {
        std::cerr << failed << " test(s) failed\n";
        return 1;
    }
    return 0;
}
