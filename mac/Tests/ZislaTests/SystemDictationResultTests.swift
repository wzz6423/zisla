import Foundation
import Testing

@testable import Zisla

struct SystemDictationResultTests {
    @Test
    func completionWaitsForLastTranscriptUpdate() async {
        guard #available(macOS 26.0, *) else { return }
        let input = AsyncThrowingStream<String, Error>.makeStream()
        let events = AsyncStream<String>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        input.continuation.yield("最终转写，保留尾字。")
        input.continuation.finish()

        let task = SystemDictationSession.makeResultsTask(
            for: input.stream,
            onResult: { @MainActor text in
                events.continuation.yield("started")
                for await _ in release.stream { break }
                events.continuation.yield(text)
            },
            onError: { _ in Issue.record("Unexpected recognition failure") }
        )
        let completion = Task {
            await task.value
            events.continuation.yield("completed")
            events.continuation.finish()
        }
        var iterator = events.stream.makeAsyncIterator()
        #expect(await iterator.next() == "started")
        release.continuation.yield(())
        release.continuation.finish()
        #expect(await iterator.next() == "最终转写，保留尾字。")
        #expect(await iterator.next() == "completed")
        await completion.value
    }

    @Test
    func recognitionFailureFollowsPendingTranscriptUpdates() async {
        guard #available(macOS 26.0, *) else { return }
        let input = AsyncThrowingStream<String, Error>.makeStream()
        let events = AsyncStream<String>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        input.continuation.yield("partial")
        input.continuation.yield("final")
        input.continuation.finish(throwing: RecognitionFailure.unavailable)

        let task = SystemDictationSession.makeResultsTask(
            for: input.stream,
            onResult: { @MainActor text in
                if text == "partial" {
                    events.continuation.yield("started")
                    for await _ in release.stream { break }
                }
                events.continuation.yield(text)
            },
            onError: { error in
                #expect(error is RecognitionFailure)
                events.continuation.yield("error")
            }
        )
        let completion = Task {
            await task.value
            events.continuation.finish()
        }
        var iterator = events.stream.makeAsyncIterator()
        #expect(await iterator.next() == "started")
        release.continuation.finish()
        #expect(await iterator.next() == "partial")
        #expect(await iterator.next() == "final")
        #expect(await iterator.next() == "error")
        await completion.value
    }

    @Test
    func cancellationDropsBufferedResultsAfterCurrentDelivery() async {
        guard #available(macOS 26.0, *) else { return }
        let input = AsyncThrowingStream<String, Error>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let events = AsyncStream<String>.makeStream()
        input.continuation.yield("current")
        input.continuation.yield("stale")
        input.continuation.finish()
        let task = SystemDictationSession.makeResultsTask(
            for: input.stream,
            onResult: { text in
                events.continuation.yield(text)
                started.continuation.yield(())
                for await _ in release.stream { break }
            },
            onError: { _ in Issue.record("Cancellation must not be reported as a recognition error") }
        )
        for await _ in started.stream { break }
        task.cancel()
        release.continuation.finish()
        await task.value
        started.continuation.finish()
        events.continuation.finish()
        var received: [String] = []
        for await event in events.stream { received.append(event) }
        #expect(received == ["current"])
    }

    @Test
    func emptyAndCancelledStreamsProduceNoTranscriptOrError() async {
        guard #available(macOS 26.0, *) else { return }
        for error: Error? in [nil, CancellationError()] {
            let input = AsyncThrowingStream<String, Error>.makeStream()
            input.continuation.finish(throwing: error)
            await SystemDictationSession.makeResultsTask(
                for: input.stream,
                onResult: { _ in Issue.record("Unexpected transcript") },
                onError: { _ in Issue.record("Unexpected recognition error") }
            ).value
        }
    }

    private enum RecognitionFailure: Error {
        case unavailable
    }
}
