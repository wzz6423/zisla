import Foundation
import SQLite3
import Testing
@testable import ZislaCore

struct IslandPresentationReducerTests {
    @Test
    func pointerEntryShowsIslandAndCancelsPendingCollapse() {
        var reducer = IslandPresentationReducer()

        let effects = reducer.send(.pointerEntered)

        #expect(reducer.state.visibility == .expanded)
        #expect(effects == [.cancelScheduledCollapse, .show])
    }

    @Test
    func pointerExitSchedulesCollapseAndElapsedDelayCollapses() {
        var reducer = IslandPresentationReducer()
        _ = reducer.send(.pointerEntered)

        #expect(reducer.send(.pointerExited) == [.scheduleCollapse])
        #expect(reducer.send(.collapseDelayElapsed) == [.collapse])
        #expect(reducer.state.visibility == .collapsed)
    }

    @Test
    func pointerReentryAfterTransientExitCancelsThePendingCollapse() {
        var reducer = IslandPresentationReducer()
        _ = reducer.send(.pointerEntered)

        #expect(reducer.send(.pointerExited) == [.scheduleCollapse])
        #expect(reducer.send(.pointerEntered) == [.cancelScheduledCollapse, .show])
        #expect(reducer.send(.collapseDelayElapsed).isEmpty)
        #expect(reducer.state.visibility == .expanded)
    }

    @Test
    func pinAndDragBothPreventCollapse() {
        var reducer = IslandPresentationReducer()
        _ = reducer.send(.setPinned(true))
        _ = reducer.send(.pointerExited)
        #expect(reducer.send(.collapseDelayElapsed).isEmpty)
        #expect(reducer.state.visibility == .pinned)

        _ = reducer.send(.setPinned(false))
        _ = reducer.send(.setDragging(true))
        #expect(reducer.send(.collapseDelayElapsed).isEmpty)
        #expect(reducer.state.visibility == .expanded)
        #expect(reducer.send(.setDragging(false)) == [.scheduleCollapse])
    }

    @Test
    func deterministicChaosEventsKeepVisibilityAndEffectsConsistent() {
        var reducer = IslandPresentationReducer()
        var seed: UInt64 = 0xD1CE_F00D

        for _ in 0..<512 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let action: IslandPresentationReducer.Action
            switch seed % 5 {
            case 0: action = .pointerEntered
            case 1: action = .pointerExited
            case 2: action = .collapseDelayElapsed
            case 3: action = .setPinned(seed & 1 == 0)
            default: action = .setDragging(seed & 1 == 0)
            }

            let effects = reducer.send(action)
            if effects.contains(.show) {
                #expect(reducer.state.isVisible)
            }
            if effects.contains(.collapse) {
                #expect(reducer.state.visibility == .collapsed)
            }
        }
    }
}

struct AIStateRepositoryTests {
    @Test
    func progressStatusSeparatesActiveAttentionFromTerminalFailure() {
        #expect(AIProgressStatus.queued.isActive)
        #expect(AIProgressStatus.running.isActive)
        #expect(AIProgressStatus.blocked.isActive)
        #expect(AIProgressStatus.error.isActive)
        #expect(!AIProgressStatus.succeeded.isActive)
        #expect(!AIProgressStatus.failed.isActive)
        #expect(AIProgressStatus.running.noticeKind == .info)
        #expect(AIProgressStatus.blocked.noticeKind == .warning)
        #expect(AIProgressStatus.error.noticeKind == .error)
    }

    @Test
    func legacyTaskWithoutSessionURLStillDecodes() throws {
        let data = Data(
            #"{"id":"legacy","provider":"codex","title":"Codex","progress":null,"status":"running","updatedAt":0}"#.utf8
        )

        let task = try JSONDecoder().decode(AIProgressTask.self, from: data)

        #expect(task.id == "legacy")
        #expect(task.sessionURL == nil)
        #expect(task.effort == nil)
        #expect(task.startedAt == nil)
    }

    @Test
    func repositoryUpsertsFinishesAndPersistsTask() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let task = AIProgressTask(
            id: "compile",
            provider: .claude,
            title: "Compile project",
            detail: "12/30",
            progress: 0.4,
            status: .running,
            updatedAt: now
        )

        try repository.upsert(task)
        try repository.finish(id: task.id, failed: false, detail: "Done", at: now.addingTimeInterval(10))

