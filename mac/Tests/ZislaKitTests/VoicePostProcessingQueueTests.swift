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
    func longQueueRemainsFIFOWhileCompacting() async {
        let queue = VoicePostProcessingQueue()
        var events: [Int] = []

        await withCheckedContinuation { completion in
            for index in 0..<128 {
                queue.enqueue {
                    events.append(index)
                    if index == 127 {
                        completion.resume()
                    }
                }
            }
        }

        #expect(events == Array(0..<128))
    }

    @Test
    func cancelAllCancelsCurrentWorkAndDropsPendingWork() async throws {
        let queue = VoicePostProcessingQueue()
        let cancellationGate = VoicePostProcessingQueueTestGate()
        var cancellationObserved = false
        var pendingOperationRan = false

        await withCheckedContinuation { started in
            queue.enqueue {
                started.resume()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError {
                    cancellationObserved = true
                    await cancellationGate.signal()
                } catch {}
            }
            queue.enqueue {
                pendingOperationRan = true
            }
        }

        queue.cancelAll()
        await cancellationGate.wait()

        #expect(cancellationObserved)
        #expect(!pendingOperationRan)
    }

    @Test
    func cancelAllWaitsForCurrentWorkBeforeStartingNewGeneration() async {
        let queue = VoicePostProcessingQueue()
        let cancellationGate = VoicePostProcessingQueueTestGate()
        let releaseGate = VoicePostProcessingQueueTestGate()
        let secondOperationGate = VoicePostProcessingQueueTestGate()
        var pendingOperationRan = false

        await withCheckedContinuation { started in
            queue.enqueue {
                started.resume()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError {
                    await cancellationGate.signal()
                    await releaseGate.wait()
                } catch {}
            }
        }

        queue.cancelAll()
        queue.enqueue {
            pendingOperationRan = true
            await secondOperationGate.signal()
        }
        await cancellationGate.wait()
        #expect(!pendingOperationRan)

        await releaseGate.signal()
        await secondOperationGate.wait()
        #expect(pendingOperationRan)
    }
}

private actor VoicePostProcessingQueueTestGate {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isSignaled {
            isSignaled = false
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            isSignaled = true
        }
    }
}
