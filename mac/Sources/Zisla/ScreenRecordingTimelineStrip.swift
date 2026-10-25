import SwiftUI
import ZislaCore

struct ScreenRecordingTimelineStripGeometry {
    struct Item: Identifiable {
        let segment: RecordingSegment
        let slice: RecordingExportSlice
        let x: CGFloat
        let width: CGFloat
        var id: UUID { segment.id }
    }

    struct Target: Equatable {
        let segmentID: UUID
        let sourceTime: Double
        let outputTime: Double
    }

    let items: [Item]
    let width: CGFloat
    let duration: Double
    let pointsPerSecond: CGFloat

    init?(segments: [RecordingSegment], viewportWidth: CGFloat, zoom: Double) {
        guard viewportWidth.isFinite, viewportWidth > 0, zoom.isFinite, (1...16).contains(zoom),
              viewportWidth <= CGFloat.greatestFiniteMagnitude / zoom else { return nil }
        width = viewportWidth * zoom
        duration = segments.reduce(0) { $0 + $1.outputDuration }
        pointsPerSecond = duration > 0 ? width / duration : 0
        let scale = pointsPerSecond
        var cursor = 0.0
        items = segments.enumerated().map { index, segment in
            let end = cursor + segment.outputDuration
            defer { cursor = end }
            let slice = RecordingExportSlice(index: index, sourceStart: segment.start, sourceEnd: segment.end,
                speed: segment.speed, outputStart: cursor, outputEnd: end)
            return Item(segment: segment, slice: slice, x: cursor * scale, width: segment.outputDuration * scale)
        }
    }

    func target(at x: CGFloat) -> Target? {
        guard duration > 0, x.isFinite else { return nil }
        let output = min(duration, max(0, x / pointsPerSecond))
        let index = recordingUpperBound(items, value: output + output.ulp * 4, key: \.slice.outputEnd)
        let item = items[min(index, items.count - 1)]
        return Target(segmentID: item.id, sourceTime: item.slice.sourceTime(at: output), outputTime: output)
    }

    func playheadX(sourceTime: Double, selectedID: UUID?, outputTime: Double?) -> CGFloat? {
        guard duration > 0 else { return nil }
        if let outputTime, outputTime.isFinite {
            return min(width, max(0, outputTime * pointsPerSecond))
        }
        let contains: (Item) -> Bool = { sourceTime >= $0.segment.start && sourceTime <= $0.segment.end }
        guard let item = items.first(where: { $0.id == selectedID && contains($0) }) ?? items.first(where: contains) else { return nil }
        return item.x + (sourceTime - item.segment.start) / item.segment.speed * pointsPerSecond
    }

    var ticks: [Double] {
        guard duration > 0 else { return [] }
        let interval = duration / max(1, min(240, width / 80))
        let unit = pow(10, floor(log10(interval)))
        let multiplier = [1.0, 2, 5, 10].first(where: { $0 * unit >= interval })!
        let step = multiplier * unit
        return (0...Int(floor(duration / step))).map { Double($0) * step }
    }
}

struct ScreenRecordingTimelineTrim {
    enum Edge: Equatable { case start, end }

    let original: RecordingSegment
    let edge: Edge
    let pointsPerSecond: CGFloat
    var translation: CGFloat = 0

    func replacement(sourceDuration: Double) -> RecordingSegment? {
        guard translation.isFinite, pointsPerSecond.isFinite, pointsPerSecond > 0 else { return nil }
        let change = translation / pointsPerSecond * original.speed
        let minimum = min(0.001, original.end - original.start)
        var replacement = original
        switch edge {
        case .start: replacement.start = min(original.end - minimum, max(0, original.start + change))
        case .end: replacement.end = min(sourceDuration, max(original.start + minimum, original.end + change))
        }
        return replacement
    }

    static func split(_ segment: RecordingSegment, at time: Double) -> [RecordingSegment]? {
        guard time > segment.start + 0.001, time < segment.end - 0.001 else { return nil }
        var leading = segment
        leading.end = time
        var trailing = segment
        trailing.id = UUID()
        trailing.start = time
        return [leading, trailing]
    }
}