        let state = try repository.load()
        #expect(state.tasks.count == 1)
        #expect(state.tasks[0].status == .succeeded)
        #expect(state.tasks[0].progress == 1)
        #expect(state.tasks[0].detail == "Done")
    }

    @Test
    func corruptedDatabaseIsReportedAndNeverOverwritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = Data("not a sqlite database".utf8)
        try invalid.write(to: repository.databaseURL)

        do {
            try repository.upsert(.init(
                id: "x", provider: .grok, title: "Task", progress: nil,
                status: .running, updatedAt: .now
            ))
            Issue.record("Corrupted database should throw")
        } catch let error as AIStateRepositoryError {
            guard case .storageFailure = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: repository.databaseURL) == invalid)
    }

    @Test
    func repositoryIgnoresLegacyJSONAndCreatesEmptySQLite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let legacy = AIState(usageSamples: [AIUsageSample(
            sourceID: "legacy-usage",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 101),
            inputTokens: 12,
            outputTokens: 3
        )])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyURL = directory.appendingPathComponent("ai-state.json")
        try legacyData.write(to: legacyURL)

        #expect(try repository.load() == .empty)
        #expect(FileManager.default.fileExists(atPath: repository.databaseURL.path))
        #expect(try Data(contentsOf: legacyURL) == legacyData)
    }

    @Test
    func repositoryWritesNewUsageOnlyToSQLiteWhenLegacyJSONExists() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let original = AIState(usageSamples: [AIUsageSample(
            sourceID: "legacy-usage",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 12,
            outputTokens: 3
        )])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyData = try JSONEncoder().encode(original)
        let legacyURL = directory.appendingPathComponent("ai-state.json")
        try legacyData.write(to: legacyURL)
        _ = try repository.load()

        let sample = AIUsageSample(
            sourceID: "new-usage",
            provider: .claude,
            timestamp: Date(timeIntervalSince1970: 200),
            inputTokens: 20,
            outputTokens: 5
        )
        try repository.recordUsage(sample)

        #expect(try Data(contentsOf: legacyURL) == legacyData)
        #expect(try repository.load().usageSamples == AIUsageAnalytics.dailyManualUsageSamples(samples: [sample]))
    }

    @Test
    func storageChangeTokenIgnoresLegacyJSONAndTracksSQLiteWrites() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AIStateRepository(directoryURL: directory)
        let initialToken = repository.storageChangeToken()

        try Data("{\"usageSamples\":[]}".utf8).write(
            to: directory.appendingPathComponent("ai-state.json")
        )
        #expect(repository.storageChangeToken() == initialToken)

        _ = try repository.recordUsage(AIUsageSample(
            sourceID: "sqlite-write",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 1_000),
            inputTokens: 1,
            outputTokens: 1
        ))
        #expect(repository.storageChangeToken() != initialToken)
    }

    @Test
    func repositoryRecordsUsageAndExternalNotice() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let sample = AIUsageSample(
            provider: .gpt,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 120,
            outputTokens: 80,
            costUSD: 0.02,
            model: "gpt-5"
        )
        let notice = IslandNotice(
            id: "notice-1", title: "Build complete", detail: "All checks passed",
            kind: .success, side: .right, createdAt: Date(timeIntervalSince1970: 101)
        )

        try repository.recordUsage(sample)
        try repository.enqueueNotice(notice)

        let state = try repository.load()
        #expect(state.usageSamples == AIUsageAnalytics.dailyManualUsageSamples(samples: [sample]))
        #expect(state.notices == [notice])
    }

    @Test
    func repositoryLoadsTasksAndNoticesWithoutUsageHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let task = AIProgressTask(
            id: "running-task",
            provider: .codex,
            title: "Running",
            progress: 0.5,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let notice = IslandNotice(
            id: "notice-1", title: "Finished", detail: "Done",
            kind: .success, side: .right, createdAt: Date(timeIntervalSince1970: 101)
        )
        try repository.upsert(task)
        try repository.recordUsage(AIUsageSample(
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 102),
            inputTokens: 120,
            outputTokens: 80
        ))
        try repository.enqueueNotice(notice)

        let state = try repository.load(includeUsageSamples: false)

        #expect(state.tasks == [task])
        #expect(state.usageSamples.isEmpty)
        #expect(state.notices == [notice])
    }

    @Test
    func repositoryKeepsUsageHistoryWhenRecreated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstRepository = AIStateRepository(directoryURL: directory)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: Date(timeIntervalSince1970: 100), inputTokens: 120, outputTokens: 80),
            AIUsageSample(provider: .grok, timestamp: Date(timeIntervalSince1970: 200), inputTokens: 50, outputTokens: 50),
        ]

        for sample in samples {
            try firstRepository.recordUsage(sample)
        }

        let recreatedRepository = AIStateRepository(directoryURL: directory)
        try recreatedRepository.clearTasks()

        #expect(
            try recreatedRepository.load().usageSamples
                == AIUsageAnalytics.dailyManualUsageSamples(samples: samples)
        )
    }

    @Test
    func repositoryBoundsUsageHistoryToItsConfiguredCapacity() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory, maximumUsageSamples: 2)
        let firstDay = Date(timeIntervalSinceReferenceDate: 0)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: firstDay, inputTokens: 10, outputTokens: 1),
            AIUsageSample(provider: .grok, timestamp: firstDay.addingTimeInterval(86_400), inputTokens: 20, outputTokens: 2),
            AIUsageSample(provider: .codex, timestamp: firstDay.addingTimeInterval(172_800), inputTokens: 30, outputTokens: 3),
        ]

        try repository.recordUsage(samples)

        let summaries = AIUsageAnalytics.dailyManualUsageSamples(samples: samples)
        #expect(try repository.load().usageSamples == Array(summaries.suffix(2)))
    }

    @Test
    func repositoryKeepsNewestUsageWhenTrimmedSamplesAreScannedAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory, maximumUsageSamples: 2)
        let samples = [
            AIUsageSample(
                sourceID: "old",
                provider: .claude,
                timestamp: Date(timeIntervalSince1970: 100),
                inputTokens: 10,
                outputTokens: 1
            ),
            AIUsageSample(
                sourceID: "middle",
                provider: .grok,
                timestamp: Date(timeIntervalSince1970: 200),
                inputTokens: 20,
                outputTokens: 2
            ),
            AIUsageSample(
                sourceID: "new",
                provider: .codex,
                timestamp: Date(timeIntervalSince1970: 300),
                inputTokens: 30,
                outputTokens: 3
            ),
        ]
        try repository.recordDetectedUsage(samples)

        try repository.recordDetectedUsage([samples[0]])

        #expect(try repository.load().usageSamples == Array(samples.suffix(2)))
    }

    @Test
    func repositoryCompactsExistingUsageHistoryWhenItsLimitIsLowered() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = (0..<4).map { index in
            AIUsageSample(
                provider: .claude,
                timestamp: Date(timeIntervalSinceReferenceDate: TimeInterval(index * 86_400)),
                inputTokens: index,
                outputTokens: index
            )
        }
        try AIStateRepository(directoryURL: directory, maximumUsageSamples: 4).recordUsage(samples)

        let compacted = AIStateRepository(directoryURL: directory, maximumUsageSamples: 2)

        let summaries = AIUsageAnalytics.dailyManualUsageSamples(samples: samples)
        #expect(try compacted.load().usageSamples == Array(summaries.suffix(2)))
        #expect(try AIStateRepository(directoryURL: directory, maximumUsageSamples: 4).load().usageSamples == Array(summaries.suffix(2)))
    }

    @Test
    func repositoryAccumulatesManualUsageIntoOneDailyTotal() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let timestamp = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let samples = [
            AIUsageSample(provider: .codex, timestamp: timestamp, inputTokens: 10, outputTokens: 2),
            AIUsageSample(provider: .codex, timestamp: timestamp.addingTimeInterval(60), inputTokens: 20, outputTokens: 3),
        ]

        for sample in samples {
            try repository.recordUsage(sample)
        }

        let stored = try repository.load().usageSamples
        #expect(stored == AIUsageAnalytics.dailyManualUsageSamples(samples: samples))
        #expect(stored.first?.totalTokens == 35)
    }

    @Test
    func repositoryMigratesLegacyAutomaticEventsToDailySummaries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let day = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let legacySamples = [
            AIUsageSample(
                sourceID: "codex-session-a-event-one",
                provider: .codex,
                timestamp: day.addingTimeInterval(60),
                inputTokens: 10,
                outputTokens: 2
            ),
            AIUsageSample(
                sourceID: "codex-session-a-event-two",
                provider: .codex,
                timestamp: day.addingTimeInterval(120),
                inputTokens: 20,
                outputTokens: 3
            ),
            AIUsageSample(
                sourceID: "claude-project-a-message-one",
                provider: .claude,
                timestamp: day.addingTimeInterval(180),
                inputTokens: 30,
                outputTokens: 4
            ),
        ]
        let manualSample = AIUsageSample(
            provider: .grok,
            timestamp: day.addingTimeInterval(240),
            inputTokens: 40,
            outputTokens: 5
        )
        try repository.recordDetectedUsage(legacySamples)
        try repository.recordUsage(manualSample)
        try setSQLiteUserVersion(at: repository.databaseURL, to: 0)

        let migrated = try AIStateRepository(directoryURL: directory).load().usageSamples
        let summaries = AIUsageAnalytics.dailyAutomaticUsageSamples(samples: legacySamples)

        #expect(migrated.contains(AIUsageAnalytics.dailyManualUsageSamples(samples: [manualSample])[0]))
        #expect(migrated.filter(AIUsageAnalytics.isAutomaticUsageSummary) == summaries)
        #expect(!migrated.contains(where: AIUsageAnalytics.isLegacyAutomaticUsageSample))
    }

    @Test
    func repositoryMigratesLegacyManualEventsToDailySummaries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        _ = try repository.load()
        let timestamp = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let legacySamples = [
            AIUsageSample(provider: .grok, timestamp: timestamp, inputTokens: 10, outputTokens: 2),
            AIUsageSample(provider: .grok, timestamp: timestamp.addingTimeInterval(60), inputTokens: 20, outputTokens: 3),
        ]
        for sample in legacySamples {
            try insertLegacyManualUsage(sample, into: repository.databaseURL)
        }
        try setSQLiteUserVersion(at: repository.databaseURL, to: 1)

        let migrated = try AIStateRepository(directoryURL: directory).load().usageSamples

        #expect(migrated == AIUsageAnalytics.dailyManualUsageSamples(samples: legacySamples))
    }
}

