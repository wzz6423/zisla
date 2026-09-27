#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
STREAM_SOURCE="${1:-$ROOT/Sources/ZislaKit/AirDropTransferEventStream.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-airdrop-callback-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$STREAM_SOURCE" "$TEST_ROOT/AirDropCallbackProbe.swift" <<'PYTHON'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
setup = source.index('        guard Bundle(path:')
callbacks = source.index('        generation = UUID()', setup)
# Keep the production callbacks while replacing private framework loading and XPC transport.
source = source[:setup] + '        let invocation = NSObject()\n        let remote = NSObject()\n' + source[callbacks:]
source = source.replace('NSXPCConnection', 'FakeXPCConnection')

Path(sys.argv[2]).write_text(source + r'''
import Darwin

func isolationTrap(_ signal: Int32) { _exit(86) }

private final class CallbackBox<Callback>: @unchecked Sendable {
    let call: Callback
    init(_ call: Callback) { self.call = call }
}

private final class FakeXPCConnection {
    @MainActor static var latest: FakeXPCConnection?
    var remoteObjectInterface: AnyObject?
    // Preserve the legacy SDK's unannotated callback types.
    var interruptionHandler: (() -> Void)?
    var invalidationHandler: (() -> Void)?
    var errorHandler: ((Error) -> Void)?
    let remote = FakeRemote()
    var invalidations = 0

    @MainActor init(machServiceName: String) { Self.latest = self }
    func resume() {}
    func invalidate() { invalidations += 1 }
    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> AnyObject {
        errorHandler = handler
        return remote
    }
}

private final class FakeRemote: NSObject, AirDropInvocationRPC, AirDropSequenceRPC, @unchecked Sendable {
    var invocationReply: CallbackBox<(NSData?, AnyObject?, AnyObject?, AnyObject?) -> Void>?
    var iteratorReply: CallbackBox<(AnyObject?, AnyObject?, AnyObject?) -> Void>?
    var nextReply: CallbackBox<(NSData?, AnyObject?) -> Void>?

    func invoke(
        _ invocation: AnyObject, parametersData: NSData,
        parametersAsyncSequenceContainer: AnyObject?, parametersBlocksContainer: AnyObject?,
        sync: Bool, completion: @escaping (NSData?, AnyObject?, AnyObject?, AnyObject?) -> Void
    ) {
        invocationReply = CallbackBox(completion)
    }
    func makeIterator(_ identifier: NSUUID, completion: @escaping (AnyObject?, AnyObject?, AnyObject?) -> Void) {
        iteratorReply = CallbackBox(completion)
    }
    func next(completion: @escaping (NSData?, AnyObject?) -> Void) { nextReply = CallbackBox(completion) }
}

@main struct AirDropCallbackProbe {
    @MainActor static func main() async {
        signal(SIGTRAP, isolationTrap)
        alarm(10)
        let mode = CommandLine.arguments[1]
        let error = NSError(domain: "AirDropCallbackFixture", code: 1)
        let identifier = Data("{\"uuid\":\"00000000-0000-0000-0000-000000000001\"}".utf8)
        var events: [Data] = []
        var unavailable = 0
        let stream = AirDropTransferEventStream(onEvent: {
            dispatchPrecondition(condition: .onQueue(.main))
            events.append($0)
        }, onUnavailable: {
            dispatchPrecondition(condition: .onQueue(.main))
            unavailable += 1
        })
        require(stream.start(), "the fake transport must start")
        let connection = required(FakeXPCConnection.latest, "connection was not created")
        let invoke = required(connection.remote.invocationReply, "invocation was not requested")
        let sequence = FakeRemote()
        let iterator = FakeRemote()

        switch mode {
        case "interruption":
            let callback = CallbackBox(required(connection.interruptionHandler, "interruption handler was not installed"))
            await background { callback.call() }
        case "invalidation":
            let callback = CallbackBox(required(connection.invalidationHandler, "invalidation handler was not installed"))
            await background { callback.call() }
        case "proxy-error":
            let callback = CallbackBox(required(connection.errorHandler, "proxy error handler was not installed"))
            await background { callback.call(error) }
        default:
            await background {
                invoke.call(
                    (mode == "malformed-invocation" ? Data("invalid".utf8) : identifier) as NSData,
                    mode == "missing-sequence" ? nil : sequence,
                    nil, mode == "invocation-error" ? error : nil
                )
            }
            if mode == "malformed-invocation" || mode == "missing-sequence" || mode == "invocation-error" { break }
            let makeIterator = required(sequence.iteratorReply, "iterator was not requested after the invocation reply")
            await background { makeIterator.call(mode == "missing-iterator" ? nil : iterator, nil, nil) }
            if mode == "missing-iterator" { break }
            let next = required(iterator.nextReply, "the event stream was not requested after the iterator reply")
            if mode == "next-error" || mode == "missing-event" {
                await background { next.call(nil, mode == "next-error" ? error : nil) }
                break
            }

            if mode == "stale" {
                let interrupted = CallbackBox(required(connection.interruptionHandler, "missing interruption handler"))
                let invalidated = CallbackBox(required(connection.invalidationHandler, "missing invalidation handler"))
                let proxyError = CallbackBox(required(connection.errorHandler, "missing proxy error handler"))
                stream.stop()
                require(stream.start(), "the stream must restart after stop")
                let restarted = required(FakeXPCConnection.latest, "restart did not create a connection")
                await background { interrupted.call(); invalidated.call(); proxyError.call(error) }
                await background { invoke.call(identifier as NSData, sequence, nil, nil) }
                await background { makeIterator.call(iterator, nil, nil) }
                await background { next.call(Data("stale".utf8) as NSData, nil) }
                require(events.isEmpty && unavailable == 0, "stale callbacks must not publish or stop the new stream")
                require(restarted.invalidations == 0, "stale callbacks invalidated the new connection")
                let freshInvoke = required(restarted.remote.invocationReply, "restart did not request a new invocation")
                await background { freshInvoke.call(identifier as NSData, sequence, nil, nil) }
                let freshIterator = required(sequence.iteratorReply, "restart did not request an iterator")
                await background { freshIterator.call(iterator, nil, nil) }
            }

            for payload in [Data(), Data("{\"transfer\":\"fixture\"}".utf8)] {
                let receive = required(iterator.nextReply, "the stream must keep requesting events")
                iterator.nextReply = nil
                await background { receive.call(payload as NSData, nil) }
            }
            require(events == [Data(), Data("{\"transfer\":\"fixture\"}".utf8)], "event payloads must arrive intact and in order")
            require(iterator.nextReply != nil, "the event stream did not continue after a reply")
        }

        if mode == "stream" || mode == "stale" {
            require(unavailable == 0, "successful or stale replies must not report an unavailable service")
        } else {
            require(events.isEmpty && unavailable == 1, "transport failures must stop once without publishing an event")
            require(connection.invalidations == 1, "transport failures must invalidate the connection")
        }
        stream.stop()
        require(FakeXPCConnection.latest?.invalidations == 1, "stop must release the active connection exactly once")
        print("PASS: AirDrop callback \(mode)")
    }

    @MainActor static func background(_ action: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { finished in
            DispatchQueue.global().async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                action()
                finished.resume()
            }
        }
        await withCheckedContinuation { finished in
            DispatchQueue.main.async { finished.resume() }
        }
    }
    static func required<T>(_ value: T?, _ message: String) -> T {
        guard let value else { fail(message) }
        return value
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        _exit(87)
    }
}
''')
PYTHON

xcrun swiftc -swift-version 6 -parse-as-library -Xfrontend -enable-actor-data-race-checks \
  -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/AirDropCallbackProbe.swift" -o "$TEST_ROOT/AirDropCallbackProbe"

for mode in stream interruption invalidation proxy-error invocation-error malformed-invocation missing-sequence missing-iterator next-error missing-event stale; do
  result=0
  "$TEST_ROOT/AirDropCallbackProbe" "$mode" || result=$?
  if (( result != 0 )); then
    print -u2 -- "FAIL: AirDrop callback $mode exited $result (86=actor-isolation SIGTRAP, 87=behavior assertion)"
    exit 1
  fi
done
