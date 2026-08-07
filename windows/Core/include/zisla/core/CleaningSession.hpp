#pragma once

namespace zisla::core {

enum class CleaningMode {
    idle,
    screen,
    keyboard,
};

class CleaningSession {
public:
    [[nodiscard]] CleaningMode mode() const noexcept;
    [[nodiscard]] bool active() const noexcept;
    [[nodiscard]] bool set_mode(CleaningMode mode) noexcept;
    void stop() noexcept;

private:
    CleaningMode mode_{CleaningMode::idle};
};

}  // namespace zisla::core