struct CLIParserTests {
    @Test
    func providerAliasesIncludeCodexAndGemini() {
        #expect(AIProvider(token: "codex") == .codex)
        #expect(AIProvider(token: "openai-codex") == .codex)
        #expect(AIProvider(token: "gemini") == .gemini)
        #expect(AIProvider(token: "google-gemini") == .gemini)
        #expect(AIProvider(token: "claude-code") == .claude)
        #expect(AIProvider(token: "qwen-code") == .qwen)
        #expect(AIProvider(token: "qoder") == .coder)
        #expect(AIProvider(token: "QoderWork CN") == .coder)
        #expect(AIProvider(token: "qoderwork-cn") == .coder)
        #expect(AIProvider(token: "qoderwake") == .coder)
        #expect(AIProvider(token: "copilot") == .copilot)
        #expect(AIProvider(token: "github-copilot") == .copilot)
    }

    @Test
    func updateAcceptsPercentAndNormalizesIt() throws {
        let command = try CLIParser.parse(arguments: [
            "update", "--id", "job-1", "--provider", "qwen",
            "--title", "Indexing", "--progress", "42", "--detail", "4/10"
        ])

        guard case let .update(task) = command else {
            Issue.record("Expected update command")
            return
        }
        #expect(task.provider == .qwen)
        #expect(task.progress == 0.42)
        #expect(task.detail == "4/10")
    }

    @Test
    func updateAcceptsBlockedAndErrorStatuses() throws {
        for status in [AIProgressStatus.blocked, .error] {
            let command = try CLIParser.parse(arguments: [
                "update", "--id", status.rawValue, "--provider", "codex",
                "--title", "Task", "--status", status.rawValue,
            ])
            guard case let .update(task) = command else {
                Issue.record("Expected update command")
                return
            }
            #expect(task.status == status)
        }
    }

    @Test
    func progressOutsideSupportedRangeFails() {
        do {
            _ = try CLIParser.parse(arguments: [
                "update", "--id", "job", "--provider", "grok",
                "--title", "Run", "--progress", "101"
            ])
            Issue.record("Invalid progress should throw")
        } catch {
            #expect(error is CLIParseError)
        }
    }

    @Test
    func commandsRejectUnknownAndPositionalArguments() {
        #expect(throws: CLIParseError.unknownOption("--faield")) {
            try CLIParser.parse(arguments: ["finish", "--id", "job", "--faield"])
        }
        #expect(throws: CLIParseError.unexpectedArgument("extra")) {
            try CLIParser.parse(arguments: ["clear", "extra"])
        }
    }

    @Test
    func usageAndNoticeCommandsParseStructuredValues() throws {
        let usage = try CLIParser.parse(arguments: [
            "usage", "--provider", "coder", "--input-tokens", "300",
            "--output-tokens", "75", "--cost", "0.04", "--model", "coder-pro"
        ])
        guard case let .usage(sample) = usage else {
            Issue.record("Expected usage command")
            return
        }
        #expect(sample.totalTokens == 375)
        #expect(sample.costUSD == 0.04)

        let notice = try CLIParser.parse(arguments: [
            "notify", "--title", "Ready", "--detail", "Open result",
            "--kind", "success", "--side", "left"
        ])
        guard case let .notify(value) = notice else {
            Issue.record("Expected notify command")
            return
        }
        #expect(value.kind == .success)
        #expect(value.side == .left)
    }

    @Test
    func messageRequiresAppSenderAndContent() throws {
        let command = try CLIParser.parse(arguments: [
            "message",
            "--app", "Messages",
            "--sender", "Alice",
            "--content", "Hello\nthere",
            "--app-bundle-id", "com.apple.MobileSMS",
        ], now: Date(timeIntervalSince1970: 42))

        guard case let .message(value) = command else {
            Issue.record("Expected message command")
            return
        }
        #expect(value.appName == "Messages")
        #expect(value.sender == "Alice")
        #expect(value.content == "Hello there")
        #expect(value.appBundleIdentifier == "com.apple.MobileSMS")
        #expect(value.createdAt.timeIntervalSince1970 == 42)

        do {
            _ = try CLIParser.parse(arguments: ["message", "--app", "X", "--sender", "Y"])
            Issue.record("Missing --content should fail")
        } catch let error as CLIParseError {
            #expect(error == .missingOption("--content"))
        }
    }
}


struct MessageNotificationTests {
    @Test
    func normalizeContentCollapsesWhitespaceAndTruncates() {
        let raw = "  hello\n\nworld   from   zisla  "
        #expect(MessageNotification.normalizeContent(raw) == "hello world from zisla")

        let long = String(repeating: "a", count: 120)
        let normalized = MessageNotification.normalizeContent(long)
        #expect(normalized.count == MessageNotification.maxContentLength + 1) // body limit plus ellipsis
        #expect(normalized.hasSuffix("…"))
        #expect(normalized.dropLast().count == MessageNotification.maxContentLength)
    }

    @Test
    func makeNoticesProducesLeftSenderAndRightBody() {
        let message = MessageNotification(
            appName: "Messages",
            sender: "Alice",
            content: "See you at 7",
            appBundleIdentifier: "com.apple.MobileSMS",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            pairID: "pair-1"
        )
        let pair = message.makeNotices()

        #expect(pair.left.side == .left)
        #expect(pair.left.style == .message)
        #expect(pair.left.title == "Alice")
        #expect(pair.left.detail == "Messages")
        #expect(pair.left.appName == "Messages")
        #expect(pair.left.appBundleIdentifier == "com.apple.MobileSMS")
        #expect(pair.left.id == "message-pair-1-left")

        #expect(pair.right.side == .right)
        #expect(pair.right.style == .message)
        #expect(pair.right.title == "See you at 7")
        #expect(pair.right.detail == nil)
        #expect(pair.right.id == "message-pair-1-right")
        #expect(pair.left.createdAt == pair.right.createdAt)
    }

