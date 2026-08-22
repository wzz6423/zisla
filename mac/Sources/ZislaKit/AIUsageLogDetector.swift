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
        var size: UInt64
    }

    private struct CachedSamples {
        var modificationDate: Date
        var size: UInt64
        var samples: [AIUsageSample]
        var readerState: IncrementalJSONLReader.State?
        var parserState: ParserState?
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
        maxBytesPerFile: Int = 256 * 1_024,
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
            size: candidate.size,
            samples: samples,
            readerState: nil,
            parserState: nil
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
        let canContinue = (cached?.size ?? 0) < candidate.size
        var readerState: IncrementalJSONLReader.State
        var parserState: ParserState
        var samples: [AIUsageSample]

        if canContinue,
           let cached,
           let cachedReaderState = cached.readerState,
           let cachedParserState = cached.parserState {
            readerState = cachedReaderState
            parserState = cachedParserState
            samples = cached.samples
        } else {
            readerState = IncrementalJSONLReader(initialTailBytes: .max)
                .initialState(fileSize: candidate.size)
            parserState = ParserState()
            samples = []
        }

        let reader = IncrementalJSONLReader(
            initialTailBytes: .max,
            maximumLineBytes: maxBytesPerFile
        )
        do {
            try reader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState
            ) { line in
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    return
                }
                samples.append(contentsOf: parseRoot(from: root, candidate: candidate, parserState: &parserState))
            }
        } catch {
            return cached ?? CachedSamples(
                modificationDate: candidate.modificationDate,
                size: candidate.size,
                samples: [],
                readerState: nil,
                parserState: nil
            )
        }

        if parserState.copilotHasDetailedUsage {
            samples.removeAll(where: isCopilotShutdownSummary)
        }

        return CachedSamples(
            modificationDate: candidate.modificationDate,
            size: candidate.size,
            samples: Array(samples.suffix(maxSamplesPerFile)),
            readerState: readerState,
            parserState: parserState
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
            sourceID: sourceID(candidate, component: "event-\(stableDigest(root))"),
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
        let input = integer(usage["input"])
            + integer(usage["cacheRead"])
            + integer(usage["cacheWrite"])
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
        guard current.input + current.output > 0 else { return nil }
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
            sourceID: sourceID(candidate, component: "prompt-\(promptID)"),
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
        return usageSample(
            provider: .copilot,
            sourceID: sourceID,
            timestamp: timestamp,
            inputTokens: tokens.input
                + integer(usage["cacheReadTokens"])
                + integer(usage["cacheWriteTokens"]),
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
            tokens.input += integer(usage["cache_creation_input_tokens"])
            tokens.input += integer(usage["cache_read_input_tokens"])
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
        guard permitsZero || inputTokens + outputTokens > 0 else { return nil }
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
        guard candidate.url.pathExtension == "jsonl",
              candidate.size > UInt64(maxBytesPerFile) else {
            return (try? Data(contentsOf: candidate.url)).map {
                LogData(data: $0)
            }
        }
        guard candidate.url.pathExtension == "jsonl",
              let handle = try? FileHandle(forReadingFrom: candidate.url) else {
            return nil
        }
        defer { try? handle.close() }

        let offset = candidate.size - UInt64(maxBytesPerFile)
        guard (try? handle.seek(toOffset: offset)) != nil,
              let tail = try? handle.readToEnd(),
              let firstNewline = tail.firstIndex(of: 0x0A)
        else { return nil }
        return LogData(data: Data(tail[tail.index(after: firstNewline)...]))
    }

    private func cacheKey(for candidate: Candidate) -> String {
        "\(candidate.provider.rawValue):\(candidate.url.standardizedFileURL.path)"
    }

    private func sourceID(_ candidate: Candidate, component: String) -> String {
        "\(candidate.provider.rawValue)-\(stableDigest(candidate.url.standardizedFileURL.path))-\(component)"
    }

    private func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let parsed = Int(value) { return max(0, parsed) }
        return 0
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
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
