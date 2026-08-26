import Foundation

struct MediaRemoteAdapterEvent: Decodable, Sendable {
    var type: String
    var diff: Bool
    var payload: MediaRemoteAdapterPayload
}

struct MediaRemoteAdapterPayload: Decodable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: String?
    var duration: Double?
    var elapsedTime: Double?
    var timestamp: String?
    var playing: Bool?
    var playbackRate: Double?
    var processIdentifier: pid_t?
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var mediaType: String?
    var isVideosApp: Bool?
    var repeatMode: Int?
    var shuffleMode: Int?
    var isInWishList: Bool?
    var isLiked: Bool?
    var supportsWishlisting: Bool?
    var supportsIsLiked: Bool?
}

@MainActor
final class MediaRemoteAdapterClient {
    private let commandQueue = DispatchQueue(label: "dev.wzz.zisla.media-command")
    private var listener: Process?
    private var listenerPipe: Pipe?
    private var listenerToken: UUID?
    private var commandProcesses: [UUID: Process] = [:]

    var isListening: Bool {
        listener?.isRunning == true
    }

    func start(
        onEvent: @escaping @MainActor (MediaRemoteAdapterEvent) -> Void,
        onTermination: @escaping @MainActor () -> Void
    ) -> Bool {
        if isListening { return true }
        guard let resources = MediaRemoteAdapterResources.locate() else { return false }

        let token = UUID()
        let pipe = Pipe()
        let decoder = MediaRemoteAdapterStreamDecoder { event in
            Task { @MainActor in onEvent(event) }
        }
        let process = Self.configuredProcess(
            resources: resources,
            arguments: ["stream", "--no-diff", "--debounce=80"]
        )
        process.standardOutput = pipe
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.listenerToken == token else { return }
                self.listener = nil
                self.listenerPipe = nil
                self.listenerToken = nil
                onTermination()
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { await decoder.append(data) }
        }

        do {
            try process.run()
            listener = process
            listenerPipe = pipe
            listenerToken = token
            return true
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return false
        }
    }

    func stop() {
        listenerToken = nil
        listenerPipe?.fileHandleForReading.readabilityHandler = nil
        if listener?.isRunning == true { listener?.terminate() }
        listener = nil
        listenerPipe = nil

        for process in commandProcesses.values where process.isRunning {
            process.terminate()
        }
        commandProcesses.removeAll()
    }

    func run(_ arguments: [String]) -> Bool {
        guard let resources = MediaRemoteAdapterResources.locate() else { return false }
        let token = UUID()
        let process = Self.configuredProcess(resources: resources, arguments: arguments)
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.commandProcesses.removeValue(forKey: token)
            }
        }
        commandProcesses[token] = process
        do {
            try process.run()
            return true
        } catch {
            commandProcesses.removeValue(forKey: token)
            return false
        }
    }

    func fetchNowPlayingInfo(
        completion: @escaping @MainActor (MediaRemoteAdapterPayload?) -> Void
    ) -> Bool {
        guard let resources = MediaRemoteAdapterResources.locate() else { return false }
        commandQueue.async {
            let output = try? AIAgentProcessRunner.runSynchronously(
                executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                arguments: [resources.scriptURL.path, resources.frameworkURL.path, "get"],
                standardInput: Data(),
                workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                timeout: 15,
                maximumOutputBytes: 16 * 1_024 * 1_024,
                maximumErrorBytes: 64 * 1_024
            )
            let payload = output.flatMap {
                !$0.didTimeout && $0.status == 0
                    ? Self.decodeNowPlayingInfo($0.standardOutput)
                    : nil
            }
            Task { @MainActor in completion(payload) }
        }
        return true
    }

    func runSequence(
        _ commands: [[String]],
        completion: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        guard !commands.isEmpty,
              let resources = MediaRemoteAdapterResources.locate() else { return false }
        commandQueue.async {
            var succeeded = true
            for arguments in commands {
                let output = try? AIAgentProcessRunner.runSynchronously(
                    executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                    arguments: [resources.scriptURL.path, resources.frameworkURL.path] + arguments,
                    standardInput: Data(),
                    workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                    timeout: 15,
                    maximumOutputBytes: 1,
                    maximumErrorBytes: 64 * 1_024
                )
                guard let output,
                      !output.didTimeout,
                      output.status == 0 else {
                    succeeded = false
                    break
                }
            }
            Task { @MainActor in completion(succeeded) }
        }
        return true
    }

    nonisolated private static func configuredProcess(
        resources: MediaRemoteAdapterResources,
        arguments: [String]
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.scriptURL.path, resources.frameworkURL.path] + arguments
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        return process
    }

    nonisolated static func decodeNowPlayingInfo(_ data: Data) -> MediaRemoteAdapterPayload? {
        try? JSONDecoder().decode(MediaRemoteAdapterPayload.self, from: data)
    }
}

private actor MediaRemoteAdapterStreamDecoder {
    private var buffer = Data()
    private let onEvent: @Sendable (MediaRemoteAdapterEvent) -> Void

    init(onEvent: @escaping @Sendable (MediaRemoteAdapterEvent) -> Void) {
        self.onEvent = onEvent
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let event = try? JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: line)
            else { continue }
            onEvent(event)
        }
    }
}

private struct MediaRemoteAdapterResources: Sendable {
    var scriptURL: URL
    var frameworkURL: URL

    static func locate() -> Self? {
        let fileManager = FileManager.default
        if let scriptURL = Bundle.main.resourceURL?
            .appendingPathComponent("MediaRemoteAdapter/mediaremote-adapter.pl"),
           let frameworkURL = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("MediaRemoteAdapter.framework"),
           fileManager.fileExists(atPath: scriptURL.path),
           fileManager.fileExists(atPath: frameworkURL.path) {
            return Self(scriptURL: scriptURL, frameworkURL: frameworkURL)
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root.appendingPathComponent(
            "Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
        )
        let frameworkURL = root.appendingPathComponent("Vendor/MediaRemoteAdapter.framework")
        guard fileManager.fileExists(atPath: scriptURL.path),
              fileManager.fileExists(atPath: frameworkURL.path) else { return nil }
        return Self(scriptURL: scriptURL, frameworkURL: frameworkURL)
    }
}
