#include "pch.h"
#include "VoiceInputService.h"

#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <utility>

namespace winrt::Zisla {
namespace {

using zisla::core::VoiceInputFailure;
using Windows::Media::SpeechRecognition::SpeechRecognizer;
using Windows::Media::SpeechRecognition::SpeechRecognitionResultStatus;

std::optional<VoiceInputFailure> microphone_access_failure(
    Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus status)
    noexcept {
    using AccessStatus =
        Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;
    switch (status) {
    case AccessStatus::DeniedBySystem:
    case AccessStatus::DeniedByUser:
    case AccessStatus::NotDeclaredByApp:
        return VoiceInputFailure::microphone_permission_denied;
    case AccessStatus::Allowed:
    case AccessStatus::UserPromptRequired:
        return std::nullopt;
    }
    return VoiceInputFailure::microphone_permission_denied;
}

VoiceInputFailure failure_for_error(hresult code) noexcept {
    if (code == E_ACCESSDENIED) {
        return VoiceInputFailure::microphone_permission_denied;
    }
    // SPERR_NOT_FOUND: 0x8004503a - 识别器不可用
    // SPERR_DEVICE_NOT_SUPPORTED: 0x80045037 - 设备不支持
    constexpr HRESULT recognizer_not_found = static_cast<HRESULT>(0x8004503a);
    constexpr HRESULT device_not_supported = static_cast<HRESULT>(0x80045037);
    if (code == recognizer_not_found || code == device_not_supported) {
        return VoiceInputFailure::recognizer_unavailable;
    }
    return VoiceInputFailure::startup_failed;
}

VoiceInputFailure failure_for_status(
    SpeechRecognitionResultStatus status,
    VoiceInputFailure fallback) noexcept {
    if (status == SpeechRecognitionResultStatus::MicrophoneUnavailable) {
        return VoiceInputFailure::no_audio_input;
    }
    if (status == SpeechRecognitionResultStatus::TopicLanguageNotSupported) {
        return VoiceInputFailure::recognizer_unavailable;
    }
    return fallback;
}

std::string trim_text(std::string text) {
    const auto is_space = [](unsigned char value) {
        return std::isspace(value) != 0;
    };
    const auto first = std::find_if_not(
        text.begin(),
        text.end(),
        [is_space](char value) { return is_space(static_cast<unsigned char>(value)); });
    const auto last = std::find_if_not(
        text.rbegin(),
        text.rend(),
        [is_space](char value) { return is_space(static_cast<unsigned char>(value)); }).base();
    if (first >= last) {
        return {};
    }
    return {first, last};
}

void append_text(std::string& transcript, std::string text) {
    text = trim_text(std::move(text));
    if (text.empty()) {
        return;
    }
    if (!transcript.empty()) {
        transcript.push_back(' ');
    }
    transcript.append(text);
}

}

VoiceInputService::VoiceInputService(
    HWND target,
    UINT changed_message)
    : target_(target),
      changed_message_(changed_message) {
    if (!target_ || changed_message_ == 0) {
        throw std::invalid_argument("voice input service requires a target");
    }
}

VoiceInputService::~VoiceInputService() {
    session_.cancel();
    current_generation_ = 0;
    committed_text_.clear();
    {
        const std::lock_guard lock{pending_events_mutex_};
        pending_events_.clear();
    }
    release_resources();
}

void VoiceInputService::start() {
    release_resources();
    committed_text_.clear();
    current_generation_ = session_.begin();
    notify_changed();
    start_async(current_generation_);
}

void VoiceInputService::stop() noexcept {
    try {
        const auto snap = session_.snapshot();
        if (snap.phase == zisla::core::VoiceInputPhase::listening) {
            if (!session_.mark_finalizing(current_generation_)) {
                return;
            }
            notify_changed();
            stop_async(current_generation_);
        }
    } catch (...) {
    }
}

void VoiceInputService::cancel() noexcept {
    session_.cancel();
    current_generation_ = 0;
    committed_text_.clear();
    {
        const std::lock_guard lock{pending_events_mutex_};
        pending_events_.clear();
    }
    release_resources();
    notify_changed();
}

void VoiceInputService::finish_finalization() noexcept {
    const auto snap = session_.snapshot();
    if (snap.phase != zisla::core::VoiceInputPhase::finalizing) {
        return;
    }
    if (session_.finish_finalization(current_generation_)) {
        release_resources();
        notify_changed();
    }
}

const zisla::core::VoiceInputSnapshot& VoiceInputService::snapshot() const noexcept {
    return session_.snapshot();
}

void VoiceInputService::handle_pending_events() noexcept {
    std::deque<VoiceInputEvent> events;
    try {
        {
            const std::lock_guard lock{pending_events_mutex_};
            events.swap(pending_events_);
        }
        for (auto& event : events) {
            handle_event(std::move(event));
        }
    } catch (...) {
        finish_failure(current_generation_, VoiceInputFailure::recognition_failed);
    }
}

void VoiceInputService::handle_event(VoiceInputEvent event) noexcept {
    try {
        if (!session_.accepts(event.generation)) {
            return;
        }

        const auto phase = session_.snapshot().phase;
        switch (event.kind) {
        case VoiceInputEventKind::hypothesis:
            if (phase == zisla::core::VoiceInputPhase::listening) {
                auto transcript = committed_text_;
                append_text(transcript, std::move(event.text));
                if (session_.update_partial_text(event.generation, std::move(transcript))) {
                    notify_changed();
                }
            }
            return;
        case VoiceInputEventKind::result:
            if (event.status != SpeechRecognitionResultStatus::Success) {
                finish_failure(
                    event.generation,
                    failure_for_status(event.status, VoiceInputFailure::recognition_failed));
                return;
            }
            if (phase == zisla::core::VoiceInputPhase::listening) {
                append_text(committed_text_, std::move(event.text));
                if (session_.update_partial_text(event.generation, committed_text_)) {
                    notify_changed();
                }
                return;
            }
            if (phase == zisla::core::VoiceInputPhase::finalizing) {
                auto transcript = committed_text_;
                append_text(transcript, std::move(event.text));
                if (session_.update_final_text(event.generation, std::move(transcript))) {
                    release_resources();
                    notify_changed();
                }
            }
            return;
        case VoiceInputEventKind::completed:
            if (event.status != SpeechRecognitionResultStatus::Success) {
                finish_failure(
                    event.generation,
                    failure_for_status(event.status, VoiceInputFailure::recognition_failed));
            }
            return;
        }
    } catch (...) {
        finish_failure(current_generation_, VoiceInputFailure::recognition_failed);
    }
}

winrt::fire_and_forget VoiceInputService::start_async(
    std::uint64_t generation) {
    const auto lifetime = shared_from_this();
    (void)lifetime;

    try {
        using namespace Windows::Security::Authorization::AppCapabilityAccess;

        // Windows Speech API 不需要单独的语音权限，直接进入麦克风权限
        if (!session_.mark_speech_permission_granted(generation)) {
            co_return;
        }
        notify_changed();

        const auto capability = AppCapability::Create(L"microphone");
        auto access = capability.CheckAccess();
        if (access == AppCapabilityAccessStatus::UserPromptRequired) {
            access = co_await capability.RequestAccessAsync();
        }
        if (!session_.accepts(generation)) {
            co_return;
        }
        if (const auto failure = microphone_access_failure(access)) {
            if (session_.mark_microphone_permission_denied(generation)) {
                release_resources();
                notify_changed();
            }
            co_return;
        }

        if (!session_.mark_microphone_permission_granted(generation)) {
            co_return;
        }
        notify_changed();

        SpeechRecognizer recognizer;
        try {
            recognizer = SpeechRecognizer();
        } catch (const hresult_error& error) {
            finish_failure(generation, failure_for_error(error.code()));
            co_return;
        }

        if (!session_.accepts(generation)) {
            recognizer.Close();
            co_return;
        }

        recognizer.Constraints().Clear();
        Windows::Media::SpeechRecognition::SpeechRecognitionTopicConstraint dictation_constraint(
            Windows::Media::SpeechRecognition::SpeechRecognitionScenario::Dictation,
            L"dictation");
        recognizer.Constraints().Append(dictation_constraint);

        const auto compilation = co_await recognizer.CompileConstraintsAsync();
        if (!session_.accepts(generation)) {
            recognizer.Close();
            co_return;
        }
        if (compilation.Status() != SpeechRecognitionResultStatus::Success) {
            recognizer.Close();
            finish_failure(
                generation,
                failure_for_status(compilation.Status(), VoiceInputFailure::startup_failed));
            co_return;
        }

        auto hypothesis_revoker = recognizer.HypothesisGenerated(auto_revoke, [
            lifetime,
            generation](auto&&, auto&& args) noexcept {
                try {
                    lifetime->post_event({
                        VoiceInputEventKind::hypothesis,
                        generation,
                        SpeechRecognitionResultStatus::Success,
                        winrt::to_string(args.Hypothesis().Text()),
                    });
                } catch (...) {
                }
            });

        const auto continuous_session = recognizer.ContinuousRecognitionSession();
        auto result_revoker = continuous_session.ResultGenerated(auto_revoke, [
            lifetime,
            generation](auto&&, auto&& args) noexcept {
                try {
                    const auto result = args.Result();
                    lifetime->post_event({
                        VoiceInputEventKind::result,
                        generation,
                        result.Status(),
                        winrt::to_string(result.Text()),
                    });
                } catch (...) {
                }
            });

        auto completed_revoker = continuous_session.Completed(auto_revoke, [
            lifetime,
            generation](auto&&, auto&& args) noexcept {
                try {
                    lifetime->post_event({
                        VoiceInputEventKind::completed,
                        generation,
                        args.Status(),
                        {},
                    });
                } catch (...) {
                }
            });

        recognizer_ = std::move(recognizer);
        hypothesis_revoker_ = std::move(hypothesis_revoker);
        result_revoker_ = std::move(result_revoker);
        completed_revoker_ = std::move(completed_revoker);

        co_await continuous_session.StartAsync();
        if (!session_.accepts(generation)) {
            release_resources();
            co_return;
        }
        if (session_.mark_listening(generation)) {
            notify_changed();
        }

    } catch (const hresult_error& error) {
        finish_failure(generation, failure_for_error(error.code()));
    } catch (...) {
        finish_failure(generation, VoiceInputFailure::startup_failed);
    }
}

winrt::fire_and_forget VoiceInputService::stop_async(
    std::uint64_t generation) {
    const auto lifetime = shared_from_this();
    (void)lifetime;

    try {
        const auto recognizer = recognizer_;
        if (recognizer) {
            co_await recognizer.ContinuousRecognitionSession().StopAsync();
        }
    } catch (const hresult_error& error) {
        if (session_.accepts(generation)) {
            finish_failure(generation, failure_for_error(error.code()));
        }
    } catch (...) {
        if (session_.accepts(generation)) {
            finish_failure(generation, VoiceInputFailure::recognition_failed);
        }
    }
}

void VoiceInputService::finish_failure(
    std::uint64_t generation,
    VoiceInputFailure failure) noexcept {
    if (!session_.mark_failed(generation, failure)) {
        return;
    }
    release_resources();
    notify_changed();
}

void VoiceInputService::release_resources() noexcept {
    try {
        hypothesis_revoker_.revoke();
    } catch (...) {
    }
    try {
        result_revoker_.revoke();
    } catch (...) {
    }
    try {
        completed_revoker_.revoke();
    } catch (...) {
    }
    if (recognizer_) {
        try {
            recognizer_.Close();
        } catch (...) {
        }
        recognizer_ = nullptr;
    }
}

void VoiceInputService::post_event(VoiceInputEvent event) noexcept {
    try {
        {
            const std::lock_guard lock{pending_events_mutex_};
            pending_events_.push_back(std::move(event));
        }
        notify_changed();
    } catch (...) {
    }
}

void VoiceInputService::notify_changed() const noexcept {
    (void)PostMessageW(target_, changed_message_, 0, 0);
}

}
