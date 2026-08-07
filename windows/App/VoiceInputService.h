#pragma once

#include <zisla/core/VoiceInput.hpp>

#include <windows.h>
#include <winrt/Windows.Media.SpeechRecognition.h>

#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>

namespace winrt::Zisla {

enum class VoiceInputEventKind {
    hypothesis,
    result,
    completed,
};

struct VoiceInputEvent {
    VoiceInputEventKind kind{VoiceInputEventKind::hypothesis};
    std::uint64_t generation{0};
    Windows::Media::SpeechRecognition::SpeechRecognitionResultStatus status{
        Windows::Media::SpeechRecognition::SpeechRecognitionResultStatus::Success};
    std::string text;
};

class VoiceInputService : public std::enable_shared_from_this<VoiceInputService> {
public:
    VoiceInputService(HWND target, UINT changed_message);
    ~VoiceInputService();

    VoiceInputService(const VoiceInputService&) = delete;
    VoiceInputService& operator=(const VoiceInputService&) = delete;

    void start();
    void stop() noexcept;
    void cancel() noexcept;
    void finish_finalization() noexcept;
    void handle_pending_events() noexcept;

    [[nodiscard]] const zisla::core::VoiceInputSnapshot& snapshot() const noexcept;

private:
    winrt::fire_and_forget start_async(std::uint64_t generation);
    winrt::fire_and_forget stop_async(std::uint64_t generation);
    void handle_event(VoiceInputEvent event) noexcept;
    void finish_failure(
        std::uint64_t generation,
        zisla::core::VoiceInputFailure failure) noexcept;
    void release_resources() noexcept;
    void post_event(VoiceInputEvent event) noexcept;
    void notify_changed() const noexcept;

    HWND target_{nullptr};
    UINT changed_message_{0};
    zisla::core::VoiceInputSession session_;
    std::uint64_t current_generation_{0};
    std::string committed_text_;
    std::mutex pending_events_mutex_;
    std::deque<VoiceInputEvent> pending_events_;
    Windows::Media::SpeechRecognition::SpeechRecognizer recognizer_{nullptr};
    Windows::Media::SpeechRecognition::SpeechRecognizer::HypothesisGenerated_revoker hypothesis_revoker_{};
    Windows::Media::SpeechRecognition::SpeechContinuousRecognitionSession::ResultGenerated_revoker result_revoker_{};
    Windows::Media::SpeechRecognition::SpeechContinuousRecognitionSession::Completed_revoker completed_revoker_{};
};

}
