import SwiftUI
import ZislaCore

struct RecordingMultitrackClipDrag {
    enum Mode { case move, trimStart, trimEnd }
    let original: RecordingTimelineClip
    let mode: Mode
    let pointsPerSecond: CGFloat
    var translation: CGSize = .zero

    func replacement(sourceDuration: Double?, tracks: [RecordingTimelineTrack], rowHeight: CGFloat) -> RecordingTimelineClip? {
        guard pointsPerSecond.isFinite, pointsPerSecond > 0,
              translation.width.isFinite, translation.height.isFinite else { return nil }
        let delta = translation.width / pointsPerSecond
        var clip = original
        let minimum = min(0.001, original.sourceEnd - original.sourceStart)
        switch mode {
        case .move:
            clip.start = max(0, original.start + delta)
            let row = tracks.firstIndex(where: { $0.id == original.trackID })!
            let destination = min(tracks.count - 1, max(0, row + Int((translation.height / rowHeight).rounded())))
            clip.trackID = tracks[destination].id
        case .trimStart:
            let earliest = max(0, original.sourceStart - original.start * original.speed)
            clip.sourceStart = min(original.sourceEnd - minimum, max(earliest, original.sourceStart + delta * original.speed))
            clip.start = original.start + (clip.sourceStart - original.sourceStart) / original.speed
        case .trimEnd:
            let latest = sourceDuration ?? (original.sourceStart + (604_800 - original.start) * original.speed)
            clip.sourceEnd = min(latest, max(original.sourceStart + minimum, original.sourceEnd + delta * original.speed))
        }
        return clip
    }
}

