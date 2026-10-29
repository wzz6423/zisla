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
    private let transitionSources: [String: RecordingTimelineClip]

    init(_ timeline: RecordingMultitrackTimeline) {
        let order = Dictionary(uniqueKeysWithValues: timeline.tracks.enumerated().filter {
            !$0.element.isHidden
        }.map { ($0.element.id, $0.offset) })
        trackOrder = order
        let entries = timeline.clips.enumerated().filter {
            order[$0.element.trackID] != nil && $0.element.content.trackKind != .audio
        }
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
        transitionSources = timeline.transitionSources()
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

    func transitionSource(for clipID: String) -> RecordingTimelineClip? { transitionSources[clipID] }
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
    private var transparentCanvas: CIImage?

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
        let clips = index.clips(at: time).filter { clip in
            switch clip.content {
            case .caption: return project.edits.showCaptions
            case let .annotation(id): return editingText != .annotation(id)
            default: return true
            }
        }
        let visible = Set(clips.map(\.id))
        var transitions: [String: (source: String, sample: RecordingClipTransitionSample)] = [:]
        var consumed: Set<String> = []
        for clip in clips {
            if let source = index.transitionSource(for: clip.id), visible.contains(source.id),
               let sample = RecordingClipTransitionSample.sample(clip, from: source, at: time) {
                transitions[clip.id] = (source.id, sample)
                consumed.insert(source.id)
            }
        }
        var layers: [String: CIImage] = [:]
        for clip in clips {
            layers[clip.id] = try layer(clip, frames: frames, at: time, editingText: editingText)
        }
        var result = recording.background
        for clip in clips where !consumed.contains(clip.id) {
            var chain = [clip.id]
            while let source = transitions[chain.last!]?.source { chain.append(source) }
            var composed = layers[chain.last!]!
            for id in chain.dropLast().reversed() {
                composed = try transitioned(from: composed, to: layers[id]!, sample: transitions[id]!.sample)
            }
            result = composed.composited(over: result)
        }
        return result.cropped(to: canvas)
    }

    private func layer(_ clip: RecordingTimelineClip, frames: [String: CIImage], at time: Double,
                       editingText: RecordingCanvasSelection?) throws -> CIImage {
        let characters: Int?
        switch clip.content {
        case let .annotation(id): characters = annotations[id]?.text.count
        case let .caption(id): characters = captions[id]?.text.count
        default: characters = nil
        }
        let animation = RecordingClipAnimationSample.sample(clip, at: time, characterCount: characters)
        let image: CIImage
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
            // Flatten before a transition filter. The render graph still contains an infinite
            // color image, which CIDissolveTransition would sample without ever finishing.
            image = try flatten(RecordingExportRenderer.fit(rendered, from: canvas, to: rect(clip.layout), fill: false))
        case let .image(id):
            let bounds = rect(clip.layout)
            let decodeSize = CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
            let source = CIImage(cgImage: try images.image(for: id, maximumSize: decodeSize))
            image = RecordingExportRenderer.fit(source, from: source.extent, to: bounds, fill: false)
        case let .annotation(id):
            guard let annotation = annotations[id] else { throw ScreenRecordingProjectError.invalidProject }
            image = try RecordingExportRenderer.annotationImage(annotation, canvas: canvas,
                visibleCharacters: animation.visibleCharacters)
        case let .caption(id):
            guard let caption = captions[id] else { throw ScreenRecordingProjectError.invalidProject }
            image = try RecordingExportRenderer.captionImage(caption, canvas: canvas,
                drawsText: editingText != .caption(id), visibleCharacters: animation.visibleCharacters)
        case .audio: throw ScreenRecordingProjectError.invalidProject
        }
        return animated(image, sample: animation)
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

    private func animated(_ layer: CIImage, sample: RecordingClipAnimationSample) -> CIImage {
        let center = CGPoint(x: layer.extent.midX, y: layer.extent.midY)
        return layer.transformed(by: .init(translationX: -center.x, y: -center.y))
            .transformed(by: .init(scaleX: sample.scale, y: sample.scale))
            .transformed(by: .init(translationX: center.x, y: center.y))
            .transformed(by: .init(translationX: sample.offsetX * canvas.width,
                y: -sample.offsetY * canvas.height))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: sample.opacity),
            ])
    }

    private func transitioned(from outgoing: CIImage, to incoming: CIImage,
                              sample: RecordingClipTransitionSample) throws -> CIImage {
        switch sample.kind {
        case .dissolve:
            return try crossfade(outgoing, incoming, progress: sample.progress)
        case .slideLeft, .slideRight:
            let direction = sample.kind == .slideLeft ? -1.0 : 1.0
            let previous = try transitionImage(outgoing)
                .transformed(by: .init(translationX: direction * sample.progress * canvas.width, y: 0))
            let next = try transitionImage(incoming)
                .transformed(by: .init(translationX: -direction * (1 - sample.progress) * canvas.width, y: 0))
            return next.composited(over: previous).cropped(to: canvas)
        case .zoom:
            var previous = RecordingClipAnimationSample()
            previous.scale = 1 + sample.progress * 0.5
            var next = RecordingClipAnimationSample()
            next.scale = 0.5 + sample.progress * 0.5
            // Scale around each layer's own center first; the dissolve inputs are rasterized afterwards.
            return try crossfade(animated(outgoing, sample: previous), animated(incoming, sample: next),
                progress: sample.progress)
        }
    }

    private func crossfade(_ outgoing: CIImage, _ incoming: CIImage, progress: Double) throws -> CIImage {
        try transitionImage(outgoing).applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: try transitionImage(incoming), kCIInputTimeKey: progress,
        ]).cropped(to: canvas)
    }

    /// Full-canvas image clips keep their original graph so blended pixel tests stay exact.
    /// Smaller layers and infinite domains are drawn into a finite canvas bitmap first:
    /// CIDissolveTransition otherwise samples the uncropped domain and does not return.
    private func transitionImage(_ image: CIImage) throws -> CIImage {
        let extent = image.extent
        if !extent.isInfinite, extent.integral == canvas.integral { return image }
        let placed = image.composited(over: try transparentCanvasImage()).cropped(to: canvas)
        return try flatten(placed)
    }

    private func transparentCanvasImage() throws -> CIImage {
        if let transparentCanvas { return transparentCanvas }
        let clear = try flatten(CIImage(color: .clear).cropped(to: canvas))
        transparentCanvas = clear
        return clear
    }

    private func flatten(_ image: CIImage) throws -> CIImage {
        let extent = image.extent.intersection(canvas)
        guard !extent.isInfinite, !extent.isNull, extent.width >= 1, extent.height >= 1 else {
            throw ScreenRecordingExportError.cannotRender
        }
        guard let raster = context.createCGImage(image, from: extent, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw ScreenRecordingExportError.cannotRender
        }
        let bitmap = CIImage(cgImage: raster)
        guard extent.minX != 0 || extent.minY != 0 else { return bitmap }
        return bitmap.transformed(by: .init(translationX: extent.minX, y: extent.minY))
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