    @Test
    func legacyIslandNoticeJSONStillDecodesWithoutStyle() throws {
        let data = Data(
            #"{"id":"legacy-notice","title":"Hello","kind":"info","side":"right","createdAt":0}"#.utf8
        )
        let notice = try JSONDecoder().decode(IslandNotice.self, from: data)
        #expect(notice.style == .standard)
        #expect(notice.appName == nil)
        #expect(notice.appBundleIdentifier == nil)
        #expect(notice.symbolName == nil)
        #expect(notice.title == "Hello")
    }

    @Test
    func repositoryEnqueuesMessagePairAtomically() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let message = MessageNotification(
            appName: "WeChat",
            sender: "Bob",
            content: "ping",
            pairID: "atomic-1"
        )
        let pair = message.makeNotices()
        try repository.enqueueNotices([pair.left, pair.right])

        let state = try repository.load()
        #expect(state.notices.count == 2)
        #expect(state.notices.map(\.id) == ["message-atomic-1-left", "message-atomic-1-right"])
        #expect(state.notices.allSatisfy { $0.style == .message })
    }
}

struct FileShelfTests {
    @Test
    func shelfNormalizesDuplicatesAndEvictsOldestAtCapacity() {
        var shelf = FileShelf(capacity: 2)
        let first = URL(fileURLWithPath: "/tmp/a/../a/file.txt")
        let duplicate = URL(fileURLWithPath: "/tmp/a/file.txt")
        let second = URL(fileURLWithPath: "/tmp/b.txt")
        let third = URL(fileURLWithPath: "/tmp/c.txt")

        let addedFirst = shelf.add(first)
        let addedDuplicate = shelf.add(duplicate)
        let addedSecond = shelf.add(second)
        let addedThird = shelf.add(third)
        #expect(addedFirst)
        #expect(!addedDuplicate)
        #expect(addedSecond)
        #expect(addedThird)

        #expect(shelf.urls.map(\.path) == ["/tmp/b.txt", "/tmp/c.txt"])
        let removedThird = shelf.remove(third)
        #expect(removedThird)
        #expect(shelf.urls == [second.standardizedFileURL])
    }
}

struct WeatherTests {
    @Test
    func openMeteoResponseDecodesCurrentWeather() throws {
        let json = """
        {"timezone":"Asia/Shanghai","current":{"time":"2026-07-18T12:00","temperature_2m":31.5,"apparent_temperature":35.1,"weather_code":2,"is_day":1}}
        """

        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(json.utf8))

        #expect(response.current.temperature == 31.5)
        #expect(response.current.weatherCode == 2)
        #expect(WeatherCondition(code: 2, isDay: true).summary == "多云")
        #expect(WeatherCondition(code: 2, isDay: true).symbolName == "cloud.sun.fill")
    }

    @Test
    func unknownWeatherCodeHasStableFallback() {
        let condition = WeatherCondition(code: 999, isDay: false)
        #expect(condition.summary == "天气未知")
        #expect(condition.symbolName == "questionmark.circle")
    }
}

struct DownloadCoreTests {
    @Test
    func requestUsesDownloadsDirectoryByDefault() throws {
        let request = try DownloadRequest(
            urlString: "https://example.com/video.mp4",
            mode: .video
        )

        #expect(request.outputDirectory == DownloadRequest.defaultOutputDirectory)
    }

    @Test
    func requestRejectsNonHTTPURLs() {
        do {
            _ = try DownloadRequest(
                urlString: "file:///tmp/private.mov", mode: .video,
                outputDirectory: URL(fileURLWithPath: "/tmp")
            )
            Issue.record("Non-HTTP URL should fail")
        } catch {
            #expect((error as? DownloadRequestError) == DownloadRequestError.unsupportedURL)
        }
    }

    @Test
    func argumentBuilderIsolatedURLAndMandatorySafetyFlags() throws {
        let url = "https://example.com/watch?v=1;$(touch%20/tmp/pwned)&name=--exec"
        let request = try DownloadRequest(
            urlString: url, mode: .video,
            outputDirectory: URL(fileURLWithPath: "/tmp/Downloads")
        )
        let taskTemporaryDirectory = URL(fileURLWithPath: "/tmp/Zisla/task-123")

        let arguments = YTDLPArgumentBuilder.arguments(
            for: request,
            capabilities: .init(hasFFmpeg: false),
            taskTemporaryDirectory: taskTemporaryDirectory
        )

        for flag in [
            "--ignore-config", "--no-plugin-dirs", "--no-exec",
            "--no-playlist", "--no-overwrites",
        ] {
            #expect(arguments.contains(flag))
        }
        #expect(arguments.contains(where: { $0.contains("b[ext=mp4]/b") }))
        #expect(arguments.last == url)
        #expect(arguments.dropLast().last == "--")
        #expect(arguments.filter { $0 == url }.count == 1)
        #expect(arguments.contains("temp:\(taskTemporaryDirectory.path)"))
        #expect(!arguments.contains("touch"))
    }

    @Test
    func videoWithoutFFmpegDownloadsSeparateDASHTracksForNativeMuxing() throws {
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: URL(fileURLWithPath: "/tmp/Downloads")
        )
        let taskDirectory = URL(fileURLWithPath: "/tmp/Zisla/task-dash")

        let arguments = YTDLPArgumentBuilder.arguments(
            for: request,
            capabilities: .init(hasFFmpeg: false),
            taskTemporaryDirectory: taskDirectory
        )

