import Darwin
import Foundation
import ZislaCore

/// Reads recorded token usage from the structured session logs of local AI tools.
/// Only parses numeric usage fields; does not read or persist session content.
public final class AIUsageLogDetector: AIUsageDetecting {
    private struct TokenUsage {
        var input: Int
        var output: Int
    }

    private struct Candidate {
        var provider: AIProvider
        var url: URL
        var modificationDate: Date
        var changeDate: Date?
        var size: UInt64
    }

    private struct CachedSamples {
        var modificationDate: Date
        var changeDate: Date?
        var size: UInt64
        var samples: [AIUsageSample]
        var readerState: IncrementalJSONLReader.State?
        var parserState: ParserState?
        var contentHash: UInt64?
        var edgeHash: UInt64?
    }

    private struct ParserState {
        var codexPriorTotal: TokenUsage?
        var grokPriorUsageBySession: [String: TokenUsage] = [:]
        var copilotHasDetailedUsage = false
    }

    private struct LogData {
        var data: Data
    }

    public let codexSessionsDirectory: URL
    public let claudeProjectsDirectory: URL
    public let geminiSessionsDirectory: URL
    public let grokSessionsDirectory: URL
    public let qwenProjectsDirectory: URL
    public let piSessionsDirectory: URL
    public let qoderRoots: [URL]
    public let doubaoRoots: [URL]
    public let copilotUsageLogRoots: [URL]
    public let maxFilesPerProvider: Int
    public let maxBytesPerFile: Int
    public let maxSamplesPerFile: Int

    private let fileManager: FileManager
    private let scanInterval: TimeInterval
    private var cache: [String: CachedSamples] = [:]
    private var lastScanAt: Date = .distantPast

    private static let contentHashOffset: UInt64 = 14_695_981_039_346_656_037
    private static let contentHashPrime: UInt64 = 1_099_511_628_211
    static let incrementalVerificationBytes = 4 * 1_024

    static func incrementalVerificationByteCount(for fileSize: UInt64) -> UInt64 {
        guard fileSize > 0 else { return 0 }
        let bytesPerEdge = incrementalVerificationBytesPerEdge(for: fileSize)
        return fileSize > bytesPerEdge ? bytesPerEdge * 2 : bytesPerEdge
    }

    private static func incrementalVerificationBytesPerEdge(for fileSize: UInt64) -> UInt64 {
        min(UInt64(incrementalVerificationBytes), max(1, fileSize / 2))
    }

    public init(
        codexSessionsDirectory: URL? = nil,
        claudeProjectsDirectory: URL? = nil,
        geminiSessionsDirectory: URL? = nil,
        grokSessionsDirectory: URL? = nil,
        qwenProjectsDirectory: URL? = nil,
        piSessionsDirectory: URL? = nil,
        qoderRoots: [URL]? = nil,
        doubaoRoots: [URL]? = nil,
        copilotUsageLogRoots: [URL]? = nil,
        maxFilesPerProvider: Int = .max,
        maxBytesPerFile: Int = .max,
        maxSamplesPerFile: Int = .max,
        scanInterval: TimeInterval = 60,
        fileManager: FileManager = .default
    ) {
        let home = fileManager.homeDirectoryForCurrentUser
        self.codexSessionsDirectory = codexSessionsDirectory
            ?? home.appendingPathComponent(".codex/sessions", isDirectory: true)
        self.claudeProjectsDirectory = claudeProjectsDirectory
            ?? home.appendingPathComponent(".claude/projects", isDirectory: true)
        self.geminiSessionsDirectory = geminiSessionsDirectory
            ?? home.appendingPathComponent(".gemini/tmp", isDirectory: true)
        self.grokSessionsDirectory = grokSessionsDirectory
            ?? home.appendingPathComponent(".grok/sessions", isDirectory: true)
        self.qwenProjectsDirectory = qwenProjectsDirectory
            ?? home.appendingPathComponent(".qwen/projects", isDirectory: true)
        self.piSessionsDirectory = piSessionsDirectory
            ?? home.appendingPathComponent(".pi/agent/sessions", isDirectory: true)
        self.qoderRoots = qoderRoots
            ?? QoderSessionActivityDetector.defaultConfigRoots(home: home, fileManager: fileManager)
        self.doubaoRoots = doubaoRoots
            ?? DoubaoSessionActivityDetector.defaultDataRoots(home: home, fileManager: fileManager)
        self.copilotUsageLogRoots = copilotUsageLogRoots ?? [
            home.appendingPathComponent(".copilot/logs", isDirectory: true),
            home.appendingPathComponent(".copilot/diagnostics", isDirectory: true),
            home.appendingPathComponent(
                "Library/Application Support/Code/User/globalStorage/github.copilot-chat/diagnostics",
                isDirectory: true
            ),
            home.appendingPathComponent(
                "Library/Application Support/Code - Insiders/User/globalStorage/github.copilot-chat/diagnostics",
                isDirectory: true
            ),
        ]
        self.maxFilesPerProvider = max(1, maxFilesPerProvider)
        self.maxBytesPerFile = max(4_096, maxBytesPerFile)
        self.maxSamplesPerFile = max(1, maxSamplesPerFile)
        self.scanInterval = max(0, scanInterval)
        self.fileManager = fileManager
    }

