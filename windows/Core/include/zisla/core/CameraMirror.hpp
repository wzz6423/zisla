#pragma once

#include <cstdint>
#include <optional>

namespace zisla::core {

enum class CameraMirrorPhase {
    idle,
    preparing,
    running,
    failed,
};

enum class CameraMirrorFailure {
    denied,
    restricted,
    unavailable,
    configuration,
};

struct CameraMirrorSnapshot {
    CameraMirrorPhase phase{CameraMirrorPhase::idle};
    std::optional<CameraMirrorFailure> failure;

    friend bool operator==(const CameraMirrorSnapshot&, const CameraMirrorSnapshot&) = default;
};

class CameraMirrorSession {
public:
    [[nodiscard]] const CameraMirrorSnapshot& snapshot() const noexcept;
    [[nodiscard]] std::uint64_t begin_start() noexcept;
    [[nodiscard]] bool mark_running(std::uint64_t generation) noexcept;
    [[nodiscard]] bool mark_failed(
        std::uint64_t generation,
        CameraMirrorFailure failure) noexcept;
    void stop() noexcept;
    [[nodiscard]] bool accepts(std::uint64_t generation) const noexcept;

private:
    [[nodiscard]] std::uint64_t next_generation() noexcept;

    CameraMirrorSnapshot snapshot_;
    std::uint64_t generation_{0};
};

}  // namespace zisla::core