        #expect(
            YTDLPArgumentBuilder.strategy(for: request, capabilities: .init(hasFFmpeg: false))
                == .nativePackaging
        )
        #expect(
            argument(after: "-f", in: arguments)
                == "(bv*[ext=mp4][vcodec^=avc1][acodec=none]/bv*[ext=mp4][acodec=none],ba[ext=m4a][vcodec=none])/b[ext=mp4]/b"
        )
        // -o must be a relative template; set directories via --paths home: to avoid yt-dlp ignoring --paths
        #expect(argument(after: "-o", in: arguments)?.hasPrefix("/") == false)
        #expect(arguments.contains("home:\(taskDirectory.path)"))
        #expect(arguments.contains("temp:\(taskDirectory.path)"))
        #expect(arguments.contains(where: { $0.contains(#""event":"component""#) }))
        #expect(arguments.contains(where: { $0.contains("%(format_id)j") }))
    }

    @Test
    func audioArgumentsUseExtractionOnlyWhenFFmpegExists() throws {
        let request = try DownloadRequest(
            urlString: "https://youtu.be/abc", mode: .audio,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        let withFFmpeg = YTDLPArgumentBuilder.arguments(
            for: request, capabilities: .init(hasFFmpeg: true)
        )
        let withoutFFmpeg = YTDLPArgumentBuilder.arguments(
            for: request, capabilities: .init(hasFFmpeg: false)
        )

        #expect(withFFmpeg.contains("--extract-audio"))
        #expect(withFFmpeg.contains("m4a"))
        #expect(!withoutFFmpeg.contains("--extract-audio"))
        #expect(withoutFFmpeg.contains("ba[ext=m4a]/ba"))
    }

    @Test
    func videoWithFFmpegUsesBroadMergedFormatFallback() throws {
        let request = try DownloadRequest(
            urlString: "https://youtu.be/abc",
            mode: .video,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        let arguments = YTDLPArgumentBuilder.arguments(
            for: request,
            capabilities: .init(hasFFmpeg: true)
        )

        #expect(argument(after: "-f", in: arguments) == "bv*+ba/b")
        #expect(arguments.contains("--merge-output-format"))
    }

    @Test
    func pathsAndOutputTemplateNeverConflict() throws {
        // Regression: yt-dlp warns "--paths is ignored since an absolute path is given in output template"
        // because -o contained an absolute path. After the fix, -o is relative only; directories come from --paths home:.
        let outputDir = URL(fileURLWithPath: "/tmp/Downloads")
        let taskDir = URL(fileURLWithPath: "/tmp/Zisla/task-conflict")

        for mode in [DownloadMode.video, DownloadMode.audio] {
            for hasFFmpeg in [false, true] {
                let request = try DownloadRequest(
                    urlString: "https://youtu.be/abc",
                    mode: mode,
                    outputDirectory: outputDir
                )
                let args = YTDLPArgumentBuilder.arguments(
                    for: request,
                    capabilities: .init(hasFFmpeg: hasFFmpeg),
                    taskTemporaryDirectory: taskDir
                )

                let outputTemplate = argument(after: "-o", in: args)
                // -o must not be absolute or yt-dlp ignores --paths
                #expect(
                    outputTemplate?.hasPrefix("/") == false,
                    "mode=\(mode) ffmpeg=\(hasFFmpeg): -o 不应为绝对路径，实际值=\(outputTemplate ?? "nil")"
                )
                let expectedHomeDirectory = YTDLPArgumentBuilder.strategy(
                    for: request,
                    capabilities: .init(hasFFmpeg: hasFFmpeg)
                ) == .direct ? outputDir : taskDir
                // Native remux lands in the task directory; direct download lands in the user-chosen directory.
                #expect(
                    args.contains("home:\(expectedHomeDirectory.path)"),
                    "mode=\(mode) ffmpeg=\(hasFFmpeg): 缺少 --paths home:\(expectedHomeDirectory.path)"
                )
                // --paths temp: isolation is still retained
                #expect(
                    args.contains("temp:\(taskDir.path)"),
                    "mode=\(mode) ffmpeg=\(hasFFmpeg): 缺少 --paths temp:\(taskDir.path)"
                )
                // URL must follow -- to prevent injection
                #expect(args.last == "https://youtu.be/abc")
                #expect(args.dropLast().last == "--")
            }
        }
    }

    @Test
    func outputParserReadsOnlyStructuredSentinelJSON() {
        let prefix = YTDLPOutputParser.sentinel
        let progress = YTDLPOutputParser.parse(
            #"\#(prefix){"event":"progress","percent":"42.5%","speed":"1.20MiB/s","eta":"00:12"}"#
        )
        let path = YTDLPOutputParser.parse(
            #"\#(prefix){"event":"completed","filepath":"/Users/me/Downloads/video.mp4"}"#
        )

        #expect(progress == .progress(fraction: 0.425, speed: "1.20MiB/s", eta: "00:12"))
        #expect(path == .completedFile(URL(fileURLWithPath: "/Users/me/Downloads/video.mp4")))
        #expect(YTDLPOutputParser.parse("[download] 42.5%") == nil)
        #expect(YTDLPOutputParser.parse("\(prefix){not-json}") == nil)
    }

    @Test
    func outputParserReadsNativePackagingComponents() {
        let line = #"\#(YTDLPOutputParser.sentinel){"event":"component","filepath":"/tmp/task/video.32.mp4","format_id":"32","vcodec":"avc1.64001F","acodec":"none"}"#

        let event = YTDLPOutputParser.parse(line)

        #expect(
            event == .completedComponent(.init(
                fileURL: URL(fileURLWithPath: "/tmp/task/video.32.mp4"),
                formatID: "32",
                kind: .video
            ))
        )
    }

    @Test
    func bilibiliHTTP412MapsToActionableRiskControlMessageBeforeFormatErrors() {
        let raw = "ERROR: Requested format is not available; HTTP Error 412: Precondition Failed"

        let message = DownloadFailureDiagnostics.actionableMessage(
            rawDiagnostic: raw,
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6"
        )

        #expect(message.contains("B站"))
        #expect(message.contains("HTTP 412"))
        #expect(message.contains("Cookies"))
        #expect(
            DownloadFailureDiagnostics.shouldUseBilibiliNativeFallback(
                rawDiagnostic: "ERROR: Requested format is not available",
                urlString: "https://www.bilibili.com/video/BV1d2N16KEh6"
            )
        )
        #expect(
            DownloadFailureDiagnostics.actionableMessage(
                rawDiagnostic: raw,
                urlString: "https://example.com/video"
            ) == raw
        )
    }

    @Test
    func completedOutputPathMustRemainInsideConfiguredDirectory() {
        let directory = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
        let valid = URL(fileURLWithPath: "/Users/me/Downloads/album/../video.mp4")
        let sibling = URL(fileURLWithPath: "/Users/me/Downloads-escape/video.mp4")
        let traversal = URL(fileURLWithPath: "/Users/me/Downloads/../../private/video.mp4")

        #expect(
            DownloadOutputPathValidator.normalizedFileURL(valid, within: directory)?.path
                == "/Users/me/Downloads/video.mp4"
        )
        #expect(DownloadOutputPathValidator.normalizedFileURL(sibling, within: directory) == nil)
        #expect(DownloadOutputPathValidator.normalizedFileURL(traversal, within: directory) == nil)
    }

    @Test
    func clipboardClassifierRecognizesSupportedAndDirectMediaLinks() {
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://www.youtube.com/watch?v=abc"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://v.qq.com/x/cover/abc.html"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://www.youku.com/video/id_X.html"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://www.iqiyi.com/v_abc.html"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://music.163.com/#/song?id=1"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://y.qq.com/n/ryqq/songDetail/abc"))
        #expect(DownloadURLClassifier.isLikelyDownloadable("https://cdn.example.com/movie.mp4"))
        #expect(!DownloadURLClassifier.isLikelyDownloadable("https://example.com/article"))
        #expect(!DownloadURLClassifier.isLikelyDownloadable("not a url"))
    }

    @Test
    func clipboardDetectorRequiresAChangeAndDeduplicatesLinks() {
        var detector = ClipboardLinkDetector(recentCapacity: 4)
        detector.begin(atChangeCount: 10)

        #expect(detector.detect(changeCount: 10, string: "https://youtu.be/abc") == nil)
        #expect(
            detector.detect(changeCount: 11, string: "https://youtu.be/abc")?.absoluteString
                == "https://youtu.be/abc"
        )
        #expect(detector.detect(changeCount: 11, string: "https://youtu.be/other") == nil)
        #expect(detector.detect(changeCount: 12, string: "https://youtu.be/abc") == nil)
        #expect(detector.detect(changeCount: 13, string: "https://example.com/article") == nil)
    }
}

