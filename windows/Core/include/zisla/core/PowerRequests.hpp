#pragma once

namespace zisla::core {

enum class PowerRequestKind {
    display_required,
    system_required,
};

class PowerRequestBackend {
public:
    virtual ~PowerRequestBackend() = default;

    [[nodiscard]] virtual bool acquire(PowerRequestKind kind) noexcept = 0;
    [[nodiscard]] virtual bool release(PowerRequestKind kind) noexcept = 0;
};

struct PowerRequestSnapshot {
    bool keep_display_awake{false};
    bool prevent_idle_system_sleep{false};

    friend bool operator==(
        const PowerRequestSnapshot&,
        const PowerRequestSnapshot&) = default;
};

class PowerRequestController {
public:
    explicit PowerRequestController(PowerRequestBackend& backend) noexcept;
    ~PowerRequestController();

    PowerRequestController(const PowerRequestController&) = delete;
    PowerRequestController& operator=(const PowerRequestController&) = delete;

    [[nodiscard]] PowerRequestSnapshot snapshot() const noexcept;
    [[nodiscard]] bool set_keep_display_awake(bool enabled) noexcept;
    [[nodiscard]] bool set_prevent_idle_system_sleep(bool enabled) noexcept;
    void release_all() noexcept;

private:
    PowerRequestBackend& backend_;
    PowerRequestSnapshot snapshot_;
};

}  // namespace zisla::core
