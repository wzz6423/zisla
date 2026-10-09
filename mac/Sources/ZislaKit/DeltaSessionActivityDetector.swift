import Foundation
import ZislaCore

/// Delta owns a separate SQLite store for each signed-in account. Read indexed metadata only;
/// replicated thread state, prompts, worktree contents and credentials are never queried.
public final class DeltaSessionActivityDetector: AIActivityDetecting, AIUsageDetecting {
    public let dataRoot: URL
    public let maxThreads: Int
    public let recencyThreshold: TimeInterval
    private let now: () -> Date
    private let fileManager: FileManager

    public init(
        dataRoot: URL? = nil,
        maxThreads: Int = 4,
        recencyThreshold: TimeInterval = 30 * 60,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.dataRoot = dataRoot ?? Self.defaultDataRoot(home: fileManager.homeDirectoryForCurrentUser)
        self.maxThreads = max(1, maxThreads)
        self.recencyThreshold = max(0, recencyThreshold)
        self.fileManager = fileManager
        self.now = now
    }

    public static func defaultDataRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Delta", isDirectory: true)
    }

    var databaseURLs: [URL] {
        // Older installations had a root database; current releases isolate user_* stores.
        let rootDatabase = dataRoot.appendingPathComponent("data.sqlite")
        let accounts = (try? fileManager.contentsOfDirectory(
            at: dataRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let databases = [rootDatabase] + accounts.filter {
            $0.lastPathComponent.hasPrefix("user_") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map { $0.appendingPathComponent("data.sqlite") }
        return databases.filter { fileManager.fileExists(atPath: $0.path) }.sorted { $0.path < $1.path }
    }

    public var activityFileURLs: [URL] {
        databaseURLs.flatMap { [$0, URL(fileURLWithPath: $0.path + "-wal")] }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let cutoff = now().addingTimeInterval(-recencyThreshold)
        let tasks = databaseURLs.flatMap { database in
            DesktopAIStorage.rows(at: database, sql: """
                SELECT id, name, status, created_at, last_prompted_at
                FROM app_threads WHERE archived = 0 AND status = 'streaming'
                ORDER BY last_prompted_at DESC LIMIT \(maxThreads)
                """, limit: maxThreads).compactMap { row -> AIProgressTask? in
                guard let id = row["id"] as? String, !id.isEmpty,
                      let promptedAt = DesktopAIStorage.milliseconds(row["last_prompted_at"]), promptedAt >= cutoff else { return nil }
                let title = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return AIProgressTask(
                    id: "delta-thread-" + DesktopAIStorage.identity([database.deletingLastPathComponent().lastPathComponent, id]),
                    provider: .delta,
                    title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Delta Agent",
                    progress: nil, status: .running, updatedAt: promptedAt,
                    startedAt: DesktopAIStorage.milliseconds(row["created_at"])
                )
            }
        }
        return Array(tasks.sorted {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
        }.prefix(maxThreads))
    }

    public func usageSamples() throws -> [AIUsageSample] {
        databaseURLs.flatMap { database in
            // This numeric daily ledger is available in newer Delta builds. Older schemas report
            // no usage rather than attempting to deserialize the replicated conversation tree.
            DesktopAIStorage.rows(at: database, sql: """
                SELECT day, access_provider, model_provider, model, pricing_tier,
                       input_tokens, output_tokens, cache_write_tokens, cache_read_tokens
                FROM app_model_usage_daily ORDER BY day ASC
                """).compactMap { row -> AIUsageSample? in
                guard let day = row["day"] as? NSNumber else { return nil }
                let rawDay = day.doubleValue
                // Delta's decode_usage_bucket multiplies day by 86,400,000 to produce Unix
                // milliseconds. It is an epoch day, not a YYYYMMDD or Common Era ordinal.
                guard rawDay.isFinite, rawDay.rounded(.towardZero) == rawDay,
                      rawDay >= 0, rawDay <= 2_932_896 else { return nil }
                let input = AIUsageTokenMath.adding(
                    AIUsageTokenMath.adding(DesktopAIStorage.tokenCount(row["input_tokens"]), DesktopAIStorage.tokenCount(row["cache_write_tokens"])),
                    DesktopAIStorage.tokenCount(row["cache_read_tokens"])
                )
                let output = DesktopAIStorage.tokenCount(row["output_tokens"])
                guard AIUsageTokenMath.adding(input, output) > 0 else { return nil }
                let identity = [database.standardizedFileURL.path, day.stringValue] +
                    ["access_provider", "model_provider", "model", "pricing_tier"].map { row[$0] as? String ?? "" }
                return AIUsageSample(
                    sourceID: "delta-usage-" + DesktopAIStorage.identity(identity), provider: .delta,
                    timestamp: Date(timeIntervalSince1970: rawDay * 86_400),
                    inputTokens: input, outputTokens: output, model: row["model"] as? String
                )
            }
        }
    }
}