struct AIUsageAnalyticsTests {
    @Test
    func analyticsBuildsHourlySeriesAndWeekHeatmap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 7 * 24 * 3_600)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: now.addingTimeInterval(-600), inputTokens: 100, outputTokens: 50),
            AIUsageSample(provider: .grok, timestamp: now.addingTimeInterval(-1_200), inputTokens: 25, outputTokens: 25),
            AIUsageSample(provider: .gpt, timestamp: now.addingTimeInterval(-3_700), inputTokens: 20, outputTokens: 10),
            AIUsageSample(provider: .codex, timestamp: now.addingTimeInterval(600), inputTokens: 999, outputTokens: 1),
        ]

        let series = AIUsageAnalytics.hourlySeries(samples: samples, endingAt: now, hours: 2, calendar: calendar)
        let heatmap = AIUsageAnalytics.weekHeatmap(samples: samples, endingAt: now, calendar: calendar)

        #expect(series.map(\.tokens) == [30, 200])
        #expect(heatmap.count == 7)
        #expect(heatmap.allSatisfy { $0.count == 24 })
        #expect(heatmap.flatMap { $0 }.reduce(0, +) == 230)
    }

    @Test
    func contributionCalendarAggregatesAcrossMonthsAndLocatesMonthStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday

        // endingAt = 2026-03-15 12:00 UTC
        let endingAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 15, hour: 12
        )))
        let feb28 = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 10)))
        let mar1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9)))
        let mar1Afternoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 18)))
        let mar15 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 8)))
        let mar15AfterEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 13)))
        let future = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 1)))

        let samples = [
            AIUsageSample(provider: .claude, timestamp: feb28, inputTokens: 40, outputTokens: 10),
            AIUsageSample(provider: .grok, timestamp: mar1, inputTokens: 100, outputTokens: 50),
            AIUsageSample(provider: .gpt, timestamp: mar1Afternoon, inputTokens: 20, outputTokens: 30),
            AIUsageSample(provider: .claude, timestamp: mar15, inputTokens: 5, outputTokens: 5),
            AIUsageSample(provider: .codex, timestamp: mar15AfterEnd, inputTokens: 999, outputTokens: 1),
            AIUsageSample(provider: .claude, timestamp: future, inputTokens: 999, outputTokens: 1),
        ]

        let grid = AIUsageAnalytics.contributionCalendar(
            samples: samples,
            endingAt: endingAt,
            weeks: 26,
            calendar: calendar
        )

        #expect(grid.count == 26)
        #expect(grid.allSatisfy { $0.count == 7 })

        let flat = grid.flatMap { $0 }
        let present = flat.compactMap { $0 }
        #expect(present.allSatisfy { $0.date <= calendar.startOfDay(for: endingAt) })
        #expect(!present.contains(where: { calendar.isDate($0.date, inSameDayAs: future) }))

        // Cross-month: 2/28 and 3/1 aggregate separately; two entries on 3/1 merge to 200
        let feb28Cell = try #require(present.first { calendar.isDate($0.date, inSameDayAs: feb28) })
        #expect(feb28Cell.tokens == 50)

        let mar1Cell = try #require(present.first { calendar.isDate($0.date, inSameDayAs: mar1) })
        #expect(mar1Cell.tokens == 200)

        let mar15Cell = try #require(present.first { calendar.isDate($0.date, inSameDayAs: mar15) })
        #expect(mar15Cell.tokens == 10)

        // Month-start date is locatable: 3/1 appears in the grid as startOfDay
        #expect(mar1Cell.date == calendar.startOfDay(for: mar1))

        // Includes endingAt's day; slots after endingAt in the same column are nil
        let endDay = calendar.startOfDay(for: endingAt)
        #expect(present.contains { calendar.isDate($0.date, inSameDayAs: endDay) })
        let futureSlots = flat.filter { cell in
            guard let cell else { return true }
            return cell.date > endDay
        }
        #expect(futureSlots.allSatisfy { $0 == nil })
    }

    @Test
    func trendAndContributionCalendarAggregateUsageFromEveryProvider() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endingAt = Date(timeIntervalSince1970: 7 * 86_400 + 3_600)
        let samples = AIProvider.allCases.enumerated().map { index, provider in
            AIUsageSample(
                provider: provider,
                timestamp: endingAt.addingTimeInterval(-60),
                inputTokens: index + 1,
                outputTokens: (index + 1) * 10
            )
        }
        let expectedInput = samples.map(\.inputTokens).reduce(0, +)
        let expectedOutput = samples.map(\.outputTokens).reduce(0, +)

        let trend = AIUsageAnalytics.dailyUsageSeries(
            samples: samples,
            endingAt: endingAt,
            days: 1,
            calendar: calendar
        )
        let calendarDay = try #require(AIUsageAnalytics.contributionCalendar(
            samples: samples,
            endingAt: endingAt,
            weeks: 1,
            calendar: calendar
        ).flatMap { $0 }.compactMap { $0 }.first {
            calendar.isDate($0.date, inSameDayAs: endingAt)
        })

        #expect(trend.map(\.inputTokens) == [expectedInput])
        #expect(trend.map(\.outputTokens) == [expectedOutput])
        #expect(calendarDay.tokens == expectedInput + expectedOutput)
    }

    @Test
    func contributionIntensityUsesFiveTokenThresholds() {
        #expect(ContributionIntensity.thresholds == [
            0, 50_000_000, 100_000_000, 150_000_000, 200_000_000,
        ])

        #expect(ContributionIntensity.classify(tokens: 0) == .none)
        #expect(ContributionIntensity.classify(tokens: -1) == .none)
        #expect(ContributionIntensity.classify(tokens: 1) == .level1)
        #expect(ContributionIntensity.classify(tokens: 50_000_000) == .level1)
        #expect(ContributionIntensity.classify(tokens: 50_000_001) == .level2)
        #expect(ContributionIntensity.classify(tokens: 100_000_000) == .level2)
        #expect(ContributionIntensity.classify(tokens: 100_000_001) == .level3)
        #expect(ContributionIntensity.classify(tokens: 150_000_000) == .level3)
        #expect(ContributionIntensity.classify(tokens: 150_000_001) == .level4)
        #expect(ContributionIntensity.classify(tokens: 200_000_000) == .level4)
        #expect(ContributionIntensity.classify(tokens: 500_000_000) == .level4)
    }

    @Test
    func recentUsageSeriesSortsAscendingAndPrependsZeroBaseline() {
        let end = Date(timeIntervalSince1970: 10_000)
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let t3 = Date(timeIntervalSince1970: 3_000)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: t3, inputTokens: 30, outputTokens: 0),
            AIUsageSample(provider: .grok, timestamp: t1, inputTokens: 10, outputTokens: 0),
            AIUsageSample(provider: .gpt, timestamp: t2, inputTokens: 20, outputTokens: 0),
        ]

        let series = AIUsageAnalytics.recentUsageSeries(samples: samples, endingAt: end, limit: 10)

        #expect(series.map(\.tokens) == [0, 10, 20, 30])
        #expect(series.map(\.timestamp) == [t1.addingTimeInterval(-1), t1, t2, t3])
    }

    @Test
    func recentUsageSeriesKeepsMostRecentWithinLimit() {
        let end = Date(timeIntervalSince1970: 10_000)
        let samples = (1...5).map { i in
            AIUsageSample(
                provider: .claude,
                timestamp: Date(timeIntervalSince1970: Double(i) * 1_000),
                inputTokens: i * 10,
                outputTokens: 0
            )
        }

        let series = AIUsageAnalytics.recentUsageSeries(samples: samples, endingAt: end, limit: 3)

        // Keep the latest 3 of 5 samples (t3/t4/t5); the baseline point precedes them and does not count toward limit.
        #expect(series.map(\.tokens) == [0, 30, 40, 50])
        #expect(series.first?.timestamp == Date(timeIntervalSince1970: 3_000).addingTimeInterval(-1))
    }

    @Test
    func recentUsageSeriesIgnoresFutureAndZeroSamples() {
        let end = Date(timeIntervalSince1970: 5_000)
        let past = Date(timeIntervalSince1970: 1_000)
        let zeroAt = Date(timeIntervalSince1970: 2_000)
        let future = Date(timeIntervalSince1970: 9_000)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: past, inputTokens: 40, outputTokens: 10),
            AIUsageSample(provider: .grok, timestamp: zeroAt, inputTokens: 0, outputTokens: 0),
            AIUsageSample(provider: .gpt, timestamp: future, inputTokens: 100, outputTokens: 100),
        ]

        let series = AIUsageAnalytics.recentUsageSeries(samples: samples, endingAt: end, limit: 10)

        #expect(series.map(\.tokens) == [0, 50])
        #expect(series.map(\.timestamp) == [past.addingTimeInterval(-1), past])
    }

    @Test
    func recentUsageSeriesAddsZeroBaselineForSingleSample() {
        let end = Date(timeIntervalSince1970: 5_000)
        let onlySample = Date(timeIntervalSince1970: 1_000)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: onlySample, inputTokens: 70, outputTokens: 30),
        ]

        let series = AIUsageAnalytics.recentUsageSeries(samples: samples, endingAt: end, limit: 10)

        #expect(series.count == 2)
        #expect(series.map(\.tokens) == [0, 100])
        #expect(series[0].timestamp < series[1].timestamp)
        #expect(series[1].timestamp == onlySample)
    }

    @Test
    func recentUsageSeriesReturnsEmptyWhenNoValidSamplesOrNonPositiveLimit() {
        let end = Date(timeIntervalSince1970: 5_000)
        let onlyInvalid = [
            AIUsageSample(provider: .claude, timestamp: Date(timeIntervalSince1970: 9_000), inputTokens: 10, outputTokens: 0),
            AIUsageSample(provider: .grok, timestamp: Date(timeIntervalSince1970: 1_000), inputTokens: 0, outputTokens: 0),
        ]
        let valid = [
            AIUsageSample(provider: .gpt, timestamp: Date(timeIntervalSince1970: 1_000), inputTokens: 5, outputTokens: 5),
        ]

        #expect(AIUsageAnalytics.recentUsageSeries(samples: [], endingAt: end, limit: 10).isEmpty)
        #expect(AIUsageAnalytics.recentUsageSeries(samples: onlyInvalid, endingAt: end, limit: 10).isEmpty)
        #expect(AIUsageAnalytics.recentUsageSeries(samples: valid, endingAt: end, limit: 0).isEmpty)
    }

    @Test
    func cumulativeUsageSeriesBuildsTotalHistoryAndMergesMatchingTimestamps() {
        let end = Date(timeIntervalSince1970: 1_000)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: second, inputTokens: 10, outputTokens: 5),
            AIUsageSample(provider: .grok, timestamp: first, inputTokens: 20, outputTokens: 10),
            AIUsageSample(provider: .gpt, timestamp: second, inputTokens: 3, outputTokens: 2),
            AIUsageSample(provider: .gpt, timestamp: Date(timeIntervalSince1970: 1_001), inputTokens: 99, outputTokens: 1),
            AIUsageSample(provider: .gpt, timestamp: Date(timeIntervalSince1970: 300), inputTokens: 0, outputTokens: 0),
        ]

        let series = AIUsageAnalytics.cumulativeUsageSeries(samples: samples, endingAt: end)

        #expect(series.map(\.timestamp) == [first.addingTimeInterval(-1), first, second, end])
        #expect(series.map(\.tokens) == [0, 30, 50, 50])
    }

    @Test
    func cumulativeUsageSeriesDrawsSingleRecordWithBaselineAndEndpoint() {
        let sample = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 5_000)

        let series = AIUsageAnalytics.cumulativeUsageSeries(
            samples: [AIUsageSample(provider: .claude, timestamp: sample, inputTokens: 70, outputTokens: 30)],
            endingAt: end
        )

        // A single history sample still draws a trend: 0 baseline → sample (cumulative = total) → hold cumulative total at end.
        #expect(series.map(\.timestamp) == [sample.addingTimeInterval(-1), sample, end])
        #expect(series.map(\.tokens) == [0, 100, 100])
    }

    @Test
    func dailyUsageSeriesCombinesInputAndOutputAndKeepsEmptyDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = Date(timeIntervalSince1970: 5 * 86_400 + 3_600)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: Date(timeIntervalSince1970: 3 * 86_400 + 10), inputTokens: 40, outputTokens: 10),
            AIUsageSample(provider: .grok, timestamp: Date(timeIntervalSince1970: 3 * 86_400 + 20), inputTokens: 20, outputTokens: 30),
            AIUsageSample(provider: .gpt, timestamp: Date(timeIntervalSince1970: 5 * 86_400 + 30), inputTokens: 10, outputTokens: 5),
            AIUsageSample(provider: .gpt, timestamp: Date(timeIntervalSince1970: 6 * 86_400), inputTokens: 999, outputTokens: 1),
        ]

        let series = AIUsageAnalytics.dailyUsageSeries(
            samples: samples,
            endingAt: end,
            days: 3,
            calendar: calendar
        )

        #expect(series.map(\.timestamp) == [
            Date(timeIntervalSince1970: 3 * 86_400),
            Date(timeIntervalSince1970: 4 * 86_400),
            Date(timeIntervalSince1970: 5 * 86_400),
        ])
        #expect(series.map(\.inputTokens) == [60, 0, 10])
        #expect(series.map(\.outputTokens) == [40, 0, 5])
        #expect(series.map(\.totalTokens) == [100, 0, 15])
    }

    @Test
    func smoothedDailyUsageSeriesSoftensSingleDaySpikesWithoutChangingDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = Date(timeIntervalSince1970: 4 * 86_400 + 3_600)
        let samples = [
            AIUsageSample(provider: .codex, timestamp: Date(timeIntervalSince1970: 2 * 86_400 + 30), inputTokens: 100, outputTokens: 20),
        ]

        let series = AIUsageAnalytics.smoothedDailyUsageSeries(
            samples: samples,
            endingAt: end,
            days: 5,
            calendar: calendar
        )

        #expect(series.map(\.timestamp) == [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 86_400),
            Date(timeIntervalSince1970: 2 * 86_400),
            Date(timeIntervalSince1970: 3 * 86_400),
            Date(timeIntervalSince1970: 4 * 86_400),
        ])
        #expect(series.map(\.inputTokens) == [6, 25, 38, 25, 6])
        #expect(series.map(\.outputTokens) == [1, 5, 8, 5, 1])
    }

    @Test
    func tokenAxisTicksCoverTheHighestUsage() {
        #expect(
            AIUsageAnalytics.tokenAxisTicks(maximum: 320_000_000, desiredCount: 6)
                == [0, 100_000_000, 200_000_000, 300_000_000, 400_000_000]
        )
        #expect(AIUsageAnalytics.tokenAxisTicks(maximum: 0) == [0, 1])
    }

    /// Regression: the trend series uses daily deltas; alternating high/low usage should rise and fall,
    /// not a monotonically increasing cumulative curve (AreaMark/LineMark with unit:.day would sum cumulatively).
    @Test
    func smoothedDailyUsageSeriesIsNotMonotonicallyIncreasingForVariedUsage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // day2=high, day4=low, day6=high — a correct delta series must not be monotonically increasing
        let base = Date(timeIntervalSince1970: 0)
        let samples = [
            AIUsageSample(provider: .claude, timestamp: base.addingTimeInterval(2 * 86_400 + 100), inputTokens: 500, outputTokens: 200),
            AIUsageSample(provider: .grok,   timestamp: base.addingTimeInterval(4 * 86_400 + 100), inputTokens: 10,  outputTokens: 5),
            AIUsageSample(provider: .codex,  timestamp: base.addingTimeInterval(6 * 86_400 + 100), inputTokens: 600, outputTokens: 300),
        ]

        let series = AIUsageAnalytics.smoothedDailyUsageSeries(
            samples: samples,
            endingAt: base.addingTimeInterval(7 * 86_400),
            days: 7,
            calendar: calendar
        )
        let totals = series.map(\.totalTokens)

        // Alternating usage must decrease somewhere; non-negative monotonic growth means the algorithm degraded to cumulative
        let hasDecrease = zip(totals, totals.dropFirst()).contains { $0 > $1 }
        #expect(hasDecrease, "每日增量曲线在用量高低交替时不应单调递增，实际 totalTokens：\(totals)")
    }
}

