import Foundation
import ZislaCore

/// 从各本地 AI 工具的结构化会话日志中读取已记录的 token 用量。
/// 只解析数值用量字段，不读取或持久化会话正文。
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
    }

    private struct LogData {
        var data: Data
        var startsAtFileStart: Bool
    }

    public let codexSessionsDirectory: URL
    public let claudeProjectsDirectory: URL
    public let geminiSessionsDirectory: URL
    public let grokSessionsDirectory: URL
    public let qwenProjectsDirectory: URL
    public let qoderRoots: [URL]
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
        qoderRoots: [URL]? = nil,
        maxFilesPerProvider: Int = 4,
        maxBytesPerFile: Int = 256 * 1_024,
        maxSamplesPerFile: Int = 256,
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
        self.qoderRoots = qoderRoots
            ?? QoderSessionActivityDetector.defaultConfigRoots(home: home, fileManager: fileManager)
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
            let parsed = autoreleasepool { parse(candidate) }
            cache[key] = CachedSamples(
                modificationDate: candidate.modificationDate,
                size: candidate.size,
                samples: parsed
            )
            samples.append(contentsOf: parsed)
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
        for root in qoderRoots {
            result.append(contentsOf: candidates(provider: .coder, root: root))
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
        case .trae, .opencode, .harness, .doubao:
            return false
        case .codex, .claude, .qwen, .gpt:
            return true
        }
    }

    private func parse(_ candidate: Candidate) -> [AIUsageSample] {
        guard let logData = trailingData(from: candidate) else { return [] }
        let roots = jsonRoots(from: logData.data, pathExtension: candidate.url.pathExtension)
        let samples: [AIUsageSample]
        switch candidate.provider {
        case .codex:
            samples = parseCodex(
                roots,
                candidate: candidate,
                startsAtFileStart: logData.startsAtFileStart
            )
        case .claude:
            samples = parseClaude(roots, candidate: candidate)
        case .grok:
            samples = parseGrok(roots, candidate: candidate)
        case .gemini, .qwen, .coder, .gpt:
            samples = parseGeneric(roots, candidate: candidate)
        case .trae, .opencode, .harness, .doubao:
            return []
        }
        return Array(samples.suffix(maxSamplesPerFile))
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
        _ roots: [[String: Any]],
        candidate: Candidate,
        startsAtFileStart: Bool
    ) -> [AIUsageSample] {
        var priorTotal: TokenUsage?

        return roots.compactMap { root in
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
                let total = tokenUsage(totalUsage, excludingCachedInput: true)
                if let priorTotal,
                   total.input >= priorTotal.input,
                   total.output >= priorTotal.output {
                    current = TokenUsage(
                        input: total.input - priorTotal.input,
                        output: total.output - priorTotal.output
                    )
                } else if !startsAtFileStart, priorTotal == nil {
                    // 尾部缺失前序累计点，首条只能可信地使用本次消耗。
                    current = tokenUsage(usage, excludingCachedInput: true)
                } else {
                    current = total
                }
                priorTotal = total
                permitsZero = true
            } else {
                current = tokenUsage(usage, excludingCachedInput: true)
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
    }

    private func parseClaude(_ roots: [[String: Any]], candidate: Candidate) -> [AIUsageSample] {
        roots.compactMap { root in
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
                includeClaudeCacheTokens: true
            )
        }
    }

    private func parseGrok(_ roots: [[String: Any]], candidate: Candidate) -> [AIUsageSample] {
        var priorUsageBySession: [String: (input: Int, output: Int)] = [:]
        var samples: [AIUsageSample] = []
        for root in roots {
            guard root["method"] as? String == "_x.ai/session/update",
                  let params = root["params"] as? [String: Any],
                  let sessionID = params["sessionId"] as? String,
                  let update = params["update"] as? [String: Any],
                  let promptID = update["prompt_id"] as? String,
                  let usage = update["usage"] as? [String: Any] else {
                continue
            }
            let input = integer(usage["inputTokens"])
            let output = integer(usage["outputTokens"])
            guard input + output > 0 else { continue }
            let prior = priorUsageBySession[sessionID] ?? (0, 0)
            priorUsageBySession[sessionID] = (max(prior.input, input), max(prior.output, output))
            let delta = ["inputTokens": max(0, input - prior.input), "outputTokens": max(0, output - prior.output)]
            let model = (usage["modelUsage"] as? [String: Any])?.keys.sorted().first
            if let sample = sample(
                provider: .grok,
                sourceID: sourceID(candidate, component: "prompt-\(promptID)"),
                timestamp: timestamp(in: root, fallback: candidate.modificationDate),
                usage: delta,
                model: model
            ) {
                samples.append(sample)
            }
        }
        return samples
    }

    private func parseGeneric(_ roots: [[String: Any]], candidate: Candidate) -> [AIUsageSample] {
        roots.flatMap { root in
            usageDictionaries(in: root).enumerated().compactMap { usageIndex, usage in
                sample(
                    provider: candidate.provider,
                    sourceID: sourceID(
                        candidate,
                        component: "entry-\(stableDigest(root))-usage-\(usageIndex)"
                    ),
                    timestamp: timestamp(in: root, fallback: candidate.modificationDate),
                    usage: usage,
                    model: model(in: root)
                )
            }
        }
    }

    private func sample(
        provider: AIProvider,
        sourceID: String,
        timestamp: Date,
        usage: [String: Any],
        model: String?,
        includeClaudeCacheTokens: Bool = false
    ) -> AIUsageSample? {
        var tokens = tokenUsage(usage)
        if includeClaudeCacheTokens {
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

    private func tokenUsage(
        _ usage: [String: Any],
        excludingCachedInput: Bool = false
    ) -> TokenUsage {
        var input = integer(usage["input_tokens"])
        if input == 0 { input = integer(usage["inputTokens"])
        }
        if input == 0 { input = integer(usage["prompt_tokens"])
        }
        if input == 0 { input = integer(usage["promptTokens"])
        }
        if excludingCachedInput {
            input = max(0, input - integer(usage["cached_input_tokens"]))
        }
        var output = integer(usage["output_tokens"])
        if output == 0 { output = integer(usage["outputTokens"])
        }
        if output == 0 { output = integer(usage["completion_tokens"])
        }
        if output == 0 { output = integer(usage["completionTokens"])
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

    private func usageDictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var result: [[String: Any]] = []
            let keys = Set(dictionary.keys)
            if !keys.intersection([
                "input_tokens", "inputTokens", "prompt_tokens", "promptTokens",
                "output_tokens", "outputTokens", "completion_tokens", "completionTokens",
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
        guard candidate.size > UInt64(maxBytesPerFile) else {
            return (try? Data(contentsOf: candidate.url)).map {
                LogData(data: $0, startsAtFileStart: true)
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
        return LogData(
            data: Data(tail[tail.index(after: firstNewline)...]),
            startsAtFileStart: false
        )
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