struct ScreenRecordingTimelineStrip: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Binding var selectedID: UUID?
    @Environment(\.isEnabled) private var isEnabled
    @State private var zoom = 1.0
    @State private var trim: ScreenRecordingTimelineTrim?

    var body: some View {
        if let project = model.project {
            content(project).disabled(!model.canEdit)
        }
    }

    private var selectedSegmentID: UUID? { selectedID ?? model.project?.edits.segments.first?.id }

    private func content(_ project: ScreenRecordingProject) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(AppLocalization.text("时间线")).font(.caption.bold())
                Button(action: splitAtPlayhead) { Image(systemName: "scissors") }
                    .help(AppLocalization.text("在播放头处分割"))
                    .accessibilityLabel(AppLocalization.text("在播放头处分割"))
                    .accessibilityIdentifier("screenRecording.timelineSplit")
                    .disabled(model.timelineSplitTarget(at: model.playbackTime) == nil)
                Button { if let id = selectedSegmentID { duplicate(id) } } label: { Image(systemName: "plus.square.on.square") }
                    .help(AppLocalization.text("复制片段"))
                    .accessibilityLabel(AppLocalization.text("复制片段"))
                    .accessibilityIdentifier("screenRecording.timelineDuplicate")
                    .disabled(selectedSegmentID == nil)
                Button(role: .destructive) { if let id = selectedSegmentID { remove(id) } } label: { Image(systemName: "trash") }
                    .help(AppLocalization.text("删除片段"))
                    .accessibilityLabel(AppLocalization.text("删除片段"))
                    .accessibilityIdentifier("screenRecording.timelineDelete")
                    .disabled(selectedSegmentID == nil)
                Spacer(minLength: 4)
                Button { zoom = max(1, zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help(AppLocalization.text("缩小")).disabled(zoom <= 1)
                    .accessibilityLabel(AppLocalization.text("缩小"))
                    .accessibilityIdentifier("screenRecording.timelineZoomOut")
                Slider(value: $zoom, in: 1...16).frame(maxWidth: 100)
                    .accessibilityLabel(AppLocalization.text("缩放倍率"))
                    .accessibilityIdentifier("screenRecording.timelineZoom")
                Button { zoom = min(16, zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help(AppLocalization.text("放大")).disabled(zoom >= 16)
                    .accessibilityLabel(AppLocalization.text("放大"))
                    .accessibilityIdentifier("screenRecording.timelineZoomIn")
            }.buttonStyle(.plain)
            GeometryReader { proxy in
                if let geometry = ScreenRecordingTimelineStripGeometry(segments: project.edits.segments,
                    viewportWidth: proxy.size.width - 16, zoom: zoom) {
                    ScrollView(.horizontal) {
                        timeline(geometry, project: project).padding(.horizontal, 8)
                    }
                }
            }.frame(height: 98)
        }
        .onChange(of: project.edits.segments) { _, segments in
            trim = nil
            if !segments.contains(where: { $0.id == selectedID }) { selectedID = segments.first?.id }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { trim = nil } }
        .onExitCommand { trim = nil }
    }

    private func timeline(_ geometry: ScreenRecordingTimelineStripGeometry, project: ScreenRecordingProject) -> some View {
        let splitID = model.timelineSplitTarget(at: model.playbackTime)?.segmentID
        return ZStack(alignment: .topLeading) {
            ruler(geometry)
            ForEach(geometry.items) { item in
                segment(item, splitID: splitID)
                    .frame(width: item.width, height: 48)
                    .position(x: item.x + item.width / 2, y: 48)
            }
            if let selected = geometry.items.first(where: { $0.id == (selectedID ?? geometry.items.first?.id) }) {
                let preview = trim?.original.id == selected.id ? trim?.replacement(sourceDuration: project.duration) : nil
                let start = preview?.start ?? selected.segment.start
                let end = preview?.end ?? selected.segment.end
                let left = selected.x + (start - selected.segment.start) / selected.segment.speed * geometry.pointsPerSecond
                let right = selected.x + (end - selected.segment.start) / selected.segment.speed * geometry.pointsPerSecond
                if preview != nil {
                    RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: right - left, height: 48).position(x: (left + right) / 2, y: 48)
                        .allowsHitTesting(false)
                }
                trimHandle(selected, edge: .start, geometry: geometry, sourceDuration: project.duration)
                    .position(x: left, y: 48)
                trimHandle(selected, edge: .end, geometry: geometry, sourceDuration: project.duration)
                    .position(x: right, y: 48)
            }
            if let position = geometry.playheadX(sourceTime: model.currentTime, selectedID: selectedID, outputTime: model.playbackTime) {
                Rectangle().fill(.red).frame(width: 2, height: 76).position(x: position, y: 38)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: geometry.width, height: 78)
        .coordinateSpace(name: "screenRecording.timelineCoordinates")
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { event in
            if let target = geometry.target(at: event.location.x) {
                selectedID = target.segmentID
                model.seekTimeline(to: target.outputTime)
            }
        })
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("screenRecording.timelineStrip")
    }

    private func ruler(_ geometry: ScreenRecordingTimelineStripGeometry) -> some View {
        Canvas { context, _ in
            for time in geometry.ticks {
                let x = time * geometry.pointsPerSecond
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 16))
                tick.addLine(to: CGPoint(x: x, y: 21))
                context.stroke(tick, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                let label = Text(time, format: .number.precision(.fractionLength(0...3)))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                context.draw(label, at: CGPoint(x: x, y: 7), anchor: time == 0 ? .leading : .center)
            }
        }.frame(height: 22).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func segment(_ item: ScreenRecordingTimelineStripGeometry.Item, splitID: UUID?) -> some View {
        let selected = item.id == selectedSegmentID
        return RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(selected ? 0.35 : 0.14))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
            .overlay {
                if item.width >= 50 {
                    VStack(spacing: 3) {
                        Text(AppLocalization.text("片段 %d", item.slice.index + 1)).font(.caption.bold())
                        Text(item.segment.outputDuration, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 10, design: .monospaced))
                    }.padding(.horizontal, 10).lineLimit(1)
                }
            }
            .opacity(trim?.original.id == item.id ? 0.4 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.text("片段 %d", item.slice.index + 1))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            .contextMenu {
                Button(AppLocalization.text("在播放头处分割"), action: splitAtPlayhead)
                    .disabled(splitID != item.id)
                Button(AppLocalization.text("复制片段")) { duplicate(item.id) }
                Button(AppLocalization.text("上移")) { move(item.id, to: item.slice.index - 1) }
                    .disabled(item.slice.index == 0)
                Button(AppLocalization.text("下移")) { move(item.id, to: item.slice.index + 1) }
                    .disabled(item.slice.index == (model.project?.edits.segments.count ?? 0) - 1)
                Divider()
                Button(AppLocalization.text("删除片段"), role: .destructive) { remove(item.id) }
            }
            .accessibilityAction { selectSegment(item.id) }
            .accessibilityIdentifier("screenRecording.timelineSegment." + item.id.uuidString)
    }

    private func trimHandle(_ item: ScreenRecordingTimelineStripGeometry.Item, edge: ScreenRecordingTimelineTrim.Edge,
                            geometry: ScreenRecordingTimelineStripGeometry, sourceDuration: Double) -> some View {
        let start = edge == .start
        return RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
            .overlay(Image(systemName: "line.3.vertical").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
            .frame(width: 10, height: 48).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("screenRecording.timelineCoordinates"))
                .onChanged { event in
                    selectedID = item.id
                    if trim == nil { trim = .init(original: item.segment, edge: edge, pointsPerSecond: geometry.pointsPerSecond) }
                    trim?.translation = event.translation.width
                }
                .onEnded { event in
                    guard var completed = trim else { return }
                    trim = nil
                    completed.translation = event.translation.width
                    guard let replacement = completed.replacement(sourceDuration: sourceDuration), replacement != completed.original else { return }
                    model.update { project in
                        guard let index = project.edits.segments.firstIndex(where: { $0.id == completed.original.id }),
                              project.edits.segments[index] == completed.original else { return }
                        project.edits.segments[index] = replacement
                    }
                    model.seekTimeline(to: item.slice.outputStart + (start ? 0 : replacement.outputDuration))
                })
            .help(AppLocalization.text(start ? "起点（秒）" : "终点（秒）"))
            .accessibilityLabel(AppLocalization.text(start ? "起点（秒）" : "终点（秒）"))
            .accessibilityIdentifier("screenRecording.timelineTrim." + (start ? "start." : "end.") + item.id.uuidString)
    }

    private func selectSegment(_ id: UUID) {
        guard let project = model.project, let index = project.edits.segments.firstIndex(where: { $0.id == id }) else { return }
        selectedID = id
        model.seekTimeline(to: project.edits.segments.prefix(index).reduce(0) { $0 + $1.outputDuration })
    }

    private func splitAtPlayhead() {
        if let id = model.splitTimeline(at: model.playbackTime) { selectedID = id }
    }

    private func duplicate(_ id: UUID) {
        if let copyID = model.duplicateSegment(id) { selectSegment(copyID) }
    }

    private func move(_ id: UUID, to index: Int) {
        model.moveSegment(id, to: index)
        selectSegment(id)
    }

    private func remove(_ id: UUID) {
        selectedID = model.deleteSegment(id)
        if let selectedID { selectSegment(selectedID) }
    }
}