struct UpdateCoreTests {
    @Test
    func semanticVersionsHandlePrefixAndPrerelease() throws {
        #expect(try SemanticVersion("v1.2.3") > SemanticVersion("1.2.2"))
        #expect(try SemanticVersion("1.2.3") > SemanticVersion("1.2.3-beta.1"))
        #expect(try SemanticVersion("2.0") == SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    @Test
    func releaseDecoderSelectsMacArchiveAndChecksum() throws {
        let json = """
        {"tag_name":"v1.4.0","html_url":"https://github.com/wzz6423/zisla/releases/tag/v1.4.0","draft":false,"prerelease":false,"assets":[
          {"name":"zisla-macos.zip","browser_download_url":"https://example.com/app.zip","size":1234},
          {"name":"zisla-macos.zip.sha256","browser_download_url":"https://example.com/app.zip.sha256","size":64}
        ]}
        """

        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        let selection = release.macUpdateAssets

        let expectedVersion = try SemanticVersion("1.4.0")
        #expect(release.version == expectedVersion)
        #expect(selection?.archive.name == "zisla-macos.zip")
        #expect(selection?.checksum?.name.hasSuffix(".sha256") == true)
    }
}

struct FeatureSettingsTests {
    @Test
    func privacySensitiveDetectionDefaultsOffAndCoreModulesDefaultOn() {
        let settings = FeatureSettings.default
        #expect(settings.mediaEnabled)
        #expect(settings.fileShelfEnabled)
        #expect(settings.aiProgressEnabled)
        #expect(settings.downloaderEnabled)
        #expect(settings.updateChecksEnabled)
        #expect(!settings.clipboardDetectionEnabled)
        #expect(settings.sideNoticesEnabled)
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ZislaTests-\(UUID().uuidString)", isDirectory: true)
}

private func argument(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private func setSQLiteUserVersion(at url: URL, to version: Int) throws {
    try executeSQLite(at: url, sql: "PRAGMA user_version = \(version)")
}

private func insertLegacyManualUsage(_ sample: AIUsageSample, into url: URL) throws {
    try executeSQLite(
        at: url,
        sql: """
        INSERT INTO usage_samples(
            source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
        ) VALUES(
            NULL, '\(sample.provider.rawValue)', \(sample.timestamp.timeIntervalSinceReferenceDate),
            \(sample.inputTokens), \(sample.outputTokens), NULL, NULL
        )
        """
    )
}

private func executeSQLite(at url: URL, sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw SQLiteTestError.openFailed
    }
    defer { sqlite3_close(database) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer { sqlite3_free(errorMessage) }
    guard result == SQLITE_OK else { throw SQLiteTestError.statementFailed }
}

private enum SQLiteTestError: Error {
    case openFailed
    case statementFailed
}
