#include "zisla/core/VoiceInput.hpp"

#include <chrono>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void startsIdle() {
    VoiceInputSession session;

    expect(session.snapshot() == VoiceInputSnapshot{},
        "a voice input session should start idle");
}

void beginEntersRequestingSpeechPermission() {
    VoiceInputSession session;

    const auto generation = session.begin();

    expect(generation != 0, "begin should issue a nonzero generation");
    expect(session.snapshot().phase == VoiceInputPhase::requesting_speech_permission,
        "begin should enter requesting_speech_permission phase");
}

void singleGenerationPermissionSequence() {
    VoiceInputSession session;

    const auto generation = session.begin();
    expect(session.snapshot().phase == VoiceInputPhase::requesting_speech_permission,
        "should start with requesting_speech_permission");

    expect(session.mark_speech_permission_granted(generation),
        "same generation should accept speech permission grant");
    expect(session.snapshot().phase == VoiceInputPhase::requesting_microphone_permission,
        "speech granted should auto-enter requesting_microphone_permission");

    expect(session.mark_microphone_permission_granted(generation),
        "same generation should accept microphone permission grant");
    expect(session.snapshot().phase == VoiceInputPhase::starting,
        "microphone granted should auto-enter starting");

    expect(session.mark_listening(generation),
        "same generation should accept listening transition");
    expect(session.snapshot().phase == VoiceInputPhase::listening,
        "should enter listening phase");
}

void outOfOrderPermissionRejected() {
    VoiceInputSession session;

    const auto generation = session.begin();
    expect(session.snapshot().phase == VoiceInputPhase::requesting_speech_permission,
        "should start with requesting_speech_permission");

    expect(!session.mark_microphone_permission_granted(generation),
        "should reject microphone grant when still requesting speech");
    expect(session.snapshot().phase == VoiceInputPhase::requesting_speech_permission,
        "phase should remain unchanged after rejection");

    expect(!session.mark_listening(generation),
        "should reject listening when still requesting speech");
}

void speechPermissionDenied() {
    VoiceInputSession session;
    const auto generation = session.begin();

    expect(session.mark_speech_permission_denied(generation),
        "current generation should accept permission denial");
    expect(session.snapshot().phase == VoiceInputPhase::failed,
        "denied permission should enter failed phase");
    expect(session.snapshot().failure == VoiceInputFailure::speech_permission_denied,
        "failure reason should be speech_permission_denied");
}

void microphonePermissionDenied() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);

    expect(session.mark_microphone_permission_denied(generation),
        "current generation should accept permission denial");
    expect(session.snapshot().phase == VoiceInputPhase::failed,
        "denied permission should enter failed phase");
    expect(session.snapshot().failure == VoiceInputFailure::microphone_permission_denied,
        "failure reason should be microphone_permission_denied");
}

void partialTextUpdate() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);

    expect(session.update_partial_text(generation, "hello"),
        "listening session should accept partial text");
    expect(session.snapshot().partial_text == "hello",
        "partial text should be stored");
    expect(session.snapshot().phase == VoiceInputPhase::listening,
        "partial text update should remain in listening phase");

    expect(session.update_partial_text(generation, "hello world"),
        "listening session should accept updated partial text");
    expect(session.snapshot().partial_text == "hello world",
        "partial text should be updated");
}

void finalizingFlow() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.update_partial_text(generation, "partial");

    expect(session.mark_finalizing(generation),
        "listening session should accept finalizing transition");
    expect(session.snapshot().phase == VoiceInputPhase::finalizing,
        "should enter finalizing phase");
    expect(session.snapshot().partial_text == "partial",
        "partial text should be retained during finalizing");
}

void finalTextCompletesSession() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.mark_finalizing(generation);

    expect(session.update_final_text(generation, "final result"),
        "finalizing session should accept final text");
    expect(session.snapshot().final_text == "final result",
        "final text should be stored");
    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "final text should complete and return to idle");
}

void finalizationTimeoutWithPartialText() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.update_partial_text(generation, "partial result");
    (void)session.mark_finalizing(generation);

    expect(session.finish_finalization(generation),
        "should accept finalization finish");
    expect(session.snapshot().final_text == "partial result",
        "should fallback to partial text when final text is empty");
    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "should return to idle after finalization");
}

void finalizationTimeoutWithFinalText() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.update_partial_text(generation, "partial");
    (void)session.mark_finalizing(generation);
    (void)session.update_final_text(generation, "final");

    const auto generation2 = session.begin();
    (void)session.mark_speech_permission_granted(generation2);
    (void)session.mark_microphone_permission_granted(generation2);
    (void)session.mark_listening(generation2);
    (void)session.mark_finalizing(generation2);

    expect(session.finish_finalization(generation2),
        "should accept finalization finish");
    expect(session.snapshot().final_text.empty(),
        "should keep final text empty when no text is available");
    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "should return to idle");
}

void finalizingErrorFallsBackToPartialText() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.update_partial_text(generation, "incomplete");
    (void)session.mark_finalizing(generation);

    expect(session.mark_failed(generation, VoiceInputFailure::recognition_failed),
        "should accept error during finalizing");
    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "should return to idle, not failed");
    expect(session.snapshot().final_text == "incomplete",
        "should fallback to partial text on finalizing error");
    expect(!session.snapshot().failure,
        "should not expose failure when in finalizing phase");
}

