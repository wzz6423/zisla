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
    func longQueueRemainsFIFOWhileGrowingAndWrapping() async {
        let queue = VoicePostProcessingQueue()
        var events: [Int] = []
        let firstStarted = VoicePostProcessingQueueTestGate()
        let releaseFirst = VoicePostProcessingQueueTestGate()
        let completed = VoicePostProcessingQueueTestGate()

        for index in 0...3 {
            queue.enqueue {
                events.append(index)
                if index == 1 {
                    await firstStarted.signal()
                    await releaseFirst.wait()
                }
            }
        }
        await firstStarted.wait()

        for index in 4...128 {
            queue.enqueue {
                events.append(index)
                if index == 128 {
                    await completed.signal()
                }
            }
        }
        await releaseFirst.signal()
        await completed.wait()

        #expect(events == Array(0...128))
    }

    @Test
    func cancelAllCancelsCurrentWorkAndDropsPendingWork() async {
        let queue = VoicePostProcessingQueue()
        let cancellationGate = VoicePostProcessingQueueTestGate()
        let releaseGate = VoicePostProcessingQueueTestGate()
        let completedGate = VoicePostProcessingQueueTestGate()
        var cancellationObserved = false
        var pendingOperationRan = false

        await withCheckedContinuation { started in
            queue.enqueue {
                started.resume()
                await withTaskCancellationHandler {
                    await releaseGate.wait()
                } onCancel: {
                    Task { await cancellationGate.signal() }
                }
                cancellationObserved = Task.isCancelled
                await completedGate.signal()
            }
            queue.enqueue {
                pendingOperationRan = true
            }
        }

        queue.cancelAll()
        await cancellationGate.wait()
        await releaseGate.signal()
        await completedGate.wait()

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
                await withTaskCancellationHandler {
                    await releaseGate.wait()
                } onCancel: {
                    Task { await cancellationGate.signal() }
                }
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
