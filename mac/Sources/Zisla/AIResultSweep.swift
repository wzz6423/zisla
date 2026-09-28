import Combine
import Foundation
import SwiftUI
import ZislaCore

struct AIResultSweep: Identifiable {
    static let duration: TimeInterval = 4

    let id = UUID()
    let status: AIProgressStatus
    let startedAt: Date

    func progress(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(startedAt) / Self.duration))
    }
}

@MainActor
final class AIResultSweepController: ObservableObject {
    @Published private(set) var current: AIResultSweep?
    private var pending: [AIProgressStatus] = []
    private var playbackTask: Task<Void, Never>?

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
            start(task.status)
        } else {
            pending.append(task.status)
        }
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

    private func start(_ status: AIProgressStatus) {
        let sweep = AIResultSweep(status: status, startedAt: .now)
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
            TimelineView(.animation) { context in
                AIResultSweepBand(
                    status: sweep.status,
                    progress: sweep.progress(at: context.date),
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
            let width = size.width * 0.42
            let position = reduceMotion ? 0.5 : progress
            let x = -width + (size.width + width) * position
            let tint = status == .succeeded
                ? Color(red: 0.015, green: 0.30, blue: 0.20)
                : Color(red: 0.34, green: 0.025, blue: 0.085)
            let highlight = status == .succeeded
                ? Color(red: 0.10, green: 0.62, blue: 0.42)
                : Color(red: 0.68, green: 0.10, blue: 0.21)
            context.opacity = sin(.pi * progress)
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
                for index in 0..<18 {
                    let horizontal = Double((index * 7) % 19 + 1) / 20
                    let brightness = pow(sin(.pi * horizontal), 2)
                    let center = CGPoint(
                        x: x + width * horizontal,
                        y: 0.9 + Double((index * 11) % 19) / 18 * (size.height - 1.8)
                    )
                    let radius = 1.8
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
