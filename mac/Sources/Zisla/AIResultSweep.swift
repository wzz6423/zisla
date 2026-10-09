import Combine
import Foundation
import SwiftUI
import ZislaCore

struct AIResultSweep: Identifiable {
    static let duration: TimeInterval = 4

    let id = UUID()
    let task: AIProgressTask
    let startedAt: Date

    var status: AIProgressStatus { task.status }

    func progress(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(startedAt) / Self.duration))
    }
}

@MainActor
final class AIResultSweepController: ObservableObject {
    @Published private(set) var current: AIResultSweep?
    let now: () -> Date
    private var pending: [AIProgressTask] = []
    private var playbackTask: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func receive(previous: AIProgressStatus?, task: AIProgressTask, observedSince: Date, settings: FeatureSettings) {
        guard settings.aiProgressEnabled, settings.aiTaskResultSweepEnabled else {
            cancel()
            return
        }
        let startedSinceObservation = previous == nil && task.startedAt.map { $0 >= observedSince } == true
        guard previous?.isActive == true || startedSinceObservation,
              previous != task.status,
              task.status == .succeeded || task.status == .failed || task.status == .error else { return }
        if current == nil {
            start(task)
        } else {
            pending.append(task)
        }
    }

    func presentationNotices(from notices: [IslandNotice]) -> [IslandNotice] {
        guard let task = current?.task else { return notices }
        let activityNotices = notices.filter { $0.id.hasPrefix("ai-active-") }
        let id = "ai-active-\(task.provider.rawValue)-\(task.id)"
        guard !activityNotices.contains(where: { $0.id == id }) else { return activityNotices }
        // The client may have exited, but its result still owns the bar until playback finishes.
        return activityNotices + [IslandNotice(
            id: id,
            title: task.title,
            detail: task.detail,
            kind: task.status.noticeKind,
            side: .right,
            createdAt: task.updatedAt,
            progress: task.progress
        )]
    }

    func cancel() {
        playbackTask?.cancel()
        playbackTask = nil
        pending.removeAll()
        current = nil
    }

    func finish(id: UUID) {
        guard current?.id == id else { return }
        playbackTask?.cancel()
        playbackTask = nil
        if pending.isEmpty {
            current = nil
        } else {
            start(pending.removeFirst())
        }
    }

    private func start(_ task: AIProgressTask) {
        let sweep = AIResultSweep(task: task, startedAt: now())
        current = sweep
        playbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(AIResultSweep.duration))
            } catch {
                return
            }
            self?.finish(id: sweep.id)
        }
    }
}

struct AIResultSweepOverlay: View {
    @ObservedObject var controller: AIResultSweepController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let sweep = controller.current {
            TimelineView(.animation) { _ in
                AIResultSweepBand(
                    status: sweep.status,
                    progress: sweep.progress(at: controller.now()),
                    reduceMotion: reduceMotion
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct AIResultSweepBand: View {
    let status: AIProgressStatus
    let progress: Double
    var reduceMotion = false

    var body: some View {
        Canvas { context, size in
            let width = size.width * 0.72
            let position = reduceMotion ? 0.5 : progress
            let x = -width + (size.width + width) * position
            let tint = status == .succeeded
                ? Color(red: 0.015, green: 0.30, blue: 0.20)
                : Color(red: 0.34, green: 0.025, blue: 0.085)
            let highlight = status == .succeeded
                ? Color(red: 0.10, green: 0.62, blue: 0.42)
                : Color(red: 0.68, green: 0.10, blue: 0.21)
            let breathing = reduceMotion ? 1 : 0.86 - 0.14 * cos(.pi * 4 * progress)
            context.opacity = sin(.pi * progress) * breathing
            context.fill(
                Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: tint.opacity(0.15), location: 0.18),
                        .init(color: tint.opacity(0.55), location: 0.35),
                        .init(color: tint.opacity(0.95), location: 0.50),
                        .init(color: tint.opacity(0.55), location: 0.65),
                        .init(color: tint.opacity(0.15), location: 0.82),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: CGPoint(x: x, y: 0),
                    endPoint: CGPoint(x: x + width, y: 0)
                )
            )
            if !reduceMotion {
                for index in 0..<30 {
                    let phase = Double(index) * 2.4
                        + progress * AIResultSweep.duration * (1.1 + Double(index % 4) * 0.2)
                    let horizontal = Double((index * 7) % 31 + 1) / 32
                    let brightness = pow(sin(.pi * horizontal), 2)
                    let center = CGPoint(
                        x: x + width * horizontal,
                        y: 0.9 + Double((index * 11) % 31) / 30 * (size.height - 1.8)
                            + cos(phase * 1.3) * min(6, size.height * 0.14)
                    )
                    let radius = 0.65 + Double(index % 4) * 0.1
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: highlight.opacity(0.65 * brightness), location: 0),
                                .init(color: highlight.opacity(0.40 * brightness), location: 0.3),
                                .init(color: .clear, location: 1),
                            ]),
                            center: center, startRadius: 0, endRadius: radius
                        )
                    )
                }
            }
        }
        .blendMode(.screen)
    }
}
