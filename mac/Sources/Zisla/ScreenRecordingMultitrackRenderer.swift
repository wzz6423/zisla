import CoreImage
import Foundation
import ZislaCore

struct RecordingTimelineClipIndex {
    private struct Node {
        let clip: RecordingTimelineClip
        let order: Int
        let maximumEnd: Double
        let left: Int?
        let right: Int?
    }
    private var nodes: [Node] = []
    private let root: Int?
    private let trackOrder: [String: Int]

    init(_ timeline: RecordingMultitrackTimeline) {
        let order = Dictionary(uniqueKeysWithValues: timeline.tracks.enumerated().filter {
            !$0.element.isHidden && $0.element.kind != .audio
        }.map { ($0.element.id, $0.offset) })
        trackOrder = order
        let entries = timeline.clips.enumerated().filter { order[$0.element.trackID] != nil }
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
        var built: [Node] = []
        func build(_ start: Int, _ end: Int) -> Int? {
            guard start < end else { return nil }
            let middle = (start + end) / 2
            let left = build(start, middle)
            let right = build(middle + 1, end)
            let maximum = max(entries[middle].element.end, max(left.map { built[$0].maximumEnd } ?? 0,
                right.map { built[$0].maximumEnd } ?? 0))
            let index = built.count
            built.append(.init(clip: entries[middle].element, order: entries[middle].offset,
                maximumEnd: maximum, left: left, right: right))
            return index
        }
        root = build(0, entries.count)
        nodes = built
    }

    func clips(at time: Double) -> [RecordingTimelineClip] {
        let boundary = time + time.ulp * 4
        var found: [Node] = []
        func collect(_ index: Int?) {
            guard let index, nodes[index].maximumEnd > boundary else { return }
            let node = nodes[index]
            collect(node.left)
            if node.clip.start <= boundary {
                if node.clip.end > boundary { found.append(node) }
                collect(node.right)
            }
        }
        collect(root)
        return found.sorted {
            let left = trackOrder[$0.clip.trackID]!
            let right = trackOrder[$1.clip.trackID]!
            return left == right ? $0.order < $1.order : left < right
        }.map(\.clip)
    }
}

struct RecordingMultitrackPreviewScene: @unchecked Sendable {
    let time: Double
    let size: CGSize
    let frames: [String: CGImage]
    let directory: URL
    let imageStore: RecordingMediaImageStore

    init(project: ScreenRecordingProject, directory: URL, time: Double, size: CGSize,
         frames: [String: CGImage]) {
        self.directory = directory
        self.time = time
        self.size = size
        self.frames = frames
        imageStore = RecordingMediaImageStore(project: project, directory: directory)
    }

    func image(project: ScreenRecordingProject, editingText: RecordingCanvasSelection? = nil) throws -> CGImage {
        let renderer = try RecordingMultitrackRenderer(project: project, directory: directory, size: size, imageStore: imageStore)
        let renderedTime = project.outputDuration > 0 ? min(time, max(0, project.outputDuration - 1.0 / 60_000)) : 0
        return try renderer.image(frames: frames.mapValues(CIImage.init(cgImage:)), at: renderedTime, editingText: editingText)
    }
}

final class RecordingMultitrackRenderer {
    let canvas: CGRect
    let context: CIContext
    let index: RecordingTimelineClipIndex
    private let project: ScreenRecordingProject
    private let recording: RecordingExportRenderer
    private let videoProject: ScreenRecordingProject
    private let assets: [UUID: RecordingMediaAsset]
    private let videoLock = NSLock()
    private var videoRenderers: [UUID: RecordingExportRenderer] = [:]
    private var videoOrder: [UUID] = []
    private let images: RecordingMediaImageStore
    private let annotations: [UUID: RecordingAnnotation]
    private let captions: [UUID: RecordingCaption]

