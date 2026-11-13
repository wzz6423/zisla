import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceViewTests {

    @Test(arguments: [AIProvider.codex, .gpt], [ColorScheme.light, .dark])
    func openAIProviderUsesTransparentBrandLogoWithItsOwnName(provider: AIProvider, colorScheme: ColorScheme) async throws {
        let cache = AIMascotImageCache()
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        let appIcon = NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 24, height: 24))
        try #require(cache.image(for: "installed|desktop-\(provider.rawValue)", load: { appIcon }) != nil)
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
        let asset = try #require(AIMascotLibrary.providerAssetName(for: provider))
        let cachedLogo = cache.image(for: "provider|\(asset)", url: {
            AIMascotLibrary.providerAssetURL(for: provider, resourceRoots: [resources])
        })
        let logo = try #require(cachedLogo)
        let source = NSBitmapImageRep(cgImage: try #require(logo.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        var transparentPixels = 0, visiblePixels = 0
        for y in 0..<source.pixelsHigh {
            for x in 0..<source.pixelsWide {
                let alpha = try #require(source.colorAt(x: x, y: y)).alphaComponent
                if alpha < 0.01 { transparentPixels += 1 }
                if alpha > 0.5 { visiblePixels += 1 }
            }
        }
        #expect(transparentPixels > source.pixelsWide * source.pixelsHigh / 5 && visiblePixels > 0,
            "Brand logos must have transparent space around a visible glyph, without an app-icon backplate")
        let identity = AIMascotIdentity(provider: provider, taskID: "")
        #expect(identity.displayName == (provider == .gpt ? "ChatGPT" : "Codex"))
        let bitmap = try await renderOffscreen(AIMascotView(identity: identity, size: 24, imageCache: cache)
            .environment(\.colorScheme, colorScheme), size: CGSize(width: 24, height: 24))
        let reference = try await renderOffscreen(Image(nsImage: logo)
            .renderingMode(provider == .gpt ? .template : .original).resizable().interpolation(.high).scaledToFit()
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 24, height: 24), size: CGSize(width: 24, height: 24))
        var changedPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let actual = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let expected = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(actual.redComponent - expected.redComponent) > 0.02
                    || abs(actual.greenComponent - expected.greenComponent) > 0.02
                    || abs(actual.blueComponent - expected.blueComponent) > 0.02 { changedPixels += 1 }
            }
        }
        #expect(changedPixels == 0, "The AI icon must render the transparent brand logo even when an installed app icon is cached")
    }

    @Test(arguments: [CGFloat(32), 52])
    func concentricQuotaRingsKeepFiveHoursInsideAndWeekOutside(diameter: CGFloat) throws {
        func render(_ inner: Double?, _ innerSeverity: AIAccountQuotaSeverity?, _ outer: Double?,
                    _ outerSeverity: AIAccountQuotaSeverity? = .normal) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: AIAccountQuotaRing(provider: nil, fraction: outer,
                severity: outerSeverity, diameter: diameter, innerFraction: inner, innerSeverity: innerSeverity)
                .background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark))
            renderer.scale = 3
            let image = try #require(renderer.cgImage)
            return try #require(NSBitmapImageRep(cgImage: image).converting(to: .sRGB, renderingIntent: .default))
        }
        let dual = try render(0.1, .critical, 0.51)
        let weekOnly = try render(nil, nil, 0.51)
        let resetFiveHours = try render(1, .normal, 0.51)
        let fiveHoursOnly = try render(0.1, .critical, nil, nil)
        let scale = CGFloat(dual.pixelsWide) / diameter
        let center = CGFloat(dual.pixelsWide) / 2
        var innerRed = 0, innerColored = 0, outerGreen = 0, outerColored = 0
        var missingInner = 0, missingOuter = 0, changedOuter = 0
        for y in 0..<dual.pixelsHigh {
            for x in 0..<dual.pixelsWide {
                let radius = hypot(CGFloat(x) + 0.5 - center, CGFloat(y) + 0.5 - center) / scale
                let color = try #require(dual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let missing = try #require(weekOnly.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let changed = try #require(resetFiveHours.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let only = try #require(fiveHoursOnly.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if radius < diameter * 0.36 {
                    if color.redComponent > 0.65 && color.redComponent > color.greenComponent * 2 { innerRed += 1 }
                    if color.redComponent > 0.03 { innerColored += 1 }
                    if max(missing.redComponent, missing.greenComponent, missing.blueComponent) > 0.03 { missingInner += 1 }
                } else {
                    if color.greenComponent > 0.45 && color.greenComponent > color.redComponent * 1.4
                        && color.greenComponent > color.blueComponent * 1.15 { outerGreen += 1 }
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.03 { outerColored += 1 }
                    if max(only.redComponent, only.greenComponent, only.blueComponent) > 0.03 { missingOuter += 1 }
                    if abs(color.redComponent - changed.redComponent) > 0.02
                        || abs(color.greenComponent - changed.greenComponent) > 0.02 { changedOuter += 1 }
                }
            }
        }
        #expect(innerRed > 80 && outerGreen > 100)
        #expect((0.07...0.22).contains(Double(innerRed) / Double(innerColored)))
        #expect((0.4...0.65).contains(Double(outerGreen) / Double(outerColored)))
        #expect(missingInner == 0, "A missing five-hour window must leave no inner track")
        #expect(missingOuter == 0, "A five-hour-only account must leave no fabricated weekly track")
        #expect(changedOuter == 0, "Resetting five hours cannot change the independent weekly ring")
    }

    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [(CGFloat(32), false), (32, true), (34, false), (34, true)])
    func realChatGPTNoticeSharesTheDoubleRingAndTwoRemainingRows(edge: IslandEdge, configuration: (CGFloat, Bool)) async throws {
        let (thickness, rightToLeft) = configuration
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "chatgpt", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)])
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.gpt],
            aiAccountBalanceDisplayedProviders: [.gpt])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        controller.update(balances: [reading], settings: settings, language: .english)
        let notice = try #require(queue.left.first)
        #expect(notice.title == "ChatGPT" && notice.metadata?["quotaProviderID"] == "gpt")
        #expect(notice.metadata?["quotaLine0"] == "5h 10%" && notice.metadata?["quotaLine1"] == "7d 51%")
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        let length = presentation.length(thickness: thickness, edge: edge)
        let size = CGSize(width: edge.isVertical ? thickness : length, height: edge.isVertical ? length : thickness)
        let bitmap = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight), size: size, reduceMotion: true)
        var red = 0, green = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let axis = edge.isVertical ? y : x
                guard CGFloat(axis) / (CGFloat(edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide) / length) > 46 else { continue }
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.5 && color.greenComponent < 0.3 { red += 1 }
                if color.greenComponent > 0.45 && color.greenComponent > color.redComponent * 1.4
                    && color.greenComponent > color.blueComponent * 1.15 { green += 1 }
            }
        }
        #expect(red > 10 && green > 10, "Critical five-hour values must stay red while healthy weekly values are green")

        let expectedRing = try await renderOffscreen(AIAccountQuotaRing(provider: .gpt, fraction: 0.51,
            severity: .normal, diameter: thickness - 8, innerFraction: 0.1, innerSeverity: .critical)
            .foregroundStyle(.white).environment(\.colorScheme, .dark),
            size: CGSize(width: thickness - 8, height: thickness - 8))
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let ringX = Int((edge.isVertical ? 4 : 12) * scale)
        let ringY = Int((edge.isVertical ? 12 : 4) * scale)
        var differentRingPixels = 0
        for y in 0..<expectedRing.pixelsHigh {
            for x in 0..<expectedRing.pixelsWide {
                let a = try #require(bitmap.colorAt(x: x + ringX, y: y + ringY)?.usingColorSpace(.sRGB))
                let b = try #require(expectedRing.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(a.redComponent - b.redComponent) > 0.02 || abs(a.greenComponent - b.greenComponent) > 0.02 {
                    differentRingPixels += 1
                }
            }
        }
        #expect(differentRingPixels == 0, "The real notice must map five hours to the inner arc and weekly quota to the outer arc")

        let ringPixels = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge)
            .foregroundStyle(.white).environment(\.colorScheme, .dark), size: size, reduceMotion: true)
        settings.aiAccountBalanceCompactStyle = .compact
        controller.update(balances: [reading], settings: settings, language: .english)
        let brief = try #require(queue.left.first)
        let briefPixels = try await renderOffscreen(CompactAIAccountBalanceBar(notice: brief, height: thickness, edge: edge)
            .foregroundStyle(.white).environment(\.colorScheme, .dark), size: size, reduceMotion: true)
        for y in 0..<ringPixels.pixelsHigh {
            for x in 0..<ringPixels.pixelsWide {
                let scale = CGFloat(edge.isVertical ? ringPixels.pixelsHigh : ringPixels.pixelsWide) / length
                let position = CGFloat(edge.isVertical ? y : x) / scale
                guard position >= 12 && position < 12 + thickness - 8 else { continue }
                let a = try #require(ringPixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(briefPixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                #expect(abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02,
                    "Brief and full modes share the same real two-ring quota mark")
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark], [IslandEdge.top, .left])
    func healthyNoticeRendersGreenRingsAndBothQuotaValues(colorScheme: ColorScheme, edge: IslandEdge) async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "healthy", providers: [.gpt], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 80, durationSeconds: 604_800)])
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.gpt],
            aiAccountBalanceDisplayedProviders: [.gpt])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        controller.update(balances: [reading], settings: settings, language: .english)
        let notice = try #require(queue.left.first)
        #expect(notice.metadata?["quotaLine0"] == "5h 70%" && notice.metadata?["quotaLine1"] == "7d 80%")
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        let length = presentation.length(thickness: 34, edge: edge)
        let size = CGSize(width: edge.isVertical ? 34 : length, height: edge.isVertical ? length : 34)
        let bitmap = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: 34, edge: edge)
            .foregroundStyle(.white).environment(\.colorScheme, colorScheme), size: size, reduceMotion: true)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        var ringGreen = 0, lineGreen = [0, 0]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                guard color.greenComponent > 0.45 && color.greenComponent > color.redComponent * 1.4
                    && color.greenComponent > color.blueComponent * 1.15 else { continue }
                if CGFloat(edge.isVertical ? y : x) / scale < 44 { ringGreen += 1 }
                else {
                    let line = edge.isVertical ? (x < bitmap.pixelsWide / 2 ? 0 : 1) : (y < bitmap.pixelsHigh / 2 ? 0 : 1)
                    lineGreen[line] += 1
                }
            }
        }
        #expect(ringGreen > 20, "Healthy compact quota arcs must render green in both color schemes")
        #expect(lineGreen.allSatisfy { $0 > 10 }, "Both healthy remaining values must render green independently")
    }

    @Test(arguments: [AIProvider.codex, .gpt])
    func selectedQuotaRingUsesTheSameProviderAssetAsAITasks(provider: AIProvider) async throws {
        let diameter: CGFloat = 52
        let reading = AIAccountBalance(id: "shared", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)])
        let section = AIAccountBalanceSection(balances: [reading], displayedProviders: [provider],
            monitoredProviders: [provider], language: .english)
        let selected = try #require(section.displayedBalances.first)
        #expect(section.displayedBalances.count == 1 && selected.displayProvider == provider)
        let ring = AIAccountQuotaRing(provider: selected.displayProvider, fraction: 0.51, severity: .normal, diameter: diameter,
            innerFraction: 0.1, innerSeverity: .critical)
        let actual = try await renderOffscreen(ring.foregroundStyle(.white).environment(\.colorScheme, .dark),
            size: CGSize(width: diameter, height: diameter))
        let expected = try await renderOffscreen(AIMascotView(identity: AIMascotIdentity(provider: provider, taskID: ""), size: diameter * 0.36)
            .frame(width: diameter, height: diameter).foregroundStyle(.white).environment(\.colorScheme, .dark),
            size: CGSize(width: diameter, height: diameter))
        let tracks = try await renderOffscreen(AIAccountQuotaRing(provider: nil, fraction: 0.51, severity: .normal,
            diameter: diameter, innerFraction: 0.1, innerSeverity: .critical)
            .foregroundStyle(.white).environment(\.colorScheme, .dark), size: CGSize(width: diameter, height: diameter))
        var markPixels = 0
        let scale = CGFloat(actual.pixelsWide) / diameter
        let center = CGFloat(actual.pixelsWide) / 2
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if hypot(CGFloat(x) + 0.5 - center, CGFloat(y) + 0.5 - center) / scale < diameter * 0.23 {
                    #expect(abs(a.redComponent - b.redComponent) < 0.02)
                }
                if b.redComponent > 0.3 {
                    markPixels += 1
                    let track = try #require(tracks.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    #expect(max(track.redComponent, track.greenComponent, track.blueComponent) < 0.03,
                        "The selected provider mark must sit inside the inner ring without touching its stroke")
                }
            }
        }
        #expect(markPixels > 40, "The centered provider mark must use the same bundled asset as AI tasks")
    }

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


    /// Pixel regions prove bounded padding and camera clearance without treating an image render as device acceptance.
    @Test(arguments: [CGFloat(0), 80, 180], [false, true])
    func compactBalanceKeepsBothLinesOutsidePhysicalCameraGap(centerInset: CGFloat, rightToLeft: Bool) async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        for weeklyOnly in [false, true] {
            let weekly = AIAccountQuotaWindow(id: "weekly", kind: .weekly, remainingPercent: 59, durationSeconds: 604_800)
            let short = AIAccountQuotaWindow(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000)
            var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
            settings.islandPlacement.mode = .custom
            controller.update(balances: [.init(id: "chatgpt", providers: [.codex], status: .available,
                windows: weeklyOnly ? [weekly] : [short, weekly])], settings: settings, language: .english)
            let notice = try #require(queue.left.first)
            #expect(notice.metadata?["quotaLine0"] == (weeklyOnly ? "7d 59%" : "5h 10%"))
            #expect(notice.metadata?["quotaLine1"] == (weeklyOnly ? nil : "7d 59%"))
            let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
            let sideWidth = presentation.accountBalanceSideWidth(thickness: 34)
            let width = centerInset > 0 ? centerInset + sideWidth * 2 : presentation.length(thickness: 34, edge: .top)
            if centerInset > 0 {
                #expect(sideWidth <= 57, "Canonical camera wings must not retain the old wide padding; observed \(sideWidth)pt")
            }
            for colorScheme in [ColorScheme.light, .dark] {
                let image = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: 34, centerInset: centerInset)
                    .foregroundStyle(.white).environment(\.colorScheme, colorScheme)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight),
                    size: CGSize(width: width, height: 34), reduceMotion: true)
                let scale = CGFloat(image.pixelsWide) / width
                let leftEnd = centerInset > 0 ? sideWidth : 38
                let rightStart = centerInset > 0 ? sideWidth + centerInset : 44
                var ringBounds = CGRect.null, rowBounds = [CGRect.null, CGRect.null], cameraPixels = 0
                for x in 0..<image.pixelsWide {
                    for y in 0..<image.pixelsHigh {
                        let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        guard max(color.redComponent, color.greenComponent, color.blueComponent)
                            > (CGFloat(x) / scale < leftEnd ? 0.03 : 0.3) else { continue }
                        let pixel = CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1 / scale, height: 1 / scale)
                        if pixel.midX < leftEnd { ringBounds = ringBounds.union(pixel) }
                        else if pixel.midX >= rightStart {
                            let row = weeklyOnly || y < image.pixelsHigh / 2 ? 0 : 1
                            rowBounds[row] = rowBounds[row].union(pixel)
                        } else { cameraPixels += 1 }
                    }
                }
                #expect(cameraPixels == 0, "Balance text must leave the physical camera gap empty")
                #expect(!ringBounds.isNull && !rowBounds[0].isNull)
                #expect(weeklyOnly ? rowBounds[1].isNull : !rowBounds[1].isNull,
                    "Default compact quota must render exactly the real one or two rows")
                #expect(rowBounds[0].width >= 27, "The full short quota label and percentage must remain visible")
                if !weeklyOnly {
                    #expect(rowBounds[1].width >= 27)
                    #expect(rowBounds[1].midY - rowBounds[0].midY <= 12,
                        "Two quota rows must stack as tightly as the combined monitor readings")
                }
                if centerInset > 0 {
                    #expect(ringBounds.minX <= 16 && sideWidth - ringBounds.maxX <= 16,
                        "The provider ring must leave at most 16pt of visible padding on each camera-wing edge; observed \(ringBounds.minX), \(sideWidth - ringBounds.maxX)pt")
                    let textBounds = rowBounds[0].union(rowBounds[1])
                    #expect(textBounds.minX - rightStart <= 10 && width - textBounds.maxX <= 10,
                        "Short quota text must leave only its compact edge padding")
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func compactQuotaRowsUseTheCombinedMonitorDigitTypography(weeklyOnly: Bool) async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let weekly = AIAccountQuotaWindow(id: "weekly", kind: .weekly, remainingPercent: 59, durationSeconds: 604_800)
        let short = AIAccountQuotaWindow(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000)
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        controller.update(balances: [.init(id: "quota", providers: [.codex], status: .available,
            windows: weeklyOnly ? [weekly] : [short, weekly])], settings: settings, language: .english)
        let notice = try #require(queue.left.first)
        let lines = weeklyOnly ? ["7d 59%"] : ["5h 10%", "7d 59%"]
        let font = Font.system(size: weeklyOnly ? 11 : 9, weight: weeklyOnly ? .semibold : .medium).monospacedDigit()
        let width = CGFloat(68)
        let actual = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: 34)
            .environment(\.colorScheme, .dark).foregroundStyle(.white), size: CGSize(width: width + 56, height: 34),
            reduceMotion: true)
        let reference = try await renderOffscreen(VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line).font(font).foregroundStyle((!weeklyOnly && index == 0 ? AIAccountQuotaSeverity.critical : .normal).balanceColor)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: weeklyOnly ? 16 : 11).clipped()
            }
        }.environment(\.colorScheme, .dark), size: CGSize(width: width, height: 34), reduceMotion: true)
        let scale = CGFloat(actual.pixelsWide) / (width + 56)
        var differentTextPixels = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let a = try #require(actual.colorAt(x: x + Int(44 * scale), y: y)?.usingColorSpace(.sRGB))
                let b = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(a.redComponent - b.redComponent) > 0.02 || abs(a.greenComponent - b.greenComponent) > 0.02 {
                    differentTextPixels += 1
                }
            }
        }
        #expect(differentTextPixels == 0,
            "Compact quota must render monospaced digits with the monitor's 22pt double-row rhythm and the correct font weight")
    }

    @Test(arguments: [AppLanguage.english, .arabic])
    func detailedExtraQuotaRowsKeepAccentsAndArabicMarksInsideTheirViewport(language: AppLanguage) async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let model = AIAccountQuotaWindow(id: "model", kind: .model, remainingPercent: 59,
            name: language == .arabic ? "خُطَّة مُمَيَّزَة" : "Édition Ångström")
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        controller.update(balances: [.init(id: "quota", providers: [.codex], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000), model])],
            settings: settings, language: language)
        let notice = try #require(queue.left.first)
        let line = try #require(notice.metadata?["quotaLine1"])
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let width = ceil((line as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)]).width) + 6
        let actual = try await renderOffscreen(CompactAIAccountBalanceBar(notice: notice, height: 34)
            .environment(\.colorScheme, .dark).environment(\.layoutDirection, direction).foregroundStyle(.white),
            size: CGSize(width: width + 56, height: 34), reduceMotion: true)
        let reference = try await renderOffscreen(Text(line).font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(AIAccountQuotaSeverity.normal.balanceColor).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.colorScheme, .dark).environment(\.layoutDirection, direction),
            size: CGSize(width: width, height: 34), reduceMotion: true)
        func ink(_ bitmap: NSBitmapImageRep, startX: Int, startY: Int, endY: Int) throws -> Int {
            var count = 0
            for y in startY..<endY {
                for x in startX..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if color.greenComponent > 0.45 && color.greenComponent > color.redComponent * 1.4
                        && color.greenComponent > color.blueComponent * 1.15 { count += 1 }
                }
            }
            return count
        }
        let scale = CGFloat(actual.pixelsWide) / (width + 56)
        let actualInk = try ink(actual, startX: Int(44 * scale), startY: actual.pixelsHigh / 2, endY: actual.pixelsHigh)
        let referenceInk = try ink(reference, startX: 0, startY: 0, endY: reference.pixelsHigh)
        #expect(actualInk == referenceInk,
            "The full extra quota glyphs must survive the compact row viewport in \(language.rawValue); observed \(actualInk)/\(referenceInk) pixels")
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

    @Test(arguments: [(Double(20), AIAccountQuotaSeverity.warning), (10, .critical), (0, .exhausted), (100, .normal)],
        [ColorScheme.light, .dark])
    func ringShowsRealRemainingArcAndThresholdColor(configuration: (Double, AIAccountQuotaSeverity), colorScheme: ColorScheme) throws {
        let (percent, severity) = configuration
        let window = AIAccountQuotaWindow(id: "quota", kind: .all, remainingPercent: percent)
        let renderer = ImageRenderer(content: AIAccountQuotaRing(provider: nil, fraction: window.remainingFraction,
            severity: window.severity, diameter: 42).background(.black).foregroundStyle(.white).environment(\.colorScheme, colorScheme))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var bright = 0, track = 0, green = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let level = max(color.redComponent, color.greenComponent, color.blueComponent)
                if level > 0.45 {
                    bright += 1
                    if percent == 20, level > 0.8 { #expect(color.greenComponent > 0.6 && color.blueComponent < 0.3) }
                    if percent == 10, level > 0.8 { #expect(color.redComponent > color.greenComponent * 2) }
                    if color.greenComponent > color.redComponent * 1.4
                        && color.greenComponent > color.blueComponent * 1.15 { green += 1 }
                } else if level > 0.02 { track += 1 }
            }
        }
        #expect(track > 0)
        #expect(percent == 0 ? bright == 0 : bright > 80)
        if severity == .normal { #expect(green == bright && green > 80, "Healthy remaining quota must render a green arc") }
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

    @Test(arguments: [(CGFloat(244), AppLanguage.simplifiedChinese), (244, .english), (320, .arabic)])
    func cardQuotaWindowsKeepLabelValueAndResetOnEachInlineRow(configuration: (CGFloat, AppLanguage)) async throws {
        let (width, language) = configuration
        let reset = Date(timeIntervalSince1970: 1_910_001_000)
        func card(reset: Date?, fiveHours: Double = 10, weekly: Double = 51) -> some View {
            AIAccountBalanceCard(balance: AIAccountBalance(id: "fixture", providers: [.codex], status: .available,
                windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: fiveHours,
                    resetsAt: reset, durationSeconds: 18_000),
                    .init(id: "weekly", kind: .weekly, remainingPercent: weekly,
                        resetsAt: reset, durationSeconds: 604_800)]), language: language)
                .foregroundStyle(.white).environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        let host = NSHostingView(rootView: card(reset: reset).frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= width + 0.5)
        #expect(host.fittingSize.height <= 104, "Two complete inline quota rows must fit beside the 52pt ring")
        let size = CGSize(width: width, height: ceil(host.fittingSize.height))
        let actual = try await renderOffscreen(card(reset: reset), size: size)
        let withoutReset = try await renderOffscreen(card(reset: nil), size: size)
        let differentValues = try await renderOffscreen(card(reset: reset, fiveHours: 9, weekly: 52), size: size)
        let scale = CGFloat(actual.pixelsWide) / width
        let startX = Int((language.isRightToLeft ? 12 : 72) * scale)
        let endX = Int((width - (language.isRightToLeft ? 72 : 12)) * scale)
        let startY = Int(35 * scale), endY = Int((size.height - 12) * scale)
        var resetChanges = [0, 0], valueChanges = [0, 0]
        var textRows = 0, lastInkY = startY - Int(3 * scale) - 1
        for y in startY..<endY {
            let row = y < (startY + endY) / 2 ? 0 : 1
            var hasInk = false
            for x in startX..<endX {
                let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(withoutReset.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let c = try #require(differentValues.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if max(a.redComponent, a.greenComponent, a.blueComponent) > 0.3 { hasInk = true }
                if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.1 {
                    resetChanges[row] += 1
                }
                if abs(a.redComponent - c.redComponent) + abs(a.greenComponent - c.greenComponent) + abs(a.blueComponent - c.blueComponent) > 0.1 {
                    valueChanges[row] += 1
                }
            }
            if hasInk {
                if y - lastInkY > Int(3 * scale) { textRows += 1 }
                lastInkY = y
            }
        }
        #expect(textRows == 2, "Each quota window must render its label, value, and reset time on one physical row")
        #expect(resetChanges.allSatisfy { $0 > 20 }, "Both independent quota rows must retain their localized reset time")
        #expect(valueChanges.allSatisfy { $0 > 10 }, "Both independent remaining values must remain visible beside their labels")
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
        let label = NSHostingView(rootView: Text(window.label(language: .arabic)).font(.system(size: 10))
            .frame(width: 166).fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft))
        label.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height >= label.fittingSize.height + 37,
            "The complete long window identity must wrap without a line limit or ellipsis")
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


    @Test(arguments: [false, true])
    func rotatingAccountsWithEqualQuotaTextRestartAtTheBeginningAndSamePollKeepsProgress(inheritedReduceMotion: Bool) async throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue,
            now: { Date(timeIntervalSince1970: 100) })
        defer { queue.removeAll() }
        let windows = [AIAccountQuotaWindow(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
            .init(id: "weekly", kind: .weekly, remainingPercent: 70),
            .init(id: "additional:review:secondary_window", kind: .weekly, remainingPercent: 70,
                durationSeconds: 604_800, name: "Review allowance")]
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
                .environment(\._accessibilityReduceMotion, false)
                .transaction { transaction in
                    if transaction.animation != nil, !transaction.disablesAnimations {
                        transaction.animation = Animation(FrozenProgress(progress: progress))
                    }
                }
        }
        let host = NSHostingView(rootView: content(first, progress: 1)
            .environment(\._accessibilityReduceMotion, inheritedReduceMotion))
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
            .environment(\._accessibilityReduceMotion, inheritedReduceMotion)
        #expect(try changes(tail, await sample()) == 0, "The same account's ordinary poll must not restart its reading")
        controller.updatePinned(at: Date(timeIntervalSince1970: 120))
        let rotated = try #require(queue.left.first)
        #expect(rotated.metadata?["quotaAccountID"] == "codex")
        host.rootView = content(rotated, progress: 0)
            .environment(\._accessibilityReduceMotion, inheritedReduceMotion)
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
