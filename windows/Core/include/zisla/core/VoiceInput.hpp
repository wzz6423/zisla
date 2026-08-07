#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>

namespace zisla::core {

enum class VoiceInputPhase {
    idle,
    requesting_speech_permission,
    requesting_microphone_permission,
    starting,
    listening,
    finalizing,
    failed,
};

enum class VoiceInputFailure {
    speech_permission_denied,
    microphone_permission_denied,
    recognizer_unavailable,
    no_audio_input,
    startup_failed,
    recognition_failed,
};

struct VoiceInputSnapshot {
    VoiceInputPhase phase{VoiceInputPhase::idle};
    std::optional<VoiceInputFailure> failure;
    std::string partial_text;
    std::string final_text;

    friend bool operator==(const VoiceInputSnapshot&, const VoiceInputSnapshot&) = default;
};

class VoiceInputSession {
public:
    static constexpr std::chrono::seconds finalization_timeout_seconds{3};

    [[nodiscard]] const VoiceInputSnapshot& snapshot() const noexcept;

    [[nodiscard]] std::uint64_t begin() noexcept;
    [[nodiscard]] bool mark_speech_permission_granted(std::uint64_t generation) noexcept;
    [[nodiscard]] bool mark_speech_permission_denied(std::uint64_t generation) noexcept;

    [[nodiscard]] bool mark_microphone_permission_granted(std::uint64_t generation) noexcept;
    [[nodiscard]] bool mark_microphone_permission_denied(std::uint64_t generation) noexcept;

    [[nodiscard]] bool mark_listening(std::uint64_t generation) noexcept;
    [[nodiscard]] bool mark_failed(
        std::uint64_t generation,
        VoiceInputFailure failure) noexcept;

    [[nodiscard]] bool update_partial_text(
        std::uint64_t generation,
        std::string text) noexcept;
    [[nodiscard]] bool mark_finalizing(std::uint64_t generation) noexcept;
    [[nodiscard]] bool update_final_text(
        std::uint64_t generation,
        std::string text) noexcept;
    [[nodiscard]] bool finish_finalization(std::uint64_t generation) noexcept;

    void cancel() noexcept;
    [[nodiscard]] bool accepts(std::uint64_t generation) const noexcept;

private:
    [[nodiscard]] std::uint64_t next_generation() noexcept;

    VoiceInputSnapshot snapshot_;
    std::uint64_t generation_{0};
};

}  // namespace zisla::core
