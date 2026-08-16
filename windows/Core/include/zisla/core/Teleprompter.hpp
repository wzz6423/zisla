#pragma once

#include <string>

namespace zisla::core {

struct TeleprompterSnapshot {
    std::string script;
    double scroll_speed{45.0};
    double scroll_offset{0.0};
    bool auto_scrolling{false};
};

class TeleprompterEngine {
public:
    static constexpr double minimum_scroll_speed = 15.0;
    static constexpr double maximum_scroll_speed = 150.0;
    static constexpr double default_scroll_speed = 45.0;

    explicit TeleprompterEngine(
        std::string script = {},
        double scroll_speed = default_scroll_speed);

    [[nodiscard]] const std::string& script() const noexcept;
    [[nodiscard]] double scroll_speed() const noexcept;
    [[nodiscard]] double scroll_offset() const noexcept;
    [[nodiscard]] bool auto_scrolling() const noexcept;
    [[nodiscard]] TeleprompterSnapshot snapshot() const;

    void set_script(std::string script);
    void set_scroll_speed(double scroll_speed) noexcept;
    [[nodiscard]] bool toggle_auto_scroll() noexcept;
    void pause() noexcept;
    void reset() noexcept;
    void advance(double elapsed_seconds, double maximum_offset) noexcept;

private:
    [[nodiscard]] static double normalized_speed(double value) noexcept;

    std::string script_;
    double scroll_speed_{default_scroll_speed};
    double scroll_offset_{0.0};
    bool auto_scrolling_{false};
};

}  // namespace zisla::core
