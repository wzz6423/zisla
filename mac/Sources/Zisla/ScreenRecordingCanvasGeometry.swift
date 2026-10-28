import CoreGraphics
import Foundation
import ZislaCore

enum RecordingCanvasSelection: Equatable {
    case annotation(UUID)
    case caption(UUID)
    case image(String)
    case video(String)
}

enum RecordingCanvasElement: Equatable {
    case annotation(RecordingAnnotation)
    case caption(RecordingCaption)
    case image(RecordingTimelineClip)
    case video(RecordingTimelineClip)

    var selection: RecordingCanvasSelection {
        switch self {
        case let .annotation(value): .annotation(value.id)
        case let .caption(value): .caption(value.id)
        case let .image(value): .image(value.id)
        case let .video(value): .video(value.id)
        }
    }

    var text: String? {
        switch self {
        case let .annotation(value): value.kind == .text ? value.text : nil
        case let .caption(value): value.text
        case .image, .video: nil
        }
    }

    func replacingText(_ text: String) -> Self {
        switch self {
        case var .annotation(value): value.text = text; return .annotation(value)
        case var .caption(value): value.text = text; return .caption(value)
        case .image, .video: return self
        }
    }

    func bounds(canvas: CGSize) -> CGRect {
        switch self {
        case let .annotation(value):
            if value.kind == .text, canvas.width > 0, canvas.height > 0 {
                return RecordingAnnotationTextLayout(value, canvas: canvas).bounds
            }
            let bounds = value.bounds
            return CGRect(x: bounds.x * canvas.width, y: bounds.y * canvas.height,
                          width: bounds.width * canvas.width, height: bounds.height * canvas.height)
        case let .caption(value):
            let box = RecordingExportRenderer.captionLayout(value, canvas: CGRect(origin: .zero, size: canvas)).box
            return CGRect(x: box.minX, y: canvas.height - box.maxY, width: box.width, height: box.height)
        case let .image(value), let .video(value):
            return CGRect(x: value.layout.x * canvas.width, y: value.layout.y * canvas.height,
                          width: value.layout.width * canvas.width, height: value.layout.height * canvas.height)
        }
    }

    func write(to project: inout ScreenRecordingProject, replacing original: Self) {
        switch (original, self) {
        case let (.annotation(old), .annotation(value)):
            if let index = project.edits.annotations?.firstIndex(of: old), old.id == value.id {
                project.edits.annotations?[index] = value
            }
        case let (.caption(old), .caption(value)):
            if let index = project.captions.firstIndex(of: old), old.id == value.id {
                project.captions[index] = value
            }
        case let (.image(old), .image(value)), let (.video(old), .video(value)):
            if let index = project.timeline?.clips.firstIndex(of: old), old.id == value.id {
                project.timeline?.clips[index] = value
            }
        default: break
        }
    }

    static func visible(in project: ScreenRecordingProject, at time: Double) -> [Self] {
        if let timeline = project.timeline {
            return timeline.visibleClips(at: time).compactMap { clip in
                switch clip.content {
                case .image: return .image(clip)
                case .recording, .video: return .video(clip)
                case let .annotation(id):
                    return project.edits.annotations?.first(where: { $0.id == id }).map(Self.annotation)
                case let .caption(id):
                    return project.edits.showCaptions
                        ? project.captions.first(where: { $0.id == id && !$0.text.isEmpty }).map(Self.caption) : nil
                case .audio: return nil
                }
            }
        }
        var elements = (project.edits.annotations ?? []).filter { $0.isVisible(at: time) }.map(Self.annotation)
        if project.edits.showCaptions,
           let caption = project.captions.first(where: { time >= $0.start && time < $0.end }), !caption.text.isEmpty {
            elements.append(.caption(caption))
        }
        return elements
    }
}

enum RecordingCanvasHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, start, end
}

