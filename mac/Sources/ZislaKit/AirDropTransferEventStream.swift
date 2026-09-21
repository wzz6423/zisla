import Foundation

@objc private protocol AirDropInvocationRPC {
    @objc(invoke:parametersData:parametersAsyncSequenceContainer:parametersBlocksContainer:sync:completion:)
    func invoke(
        _ invocation: AnyObject,
        parametersData: NSData,
        parametersAsyncSequenceContainer: AnyObject?,
        parametersBlocksContainer: AnyObject?,
        sync: Bool,
        completion: @escaping (NSData?, AnyObject?, AnyObject?, AnyObject?) -> Void
    )
}

@objc private protocol AirDropSequenceRPC {
    @objc(xpcMakeAsyncIteratorFor:completion:)
    func makeIterator(
        _ identifier: NSUUID,
        completion: @escaping (AnyObject?, AnyObject?, AnyObject?) -> Void
    )

    @objc(xpcNextWithCompletion:)
    func next(completion: @escaping (NSData?, AnyObject?) -> Void)
}

/// Only subscribes to receive-transfer metadata; never registers as the system's transfer presenter.
@MainActor
final class AirDropTransferEventStream {
    private struct Reply: @unchecked Sendable {
        var data: Data?
        var object: AnyObject?
        var sequence: AnyObject?
        var blocks: AnyObject?
        var failed: Bool = false
    }

    private let onEvent: @MainActor (Data) -> Void
    private let onUnavailable: @MainActor () -> Void
    private var connection: NSXPCConnection?
    private var sequence: AnyObject?
    private var iterator: AnyObject?
    private var nestedSequence: AnyObject?
    private var blocks: AnyObject?
    private var generation = UUID()

    init(
        onEvent: @escaping @MainActor (Data) -> Void,
        onUnavailable: @escaping @MainActor () -> Void
    ) {
        self.onEvent = onEvent
        self.onUnavailable = onUnavailable
    }

    func start() -> Bool {
        guard connection == nil else { return true }
        guard Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")?.load() == true,
            let invocationProtocol = NSProtocolFromString("SFXPCInvocationProtocol"),
            let sequenceProtocol = NSProtocolFromString("Sharing._SFXPCAsyncSequenceContainerProtocol"),
            let iteratorProtocol = NSProtocolFromString("Sharing._SFXPCAsyncIteratorProtocol"),
            let blockProtocol = NSProtocolFromString("_SFXPCBlockContainerProtocol"),
            let invocationClass = NSClassFromString("SFAirDropInvocationTransfersMonitor") as? NSSecureCoding.Type
        else { return false }

        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode("TransfersMonitor", forKey: "name")
        archive.finishEncoding()
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: archive.encodedData),
            let invocation = invocationClass.init(coder: coder)
        else { return false }
        coder.finishDecoding()

        let remote = NSXPCInterface(with: invocationProtocol)
        let sequenceInterface = NSXPCInterface(with: sequenceProtocol)
        let iteratorInterface = NSXPCInterface(with: iteratorProtocol)
        let blockInterface = NSXPCInterface(with: blockProtocol)
        let invoke = #selector(AirDropInvocationRPC.invoke)
        let makeIterator = #selector(AirDropSequenceRPC.makeIterator)
        for interface in [remote, blockInterface] {
            interface.setInterface(sequenceInterface, for: invoke, argumentIndex: 2, ofReply: false)
            interface.setInterface(blockInterface, for: invoke, argumentIndex: 3, ofReply: false)
            interface.setInterface(sequenceInterface, for: invoke, argumentIndex: 1, ofReply: true)
            interface.setInterface(blockInterface, for: invoke, argumentIndex: 2, ofReply: true)
        }
        sequenceInterface.setInterface(iteratorInterface, for: makeIterator, argumentIndex: 0, ofReply: true)
        sequenceInterface.setInterface(sequenceInterface, for: makeIterator, argumentIndex: 1, ofReply: true)
        sequenceInterface.setInterface(blockInterface, for: makeIterator, argumentIndex: 2, ofReply: true)

        generation = UUID()
        let session = generation
        let connection = NSXPCConnection(machServiceName: "com.apple.sharing.airdrop.service")
        connection.remoteObjectInterface = remote
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.stop(session: session) }
        }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.stop(session: session) }
        }
        self.connection = connection
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async { self?.stop(session: session) }
        } as AnyObject
        proxy.invoke?(
            invocation as AnyObject,
            parametersData: Data("{}".utf8) as NSData,
            parametersAsyncSequenceContainer: nil,
            parametersBlocksContainer: nil,
            sync: false
        ) { [weak self] data, sequence, blocks, error in
            let reply = Reply(data: data as Data?, object: sequence, blocks: blocks, failed: error != nil)
            DispatchQueue.main.async {
                self?.makeIterator(reply: reply, session: session)
            }
        }
        return true
    }

    func stop() {
        generation = UUID()
        connection?.invalidate()
        connection = nil
        iterator = nil
        sequence = nil
        nestedSequence = nil
        blocks = nil
    }

    private func stop(session: UUID) {
        guard session == generation else { return }
        stop()
        onUnavailable()
    }

    private func makeIterator(reply: Reply, session: UUID) {
        guard session == generation else { return }
        guard !reply.failed, let data = reply.data, let sequence = reply.object,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let identifier = payload["uuid"].flatMap(NSUUID.init(uuidString:))
        else { stop(session: session); return }

        // The container must outlive the asynchronous request, or XPC releases the remote iterator.
        self.sequence = sequence
        self.blocks = reply.blocks
        sequence.makeIterator?(identifier) { [weak self] iterator, sequence, blocks in
            let reply = Reply(object: iterator, sequence: sequence, blocks: blocks)
            DispatchQueue.main.async {
                guard let self, session == self.generation else { return }
                guard let iterator = reply.object else { self.stop(session: session); return }
                self.iterator = iterator
                self.nestedSequence = reply.sequence
                self.blocks = reply.blocks
                self.readNext(session: session)
            }
        }
    }

    private func readNext(session: UUID) {
        guard session == generation, let iterator else { return }
        iterator.next? { [weak self] data, error in
            let reply = Reply(data: data as Data?, failed: error != nil)
            DispatchQueue.main.async {
                guard let self, session == self.generation else { return }
                guard !reply.failed, let data = reply.data else { self.stop(session: session); return }
                self.onEvent(data)
                self.readNext(session: session)
            }
        }
    }
}
