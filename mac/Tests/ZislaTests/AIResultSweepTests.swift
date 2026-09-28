import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
private extension AIResultSweepController {
    func receive(previous: AIProgressStatus?, status: AIProgressStatus, settings: FeatureSettings) {
        receive(
            previous: previous,
            task: AIProgressTask(id: "test", provider: .codex, title: "Test", progress: nil, status: status, updatedAt: .now),
            observedSince: .distantFuture,
            settings: settings
        )
    }
}

struct AIResultSweepTests {
    @Test @MainActor
    func playbackAutomaticallyEndsWithoutAnotherMonitorUpdate() async {
        let controller = AIResultSweepController()
        defer { controller.cancel() }
        controller.receive(previous: .running, status: .succeeded, settings: .default)
        #expect(controller.current != nil)
        for await sweep in controller.$current.values {
            if sweep == nil { break }
        }
        #expect(controller.current == nil)
    }

    @Test @MainActor
    func onlyActiveTasksEnteringATerminalStateTriggerASweep() {
        let controller = AIResultSweepController()
        defer { controller.cancel() }
        let statuses: [AIProgressStatus] = [.queued, .running, .blocked, .error, .succeeded, .failed]
        for previous in [nil] + statuses.map(Optional.some) {
            for status in statuses {
                controller.receive(previous: previous, status: status, settings: .default)
                let shouldSweep = previous?.isActive == true && !status.isActive
                #expect((controller.current != nil) == shouldSweep)
                if shouldSweep { #expect(controller.current?.status == status) }
                controller.cancel()
            }
        }
    }

    @Test @MainActor
    func consecutiveResultsPlayOnceInOrderAndIgnoreStaleCompletions() throws {
        let controller = AIResultSweepController()
        defer { controller.cancel() }
        controller.receive(previous: .running, status: .succeeded, settings: .default)
        let first = try #require(controller.current)
        controller.receive(previous: .running, status: .failed, settings: .default)
        controller.receive(previous: .succeeded, status: .succeeded, settings: .default)
        #expect(controller.current?.id == first.id)
        controller.finish(id: first.id)
        let second = try #require(controller.current)
        #expect(second.id != first.id)
        #expect(second.status == .failed)
        controller.finish(id: first.id)
        #expect(controller.current?.id == second.id)
        controller.finish(id: second.id)
        #expect(controller.current == nil)
        controller.receive(previous: .running, status: .succeeded, settings: .default)
        #expect(controller.current != nil)
    }

    @Test @MainActor
    func disablingEitherSettingClearsCurrentAndQueuedResultsWithoutReplay() throws {
        for keyPath in [\FeatureSettings.aiProgressEnabled, \.aiTaskResultSweepEnabled] {
            let controller = AIResultSweepController()
            defer { controller.cancel() }
            controller.receive(previous: .running, status: .succeeded, settings: .default)
            let first = try #require(controller.current)
            controller.receive(previous: .running, status: .failed, settings: .default)
            var disabled = FeatureSettings.default
            disabled[keyPath: keyPath] = false
            controller.receive(previous: .running, status: .failed, settings: disabled)
            #expect(controller.current == nil)
            controller.finish(id: first.id)
            controller.receive(previous: .failed, status: .failed, settings: .default)
            #expect(controller.current == nil)
            controller.receive(previous: .running, status: .failed, settings: .default)
            let fresh = try #require(controller.current)
            controller.finish(id: fresh.id)
            #expect(controller.current == nil)
        }
    }

    @Test @MainActor
    func sideNoticeSettingDoesNotDisableResultSweeps() {
        let controller = AIResultSweepController()
        defer { controller.cancel() }
        var settings = FeatureSettings.default
        settings.sideNoticesEnabled = false
        controller.receive(previous: .running, status: .succeeded, settings: settings)
        #expect(controller.current?.status == .succeeded)
    }

    @Test
    func playbackProgressClampsToOnePass() {
        let start = Date(timeIntervalSince1970: 100)
        let sweep = AIResultSweep(status: .succeeded, startedAt: start)
        #expect(sweep.progress(at: start.addingTimeInterval(-1)) == 0)
        #expect(abs(sweep.progress(at: start.addingTimeInterval(0.6)) - 0.5) < 0.001)
        #expect(sweep.progress(at: start.addingTimeInterval(2)) == 1)
    }

    @Test @MainActor
    func compactSweepStaysVisibleWithoutStatusAndClearsThePhysicalNotch() throws {
        let idle = CGRect(x: 100, y: 968, width: 280, height: 32)
        #expect(SideNoticePresenter.resultSweepFrame(
            statusFrame: nil, idleFrame: idle, hasPhysicalNotch: true, isSweeping: false
        ) == nil)
        let sweep = try #require(SideNoticePresenter.resultSweepFrame(
            statusFrame: nil, idleFrame: idle, hasPhysicalNotch: true, isSweeping: true
        ))
        #expect(sweep.maxY == idle.maxY)
        #expect(sweep.height == 34)
        #expect(sweep.width == idle.width)
        let wide = CGRect(x: 50, y: 964, width: 380, height: 36)
        #expect(SideNoticePresenter.resultSweepFrame(
            statusFrame: wide, idleFrame: idle, hasPhysicalNotch: true, isSweeping: true
        ) == wide)
        #expect(SideNoticePresenter.resultSweepFrame(
            statusFrame: nil, idleFrame: idle, hasPhysicalNotch: false, isSweeping: true
        ) == idle)
        #expect(SideNoticePresenter.resultSweepFrame(
            statusFrame: wide, idleFrame: idle, hasPhysicalNotch: true, isSweeping: false
        ) == wide)
    }

    @Test @MainActor
    func renderedBandMovesLeftToRightWithGradientAndReturnsToBlack() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            for width in [240, 748] {
                var previousCenter = -1.0
                for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let colors = try renderedRow(status: status, progress: progress, width: width)
                    let values = colors.map { status == .succeeded ? $0.greenComponent : $0.redComponent }
                    if progress == 0 || progress == 1 {
                        #expect(values.max()! < 0.01)
                    } else {
                        let lit = values.indices.filter { values[$0] > 0.02 }
                        #expect(!lit.isEmpty)
                        #expect(lit.count < width / 2, "整片背景不能一起变色")
                        #expect(Set(values.map { Int($0 * 255) }).count > 20, "光带必须有明暗渐变")
                        let center = Double(lit.reduce(0, +)) / Double(lit.count)
                        #expect(center > previousCenter)
                        previousCenter = center
                        let peak = values.indices.max { values[$0] < values[$1] }!
                        let color = colors[peak]
                        #expect(status == .succeeded
                            ? color.greenComponent > color.redComponent
                            : color.redComponent > color.greenComponent)
                    }
                }
            }
        }
    }

    @Test @MainActor
    func sweepPreservesBrightContentAboveTheIslandBackground() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            let colors = try renderedRow(status: status, progress: 0.5, width: 240, background: .white)
            #expect(colors.allSatisfy {
                $0.redComponent > 0.99 && $0.greenComponent > 0.99 && $0.blueComponent > 0.99
            })
        }
    }

    @Test @MainActor
    func reducedMotionKeepsTheGradientStationaryAndFadesItsBrightness() throws {
        let rows = try [0.25, 0.5, 0.75].map {
            try renderedRow(status: .succeeded, progress: $0, width: 240, reduceMotion: true)
                .map(\.greenComponent)
        }
        let peaks = rows.map { row in row.indices.max { row[$0] < row[$1] }! }
        #expect(peaks[0] == peaks[1] && peaks[1] == peaks[2])
        #expect(rows[1].max()! > rows[0].max()!)
        #expect(abs(rows[0].max()! - rows[2].max()!) < 0.01)
    }

    @MainActor
    private func renderedRow(
        status: AIProgressStatus, progress: Double, width: Int, reduceMotion: Bool = false,
        background: Color = .black
    ) throws -> [NSColor] {
        let renderer = ImageRenderer(content: AIResultSweepBand(
            status: status, progress: progress, reduceMotion: reduceMotion
        ).frame(width: CGFloat(width), height: 34).background(background))
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try (0..<width).map {
            try #require(bitmap.colorAt(x: $0, y: 17)?.usingColorSpace(.deviceRGB))
        }
    }
}
