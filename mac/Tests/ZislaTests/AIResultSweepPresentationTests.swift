import AppKit
import Combine
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct AIResultSweepPresentationTests {
    @Test(arguments: [ColorScheme.light, .dark], [CGFloat(16), 22, 24])
    func monochromeIconContrastsWithItsColorScheme(colorScheme: ColorScheme, size: CGFloat) throws {
        let renderer = ImageRenderer(content: AIMascotView(identity: .gpt, size: size)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, colorScheme))
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var contrastingPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                if colorScheme == .dark ? brightness > 0.75 : brightness < 0.25 {
                    contrastingPixels += 1
                }
            }
        }
        // Preserve the 24 pt contrast requirement as an area fraction at smaller sizes.
        let contrastingCoverage = Double(contrastingPixels) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
        #expect(contrastingCoverage > 10.0 / (24 * 24), "The monochrome icon must contrast with its background at compact sizes")
    }

    @Test(arguments: [AIProvider.codex, .gpt], [AIProgressStatus.succeeded, .failed])
    func retainsIconAndCountAfterClientNoticesDisappear(provider: AIProvider, status: AIProgressStatus) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let task = makeTask(id: "exiting-client", provider: provider, status: status)
        fixture.queue.enqueue(notice(for: task), expiresAfter: nil)
        fixture.receive(task)
        let sweep = try #require(fixture.sweep.current)

        fixture.queue.removeAll()

        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.view.activeAINotices.count == 1, "动画播放时，退出的客户端仍须贡献一个图标和计数")
        let retained = try #require(fixture.view.activeAINotices.first)
        #expect(AIMascotIdentity(noticeID: retained.id) == AIMascotIdentity(provider: provider, taskID: task.id))
        let visiblePixels = try wingPixelCounts(in: fixture.view)
        #expect(visiblePixels[0] > 10, "动画左翼必须仍绘制客户端图标")
        #expect(visiblePixels[1] > 3, "动画右翼必须仍绘制会话数量")

        fixture.sweep.finish(id: sweep.id)

        #expect(fixture.view.activeAINotices.isEmpty)
        #expect(try wingPixelCounts(in: fixture.view) == [0, 0], "最后一段动画结束后，图标和数量必须一起消失")
    }

    @Test
    func retainedResultSharesCountWithRunningTasksWithoutDuplicates() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let error = makeTask(id: "error", provider: .codex, status: .error)
        let running = makeTask(id: "running", provider: .gpt, status: .running)
        fixture.queue.enqueue(notice(for: error), expiresAfter: nil)
        fixture.queue.enqueue(notice(for: running), expiresAfter: nil)
        fixture.receive(error)
        let sweep = try #require(fixture.sweep.current)
        #expect(fixture.view.activeAINotices.count == 2, "同一个错误会话不能在活动状态和动画中重复计数")

        fixture.queue.remove(id: notice(for: error).id)

        #expect(fixture.view.activeAINotices.count == 2)
        #expect(Set(fixture.view.activeAINotices.map(\.id)) == Set([notice(for: error).id, notice(for: running).id]))
        fixture.sweep.finish(id: sweep.id)
        #expect(fixture.view.activeAINotices.map(\.id) == [notice(for: running).id])
    }

    @Test
    func queuedResultsKeepTheirOwnClientUntilEachAnimationEnds() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chatGPT = makeTask(id: "chatgpt", provider: .gpt, status: .succeeded)
        let codex = makeTask(id: "codex", provider: .codex, status: .failed)
        fixture.receive(chatGPT)
        let first = try #require(fixture.sweep.current)
        fixture.receive(codex)

        #expect(fixture.view.activeAINotices.map(\.id) == [notice(for: chatGPT).id])
        fixture.sweep.finish(id: first.id)
        let second = try #require(fixture.sweep.current)
        #expect(fixture.view.activeAINotices.map(\.id) == [notice(for: codex).id])
        fixture.sweep.finish(id: first.id)
        #expect(fixture.view.activeAINotices.map(\.id) == [notice(for: codex).id], "过期的动画完成回调不能清掉下一段的图标")
        fixture.sweep.finish(id: second.id)
        #expect(fixture.view.activeAINotices.isEmpty)
    }

    @Test
    func cancellingPlaybackReleasesRetainedIconsAndKeepsLiveTasks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let running = makeTask(id: "running", provider: .claude, status: .running)
        fixture.queue.enqueue(notice(for: running), expiresAfter: nil)
        fixture.receive(makeTask(id: "finished", provider: .gpt, status: .succeeded))
        fixture.receive(makeTask(id: "pending", provider: .codex, status: .failed))
        let first = try #require(fixture.sweep.current)
        #expect(fixture.view.activeAINotices.count == 2)

        fixture.sweep.cancel()
        fixture.sweep.finish(id: first.id)

        #expect(fixture.sweep.current == nil)
        #expect(fixture.view.activeAINotices.map(\.id) == [notice(for: running).id])
    }

    @Test
    func playbackShowsBothWingsWhenStatusWasHiddenAndRestoresOtherContent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let media = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        fixture.settings.settings.compactStatusPriority = [.media, .aiActivity]
        fixture.queue.enqueue(media, expiresAfter: nil)
        fixture.displayState.compactStatusHidden = true
        fixture.receive(makeTask(id: "finished", provider: .gpt, status: .succeeded))
        let sweep = try #require(fixture.sweep.current)

        let visiblePixels = try wingPixelCounts(in: fixture.view)
        #expect(visiblePixels[0] > 10, "正在播放的结果动画必须显示图标，即使之前手动隐藏过状态栏")
        #expect(visiblePixels[1] > 3)
        #expect(fixture.view.selectedCompactStatusPriority == .aiActivity)
        #expect(fixture.queue.left.map(\.id) == [media.id], "临时显示结果不能改写其他模块的通知")

        fixture.sweep.finish(id: sweep.id)
        #expect(fixture.view.activeAINotices.isEmpty)
        #expect(fixture.view.selectedCompactStatusPriority == .media)
        #expect(try wingPixelCounts(in: fixture.view) == [0, 0])
    }

    @Test(.timeLimit(.minutes(1)))
    func renderedViewUpdatesWithPlaybackWithoutAnotherQueueEvent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let renderer = ImageRenderer(content: fixture.view.frame(width: 320, height: 34))
        #expect(wingPixelCounts(in: try #require(renderer.cgImage)) == [0, 0])
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let subscription = renderer.objectWillChange.sink { continuation.yield(()) }
        defer { subscription.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        fixture.receive(makeTask(id: "finished", provider: .gpt, status: .succeeded))
        let sweep = try #require(fixture.sweep.current)
        await iterator.next()

        let visiblePixels = wingPixelCounts(in: try #require(renderer.cgImage))
        #expect(visiblePixels[0] > 10, "同一个视图必须响应动画启动，不依赖活动队列再次更新")
        #expect(visiblePixels[1] > 3)
        fixture.sweep.finish(id: sweep.id)
        await iterator.next()
        #expect(wingPixelCounts(in: try #require(renderer.cgImage)) == [0, 0])
    }

    private func makeTask(id: String, provider: AIProvider, status: AIProgressStatus) -> AIProgressTask {
        AIProgressTask(id: id, provider: provider, title: id, progress: nil, status: status, updatedAt: .now)
    }

    private func notice(for task: AIProgressTask) -> IslandNotice {
        IslandNotice(id: "ai-active-\(task.provider.rawValue)-\(task.id)", title: task.title, side: .right)
    }

    private func wingPixelCounts(in view: CompactStatusBarView) throws -> [Int] {
        let renderer = ImageRenderer(content: view.statusBarContent(at: .now)
            .frame(width: 320, height: 34))
        return wingPixelCounts(in: try #require(renderer.cgImage))
    }

    private func wingPixelCounts(in image: CGImage) -> [Int] {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return [0..<40, 280..<320].map { columns in
            var count = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in columns {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.5 else { continue }
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.75 {
                        count += 1
                    }
                }
            }
            return count
        }
    }

    @MainActor
    private struct Fixture {
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let displayState = SideNoticeDisplayState()
        let media = NowPlayingService(loadLyrics: { _, _, _ in
            Issue.record("结果动画测试不应请求歌词")
            fatalError("Unexpected lyrics request")
        })
        let downloads = BrowserDownloadMonitor(directories: [], eventPaths: [])
        let suiteName = "AIResultSweepPresentationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            settings = FeatureSettingsStore(defaults: defaults)
            settings.settings.islandNotchBackground = .black
        }

        var view: CompactStatusBarView {
            CompactStatusBarView(
                queue: queue, displayState: displayState, media: media, browserDownloads: downloads,
                settingsStore: settings, resultSweep: sweep, onStatusHidden: {}
            )
        }

        func receive(_ task: AIProgressTask) {
            sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: settings.settings)
        }

        func cleanUp() {
            sweep.cancel()
            media.stop()
            downloads.stop()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
