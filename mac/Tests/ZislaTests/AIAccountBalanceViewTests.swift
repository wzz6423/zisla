import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceViewTests {
    @Test func cardsHideUnavailableIncompleteAndUnsupportedReadings() {
        let quota = AIAccountQuotaWindow(id: "quota", kind: .all, remainingPercent: 70)
        let available = AIAccountBalance(id: "claude", providers: [.claude], status: .available, windows: [quota])
        let rows = [available,
            .init(id: "expired", providers: [.gemini], status: .credentialsExpired, windows: [quota]),
            .init(id: "empty", providers: [.zed], status: .available),
            .init(id: "partial", providers: [.kimi], status: .available,
                windows: [quota, .init(id: "missing", kind: .weekly)]),
            .init(id: "unsupported", providers: [.qwen], status: .available, windows: [quota])]
        let section = AIAccountBalanceSection(balances: rows,
            displayedProviders: Set(AIProvider.allCases), monitoredProviders: Set(AIProvider.allCases), language: .english)
        #expect(section.displayedBalances == [available])
    }

    @Test func hiddenBalanceSectionUsesNoHeight() {
        let section = AIAccountBalanceSection(balances: [], displayedProviders: [], monitoredProviders: [], language: .english)
        let host = NSHostingView(rootView: section.frame(width: 400).fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height == 0, "An empty balance selection must not leave an empty header")
    }

    @Test func cardsHonorTheExplicitMonitoringSelectionAcrossSharedAliases() {
        let reading = AIAccountBalance(id: "shared", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "quota", kind: .all, remainingPercent: 70)])
        #expect(AIAccountBalanceSection(balances: [reading], displayedProviders: [.gpt],
            monitoredProviders: [.codex], language: .english).displayedBalances.isEmpty)
        let section = AIAccountBalanceSection(balances: [reading], displayedProviders: [.gpt],
            monitoredProviders: [.gpt], language: .english)
        #expect(section.displayedBalances.first?.providers == [.gpt])
    }

    @Test func unboundedCardProposalUsesTheStandardModuleWidth() throws {
        let renderer = ImageRenderer(content: AIAccountBalanceCardLayout {
            ForEach(0..<4, id: \.self) { _ in Rectangle().fill(.white).frame(height: 40) }
        })
        let image = try #require(renderer.cgImage)
        #expect(image.width == 420 && image.height == 92)
    }


    /// Pixel regions prove camera clearance and both summary lines without treating an image render as device acceptance.
    @Test(arguments: [CGFloat(0), 80, 180], [false, true])
    func compactBalanceKeepsBothLinesOutsidePhysicalCameraGap(centerInset: CGFloat, rightToLeft: Bool) async throws {
        let width = centerInset + 320
        let notice = IslandNotice(id: "ai-balance-low-fixture", title: "Claude", style: .status,
            metadata: ["quotaProvider": "Claude", "quotaProviderID": "claude", "quotaRemainingFraction": "0.7",
                "quotaSeverity": "0", "quotaLine0": "5h 70%", "quotaLine1": "All Weekly 80%"])
        let image = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: 34, centerInset: centerInset)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight), size: CGSize(width: width, height: 34))
        let scale = CGFloat(image.pixelsWide) / width
        let leftEnd = Int((centerInset > 0 ? (width - centerInset) / 2 : 40) * scale)
        let rightStart = Int((centerInset > 0 ? (width + centerInset) / 2 : 44) * scale)
        var leftPixels = 0, rightTop = 0, rightBottom = 0, cameraPixels = 0
        for x in 0..<image.pixelsWide {
            for y in 0..<image.pixelsHigh {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.5 else { continue }
                if x < leftEnd { leftPixels += 1 }
                else if x >= rightStart {
                    if y < image.pixelsHigh / 2 { rightTop += 1 } else { rightBottom += 1 }
                } else { cameraPixels += 1 }
            }
        }
        #expect(cameraPixels == 0, "Balance text must not overlap the physical camera")
        #expect(leftPixels > 0)
        #expect(rightTop > 0 && rightBottom > 0, "The detailed compact style must render both quota lines")
    }

    /// Offscreen rendering covers edge-dependent dimensions and nonempty quota content across LTR and RTL layouts.
    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [AppLanguage.simplifiedChinese, .english, .arabic])
    func customAndFloatingShapesRenderTwoQuotaLines(edge: IslandEdge, language: AppLanguage) throws {
        let thickness: CGFloat = 34, length: CGFloat = 300
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Gemini", style: .status,
            metadata: ["quotaProvider": "Gemini", "quotaSeverity": "1", "quotaLine0": "5h 20%", "quotaLine1": AppLocalization.string("每周额度", language: language) + " 70%"])
        let renderer = ImageRenderer(content: CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge)
            .frame(width: edge.isVertical ? thickness : length, height: edge.isVertical ? length : thickness)
            .background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int((edge.isVertical ? thickness : length) * 2))
        #expect(image.height == Int((edge.isVertical ? length : thickness) * 2))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var colored = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.5 { colored += 1 }
            }
        }
        #expect(colored > 0)
    }

    /// The ring replaces the old stacked provider name while the quota retains its measured row budget.
    @Test(arguments: [IslandEdge.left, .right], [(CGFloat(32), false), (32, true), (34, false), (34, true)])
    func verticalBalanceReservesRingAndKeepsQuotaWhenConstrained(
        edge: IslandEdge, configuration: (CGFloat, Bool)
    ) throws {
        let (thickness, rightToLeft) = configuration
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Claude", style: .status,
            metadata: ["quotaProvider": "Claude", "quotaSeverity": "0", "quotaRemainingFraction": "0.7", "quotaLine0": "5h 70%"])
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        #expect(presentation.length(thickness: thickness, edge: edge) == (thickness == 32 ? 110 : 98),
            "Natural length must reserve the ring, two insets, a 6pt gap, and all actual quota rows")
        for length in [presentation.length(thickness: thickness, edge: edge), CGFloat(88)] {
            let renderer = ImageRenderer(content: CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge)
                .frame(width: thickness, height: length).background(.black).foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            var ringPixels = 0, quotaPixels = 0, outsidePixels = 0
            let ringEnd = Int((12 + thickness - 8) * 2)
            let quotaStart = ringEnd + 12
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    guard color.redComponent > 0.05 else { continue }
                    if y < 24 || y >= bitmap.pixelsHigh - 24 { outsidePixels += 1 }
                    else if y < ringEnd { ringPixels += 1 }
                    else if y >= quotaStart { quotaPixels += 1 }
                }
            }
            #expect(ringPixels > 30 && quotaPixels > 30, "The provider ring and quota must both survive at \(thickness)×\(length)pt")
            #expect(outsidePixels == 0, "Vertical content must remain within its two measured outer insets")
        }
    }

    @Test func cardGridUsesTwoOrThreeColumnsAndMirrorsOnlyItsPlacement() throws {
        for (width, expectedHeight) in [(CGFloat(420), CGFloat(144)), (600, 92), (1_000, 92)] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let renderer = ImageRenderer(content: AIAccountBalanceCardLayout(direction: direction) {
                    ForEach(0..<6, id: \.self) { _ in Rectangle().fill(.white).frame(height: 40) }
                }.frame(width: width).fixedSize(horizontal: false, vertical: true).background(.black))
                renderer.scale = 1
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                #expect(bitmap.pixelsHigh == Int(expectedHeight))
                #expect(bitmap.pixelsWide == Int(width))
                let columns = width == 420 ? 2 : 3
                let cardWidth = (width - CGFloat(columns - 1) * 12) / CGFloat(columns)
                for column in 0..<columns {
                    let center = Int(CGFloat(column) * (cardWidth + 12) + cardWidth / 2)
                    #expect(try #require(bitmap.colorAt(x: center, y: 20)).redComponent > 0.9)
                    if column < columns - 1 {
                        let gap = Int(CGFloat(column + 1) * (cardWidth + 12) - 6)
                        #expect(try #require(bitmap.colorAt(x: gap, y: 20)).redComponent < 0.1)
                    }
                }
            }
        }
        let balances = [AIProvider.claude, .gemini, .kimi, .grok, .coder, .zed].map {
            AIAccountBalance(id: $0.rawValue, providers: [$0], status: .available,
                windows: [.init(id: "quota", kind: .all, remainingPercent: 70)])
        }
        func sectionHeight(_ width: CGFloat) -> CGFloat {
            let host = NSHostingView(rootView: AIAccountBalanceSection(balances: balances,
                displayedProviders: Set(AIProvider.allCases), monitoredProviders: Set(AIProvider.allCases), language: .english)
                .frame(width: width).fixedSize(horizontal: false, vertical: true))
            return host.fittingSize.height
        }
        #expect(sectionHeight(420) > sectionHeight(600) + 60,
            "The real balance section must use the full width for its supplier cards")
    }

    @Test(arguments: [(Double(20), AIAccountQuotaSeverity.warning), (10, .critical), (0, .exhausted), (100, .normal)])
    func ringShowsRealRemainingArcAndThresholdColor(configuration: (Double, AIAccountQuotaSeverity)) throws {
        let (percent, severity) = configuration
        let renderer = ImageRenderer(content: AIAccountQuotaRing(provider: nil, fraction: percent / 100,
            severity: severity, diameter: 42).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var bright = 0, track = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let level = max(color.redComponent, color.greenComponent, color.blueComponent)
                if level > 0.45 {
                    bright += 1
                    if percent == 20, level > 0.8 { #expect(color.greenComponent > 0.6 && color.blueComponent < 0.3) }
                    if percent == 10, level > 0.8 { #expect(color.redComponent > color.greenComponent * 2) }
                } else if level > 0.02 { track += 1 }
            }
        }
        #expect(track > 0)
        #expect(percent == 0 ? bright == 0 : bright > 80)
        if percent == 20 || percent == 10 { #expect(bright < 500, "A low remaining quota must not render a mostly full ring") }
    }

    @Test func unknownAmountHasOnlyTheTrackAndNoFabricatedArc() throws {
        let amount = AIAccountQuotaWindow(id: "amount", kind: .credits, remaining: 20, unit: .credits)
        let renderer = ImageRenderer(content: AIAccountQuotaRing(provider: nil, fraction: amount.remainingFraction,
            severity: amount.severity, diameter: 42).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var track = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                #expect(color.redComponent < 0.4)
                if color.redComponent > 0.02 { track += 1 }
            }
        }
        #expect(track > 100)
    }

    /// A queued quota must not undo swipe-to-hide for the real selected media, mail, or ordinary transient.
    @Test(arguments: ["media", "mail", "focus-transition", "headphone", "pinned", "voice", "camera"])
    func queuedPinnedQuotaKeepsOnlyItsSelectedStatusVisible(kind: String) throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: kind == "camera" ? .camera : .custom, edge: .left))
        settings.activityNoticeDisplayDuration = .threeSeconds
        settings.focusModeNoticeDisplayDuration = .threeSeconds
        settings.aiAccountBalancePinnedInCustomIsland = true
        let pinned = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Quota", style: .status)
        let selectedID: String?
        let priority: CompactStatusPriority?
        switch kind {
        case "media": (selectedID, priority) = ("media-active-fixture", .media)
        case "mail": (selectedID, priority) = ("mail-notification-fixture", .mail)
        case "focus-transition": (selectedID, priority) = ("focus-transition-fixture", .transient)
        case "headphone": (selectedID, priority) = ("headphone-fixture", .transient)
        case "voice": (selectedID, priority) = ("voice-processing-fixture", nil)
        case "camera": (selectedID, priority) = (nil, nil)
        default: (selectedID, priority) = (pinned.id, .aiAccountBalance)
        }
        settings.compactStatusPriority = priority.map { [$0, .aiAccountBalance] } ?? [.aiAccountBalance]
        let notices = [pinned] + (selectedID.flatMap { id in
            id == pinned.id ? nil : IslandNotice(id: id, title: "Selected", style: kind == "headphone" ? .headphone : .status)
        }.map { [$0] } ?? [])
        let presentation = SideNoticeLayoutEngine().compactBarSizing(for: notices, settings: settings)?.customPillPresentation
        #expect(presentation?.notice.id == selectedID, "The fixture must exercise the real \(kind) selection")
        #expect(presentation?.priority == priority)
        let state = SideNoticeDisplayState()
        _ = SideNoticePresenter.updateCompactVisibility(notices: notices, settings: settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: notices, settings: settings, displayState: state))
        #expect(state.compactStatusHidden == (kind != "pinned" && kind != "voice"),
            "Only a selected pinned quota or voice processing may force visibility with short activity durations")
    }

    /// A long model identity must consume extra vertical space instead of compressing values or overflowing a narrow RTL row.
    @Test func narrowRTLBalanceRowsWrapLongIdentityWithoutHorizontalOverflow() async throws {
        let window = AIAccountQuotaWindow(id: "model", kind: .model, remainingPercent: 10,
            resetsAt: Date(timeIntervalSince1970: 1_910_001_000), name: String(repeating: "gemini-long-model ", count: 6))
        let balance = AIAccountBalance(id: "fixture", providers: [.gemini], status: .available, windows: [window])
        let view = AIAccountBalanceSection(balances: [balance], displayedProviders: [.gemini], monitoredProviders: [.gemini], language: .arabic)
        let host = NSHostingView(rootView: view.frame(width: 240).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 500)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= 240.5)
        #expect(host.fittingSize.height > 70, "Long window identities must use additional lines instead of squeezing the quota value")
    }

    /// Large task counts must saturate the bounded upper viewport so quota below it remains reachable by outer scrolling.
    @Test func boundedTaskViewportLeavesBalanceReachableAfterManyTasks() {
        for count in [0, 1, 6, 20, 1_000] {
            let height = AIProgressModuleView.taskSectionHeight(taskCount: count, availableHeight: 500)
            #expect(height <= 360 && height <= 325)
        }
        #expect(AIProgressModuleView.taskSectionHeight(taskCount: 20, availableHeight: 500)
            == AIProgressModuleView.taskSectionHeight(taskCount: 1_000, availableHeight: 500))
        let balance = AIAccountBalance(id: "fixture", providers: [.claude], status: .notSignedIn)
        #expect(AIAccountBalanceSection(balances: [balance], displayedProviders: [], monitoredProviders: [], language: .english).displayedBalances.isEmpty)
    }

    @Test(arguments: [AIAccountBalanceStatus.notSignedIn, .credentialsExpired, .invalidResponse, .available])
    func settingsProviderStatusFollowsPublishedBalanceWithoutStartingRealDetectors(status: AIAccountBalanceStatus) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zisla-balance-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [],
            accountBalanceDetector: StatusDetector(status: status), accountBalanceNotificationCenter: NotificationCenter())
        defer { monitor.stop() }
        let statusView = AIAccountBalanceProviderStatus(monitor: monitor, provider: .claude, language: .english)
        let baseline = try await renderOffscreen(statusView.foregroundStyle(.white), size: CGSize(width: 180, height: 44))
        #expect(statusView.status == .notSignedIn)
        monitor.configureAccountBalanceProviders([.claude])
        monitor.start()
        for _ in 0..<400 {
            if monitor.accountBalances.first?.status == status { break }
            await Task.yield()
        }
        #expect(statusView.status == status)
        let refreshed = try await renderOffscreen(statusView.foregroundStyle(.white), size: CGSize(width: 180, height: 44))
        if status != .notSignedIn {
            #expect(baseline.tiffRepresentation != refreshed.tiffRepresentation,
                "The settings row must render the newly published localized status")
        }
    }

    @Test(arguments: [IslandEdge.top, .left])
    func sharedFloatingBalanceHonorsZeroLeadingInset(edge: IslandEdge) async throws {
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Claude", style: .status,
            metadata: ["quotaProviderID": "claude", "quotaRemainingFraction": "1.0", "quotaSeverity": "0", "quotaLine0": "5h 100%"])
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        let length = presentation.length(thickness: 32, edge: edge, leadingInset: 0)
        let size = CGSize(width: edge.isVertical ? 32 : length, height: edge.isVertical ? length : 32)
        let content = CompactPillStatusContent(presentation: presentation, text: "", edge: edge,
            visualizationStyle: .waveform, item: nil, date: .distantPast, leadingInset: 0)
        let bitmap = try await renderOffscreen(content.foregroundStyle(.white).environment(\.colorScheme, .dark), size: size)
        var firstPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard (edge.isVertical ? y : x) < 10,
                    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 else { continue }
                firstPixels += 1
            }
        }
        #expect(firstPixels > 0, "The first ring must use the caller's zero inset in the shared floating content")
    }

    private struct StatusDetector: AIAccountBalanceDetecting {
        let status: AIAccountBalanceStatus
        func accountBalances(for providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion) async throws -> [AIAccountBalance] {
            [.init(id: "status", providers: [.claude], status: status,
                windows: status == .available ? [.init(id: "quota", kind: .all, remainingPercent: 70)] : [])]
        }
    }

    @Test(arguments: [IslandEdge.top, .left], [false, true])
    func longBalanceSummaryScrollsInsideItsViewportAndHonorsReduceMotion(edge: IslandEdge, reduceMotion: Bool) async throws {
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Gemini", style: .status,
            metadata: ["quotaRemainingFraction": "0.7", "quotaSeverity": "0",
                "quotaLine0": "全部 " + String(repeating: "gemini-model 70% · ", count: 8) + "weekly 80%"])
        let size = CGSize(width: edge.isVertical ? 34 : 156, height: edge.isVertical ? 156 : 34)
        let content = CompactAIAccountBalanceBar(notice: notice, height: 34, edge: edge)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
        let first = try await renderOffscreen(content, size: size, reduceMotion: reduceMotion, progress: 0)
        let last = try await renderOffscreen(content, size: size, reduceMotion: reduceMotion, progress: 1)
        var changed = 0
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                let a = try #require(first.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(last.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(reduceMotion ? changed == 0 : changed > 30,
            "Only overflowing quota text may move, and Reduce Motion keeps its first viewport stationary")
        #expect(first.pixelsWide == last.pixelsWide && first.pixelsHigh == last.pixelsHigh)
    }


    @Test func rotatingAccountsWithEqualQuotaTextRestartAtTheBeginningAndSamePollKeepsProgress() async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let windows = [AIAccountQuotaWindow(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
            .init(id: "weekly", kind: .weekly, remainingPercent: 70)]
        let rows = [AIProvider.claude, .codex].map {
            AIAccountBalance(id: $0.rawValue, providers: [$0], status: .available, windows: windows)
        }
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.claude, .codex],
            aiAccountBalanceDisplayedProviders: [.claude, .codex])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSince1970: 100))
        let first = try #require(queue.left.first)
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: first, text: "")
        let size = CGSize(width: 34, height: presentation.length(thickness: 34, edge: .left))
        func content(_ notice: IslandNotice, progress: Double) -> some View {
            CompactAIAccountBalanceBar(notice: notice, height: 34, edge: .left)
                .frame(width: size.width, height: size.height).background(.black).foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .transaction { transaction in
                    if transaction.animation != nil, !transaction.disablesAnimations {
                        transaction.animation = Animation(FrozenProgress(progress: progress))
                    }
                }
        }
        let host = NSHostingView(rootView: content(first, progress: 1))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        func sample() async throws -> NSBitmapImageRep {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            for _ in 0..<16 {
                host.layoutSubtreeIfNeeded()
                host.cacheDisplay(in: host.bounds, to: bitmap)
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
            return try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        }
        func changes(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> Int {
            var count = 0
            for y in Int(44 * CGFloat(a.pixelsHigh) / size.height)..<a.pixelsHigh {
                for x in 0..<a.pixelsWide {
                    let first = try #require(a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let second = try #require(b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if abs(first.redComponent - second.redComponent) > 0.02 { count += 1 }
                }
            }
            return count
        }
        let tail = try await sample()
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSince1970: 101))
        host.rootView = content(try #require(queue.left.first), progress: 0)
        #expect(try changes(tail, await sample()) == 0, "The same account's ordinary poll must not restart its reading")
        controller.updatePinned(at: Date(timeIntervalSince1970: 120))
        let rotated = try #require(queue.left.first)
        #expect(rotated.metadata?["quotaAccountID"] == "codex")
        host.rootView = content(rotated, progress: 0)
        let restarted = try await sample()
        let beginning = try await renderOffscreen(content(rotated, progress: 0), size: size)
        #expect(try changes(restarted, beginning) == 0, "A new account with identical lines must start from its first quota viewport")
        #expect(try changes(tail, restarted) > 30, "The fixture must have an overflowing weekly line to distinguish the tail")
    }
    private func renderOffscreen(_ content: some View, size: CGSize, reduceMotion: Bool = false,
                                 progress: Double = 0) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(.black)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                if transaction.animation != nil, !transaction.disablesAnimations {
                    transaction.animation = Animation(FrozenProgress(progress: progress))
                }
            })
        host.sizingOptions = []
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(!panel.isVisible && panel.frame.size == size)
        return try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
    }

    private struct FrozenProgress: CustomAnimation {
        let progress: Double
        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }
}