    public func usageSamples() throws -> [AIUsageSample] {
        let now = Date()
        if now.timeIntervalSince(lastScanAt) < scanInterval {
            return uniqueSamples(cache.values.flatMap(\.samples))
        }
        lastScanAt = now
        let candidates = allCandidates()
        let keys = Set(candidates.map(cacheKey(for:)))
        cache = cache.filter { keys.contains($0.key) }

        var samples: [AIUsageSample] = []
        for candidate in candidates {
            let key = cacheKey(for: candidate)
            if let cached = cache[key],
                  cached.modificationDate == candidate.modificationDate,
               cached.changeDate == candidate.changeDate,
               cached.size == candidate.size {
                samples.append(contentsOf: cached.samples)
                continue
            }
            let updated = autoreleasepool {
                parsedSamples(for: candidate, cached: cache[key])
            }
            cache[key] = updated
            samples.append(contentsOf: updated.samples)
        }

        return uniqueSamples(samples)
    }

    private func uniqueSamples(_ samples: [AIUsageSample]) -> [AIUsageSample] {
        var unique: [String: AIUsageSample] = [:]
        for sample in samples {
            guard let sourceID = sample.sourceID else { continue }
            if let existing = unique[sourceID], existing.timestamp <= sample.timestamp {
                continue
            }
            unique[sourceID] = sample
        }
        return unique.values.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return ($0.sourceID ?? "") < ($1.sourceID ?? "")
        }
    }

    private func allCandidates() -> [Candidate] {
        var result: [Candidate] = []
        result.append(contentsOf: candidates(
            provider: .codex,
            root: codexSessionsDirectory
        ))
        result.append(contentsOf: candidates(
            provider: .claude,
            root: claudeProjectsDirectory
        ))
        result.append(contentsOf: candidates(
            provider: .gemini,
            root: geminiSessionsDirectory
        ))
        result.append(contentsOf: candidates(
            provider: .grok,
            root: grokSessionsDirectory
        ))
        result.append(contentsOf: candidates(
            provider: .qwen,
            root: qwenProjectsDirectory
        ))
        result.append(contentsOf: candidates(
            provider: .pi,
            root: piSessionsDirectory
        ))
        for root in qoderRoots {
            result.append(contentsOf: candidates(provider: .coder, root: root))
        }
        for root in doubaoRoots {
            result.append(contentsOf: candidates(provider: .doubao, root: root))
        }
        for root in copilotUsageLogRoots {
            result.append(contentsOf: candidates(provider: .copilot, root: root))
        }
        return result
    }

    private func candidates(provider: AIProvider, root: URL) -> [Candidate] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var result: [Candidate] = []
        for case let url as URL in enumerator {
            guard accepts(url, for: provider),
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
            result.append(Candidate(
                provider: provider,
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                changeDate: Self.fileChangeDate(for: url),
                size: UInt64(max(0, values.fileSize ?? 0))
            ))
        }

        return Array(result.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxFilesPerProvider))
    }

    private func accepts(_ url: URL, for provider: AIProvider) -> Bool {
        guard url.pathExtension == "jsonl" || url.pathExtension == "json" else { return false }
        switch provider {
        case .grok:
            return url.lastPathComponent == "updates.jsonl"
        case .gemini:
            return url.lastPathComponent.hasPrefix("session-")
        case .coder:
            return url.path.contains("/logs/sessions/")
        case .copilot:
            return true
        case .pi:
            return url.lastPathComponent.hasSuffix(".jsonl")
        case .kimi, .zcode, .trae, .opencode, .harness:
            return false
        case .codex, .claude, .qwen, .gpt, .doubao:
            return true
        }
    }

    private func parsedSamples(
        for candidate: Candidate,
        cached: CachedSamples?
    ) -> CachedSamples {
        if candidate.url.pathExtension == "jsonl" {
            return parseJSONL(candidate, cached: cached)
        }

        let samples = parse(candidate)
        return CachedSamples(
            modificationDate: candidate.modificationDate,
            changeDate: candidate.changeDate,
            size: candidate.size,
            samples: samples,
            readerState: nil,
            parserState: nil,
            contentHash: nil,
            edgeHash: nil
        )
    }

    private func parse(_ candidate: Candidate) -> [AIUsageSample] {
        guard let logData = trailingData(from: candidate) else { return [] }
        let roots = jsonRoots(from: logData.data, pathExtension: candidate.url.pathExtension)
        var samples: [AIUsageSample]
        switch candidate.provider {
        case .codex:
            var parserState = ParserState()
            samples = roots.flatMap { parseRoot(from: $0, candidate: candidate, parserState: &parserState) }
        case .claude:
            var parserState = ParserState()
            samples = roots.flatMap { parseRoot(from: $0, candidate: candidate, parserState: &parserState) }
        case .grok:
            var parserState = ParserState()
            samples = roots.flatMap { parseRoot(from: $0, candidate: candidate, parserState: &parserState) }
        case .gemini, .qwen, .coder, .gpt, .doubao, .copilot, .pi:
            var parserState = ParserState()
            samples = roots.flatMap { parseRoot(from: $0, candidate: candidate, parserState: &parserState) }
            if parserState.copilotHasDetailedUsage {
                samples.removeAll(where: isCopilotShutdownSummary)
            }
        case .kimi, .zcode, .trae, .opencode, .harness:
            return []
        }
        return Array(samples.suffix(maxSamplesPerFile))
    }

    private func parseJSONL(
        _ candidate: Candidate,
        cached: CachedSamples?
    ) -> CachedSamples {
        let cachedEdgeMatches: Bool = {
            guard let cached,
                  let cachedEdgeHash = cached.edgeHash,
                  cached.readerState?.offset == cached.size,
                  candidate.size > cached.size else {
                return false
            }
            return edgeHash(of: candidate.url, byteCount: cached.size) == cachedEdgeHash
        }()

        let canContinue = candidate.size > (cached?.size ?? 0) && cachedEdgeMatches
        var readerState: IncrementalJSONLReader.State
        var parserState: ParserState
        var samples: [AIUsageSample]
        var contentHash: UInt64

        if canContinue,
           let cached,
           let cachedReaderState = cached.readerState,
           let cachedParserState = cached.parserState,
           let cachedContentHash = cached.contentHash {
            readerState = cachedReaderState
            parserState = cachedParserState
            samples = cached.samples
            contentHash = cachedContentHash
        } else {
            readerState = IncrementalJSONLReader(initialTailBytes: .max)
                .initialState(fileSize: candidate.size)
            parserState = ParserState()
            samples = []
            contentHash = Self.contentHashOffset
        }

        let reader = IncrementalJSONLReader(
            initialTailBytes: .max,
            maximumLineBytes: maxBytesPerFile
        )
        do {
            let parseLine: (Data) -> Bool = { line in
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    return false
                }
                samples.append(contentsOf: self.parseRoot(
                    from: root,
                    candidate: candidate,
                    parserState: &parserState
                ))
                return true
            }
            try reader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState,
                onChunk: { chunk in
                    contentHash = Self.updateContentHash(contentHash, with: chunk)
                }
            ) { line in
                _ = parseLine(line)
            }
            readerState.consumePendingLineIfAccepted(parseLine)
        } catch {
            return cached ?? CachedSamples(
                modificationDate: candidate.modificationDate,
                changeDate: candidate.changeDate,
                size: candidate.size,
                samples: [],
                readerState: nil,
                parserState: nil,
                contentHash: nil,
                edgeHash: nil
            )
        }

        if parserState.copilotHasDetailedUsage {
            samples.removeAll(where: isCopilotShutdownSummary)
        }

        return CachedSamples(
            modificationDate: candidate.modificationDate,
            changeDate: candidate.changeDate,
            size: candidate.size,
            samples: Array(samples.suffix(maxSamplesPerFile)),
            readerState: readerState,
            parserState: parserState,
            contentHash: contentHash,
            edgeHash: edgeHash(of: candidate.url, byteCount: readerState.offset)
        )
    }

    private func parseRoot(
        from root: [String: Any],
        candidate: Candidate,
        parserState: inout ParserState
    ) -> [AIUsageSample] {
        switch candidate.provider {
        case .codex:
            return parseCodex(root, candidate: candidate, priorTotal: &parserState.codexPriorTotal).map { [$0] } ?? []
        case .claude:
            return parseClaude(root, candidate: candidate).map { [$0] } ?? []
        case .grok:
            return parseGrok(
                root,
                candidate: candidate,
                priorUsageBySession: &parserState.grokPriorUsageBySession
            ).map { [$0] } ?? []
        case .gemini, .qwen, .coder, .gpt, .doubao:
            return parseGeneric(root, candidate: candidate)
        case .copilot:
            return parseCopilot(root, candidate: candidate, parserState: &parserState)
        case .pi:
            return parsePi(root, candidate: candidate).map { [$0] } ?? []
        case .kimi, .zcode, .trae, .opencode, .harness:
            return []
        }
    }

    private func jsonRoots(from data: Data, pathExtension: String) -> [[String: Any]] {
        if pathExtension == "json",
           let object = try? JSONSerialization.jsonObject(with: data) {
            if let dictionary = object as? [String: Any] { return [dictionary] }
            return object as? [[String: Any]] ?? []
        }
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        return string.split(separator: "\n").compactMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    private func parseCodex(
        _ root: [String: Any],
        candidate: Candidate,
        priorTotal: inout TokenUsage?
    ) -> AIUsageSample? {
        guard root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else {
            return nil
        }

        let current: TokenUsage
        let permitsZero: Bool
        if let totalUsage = info["total_token_usage"] as? [String: Any] {
            let total = tokenUsage(totalUsage)
            if let priorTotal,
               total.input >= priorTotal.input,
               total.output >= priorTotal.output {
                current = TokenUsage(
                    input: total.input - priorTotal.input,
                    output: total.output - priorTotal.output
                )
            } else {
                current = total
            }
            priorTotal = total
            permitsZero = true
        } else {
            current = tokenUsage(usage)
            permitsZero = false
        }

        return usageSample(
            provider: .codex,
            sourceID: codexEventSourceID(candidate: candidate, root: root),
            timestamp: timestamp(in: root, fallback: candidate.modificationDate),
            inputTokens: current.input,
            outputTokens: current.output,
            costUSD: nil,
            model: nil,
            permitsZero: permitsZero
        )
    }

    private func parseClaude(_ root: [String: Any], candidate: Candidate) -> AIUsageSample? {
        guard root["type"] as? String == "assistant",
              let message = root["message"] as? [String: Any],
              let messageID = message["id"] as? String,
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }
        return sample(
            provider: .claude,
            sourceID: sourceID(candidate, component: "message-\(messageID)"),
            timestamp: timestamp(in: root, fallback: candidate.modificationDate),
            usage: usage,
            model: message["model"] as? String,
            includeCacheInputTokens: true
        )
    }

    private func parsePi(_ root: [String: Any], candidate: Candidate) -> AIUsageSample? {
        guard root["type"] as? String == "message",
              let message = root["message"] as? [String: Any],
              (message["role"] as? String)?.lowercased() == "assistant",
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }
        let input = AIUsageTokenMath.adding(
            AIUsageTokenMath.adding(integer(usage["input"]), integer(usage["cacheRead"])),
            integer(usage["cacheWrite"])
        )
        let output = integer(usage["output"])
        let messageID = (root["id"] as? String) ?? stableDigest(root)
        let cost = (usage["cost"] as? [String: Any]).flatMap { double($0["total"]) }
        return usageSample(
            provider: .pi,
            sourceID: sourceID(candidate, component: "message-\(messageID)"),
            timestamp: timestamp(in: root, fallback: candidate.modificationDate),
            inputTokens: input,
            outputTokens: output,
            costUSD: cost,
            model: message["model"] as? String
        )
    }

    private func parseGrok(
        _ root: [String: Any],
        candidate: Candidate,
        priorUsageBySession: inout [String: TokenUsage]
    ) -> AIUsageSample? {
        guard root["method"] as? String == "_x.ai/session/update",
              let params = root["params"] as? [String: Any],
              let sessionID = params["sessionId"] as? String,
              let update = params["update"] as? [String: Any],
              let promptID = update["prompt_id"] as? String,
              let usage = update["usage"] as? [String: Any] else {
            return nil
        }
        let current = TokenUsage(
            input: integer(usage["inputTokens"]),
            output: integer(usage["outputTokens"])
        )
        guard AIUsageTokenMath.adding(current.input, current.output) > 0 else { return nil }
        let prior = priorUsageBySession[sessionID] ?? TokenUsage(input: 0, output: 0)
        priorUsageBySession[sessionID] = TokenUsage(
            input: max(prior.input, current.input),
            output: max(prior.output, current.output)
        )
        let delta = [
            "inputTokens": max(0, current.input - prior.input),
            "outputTokens": max(0, current.output - prior.output),
        ]
        let model = (usage["modelUsage"] as? [String: Any])?.keys.sorted().first
        return sample(
            provider: .grok,
            sourceID: grokUpdateSourceID(
                candidate: candidate,
                promptID: promptID,
                root: root
            ),
            timestamp: timestamp(in: root, fallback: candidate.modificationDate),
            usage: delta,
            model: model
        )
    }

    private func parseCopilot(
        _ root: [String: Any],
        candidate: Candidate,
        parserState: inout ParserState
    ) -> [AIUsageSample] {
        let eventID = (root["id"] as? String) ?? stableDigest(root)
        let timestamp = timestamp(in: root, fallback: candidate.modificationDate)

        switch root["type"] as? String {
        case "assistant.usage":
            guard let data = root["data"] as? [String: Any] else { return [] }
            parserState.copilotHasDetailedUsage = true
            return copilotSample(
                sourceID: sourceID(candidate, component: "assistant-\(eventID)"),
                timestamp: timestamp,
                usage: data,
                model: data["model"] as? String
            ).map { [$0] } ?? []
        case "session.shutdown":
            guard !parserState.copilotHasDetailedUsage,
                  let data = root["data"] as? [String: Any],
                  let modelMetrics = data["modelMetrics"] as? [String: Any] else {
                return []
            }
            return modelMetrics.keys.sorted().compactMap { model in
                guard let metrics = modelMetrics[model] as? [String: Any],
                      let usage = metrics["usage"] as? [String: Any] else {
                    return nil
                }
                return copilotSample(
                    sourceID: sourceID(
                        candidate,
                        component: "shutdown-\(eventID)-model-\(stableDigest(model))"
                    ),
                    timestamp: timestamp,
                    usage: usage,
                    model: model
                )
            }
        default:
            let attributes: [String: Any]?
            if (root["name"] as? String)?.lowercased() == "llm_request" {
                attributes = root["attrs"] as? [String: Any]
            } else {
                attributes = ((root["llm_request"] as? [String: Any])?["attrs"] as? [String: Any])
            }
            guard let attributes else {
                return []
            }
            parserState.copilotHasDetailedUsage = true
            return copilotSample(
                sourceID: sourceID(candidate, component: "diagnostic-\(eventID)"),
                timestamp: timestamp,
                usage: attributes,
                model: attributes["model"] as? String
            ).map { [$0] } ?? []
        }
    }

    private func copilotSample(
        sourceID: String,
        timestamp: Date,
        usage: [String: Any],
        model: String?
    ) -> AIUsageSample? {
        let tokens = tokenUsage(usage)
        let inputTokens = AIUsageTokenMath.adding(
            AIUsageTokenMath.adding(tokens.input, integer(usage["cacheReadTokens"])),
            integer(usage["cacheWriteTokens"])
        )
        return usageSample(
            provider: .copilot,
            sourceID: sourceID,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: tokens.output,
            costUSD: double(usage["cost"]),
            model: model
        )
    }

    private func parseGeneric(_ root: [String: Any], candidate: Candidate) -> [AIUsageSample] {
        usageDictionaries(in: root).enumerated().compactMap { usageIndex, usage in
            sample(
                provider: candidate.provider,
                sourceID: sourceID(
                    candidate,
                    component: "entry-\(stableDigest(root))-usage-\(usageIndex)"
                ),
                timestamp: timestamp(in: root, fallback: candidate.modificationDate),
                usage: usage,
                model: model(in: root),
                includeCacheInputTokens: true
            )
        }
    }

    private func sample(
        provider: AIProvider,
        sourceID: String,
        timestamp: Date,
        usage: [String: Any],
        model: String?,
        includeCacheInputTokens: Bool = false
    ) -> AIUsageSample? {
        var tokens = tokenUsage(usage)
        if includeCacheInputTokens {
            tokens.input = AIUsageTokenMath.adding(
                tokens.input,
                integer(usage["cache_creation_input_tokens"])
            )
            tokens.input = AIUsageTokenMath.adding(
                tokens.input,
                integer(usage["cache_read_input_tokens"])
            )
        }

        return usageSample(
            provider: provider,
            sourceID: sourceID,
            timestamp: timestamp,
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            costUSD: double(usage["cost_usd"]) ?? double(usage["costUSD"]),
            model: model
        )
    }

    private func tokenUsage(_ usage: [String: Any]) -> TokenUsage {
        var input = integer(usage["input_tokens"])
        if input == 0 { input = integer(usage["inputTokens"])
        }
        if input == 0 { input = integer(usage["prompt_tokens"])
        }
        if input == 0 { input = integer(usage["promptTokens"])
        }
        if input == 0 { input = integer(usage["promptTokenCount"])
        }
        if input == 0 { input = integer(usage["prompt_token_count"])
        }
        var output = integer(usage["output_tokens"])
        if output == 0 { output = integer(usage["outputTokens"])
        }
        if output == 0 { output = integer(usage["completion_tokens"])
        }
        if output == 0 { output = integer(usage["completionTokens"])
        }
        if output == 0 { output = integer(usage["candidatesTokenCount"])
        }
        if output == 0 { output = integer(usage["candidates_token_count"])
        }
        return TokenUsage(input: input, output: output)
    }

    private func usageSample(
        provider: AIProvider,
        sourceID: String,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double?,
        model: String?,
        permitsZero: Bool = false
    ) -> AIUsageSample? {
        guard permitsZero || AIUsageTokenMath.adding(inputTokens, outputTokens) > 0 else { return nil }
        return AIUsageSample(
            sourceID: sourceID,
            provider: provider,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            model: model
        )
    }

    private func isCopilotShutdownSummary(_ sample: AIUsageSample) -> Bool {
        sample.provider == .copilot && (sample.sourceID?.contains("-shutdown-") ?? false)
    }

    private func usageDictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var result: [[String: Any]] = []
            let keys = Set(dictionary.keys)
            if !keys.intersection([
                "input_tokens", "inputTokens", "prompt_tokens", "promptTokens",
                "promptTokenCount", "prompt_token_count",
                "output_tokens", "outputTokens", "completion_tokens", "completionTokens",
                "candidatesTokenCount", "candidates_token_count",
            ]).isEmpty {
                result.append(dictionary)
            }
            for value in dictionary.values {
                result.append(contentsOf: usageDictionaries(in: value))
            }
            return result
        }
        if let values = value as? [Any] {
            return values.flatMap(usageDictionaries(in:))
        }
        return []
    }

    private func model(in root: [String: Any]) -> String? {
        if let model = root["model"] as? String { return model }
        for value in root.values {
            if let dictionary = value as? [String: Any], let model = model(in: dictionary) {
                return model
            }
        }
        return nil
    }

    private func timestamp(in root: [String: Any], fallback: Date) -> Date {
        for key in ["timestamp", "ts", "created_at", "createdAt"] {
            guard let value = root[key] else { continue }
            if let date = parseTimestamp(value) { return date }
        }
        return fallback
    }

    private func parseTimestamp(_ value: Any) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        guard let string = value as? String else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    private func trailingData(from candidate: Candidate) -> LogData? {
        (try? Data(contentsOf: candidate.url)).map { LogData(data: $0) }
    }

    private func cacheKey(for candidate: Candidate) -> String {
        "\(candidate.provider.rawValue):\(candidate.url.standardizedFileURL.path)"
    }

    private func sourceID(_ candidate: Candidate, component: String) -> String {
        "\(candidate.provider.rawValue)-\(stableDigest(candidate.url.standardizedFileURL.path))-\(component)"
    }

    private func codexEventSourceID(candidate: Candidate, root: [String: Any]) -> String {
        var identity = root
        if var payload = identity["payload"] as? [String: Any],
           var info = payload["info"] as? [String: Any] {
            info.removeValue(forKey: "total_token_usage")
            info.removeValue(forKey: "last_token_usage")
            payload["info"] = info
            identity["payload"] = payload
        }
        return sourceID(candidate, component: "event-v2-\(stableDigest(identity))")
    }

    private func grokUpdateSourceID(
        candidate: Candidate,
        promptID: String,
        root: [String: Any]
    ) -> String {
        var identity = root
        if var params = identity["params"] as? [String: Any],
           var update = params["update"] as? [String: Any] {
            update.removeValue(forKey: "usage")
            params["update"] = update
            identity["params"] = params
        }
        return sourceID(
            candidate,
            component: "prompt-\(promptID)-update-v2-\(stableDigest(identity))"
        )
    }

    private func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return boundedInteger(value.doubleValue) }
        if let value = value as? String {
            if let parsed = Int(value) { return max(0, parsed) }
            if let parsed = UInt64(value) {
                return parsed > UInt64(Int.max) ? Int.max : Int(parsed)
            }
            return boundedInteger(Double(value) ?? .nan)
        }
        return 0
    }

    private func boundedInteger(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        guard value < Double(Int.max) else { return Int.max }
        return Int(value)
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func fileChangeDate(for url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec)
                + TimeInterval(info.st_ctimespec.tv_nsec) / 1_000_000_000
        )
    }

    private func edgeHash(of url: URL, byteCount: UInt64) -> UInt64? {
        guard byteCount > 0 else { return Self.contentHashOffset }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bytesPerEdge = Self.incrementalVerificationBytesPerEdge(for: byteCount)
        var hash = Self.contentHashOffset
        do {
            guard let first = try handle.read(upToCount: Int(bytesPerEdge)),
                  first.count == Int(bytesPerEdge) else {
                return nil
            }
            hash = Self.updateContentHash(hash, with: first)
            if byteCount > bytesPerEdge {
                try handle.seek(toOffset: byteCount - bytesPerEdge)
                guard let last = try handle.read(upToCount: Int(bytesPerEdge)),
                      last.count == Int(bytesPerEdge) else {
                    return nil
                }
                hash = Self.updateContentHash(hash, with: last)
            }
        } catch {
            return nil
        }
        return hash
    }

    private static func updateContentHash(_ hash: UInt64, with data: Data) -> UInt64 {
        data.reduce(hash) { partial, byte in
            var next = partial
            next ^= UInt64(byte)
            next &*= contentHashPrime
            return next
        }
    }

    private func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func stableDigest(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        else { return stableDigest(String(describing: value)) }
        return stableDigest(data)
    }

    private func stableDigest(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
