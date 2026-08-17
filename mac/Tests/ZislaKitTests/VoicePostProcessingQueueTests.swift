import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct VoicePostProcessingQueueTests {
    @Test
    func slowOperationDoesNotDropTheNextRecording() async {
        let queue = VoicePostProcessingQueue()
        var events: [String] = []

        await withCheckedContinuation { completion in
            queue.enqueue {
                events.append("first-start")
                try? await Task.sleep(for: .milliseconds(30))
                events.append("first-end")
            }
            queue.enqueue {
                events.append("second")
                completion.resume()
            }
        }

        #expect(events == ["first-start", "first-end", "second"])
    }

    @Test
    func recordingsEnqueuedDuringProcessingStayFIFO() async {
        let queue = VoicePostProcessingQueue()
        var events: [Int] = []

        await withCheckedContinuation { completion in
            queue.enqueue {
                events.append(1)
                queue.enqueue {
                    events.append(3)
                    completion.resume()
                }
            }
            queue.enqueue {
                events.append(2)
            }
        }

        #expect(events == [1, 2, 3])
    }

    @Test
    func cancelAllCancelsCurrentWorkAndDropsPendingWork() async throws {
        let queue = VoicePostProcessingQueue()
        var cancellationObserved = false
        var pendingOperationRan = false

        await withCheckedContinuation { started in
            queue.enqueue {
                started.resume()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError {
                    cancellationObserved = true
                } catch {}
            }
            queue.enqueue {
                pendingOperationRan = true
            }
        }

        queue.cancelAll()
        try await Task.sleep(for: .milliseconds(20))

        #expect(cancellationObserved)
        #expect(!pendingOperationRan)
    }
}