void finalizingTerminationFallsBackToPartialText() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.update_partial_text(generation, "partial");
    (void)session.mark_finalizing(generation);

    expect(session.mark_failed(generation, VoiceInputFailure::no_audio_input),
        "should accept termination during finalizing");
    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "should return to idle, not failed");
    expect(session.snapshot().final_text == "partial",
        "should fallback to partial text");
}

void listeningErrorPreservesFailure() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);

    expect(session.mark_failed(generation, VoiceInputFailure::no_audio_input),
        "listening session should accept failure");
    expect(session.snapshot().phase == VoiceInputPhase::failed,
        "should enter failed phase");
    expect(session.snapshot().failure == VoiceInputFailure::no_audio_input,
        "should preserve failure reason");
}

void startingErrorPreservesFailure() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);

    expect(session.mark_failed(generation, VoiceInputFailure::startup_failed),
        "starting session should accept failure");
    expect(session.snapshot().phase == VoiceInputPhase::failed,
        "should enter failed phase");
    expect(session.snapshot().failure == VoiceInputFailure::startup_failed,
        "should preserve failure reason");
}

void cancelInvalidatesPendingResults() {
    VoiceInputSession session;
    const auto generation = session.begin();

    session.cancel();

    expect(session.snapshot().phase == VoiceInputPhase::idle,
        "canceling should return to idle");
    expect(!session.mark_failed(generation, VoiceInputFailure::startup_failed),
        "a completion arriving after cancel must be ignored");
}

void newBeginInvalidatesOldGeneration() {
    VoiceInputSession session;
    const auto old_gen = session.begin();
    const auto new_gen = session.begin();

    expect(new_gen != old_gen, "new begin should issue different generation");
    expect(!session.mark_speech_permission_granted(old_gen),
        "old generation should be rejected");
    expect(session.mark_speech_permission_granted(new_gen),
        "new generation should be accepted");
}

void staleGenerationCannotUpdateText() {
    VoiceInputSession session;
    const auto stale = session.begin();
    const auto current = session.begin();
    (void)session.mark_speech_permission_granted(current);
    (void)session.mark_microphone_permission_granted(current);
    (void)session.mark_listening(current);

    expect(!session.update_partial_text(stale, "stale text"),
        "stale generation should not update partial text");
    expect(session.snapshot().partial_text.empty(),
        "partial text should remain empty");
}

void staleGenerationCannotUpdateFinalText() {
    VoiceInputSession session;
    const auto stale = session.begin();
    const auto current = session.begin();
    (void)session.mark_speech_permission_granted(current);
    (void)session.mark_microphone_permission_granted(current);
    (void)session.mark_listening(current);
    (void)session.mark_finalizing(current);

    expect(!session.update_final_text(stale, "stale final"),
        "stale generation should not update final text");
    expect(session.snapshot().final_text.empty(),
        "final text should remain empty");
}

void failedSessionCannotReceiveFinalText() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.mark_failed(generation, VoiceInputFailure::recognition_failed);

    expect(!session.update_final_text(generation, "too late"),
        "failed session should reject final text");
}

void idleSessionRejectsTextUpdates() {
    VoiceInputSession session;
    const auto generation = session.begin();
    (void)session.mark_speech_permission_granted(generation);
    (void)session.mark_microphone_permission_granted(generation);
    (void)session.mark_listening(generation);
    (void)session.mark_finalizing(generation);
    (void)session.update_final_text(generation, "done");

    expect(!session.update_partial_text(generation, "too late"),
        "idle session should reject partial text updates");
}

void finalizationTimeoutConstantExists() {
    using namespace std::chrono_literals;
    expect(VoiceInputSession::finalization_timeout_seconds == 3s,
        "finalization timeout should be 3 seconds");
}

void generationWrapAround() {
    VoiceInputSession session;

    std::uint64_t last_gen = 0;
    for (int i = 0; i < 10; ++i) {
        const auto gen = session.begin();
        expect(gen != 0, "generation should never be zero");
        expect(gen != last_gen, "generation should increment");
        last_gen = gen;
        session.cancel();
    }
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"starts idle", startsIdle},
        {"begin enters requesting_speech_permission", beginEntersRequestingSpeechPermission},
        {"single generation permission sequence", singleGenerationPermissionSequence},
        {"out of order permission rejected", outOfOrderPermissionRejected},
        {"speech permission denied", speechPermissionDenied},
        {"microphone permission denied", microphonePermissionDenied},
        {"partial text update", partialTextUpdate},
        {"finalizing flow", finalizingFlow},
        {"final text completes session", finalTextCompletesSession},
        {"finalization timeout with partial text", finalizationTimeoutWithPartialText},
        {"finalization timeout with final text", finalizationTimeoutWithFinalText},
        {"finalizing error falls back to partial text", finalizingErrorFallsBackToPartialText},
        {"finalizing termination falls back to partial text", finalizingTerminationFallsBackToPartialText},
        {"listening error preserves failure", listeningErrorPreservesFailure},
        {"starting error preserves failure", startingErrorPreservesFailure},
        {"cancel invalidates pending results", cancelInvalidatesPendingResults},
        {"new begin invalidates old generation", newBeginInvalidatesOldGeneration},
        {"stale generation cannot update text", staleGenerationCannotUpdateText},
        {"stale generation cannot update final text", staleGenerationCannotUpdateFinalText},
        {"failed session cannot receive final text", failedSessionCannotReceiveFinalText},
        {"idle session rejects text updates", idleSessionRejectsTextUpdates},
        {"finalization timeout constant exists", finalizationTimeoutConstantExists},
        {"generation wrap around", generationWrapAround},
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
    std::cout << "All " << tests.size() << " tests passed\n";
    return 0;
}
