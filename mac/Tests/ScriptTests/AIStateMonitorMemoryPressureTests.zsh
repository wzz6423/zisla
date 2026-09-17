#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
MONITOR_SOURCE="${1:-$ROOT/Sources/ZislaKit/AIStateMonitor.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-memory-pressure-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

HANDLER="$(sed -n '/memoryPressure.setEventHandler/,/memoryPressureSource = memoryPressure/p' "$MONITOR_SOURCE" | sed '$d')"
[[ -n "$HANDLER" ]] || { print -u2 'Memory-pressure handler was not found'; exit 1; }

# Keep the production callback and actor context, replacing only the system event
# with a synthetic source that uses the same DispatchSourceProtocol entry point.
cat > "$TEST_ROOT/MemoryPressureProbe.swift" <<EOF
import Darwin
import Dispatch

func isolationTrap(_ signal: Int32) { _exit(86) }

@MainActor
final class AIStateMonitor {
    nonisolated static let relief = DispatchSemaphore(value: 0)
    let refreshQueue = DispatchQueue(label: "zisla.memory-pressure-regression")

    func start() -> any DispatchSourceUserDataAdd {
        let pressureQueue = refreshQueue
        let memoryPressure = DispatchSource.makeUserDataAddSource(queue: pressureQueue)
$HANDLER
        memoryPressure.resume()
        return memoryPressure
    }

    nonisolated static func scheduleAllocatorRelief(on queue: DispatchQueue) {
        dispatchPrecondition(condition: .onQueue(queue))
        relief.signal()
    }
}

@main
struct MemoryPressureProbe {
    @MainActor static func main() {
        signal(SIGTRAP, isolationTrap)
        alarm(10)
        let monitor = AIStateMonitor()
        let source = monitor.start()
        let canceled = DispatchSemaphore(value: 0)
        source.setCancelHandler { @Sendable in canceled.signal() }

        for _ in 0..<8 {
            source.add(data: 1)
            guard AIStateMonitor.relief.wait(timeout: .now() + 2) == .success else { _exit(87) }
        }
        source.cancel()
        guard canceled.wait(timeout: .now() + 2) == .success else { _exit(88) }
        monitor.refreshQueue.sync {}
        guard AIStateMonitor.relief.wait(timeout: .now()) == .timedOut else { _exit(89) }
        print("PASS: 8 background callbacks completed; source canceled without pending callbacks")
    }
}
EOF

xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/MemoryPressureProbe.swift" -o "$TEST_ROOT/MemoryPressureProbe"

PROBE_RESULT=0
"$TEST_ROOT/MemoryPressureProbe" || PROBE_RESULT=$?
if (( PROBE_RESULT != 0 )); then
  print -u2 "FAIL: memory-pressure callback exited $PROBE_RESULT (86=SIGTRAP, 87=callback timeout, 88=cancel timeout, 89=pending callback)"
  exit 1
fi