enum RecordingCanvasGeometry {
    static func fittedRect(canvas: CGSize, in bounds: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func handles(for element: RecordingCanvasElement, canvas: CGSize) -> [(RecordingCanvasHandle, CGPoint)] {
        if case let .annotation(value) = element, value.kind == .arrow {
            return [(.start, CGPoint(x: value.x * canvas.width, y: value.y * canvas.height)),
                    (.end, CGPoint(x: value.endX * canvas.width, y: value.endY * canvas.height))]
        }
        let box = element.bounds(canvas: canvas)
        return [(.topLeft, CGPoint(x: box.minX, y: box.minY)), (.topRight, CGPoint(x: box.maxX, y: box.minY)),
                (.bottomLeft, CGPoint(x: box.minX, y: box.maxY)), (.bottomRight, CGPoint(x: box.maxX, y: box.maxY))]
    }

    static func hit(_ element: RecordingCanvasElement, at point: CGPoint, canvas: CGSize, tolerance: CGFloat) -> Bool {
        if case let .annotation(value) = element, value.kind == .arrow {
            let start = CGPoint(x: value.x * canvas.width, y: value.y * canvas.height)
            let end = CGPoint(x: value.endX * canvas.width, y: value.endY * canvas.height)
            let dx = end.x - start.x, dy = end.y - start.y
            let progress = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
            return hypot(point.x - start.x - progress * dx, point.y - start.y - progress * dy)
                <= max(tolerance, min(canvas.width, canvas.height) * value.lineWidth / 2)
        }
        return element.bounds(canvas: canvas).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    static func transformed(_ element: RecordingCanvasElement, by translation: CGSize,
                            handle: RecordingCanvasHandle?, canvas: CGSize) -> RecordingCanvasElement {
        guard translation.width.isFinite, translation.height.isFinite,
              canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else { return element }
        let old = element.bounds(canvas: canvas)
        if case var .annotation(value) = element, value.kind == .arrow, let handle {
            let x = handle == .start ? value.x : value.endX
            let y = handle == .start ? value.y : value.endY
            let targetX = min(1, max(0, x + translation.width / canvas.width))
            let targetY = min(1, max(0, y + translation.height / canvas.height))
            if handle == .start { value.x = targetX; value.y = targetY }
            else { value.endX = targetX; value.endY = targetY }
            return hypot((value.x - value.endX) * canvas.width, (value.y - value.endY) * canvas.height) < 1
                ? element : .annotation(value)
        }
        let rect: CGRect
        var scale: CGFloat = 1
        if let handle {
            let left = handle == .topLeft || handle == .bottomLeft
            let top = handle == .topLeft || handle == .topRight
            let anchor = CGPoint(x: left ? old.maxX : old.minX, y: top ? old.maxY : old.minY)
            let width = max(4, old.width + translation.width * (left ? -1 : 1))
            let height = max(4, old.height + translation.height * (top ? -1 : 1))
            let limitWidth = left ? anchor.x : canvas.width - anchor.x
            let limitHeight = top ? anchor.y : canvas.height - anchor.y
            let newSize: CGSize
            let requested = (width * old.width + height * old.height) / (old.width * old.width + old.height * old.height)
            if element.text != nil {
                let font = fontSize(of: element, canvas: canvas)
                scale = min(max(requested, max(0.01 / font, 4 / min(old.width, old.height))),
                            min(0.3 / font, min(limitWidth / old.width, limitHeight / old.height)))
                newSize = CGSize(width: old.width * scale, height: old.height * scale)
            } else if element.isMedia {
                scale = min(max(requested, 4 / min(old.width, old.height)),
                            min(limitWidth / old.width, limitHeight / old.height))
                newSize = CGSize(width: old.width * scale, height: old.height * scale)
            } else {
                newSize = CGSize(width: min(width, limitWidth), height: min(height, limitHeight))
            }
            rect = CGRect(x: left ? anchor.x - newSize.width : anchor.x,
                          y: top ? anchor.y - newSize.height : anchor.y, width: newSize.width, height: newSize.height)
        } else {
            rect = old.offsetBy(dx: min(max(translation.width, -old.minX), canvas.width - old.maxX),
                                dy: min(max(translation.height, -old.minY), canvas.height - old.maxY))
        }
        if rect == old, scale == 1 { return element }
        switch element {
        case var .annotation(value):
            let reversedX = value.x > value.endX, reversedY = value.y > value.endY
            let right = value.kind == .text
                ? min(canvas.width, rect.minX + max(rect.width, value.bounds.width * canvas.width * scale)) : rect.maxX
            value.x = (reversedX ? right : rect.minX) / canvas.width
            value.endX = (reversedX ? rect.minX : right) / canvas.width
            value.y = (reversedY ? rect.maxY : rect.minY) / canvas.height
            value.endY = (reversedY ? rect.minY : rect.maxY) / canvas.height
            if handle != nil, value.kind == .text { value.fontSize = min(0.3, max(0.01, value.fontSize * scale)) }
            return .annotation(value)
        case var .caption(value):
            value.layout = RecordingRect(x: rect.minX / canvas.width, y: rect.minY / canvas.height,
                                         width: rect.width / canvas.width, height: rect.height / canvas.height)
            if handle != nil { value.fontSize = min(0.3, max(0.01, fontSize(of: element, canvas: canvas) * scale)) }
            return .caption(value)
        case var .image(value):
            value.layout = RecordingRect(x: rect.minX / canvas.width, y: rect.minY / canvas.height,
                                         width: rect.width / canvas.width, height: rect.height / canvas.height)
            return .image(value)
        case var .video(value):
            value.layout = RecordingRect(x: rect.minX / canvas.width, y: rect.minY / canvas.height,
                                         width: rect.width / canvas.width, height: rect.height / canvas.height)
            return .video(value)
        }
    }

    static func fontSize(of element: RecordingCanvasElement, canvas: CGSize) -> Double {
        switch element {
        case let .annotation(value): value.fontSize
        case let .caption(value): value.fontSize ?? max(12 / min(canvas.width, canvas.height), 0.035)
        case .image, .video: 0
        }
    }
}

private extension RecordingCanvasElement {
    var isMedia: Bool {
        switch self {
        case .image, .video: true
        default: false
        }
    }
}