    init(project: ScreenRecordingProject, directory: URL, size: CGSize,
         imageStore: RecordingMediaImageStore? = nil) throws {
        guard let timeline = project.timeline else { throw ScreenRecordingProjectError.invalidProject }
        self.project = project
        canvas = CGRect(origin: .zero, size: size)
        index = RecordingTimelineClipIndex(timeline)
        images = imageStore ?? RecordingMediaImageStore(project: project, directory: directory)
        assets = Dictionary(uniqueKeysWithValues: timeline.assets.map { ($0.id, $0) })
        annotations = Dictionary(uniqueKeysWithValues: (project.edits.annotations ?? []).map { ($0.id, $0) })
        captions = Dictionary(uniqueKeysWithValues: project.captions.map { ($0.id, $0) })
        var base = project
        base.edits.annotations = []
        base.edits.showCaptions = false
        recording = try RecordingExportRenderer(project: base, size: size)
        context = recording.context
        base.pointers = []
        base.edits.zoomClips = []
        base.edits.autoZoom = false
        videoProject = base
    }

    func render(frames: [String: CIImage], at time: Double,
                editingText: RecordingCanvasSelection? = nil) throws -> CIImage {
        var result = recording.background
        for clip in index.clips(at: time) {
            let layer: CIImage
            switch clip.content {
            case .recording, .video:
                guard let frame = frames[clip.id] else { throw ScreenRecordingExportError.unavailableMedia }
                let isRecording: Bool
                if case .recording = clip.content { isRecording = true } else { isRecording = false }
                let renderer = try isRecording ? recording : videoRenderer(for: clip.content.assetID!)
                let slice = RecordingExportSlice(index: 0, sourceStart: clip.sourceStart, sourceEnd: clip.sourceEnd,
                    speed: clip.speed, outputStart: clip.start, outputEnd: clip.end)
                let rendered = try renderer.render(screen: frame, camera: frames[clip.id + ".camera"],
                    sourceTime: clip.sourceTime(at: time), slice: slice, includeBackground: false)
                layer = RecordingExportRenderer.fit(rendered, from: canvas, to: rect(clip.layout), fill: false)
            case let .image(id):
                let bounds = rect(clip.layout)
                let decodeSize = CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
                let image = CIImage(cgImage: try images.image(for: id, maximumSize: decodeSize))
                layer = RecordingExportRenderer.fit(image, from: image.extent, to: bounds, fill: false)
            case let .annotation(id):
                guard let annotation = annotations[id] else { throw ScreenRecordingProjectError.invalidProject }
                if annotation.kind == .text && editingText == .annotation(id) { continue }
                layer = try RecordingExportRenderer.annotationImage(annotation, canvas: canvas)
            case let .caption(id):
                guard project.edits.showCaptions else { continue }
                guard let caption = captions[id] else { throw ScreenRecordingProjectError.invalidProject }
                layer = try RecordingExportRenderer.captionImage(caption, canvas: canvas, drawsText: editingText != .caption(id))
            case .audio: continue
            }
            result = layer.composited(over: result)
        }
        return result.cropped(to: canvas)
    }

    func image(frames: [String: CIImage], at time: Double,
               editingText: RecordingCanvasSelection? = nil) throws -> CGImage {
        let rendered = try render(frames: frames, at: time, editingText: editingText)
        guard let image = context.createCGImage(rendered, from: canvas, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw ScreenRecordingExportError.cannotRender }
        return image
    }

    private func rect(_ layout: RecordingRect) -> CGRect {
        CGRect(x: layout.x * canvas.width, y: (1 - layout.y - layout.height) * canvas.height,
            width: layout.width * canvas.width, height: layout.height * canvas.height)
    }

    private func videoRenderer(for id: UUID) throws -> RecordingExportRenderer {
        try videoLock.withLock {
            if let cached = videoRenderers[id] { return cached }
            guard let asset = assets[id] else { throw ScreenRecordingProjectError.invalidProject }
            var source = videoProject
            source.width = asset.width
            source.height = asset.height
            let renderer = try RecordingExportRenderer(project: source, size: canvas.size, fitSource: true, context: context)
            if videoOrder.count == 8 { videoRenderers[videoOrder.removeFirst()] = nil }
            videoOrder.append(id)
            videoRenderers[id] = renderer
            return renderer
        }
    }
}