struct ScreenRecordingMultitrackTimelineView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.recordingCanvasSelection) private var canvasSelection
    @State private var zoom = 1.0
    @State private var drag: RecordingMultitrackClipDrag?
    private let rowHeight: CGFloat = 44
    private let rulerHeight: CGFloat = 24
    private let headerWidth: CGFloat = 154

    var body: some View {
        if let timeline = model.timeline {
            VStack(spacing: 6) {
                toolbar
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: rulerHeight)
                            ForEach(Array(timeline.tracks.reversed())) { track in
                                trackHeader(track, timeline: timeline).frame(height: rowHeight)
                            }
                        }.frame(width: headerWidth)
                        GeometryReader { proxy in
                            if let geometry = ScreenRecordingTimelineStripGeometry(
                                segments: [.init(start: 0, end: max(10, timeline.duration))],
                                viewportWidth: max(1, proxy.size.width - 16), zoom: zoom) {
                                ScrollView(.horizontal) {
                                    lanes(timeline, geometry: geometry)
                                        .padding(.horizontal, 8)
                                        .background(ScreenRecordingTimelineMagnification(zoom: $zoom,
                                            isEnabled: isEnabled && model.canEdit, onBegan: { drag = nil }))
                                }
                            }
                        }
                        .frame(height: rulerHeight + CGFloat(max(1, timeline.tracks.count)) * rowHeight + 12)
                    }
                }
                .frame(height: min(224, rulerHeight + CGFloat(max(1, timeline.tracks.count)) * rowHeight + 12))
            }
            .disabled(!model.canEdit)
            .environment(\.layoutDirection, .leftToRight)
            .onChange(of: model.project) { _, _ in drag = nil }
            .onChange(of: isEnabled) { _, enabled in if !enabled { drag = nil } }
            .onExitCommand { drag = nil }
            .accessibilityIdentifier("screenRecording.multitrackTimeline")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(AppLocalization.text("时间线")).font(.caption.bold())
            Button { model.addTimelineTrack() } label: { Image(systemName: "rectangle.stack.badge.plus") }
            .help(AppLocalization.text("添加轨道"))
            .accessibilityLabel(AppLocalization.text("添加轨道"))
            .accessibilityIdentifier("screenRecording.multitrackAddTrack")
            Button {
                if let id = model.addTimelineText() { canvasSelection.wrappedValue = .annotation(id) }
            } label: { Image(systemName: "text.badge.plus") }
            .help(AppLocalization.text("文字标注"))
            .accessibilityLabel(AppLocalization.text("文字标注"))
            .accessibilityIdentifier("screenRecording.multitrackAddText")
            Button { if let id = model.selectedTimelineClipID { split(id) } } label: { Image(systemName: "scissors") }
                .help(AppLocalization.text("在播放头处分割"))
                .accessibilityLabel(AppLocalization.text("在播放头处分割"))
                .accessibilityIdentifier("screenRecording.multitrackSplit")
                .disabled(!canSplit(model.selectedTimelineClip))
            Button { if let id = model.selectedTimelineClipID { duplicate(id) } } label: { Image(systemName: "plus.square.on.square") }
                .help(AppLocalization.text("复制片段"))
                .accessibilityLabel(AppLocalization.text("复制片段"))
                .accessibilityIdentifier("screenRecording.multitrackDuplicate")
                .disabled(model.selectedTimelineClip == nil)
            Button(role: .destructive) { if let id = model.selectedTimelineClipID { model.deleteTimelineClip(id) } } label: {
                Image(systemName: "trash")
            }
            .help(AppLocalization.text("删除片段"))
            .accessibilityLabel(AppLocalization.text("删除片段"))
            .accessibilityIdentifier("screenRecording.multitrackDelete")
            .disabled(model.selectedTimelineClip == nil)
            Spacer(minLength: 0)
            Button { zoom = max(1, zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }
                .help(AppLocalization.text("缩小")).accessibilityLabel(AppLocalization.text("缩小")).disabled(zoom <= 1)
            Slider(value: $zoom, in: 1...16).frame(maxWidth: 90)
                .accessibilityLabel(AppLocalization.text("缩放倍率"))
            Button { zoom = min(16, zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }
                .help(AppLocalization.text("放大")).accessibilityLabel(AppLocalization.text("放大")).disabled(zoom >= 16)
        }.buttonStyle(.plain).accessibilityElement(children: .contain)
    }

    private func trackHeader(_ track: RecordingTimelineTrack, timeline: RecordingMultitrackTimeline) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.stack").foregroundStyle(Color.secondary).frame(width: 15)
            Text(track.title(at: timeline.tracks.firstIndex(where: { $0.id == track.id })!))
                .font(.system(size: 10, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.updateTimelineTrack(track.id) { $0.isHidden.toggle() } } label: {
                Image(systemName: track.isHidden ? "eye.slash" : "eye")
            }
            .help(AppLocalization.text(track.isHidden ? "显示轨道" : "隐藏轨道"))
            .accessibilityLabel(AppLocalization.text(track.isHidden ? "显示轨道" : "隐藏轨道"))
            .accessibilityIdentifier("screenRecording.trackVisibility." + track.id)
            Button { model.updateTimelineTrack(track.id) { $0.isMuted.toggle() } } label: {
                Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")
            }
            .help(AppLocalization.text(track.isMuted ? "取消轨道静音" : "静音轨道"))
            .accessibilityLabel(AppLocalization.text(track.isMuted ? "取消轨道静音" : "静音轨道"))
            .accessibilityIdentifier("screenRecording.trackMute." + track.id)
            Menu {
                Button(AppLocalization.text("移到上一层")) { model.moveTimelineTrack(track.id, by: 1) }
                    .disabled(timeline.tracks.last?.id == track.id)
                Button(AppLocalization.text("移到下一层")) { model.moveTimelineTrack(track.id, by: -1) }
                    .disabled(timeline.tracks.first?.id == track.id)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 16)
            .accessibilityLabel(AppLocalization.text("添加轨道"))
        }
        .buttonStyle(.plain).font(.system(size: 10)).padding(.trailing, 8)
        .opacity(track.isHidden ? 0.55 : 1)
    }

    private func lanes(_ timeline: RecordingMultitrackTimeline, geometry: ScreenRecordingTimelineStripGeometry) -> some View {
        let tracks = Array(timeline.tracks.reversed())
        let grouped = Dictionary(grouping: timeline.clips, by: \.trackID)
        return VStack(spacing: 0) {
            ruler(geometry)
            if tracks.isEmpty {
                Text(AppLocalization.text("将素材拖到轨道中开始剪辑"))
                    .font(.caption).foregroundStyle(.secondary).frame(width: geometry.width, height: rowHeight)
                    .dropDestination(for: String.self) { ids, location in
                        addAssets(ids, at: location.x / geometry.pointsPerSecond, trackID: nil)
                    }
            }
            ForEach(tracks) { track in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.07))
                        .contentShape(Rectangle())
                        .onTapGesture { location in model.seekTimeline(to: location.x / geometry.pointsPerSecond) }
                    ForEach(grouped[track.id] ?? []) { clip in
                        clipView(clip, timeline: timeline, geometry: geometry)
                    }
                }
                .frame(width: geometry.width, height: rowHeight)
                .overlay(alignment: .bottom) { Divider().allowsHitTesting(false) }
                .dropDestination(for: String.self) { ids, location in
                    addAssets(ids, at: location.x / geometry.pointsPerSecond, trackID: track.id)
                }
            }
        }
        .frame(width: geometry.width)
        .overlay(alignment: .topLeading) {
            Rectangle().fill(.red).frame(width: 2)
                .offset(x: model.playbackTime * geometry.pointsPerSecond).allowsHitTesting(false)
        }
        .coordinateSpace(name: "screenRecording.multitrackCoordinates")
    }

    private func ruler(_ geometry: ScreenRecordingTimelineStripGeometry) -> some View {
        Canvas { context, _ in
            for time in geometry.ticks {
                let x = time * geometry.pointsPerSecond
                var path = Path()
                path.move(to: .init(x: x, y: 17)); path.addLine(to: .init(x: x, y: 23))
                context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                context.draw(Text(time, format: .number.precision(.fractionLength(0...2)))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary),
                    at: .init(x: x, y: 8), anchor: time == 0 ? .leading : .center)
            }
        }
        .frame(height: rulerHeight).contentShape(Rectangle())
        .onTapGesture { location in model.seekTimeline(to: location.x / geometry.pointsPerSecond) }
        .accessibilityHidden(true)
    }

    private func clipView(_ clip: RecordingTimelineClip, timeline: RecordingMultitrackTimeline,
                          geometry: ScreenRecordingTimelineStripGeometry) -> some View {
        let displayed = drag?.original.id == clip.id ? replacement(for: drag!, timeline: timeline) ?? clip : clip
        let selected = clip.id == model.selectedTimelineClipID
        let rows = Array(timeline.tracks.reversed()).map(\.id)
        let shift = CGFloat((rows.firstIndex(of: displayed.trackID) ?? 0) - (rows.firstIndex(of: clip.trackID) ?? 0)) * rowHeight
        let width = max(2, displayed.duration * geometry.pointsPerSecond)
        return RoundedRectangle(cornerRadius: 5)
            .fill(color(clip.content.trackKind).opacity(selected ? 0.4 : 0.2))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .overlay {
                if width > 35 {
                    Text(model.timelineClipTitle(clip)).font(.system(size: 10, weight: .medium))
                        .lineLimit(1).padding(.horizontal, selected ? 12 : 5)
                }
            }
            .frame(width: width, height: rowHeight - 6)
            .contentShape(Rectangle())
            .onTapGesture { location in
                model.selectTimelineClip(clip.id)
                model.seekTimeline(to: clip.start + location.x / geometry.pointsPerSecond)
            }
            .gesture(dragGesture(clip, mode: .move, timeline: timeline, geometry: geometry))
            .overlay(alignment: .leading) {
                if selected { trimHandle(clip, mode: .trimStart, timeline: timeline, geometry: geometry) }
            }
            .overlay(alignment: .trailing) {
                if selected { trimHandle(clip, mode: .trimEnd, timeline: timeline, geometry: geometry) }
            }
            .offset(x: displayed.start * geometry.pointsPerSecond, y: 3 + shift)
            .zIndex(drag?.original.id == clip.id ? 1 : 0)
            .contextMenu {
                Button(AppLocalization.text("在播放头处分割")) { split(clip.id) }.disabled(!canSplit(clip))
                Button(AppLocalization.text("复制片段")) { duplicate(clip.id) }
                if clip.content.trackKind == .video {
                    Button(AppLocalization.text("分离音频")) { model.detachTimelineAudio(clip.id) }
                        .disabled(!clip.audioEnabled)
                }
                Divider()
                Button(AppLocalization.text("删除片段"), role: .destructive) { model.deleteTimelineClip(clip.id) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.timelineClipTitle(clip))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.selectTimelineClip(clip.id) }
            .accessibilityIdentifier("screenRecording.multitrackClip." + clip.id)
    }

    private func trimHandle(_ clip: RecordingTimelineClip, mode: RecordingMultitrackClipDrag.Mode,
                            timeline: RecordingMultitrackTimeline, geometry: ScreenRecordingTimelineStripGeometry) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
            .overlay(Image(systemName: "line.3.vertical").font(.system(size: 8)).foregroundStyle(.white))
            .frame(width: 9).contentShape(Rectangle())
            .highPriorityGesture(dragGesture(clip, mode: mode, timeline: timeline, geometry: geometry))
            .accessibilityLabel(AppLocalization.text(mode == .trimStart ? "起点（秒）" : "终点（秒）"))
    }

    private func dragGesture(_ clip: RecordingTimelineClip, mode: RecordingMultitrackClipDrag.Mode,
                             timeline: RecordingMultitrackTimeline, geometry: ScreenRecordingTimelineStripGeometry) -> some Gesture {
        DragGesture(minimumDistance: mode == .move ? 3 : 0, coordinateSpace: .named("screenRecording.multitrackCoordinates"))
            .onChanged { event in
                if drag == nil {
                    model.selectedTimelineClipID = clip.id
                    drag = .init(original: clip, mode: mode, pointsPerSecond: geometry.pointsPerSecond)
                }
                drag?.translation = event.translation
            }
            .onEnded { event in
                guard var completed = drag else { return }
                drag = nil
                completed.translation = event.translation
                guard let changed = replacement(for: completed, timeline: timeline), changed != completed.original,
                      model.timeline?.clips.first(where: { $0.id == clip.id }) == completed.original else { return }
                model.updateTimelineClip(clip.id) { $0 = changed }
                model.seekTimeline(to: changed.start)
            }
    }

    private func replacement(for drag: RecordingMultitrackClipDrag, timeline: RecordingMultitrackTimeline) -> RecordingTimelineClip? {
        let media = timeline.assets.first { $0.id == drag.original.content.assetID }
        let duration = media?.kind == .image ? nil : media?.duration
        return drag.replacement(sourceDuration: duration, tracks: Array(timeline.tracks.reversed()), rowHeight: rowHeight)
    }

    private func canSplit(_ clip: RecordingTimelineClip?) -> Bool {
        guard let clip else { return false }
        return model.playbackTime > clip.start + 0.001 && model.playbackTime < clip.end - 0.001
    }

    private func split(_ id: String) {
        if let tail = model.splitTimelineClip(id, at: model.playbackTime) { model.selectTimelineClip(tail) }
    }

    private func duplicate(_ id: String) {
        if let copy = model.duplicateTimelineClip(id) { model.selectTimelineClip(copy) }
    }

    private func addAssets(_ ids: [String], at time: Double, trackID: String?) -> Bool {
        guard model.canEdit else { return false }
        var added = false
        var position = max(0, time)
        for value in ids {
            guard let id = UUID(uuidString: value),
                  let clipID = model.addAssetToTimeline(id, at: position, trackID: trackID),
                  let clip = model.timeline?.clips.first(where: { $0.id == clipID }) else { continue }
            position = clip.end
            added = true
        }
        return added
    }

    private func color(_ kind: RecordingTimelineTrackKind) -> Color {
        switch kind {
        case .video: .accentColor
        case .image: .orange
        case .text: .purple
        case .audio: .green
        }
    }
}
