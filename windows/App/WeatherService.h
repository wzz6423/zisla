#pragma once

#include <zisla/core/Weather.hpp>

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace winrt::Zisla {

enum class WeatherServiceOperation {
    none,
    refresh,
    search,
};

enum class WeatherServicePhase {
    idle,
    loading,
    ready,
    failed,
};

struct WeatherServiceSnapshot {
    WeatherServiceOperation operation{WeatherServiceOperation::none};
    WeatherServicePhase phase{WeatherServicePhase::idle};
    std::vector<zisla::core::WeatherSnapshot> weather;
    std::vector<zisla::core::WeatherLocationSearchResult> search_results;
    std::string message;
    std::uint64_t generation{0};
};

class WeatherService {
public:
    WeatherService();
    ~WeatherService();

    WeatherService(const WeatherService&) = delete;
    WeatherService& operator=(const WeatherService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] bool running() const noexcept;
    [[nodiscard]] std::shared_ptr<const WeatherServiceSnapshot>
        snapshot() const noexcept;
    [[nodiscard]] bool requestRefresh(
        std::vector<zisla::core::WeatherLocation> locations,
        std::string initial_error = {}) noexcept;
    [[nodiscard]] bool requestSearch(std::string query) noexcept;

private:
    enum class CommandKind {
        refresh,
        search,
    };

    struct Command {
        CommandKind kind{CommandKind::refresh};
        std::vector<zisla::core::WeatherLocation> locations;
        std::string query;
        std::string initial_error;
        std::uint64_t generation{0};
    };

    [[nodiscard]] bool request(Command command) noexcept;
    void run() noexcept;
    void wake() noexcept;
    void notifyChanged() const noexcept;
    [[nodiscard]] std::optional<Command> takeLatestCommand() noexcept;
    void publish(std::shared_ptr<const WeatherServiceSnapshot> snapshot) noexcept;
    void publishIfCurrent(
        std::uint64_t generation,
        std::shared_ptr<const WeatherServiceSnapshot> snapshot) noexcept;

    std::atomic<std::shared_ptr<const WeatherServiceSnapshot>> snapshot_;
    std::mutex command_mutex_;
    std::deque<Command> commands_;
    std::thread thread_;
    std::atomic_bool running_{false};
    std::atomic<std::uint64_t> latest_generation_{0};
    HANDLE stop_event_{nullptr};
    HANDLE wake_event_{nullptr};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}
