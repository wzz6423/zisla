import Combine
import Foundation
import SwiftUI
import ZislaCore

struct AIResultSweep: Identifiable {
    static let duration: TimeInterval = 1.2

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

    func receive(previous: AIProgressStatus?, status: AIProgressStatus, settings: FeatureSettings) {
        guard settings.aiProgressEnabled, settings.aiTaskResultSweepEnabled else {
            cancel()
            return
        }
        guard previous?.isActive == true, status == .succeeded || status == .failed else { return }
        if current == nil {
            start(status)
        } else {
            pending.append(status)
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
            let tint: Color = status == .succeeded ? .zislaSuccess : .zislaError
            context.opacity = sin(.pi * progress)
            context.fill(
                Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: tint.opacity(0.12), location: 0.18),
                        .init(color: tint.opacity(0.45), location: 0.42),
                        .init(color: tint.opacity(0.85), location: 0.68),
                        .init(color: tint.opacity(0.25), location: 0.86),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: CGPoint(x: x, y: 0),
                    endPoint: CGPoint(x: x + width, y: 0)
                )
            )
        }
        .blendMode(.screen)
    }
}
