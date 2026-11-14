import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla
@testable import ZislaKit

@MainActor
struct AICompactMascotTests {
    private let date = Date(timeIntervalSince1970: 100)

    @Test(arguments: IslandEdge.allCases, [false, true])
    func floatingAIKeepsEveryProviderInsideItsExistingIconSlot(edge: IslandEdge, showsInformation: Bool) throws {
        let settings = FeatureSettings(statusIconDestination: .island,
            islandShowMoreInformation: showsInformation, islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        let singleProvider = (0..<3).map { notice(provider: .gpt, id: String($0)) }
        let multipleProviders = [singleProvider[0], notice(provider: .claude, id: "1"), notice(provider: .claude, id: "2")]
        let engine = SideNoticeLayoutEngine()
        let presentation = try #require(engine.compactPillPresentations(for: multipleProviders, settings: settings).first)
        #expect(presentation.aiCount == 3 && presentation.text == "3", "Provider deduplication must not reduce the task count")
        let length = presentation.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        func rendered(_ notices: [IslandNotice], direction: LayoutDirection) throws -> NSBitmapImageRep {
            if showsInformation {
                let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
                    settings: settings, item: nil, at: date))
                #expect(layout.size == size, "Stacked providers must not widen the information row")
                return try render(FloatingIslandInformationView(layout: layout, visualizationStyle: .waveform,
                    item: nil, date: date), size: size, direction: direction)
            }
            let value = try #require(engine.compactPillPresentations(for: notices, settings: settings).first)
            #expect(value.length(thickness: 32, edge: edge) == length)
            return try render(CompactPillStatusContent(presentation: value, text: value.text,
                edge: edge, visualizationStyle: .waveform, item: nil, date: date), size: size, direction: direction)
        }
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let single = try rendered(singleProvider, direction: direction)
            let multiple = try rendered(multipleProviders, direction: direction)
            let forward = edge.isVertical || direction == .leftToRight
            let iconRange = forward ? CGFloat(12)..<36 : (length - 36)..<(length - 12)
            let countRange = forward ? CGFloat(36)..<length : CGFloat(0)..<(length - 36)
            #expect(try differentPixels(single, multiple, edge: edge, range: iconRange) > 20,
                    "Changing a later task to another provider must change the visible icon stack")
            #expect(try differentPixels(single, multiple, edge: edge, range: countRange) == 0,
                    "Additional provider icons must stay within the existing icon slot and leave the count untouched")
            #expect(try orangePixels(multiple, edge: edge, range: iconRange) > 10,
                    "The later Claude provider must remain visible beside the ChatGPT logo")
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func rightToLeftProviderStacksStayInsideTheOriginalIconSlot(edge: IslandEdge) throws {
        let gpt = notice(provider: .gpt, id: "first")
        let claude = notice(provider: .claude, id: "second")
        let qwen = notice(provider: .qwen, id: "third")
        let size = CGSize(width: 40, height: 40)
        let empty = try render(Color.clear, size: size)
        for notices in [[gpt, claude], [gpt, qwen, claude]] {
            let content = AIMascotStack(notices: notices, size: 24, edge: edge)
            let leftToRight = try render(content, size: size, direction: .leftToRight)
            let rightToLeft = try render(content, size: size, direction: .rightToLeft)
            #expect(try differentPixels(leftToRight, rightToLeft, edge: edge, range: 0..<40) == 0,
                    "Changing the language direction must preserve each provider's physical position inside its icon slot")
            for axis in [IslandEdge.top, .left] {
                for margin in [CGFloat(0)..<8, CGFloat(32)..<40] {
                    #expect(try differentPixels(empty, rightToLeft, edge: axis, range: margin) == 0,
                            "Provider pixels must not escape the centered 24pt slot in either direction")
                }
            }
            #expect(try orangePixels(rightToLeft, edge: edge, range: 8..<32) > 10,
                    "The later provider must remain visible inside the slot")
        }
    }

    @Test
    func repeatedTasksKeepOneIconAndUnknownNoticesCannotConsumeAProviderSlot() {
        let gpt = notice(provider: .gpt, id: "first")
        let claude = notice(provider: .claude, id: "second")
        let qwen = notice(provider: .qwen, id: "third")
        let gemini = notice(provider: .gemini, id: "fourth")
        let invalid = IslandNotice(id: "ai-active-unknown-fixture", title: "Unknown")
        let notices = [invalid, gpt, notice(provider: .gpt, id: "another-task"), claude, qwen, gemini]
        #expect(AIMascotIdentity.stackIdentities(for: notices) == [.gpt, .claude, .qwen])
        #expect(AIMascotIdentity.stackIdentities(for: [gpt, gpt]) == [.gpt])
        #expect(AIMascotIdentity.stackIdentities(for: []).isEmpty)
        #expect(AIMascotIdentity.stackIdentities(for: [invalid]).isEmpty)
    }

    @Test
    func aSharedProviderRetainsDistinctDesktopAndHarnessBrands() {
        let notices = [
            notice(provider: .gemini, id: "gemini-desktop-chat-c1"),
            notice(provider: .gemini, id: "gemini-session-s1"),
            IslandNotice(id: "ai-active-harness-dsh-session", title: "DeepSeek Harness"),
        ]
        #expect(AIMascotIdentity.stackIdentities(for: notices) == [.geminiDesktop, .gemini, .deepseekHarness])
    }

    @Test(arguments: IslandEdge.allCases)
    func threeProviderLimitAndDuplicateTasksPreserveStackPixels(edge: IslandEdge) throws {
        let first = notice(provider: .gpt, id: "one")
        let second = notice(provider: .claude, id: "two")
        let third = notice(provider: .qwen, id: "three")
        let fourth = notice(provider: .gemini, id: "four")
        func stack(_ notices: [IslandNotice]) throws -> NSBitmapImageRep {
            try render(AIMascotStack(notices: notices, size: 24, edge: edge), size: CGSize(width: 24, height: 24))
        }
        let single = try stack([first])
        let reference = try render(AIMascotView(identity: .gpt, size: 24), size: CGSize(width: 24, height: 24))
        #expect(try differentPixels(single, reference, edge: edge, range: 0..<24) == 0,
                "A single provider must retain the original icon's size and pixels")
        #expect(try differentPixels(single, stack([first, first]), edge: edge, range: 0..<24) == 0)
        let two = try stack([first, second])
        let three = try stack([first, second, third])
        #expect(try differentPixels(two, three, edge: edge, range: 0..<24) > 20,
                "The third distinct provider must still contribute visible pixels")
        #expect(try differentPixels(three, stack([first, second, third, fourth]), edge: edge, range: 0..<24) == 0,
                "The fourth provider must not grow the stack beyond its three-icon limit")
        #expect(try differentPixels(three, stack([first, first, second, third]), edge: edge, range: 0..<24) == 0,
                "Duplicate tasks must not shift or hide another provider's icon")
        let empty = try render(Color.clear, size: CGSize(width: 24, height: 24))
        #expect(try differentPixels(empty, stack([]), edge: edge, range: 0..<24) == 0)
    }

    @Test(arguments: IslandEdge.allCases)
    func manuallyConstructedAIContentKeepsItsSingleProvider(edge: IslandEdge) throws {
        let notice = notice(provider: .claude, id: "single")
        let legacy = CompactPillStatusPresentation(priority: .aiActivity, notice: notice, text: "1")
        let current = CompactPillStatusPresentation(priority: .aiActivity, notice: notice, text: "1", aiNotices: [notice])
        let length = legacy.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        func content(_ presentation: CompactPillStatusPresentation) throws -> NSBitmapImageRep {
            try render(CompactPillStatusContent(presentation: presentation, text: "1", edge: edge,
                visualizationStyle: .waveform, item: nil, date: date), size: size)
        }
        #expect(try differentPixels(content(legacy), content(current), edge: edge, range: 0..<length) == 0)
        #expect(try orangePixels(content(legacy), edge: edge, range: 12..<36) > 10)
    }

    @Test(arguments: IslandEdge.allCases, [AIProgressStatus.succeeded, .failed, .error])
    func resultSweepsRetainAllProvidersUntilTheCompletedClientIsReleased(edge: IslandEdge, status: AIProgressStatus) throws {
        let suiteName = "Zisla.AICompactMascot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = FeatureSettingsStore(defaults: defaults)
        settings.settings.islandLayoutStyle = .pill
        settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        settings.settings.islandShowMoreInformation = false
        settings.settings.islandNotchBackground = .black
        settings.settings.collapsedProgressGlowEnabled = false
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController(now: { date })
        defer {
            sweep.cancel()
            queue.removeAll()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let running = notice(provider: .gpt, id: "running")
        queue.enqueue(running, expiresAfter: nil)
        let completed = AIProgressTask(id: "completed", provider: .claude, title: "Claude",
            progress: nil, status: status, updatedAt: date)
        sweep.receive(previous: .running, task: completed, observedSince: .distantPast, settings: settings.settings)
        let current = try #require(sweep.current)
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.compactWingHeight = 32
        let view = CompactStatusBarView(queue: queue, displayState: state, media: NowPlayingService(),
            browserDownloads: BrowserDownloadMonitor(directories: [], eventPaths: []), settingsStore: settings,
            resultSweep: sweep, pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults),
            onStatusHidden: {})
        let size = edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)
        let showingResult = try render(view.statusBarContent(at: date), size: size)
        #expect(view.activeAINotices.count == 2)
        #expect(try orangePixels(showingResult, edge: edge, range: 12..<36) > 10,
                "A client that exits must keep its own provider in the result stack until playback ends")
        sweep.finish(id: current.id)
        let finished = try render(view.statusBarContent(at: date), size: size)
        #expect(view.activeAINotices.map(\.id) == [running.id])
        #expect(try orangePixels(finished, edge: edge, range: 12..<36) == 0,
                "The completed provider must leave the stack when playback finishes")
        #expect(try differentPixels(showingResult, finished, edge: edge, range: 36..<68) > 0,
                "The task count must shrink together with the provider list")
    }

    private func notice(provider: AIProvider, id: String) -> IslandNotice {
        let task = AIProgressTask(id: id, provider: provider, title: provider.rawValue,
            progress: nil, status: .running, updatedAt: date)
        return IslandNotice(id: AIMascotLibrary.activeNoticeID(for: task), title: task.title)
    }

    private func render(_ content: some View, size: CGSize,
                        direction: LayoutDirection = .leftToRight) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height)
            .background(.black).environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, direction).environment(\._accessibilityReduceMotion, true))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private func differentPixels(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep,
                                 edge: IslandEdge, range: Range<CGFloat>) throws -> Int {
        #expect(first.pixelsWide == second.pixelsWide && first.pixelsHigh == second.pixelsHigh)
        var count = 0
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide where range.contains(CGFloat(edge.isVertical ? y : x) / 2) {
                let a = try #require(first.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(second.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(a.redComponent - b.redComponent) > 0.05 || abs(a.greenComponent - b.greenComponent) > 0.05
                    || abs(a.blueComponent - b.blueComponent) > 0.05 { count += 1 }
            }
        }
        return count
    }

    private func orangePixels(_ bitmap: NSBitmapImageRep, edge: IslandEdge, range: Range<CGFloat>) throws -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where range.contains(CGFloat(edge.isVertical ? y : x) / 2) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.5 && color.redComponent > color.greenComponent + 0.15
                    && color.greenComponent > color.blueComponent + 0.05 { count += 1 }
            }
        }
        return count
    }
}
