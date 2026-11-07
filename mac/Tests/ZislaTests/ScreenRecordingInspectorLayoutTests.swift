import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct ScreenRecordingInspectorLayoutTests {
    @Test(arguments: AppLanguage.allCases, [ControlSize.small, .regular])
    func tintedActionsMatchNativeControlHeights(language: AppLanguage, size: ControlSize) {
        let title = AppLocalization.string("移除", language: language)
        let reference = NSHostingView(rootView: Picker("", selection: Binding.constant(0)) {
            Text(title).tag(0)
        }.labelsHidden().pickerStyle(.menu).controlSize(size)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        let text = NSHostingView(rootView: Button(title) {}
            .buttonStyle(SettingsTintedButtonStyle()).controlSize(size)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        let icon = NSHostingView(rootView: Button {} label: {
            Label(title, systemImage: "arrow.clockwise")
        }.buttonStyle(SettingsTintedButtonStyle()).controlSize(size)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        let expectedHeight = reference.fittingSize.height
        #expect(expectedHeight > 0)
        #expect(abs(text.fittingSize.height - expectedHeight) < 0.5)
        #expect(abs(icon.fittingSize.height - expectedHeight) < 0.5)
    }

    @Test(arguments: AppLanguage.allCases, [296.0, 366.0])
    func preciseInputsKeepCompactWidthsInsideTheInspector(language: AppLanguage, width: Double) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let section = ScreenRecordingInspectorSection(AppLocalization.string("手动缩放", language: language), symbol: "plus.magnifyingglass") {
            ScreenRecordingNumberField(title: AppLocalization.string("起点（秒）", language: language),
                value: .constant(12.375), identifier: "start")
            ScreenRecordingNumberField(title: AppLocalization.string("焦点水平位置", language: language),
                value: .constant(0.125), identifier: "focus")
        }
        let fixture = Fixture(section.frame(width: width), language: language)
        defer { fixture.window.close() }
        await fixture.settle()
        let inputs = fixture.editableFields()
        #expect(inputs.count == 2)
        for input in inputs {
            let frame = input.convert(input.bounds, to: fixture.host)
            #expect(frame.width > 0 && frame.width <= 84.5, "Seconds and coordinates must not stretch into full-width form fields")
            #expect(fixture.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        }
        #expect(abs(fixture.host.fittingSize.width - width) <= 0.5)
        #expect(!fixture.window.isVisible)
    }

    enum MediumControlPanel: CaseIterable, Sendable { case ai, captions, effects, timeline, multitrack, media, export }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [false, true])
    func enhancementsStayOnTheEffectsPageWithVoiceUnderAudio(language: AppLanguage, multitrack: Bool) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let recording = try RecordingMultitrackTestFixture()
        let model = try recording.model()
        defer { model.shutdown(); recording.remove() }
        var project = recording.project()
        project.cameraFile = "camera.mp4"
        project.microphoneFile = "microphone.mp4"
        project.edits.portraitEffects = .init(smoothing: 0.3)
        project.edits.voiceEffects = .init(preset: .warm, amount: 0.6)
        if multitrack { project.timeline = .migrating(project) }
        model.install(project, directory: recording.directory)
        let clip = Fixture(ScreenRecordingMultitrackClipInspector(model: model).frame(width: 296), language: language)
        let effectsView = ScreenRecordingEffectsView(model: model)
        let effects = Fixture(effectsView.frame(width: 296), language: language)
        defer { clip.window.close(); effects.window.close() }
        await clip.settle()
        await effects.settle()
        #expect(clip.control(AppLocalization.text("人像效果"), role: .disclosureTriangle) == nil)
        for identifier in ["screenRecording.portrait.smoothing", "screenRecording.portrait.brightening",
                           "screenRecording.portrait.faceSlimming", "screenRecording.portrait.bodySlimming",
                           "screenRecording.voicePreset", "screenRecording.voiceAmount",
                           "screenRecording.resetPortraitEffects", "screenRecording.resetVoiceEffects"] {
            #expect(clip.element(identifier) == nil, "The clip page must not contain portrait or voice controls")
        }
        let portrait = try #require(effects.element("screenRecording.portrait.bodySlimming"))
        #expect(effects.element("screenRecording.voicePreset") == nil, "Voice must live inside the collapsed audio section")
        let audio = try #require(effects.control(AppLocalization.text("音频"), role: .disclosureTriangle))
        try effects.press(audio)
        await effects.settle()
        let voice = try #require(effects.element("screenRecording.voicePreset"))
        let amount = try #require(effects.element("screenRecording.voiceAmount"))
        #expect(effects.textValues().contains(AppLocalization.text("美声")))
        #expect(effects.frame(portrait).maxY < effects.frame(audio).minY)
        #expect(effects.frame(audio).maxY < effects.frame(voice).minY)
        for control in [voice, amount] {
            #expect(effects.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(effects.frame(control)))
        }
        let controls = ScreenRecordingPortraitControls(model: model, target: effectsView.enhancementTarget.target,
            showsPortrait: true, showsVoice: true)
        try effects.press(try #require(effects.element("screenRecording.resetVoiceEffects")))
        await effects.settle()
        #expect(controls.voice == .init() && controls.portrait == project.edits.portraitEffects)
        #expect(effects.element("screenRecording.voiceAmount") == nil)
        model.undo()
        await effects.settle()
        #expect(model.project == project)
        try effects.press(try #require(effects.element("screenRecording.resetPortraitEffects")))
        await effects.settle()
        #expect(controls.portrait == .init() && controls.voice == project.edits.voiceEffects)
        model.undo()
        #expect(model.project == project && !model.canUndo)
        #expect(!clip.window.isVisible && !effects.window.isVisible)
    }

    enum EnhancementMedia: CaseIterable, Sendable { case video, silentVideo, image, audio }

    @Test(arguments: [false, true])
    func recordingWithoutAMicrophoneDoesNotOfferVoiceEffects(camera: Bool) async throws {
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let recording = try RecordingMultitrackTestFixture()
        let model = try recording.model()
        defer { model.shutdown(); recording.remove() }
        var project = recording.project()
        if camera { project.cameraFile = "camera.mp4" }
        model.install(project, directory: recording.directory)
        let fixture = Fixture(ScreenRecordingEffectsView(model: model).frame(width: 296), language: .english)
        defer { fixture.window.close() }
        await fixture.settle()
        #expect((fixture.element("screenRecording.portrait.smoothing") != nil) == camera)
        try fixture.press(try #require(fixture.control(AppLocalization.text("音频"), role: .disclosureTriangle)))
        await fixture.settle()
        #expect(fixture.element("screenRecording.voicePreset") == nil)
        #expect(fixture.element("screenRecording.resetVoiceEffects") == nil)
        #expect(model.project == project && !model.canUndo)
        #expect(!fixture.window.isVisible)
    }

    @Test(arguments: EnhancementMedia.allCases)
    func importedEnhancementsRemainEditableOnTheEffectsPage(media: EnhancementMedia) async throws {
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let recording = try RecordingMultitrackTestFixture()
        let model = try recording.model()
        defer { model.shutdown(); recording.remove() }
        var project = recording.project()
        project.videoFile = ""
        project.edits.segments = []
        let kind: RecordingMediaKind = media == .image ? .image : media == .audio ? .audio : .video
        let asset = RecordingMediaAsset(name: "Imported", file: "imported.mp4", kind: kind, duration: 2,
            width: 64, height: 48, hasAudio: media == .audio || media == .video)
        let track = RecordingTimelineTrack()
        var timeline = RecordingMultitrackTimeline(assets: [asset], tracks: [track])
        let added = timeline.addAssetClip(asset.id, at: 0, trackID: track.id)
        let id = try #require(added)
        project.timeline = timeline
        model.install(project, directory: recording.directory)
        let fixture = Fixture(ScreenRecordingEffectsView(model: model).frame(width: 296), language: .english)
        defer { fixture.window.close() }
        await fixture.settle()
        #expect((fixture.element("screenRecording.portrait.smoothing") != nil) == (media != .audio))
        try fixture.press(try #require(fixture.control(AppLocalization.text("音频"), role: .disclosureTriangle)))
        await fixture.settle()
        #expect((fixture.element("screenRecording.voicePreset") != nil) == (media == .audio || media == .video))
        let effectsView = ScreenRecordingEffectsView(model: model)
        let controls = ScreenRecordingPortraitControls(model: model, target: effectsView.enhancementTarget.target,
            showsPortrait: media != .audio, showsVoice: media == .audio || media == .video)
        if media != .audio { controls.setPortrait(.init(brightening: 0.5)) }
        if media == .audio || media == .video { controls.setVoice(.init(preset: .bright, amount: 0.4)) }
        #expect(model.timeline?.clips.first { $0.id == id }?.portraitEffects == (media == .audio ? nil : .init(brightening: 0.5)))
        #expect(model.timeline?.clips.first { $0.id == id }?.voiceEffects == (media == .audio || media == .video
            ? .init(preset: .bright, amount: 0.4) : nil))
        #expect(model.project?.edits == project.edits, "Imported clip adjustments must not change recording defaults")
        model.selectTimelineTrack(track.id)
        await fixture.settle()
        #expect(fixture.element("screenRecording.portrait.smoothing") == nil && fixture.element("screenRecording.voicePreset") == nil)
        #expect(!fixture.window.isVisible)
    }

    @Test(arguments: AppLanguage.allCases, MediumControlPanel.allCases)
    func recordingMenusUseNativeMediumHeight(language: AppLanguage, panel: MediumControlPanel) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let recording = try RecordingMultitrackTestFixture()
        let model = try recording.model()
        defer { model.shutdown(); recording.remove() }
        var project = recording.project()
        project.cameraFile = "camera.mp4"
        if panel == .effects { project.microphoneFile = "microphone.mp4" }
        project.timeline = panel == .multitrack ? .migrating(project) : nil
        model.install(project, directory: recording.directory)
        if let clip = project.timeline?.clips.first { model.selectTimelineClip(clip.id) }
        let view: AnyView
        let expectedCount: Int
        switch panel {
        case .ai:
            view = AnyView(ScreenRecordingAIView(model: model))
            expectedCount = 1
        case .captions:
            view = AnyView(ScreenRecordingCaptionsView(model: model))
            expectedCount = 1
        case .effects:
            view = AnyView(ScreenRecordingEffectsView(model: model))
            expectedCount = 5
        case .timeline:
            view = AnyView(ScreenRecordingTimelineView(model: model, selectedSegmentID: .constant(nil)))
            expectedCount = 2
        case .multitrack:
            view = AnyView(ScreenRecordingMultitrackClipInspector(model: model))
            expectedCount = 5
        case .media:
            view = AnyView(ScreenRecordingMediaLibraryView(model: model, grouping: .importedAt))
            expectedCount = 2
        case .export:
            view = AnyView(ScreenRecordingExportSettingsView(settings: .init(configuration: .init(), panel: NSSavePanel(), duration: 2)))
            expectedCount = 3
        }
        let reference = Fixture(Picker("Reference", selection: Binding.constant(0)) { Text("Medium").tag(0) }
            .pickerStyle(.menu).controlSize(.regular).labelsHidden(), language: language)
        let fixture = Fixture(view.frame(width: 366), language: language)
        defer { fixture.window.close(); reference.window.close() }
        await reference.settle()
        await fixture.settle()
        if panel == .effects {
            for title in ["摄像头叠加", "音频"] {
                let disclosure = try #require(fixture.control(AppLocalization.text(title), role: .disclosureTriangle))
                try fixture.press(disclosure)
                await fixture.settle()
            }
        }
        let referenceHeight = try #require(reference.menuFrames().first).height
        let frames = fixture.menuFrames()
        #expect(frames.count == expectedCount)
        for frame in frames {
            #expect(abs(frame.height - referenceHeight) < 0.5,
                    "Every recording menu must keep the native medium height inside its production container")
        }
        #expect(model.project == project && !model.isDirty && !model.canUndo)
        #expect(!fixture.window.isVisible && !reference.window.isVisible)
    }

    @Test
    func collapsedSectionsLeaveThePreviewSpaceForTheTimeline() async {
        let expanded = Fixture(section(expanded: true), language: .english)
        let collapsed = Fixture(section(expanded: false), language: .english)
        defer { expanded.window.close(); collapsed.window.close() }
        await expanded.settle()
        await collapsed.settle()
        #expect(expanded.host.fittingSize.height > collapsed.host.fittingSize.height + 100)
        #expect(collapsed.host.fittingSize.height < 60)
    }

    @Test(arguments: AppLanguage.allCases, [296.0, 366.0])
    func aiActionStaysAboveTheEditorAtTheTrailingEdge(language: AppLanguage, width: Double) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        #expect(AppLocalization.currentLanguage == language)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let model = ScreenRecordingStudioModel()
        defer { model.shutdown() }
        let fixture = Fixture(ScreenRecordingAIView(model: model).frame(width: width), language: language)
        defer { fixture.window.close() }
        await fixture.settle()
        var pendingViews = [fixture.host]
        var editorScroll: NSScrollView?
        while let view = pendingViews.popLast() {
            if let editor = view as? NSTextView { editorScroll = editor.enclosingScrollView }
            pendingViews.append(contentsOf: view.subviews)
        }
        let scroll = try #require(editorScroll)
        #expect(scroll.verticalScroller is ThinScroller)
        #expect(scroll.scrollerStyle == .legacy)
        let action = try #require(fixture.element("screenRecording.generateAIEdit"))
        let editor = try #require(fixture.element("screenRecording.aiInstruction"))
        let label = try #require((action as? NSObject)?.value(forKey: "accessibilityLabel") as? String)
        #expect(label == AppLocalization.string("生成剪辑方案", language: language))
        let actionFrame = fixture.frame(action)
        let editorFrame = fixture.frame(editor)
        let naturalAction = NSHostingView(rootView: Button(AppLocalization.string("生成剪辑方案", language: language)) {}
            .buttonStyle(SettingsTintedButtonStyle()).controlSize(.small))
        #expect(actionFrame.width + 0.5 >= naturalAction.fittingSize.width,
                "The header action must retain enough width to show its complete translation")
        #expect(actionFrame.maxY <= editorFrame.minY, "The action belongs above the input, not below it")
        #expect(fixture.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(actionFrame))
        if language.isRightToLeft {
            #expect(abs(actionFrame.minX - editorFrame.minX) <= 0.5)
        } else {
            #expect(abs(actionFrame.maxX - editorFrame.maxX) <= 0.5)
        }
        #expect(abs(fixture.host.fittingSize.width - width) <= 0.5)
        #expect(fixture.textValues().isDisjoint(with: [
            AppLocalization.string("例如：删除 2 到 4 秒，将开场加速，并添加缩放", language: language),
            AppLocalization.string("仅在生成方案时发送指令和部分字幕，原始视频留在本机", language: language),
        ]))
    }

    @Test(arguments: [false, true])
    func headerActionsDoNotToggleTheDisclosureAndHonorDisabledState(disabled: Bool) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        var expanded = false
        var count = 0
        let section = ScreenRecordingInspectorSection("Canvas", symbol: "rectangle", isExpanded: Binding(
            get: { expanded }, set: { expanded = $0 })) {
                TextField("Value", text: .constant("Body")).accessibilityIdentifier("body")
            } actions: {
                Button("Add") { count += 1 }.buttonStyle(SettingsTintedButtonStyle())
                    .accessibilityIdentifier("headerAction").disabled(disabled)
            }
        let fixture = Fixture(section.frame(width: 296), language: .english)
        defer { fixture.window.close() }
        fixture.window.setFrameOrigin(.init(x: -100_000, y: -100_000))
        fixture.window.orderFrontRegardless()
        await fixture.settle()
        let action = try #require(fixture.element("headerAction"))
        try fixture.click(action.accessibilityFrame())
        await fixture.settle()
        #expect(count == (disabled ? 0 : 1))
        #expect(!expanded, "An action must not be interpreted as a disclosure click")
        #expect(fixture.element("body") == nil)
        #expect(!fixture.window.isKeyWindow)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(fixture.window.frame) })
    }

    enum PairedActionPanel: CaseIterable, Sendable { case captions, timeline, proposal }

    @Test(arguments: AppLanguage.allCases, PairedActionPanel.allCases.flatMap { panel in
        [296.0, 366.0].map { (panel: panel, width: $0) }
    })
    func pairedActionsFitAboveTheirContent(language: AppLanguage, layout: (panel: PairedActionPanel, width: Double)) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-paired-header-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Header", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        let model = ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender }, aiCompletion: { _, _, _ in
                #"{"version":1,"operations":[{"type":"cut","start":2,"end":4}]}"#
            })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.install(project, directory: root)
        let view: AnyView
        let titles: (String, String)
        switch layout.panel {
        case .captions:
            view = AnyView(ScreenRecordingCaptionsView(model: model))
            titles = ("生成字幕", "导出 SRT")
        case .timeline:
            view = AnyView(ScreenRecordingTimelineView(model: model, selectedSegmentID: .constant(nil)))
            titles = ("在播放头处分割", "恢复完整素材")
        case .proposal:
            model.aiInstruction = "Synthetic edit"
            model.requestAIEdit()
            await model.operationTask?.value
            try #require(model.pendingAIProject)
            view = AnyView(ScreenRecordingAIView(model: model))
            titles = ("应用方案", "放弃方案")
        }
        let fixture = Fixture(view.frame(width: layout.width), language: language)
        defer { fixture.window.close() }
        await fixture.settle()
        let primary = try #require(fixture.control(AppLocalization.string(titles.0, language: language), role: .button))
        let secondary = try #require(fixture.control(AppLocalization.string(titles.1, language: language), role: .button))
        let content: any NSAccessibilityElementProtocol
        if layout.panel == .captions {
            #expect(fixture.textValues().contains(AppLocalization.string("识别语言", language: language)))
            content = try #require(fixture.control(model.subtitleLanguage.nativeDisplayName, role: .popUpButton))
        } else {
            let duration = layout.panel == .proposal ? try #require(model.pendingAIProject).outputDuration : project.outputDuration
            content = try #require(fixture.control(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(duration)),
                role: .staticText))
        }
        let frames = [fixture.frame(primary), fixture.frame(secondary)]
        #expect(abs(frames[0].height - frames[1].height) < 0.5,
                "Adjacent header actions must keep the same control height")
        let naturalPrimary = NSHostingView(rootView: Button(AppLocalization.string(titles.0, language: language)) {}
            .buttonStyle(SettingsTintedButtonStyle()).controlSize(layout.panel == .timeline ? .regular : .small))
        let naturalSecondary = NSHostingView(rootView: Button(AppLocalization.string(titles.1, language: language)) {}
            .controlSize(layout.panel == .timeline ? .regular : .small))
        for (frame, naturalWidth) in zip(frames, [naturalPrimary.fittingSize.width, naturalSecondary.fittingSize.width]) {
            #expect(frame.width + 0.5 >= naturalWidth, "Both header actions must show their complete translations")
            #expect(frame.maxY <= fixture.frame(content).minY)
            #expect(fixture.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        }
        let actionsFrame = frames[0].union(frames[1])
        let contentFrame = fixture.host.bounds.insetBy(dx: layout.panel == .timeline ? 0 : 12, dy: 0)
        #expect(abs(language.isRightToLeft ? actionsFrame.minX - contentFrame.minX
            : actionsFrame.maxX - contentFrame.maxX) <= 0.5)
        if frames[0].maxY <= frames[1].minY {
            for frame in frames {
                #expect(abs(language.isRightToLeft ? frame.minX - contentFrame.minX
                    : frame.maxX - contentFrame.maxX) <= 0.5, "Stacked actions must each align to the trailing edge")
            }
        }
        #expect(abs(fixture.host.fittingSize.width - layout.width) <= 0.5)
    }

    @Test(arguments: [0.0, 10.0])
    func addingFromACollapsedZoomSectionRevealsTheNewItem(time: Double) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-header-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Header", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        let model = ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.install(project, directory: root)
        model.seek(to: time)
        let fixture = Fixture(ScreenRecordingEffectsView(model: model).frame(width: 296), language: .english)
        defer { fixture.window.close() }
        fixture.window.setFrameOrigin(.init(x: -100_000, y: -100_000))
        fixture.window.orderFrontRegardless()
        await fixture.settle()
        let previousInputCount = fixture.editableFields().count
        let add = try #require(fixture.element("screenRecording.addZoom"))
        try fixture.click(add.accessibilityFrame())
        await fixture.settle()
        if time == project.duration {
            #expect(model.project == project && !model.canUndo)
            #expect(fixture.editableFields().count == previousInputCount)
            return
        }
        let zoom = try #require(model.project?.edits.zoomClips.first)
        #expect(model.project?.edits.zoomClips.count == 1)
        #expect(fixture.element("screenRecording.zoom." + zoom.id.uuidString) != nil)
        let inputs = Array(fixture.editableFields().dropFirst(previousInputCount))
        #expect(inputs.count == 5, "Adding from a collapsed section must reveal its precise inputs")
        for (input, value) in zip(inputs, [zoom.time, zoom.duration, zoom.scale, zoom.x, zoom.y]) {
            #expect(input.doubleValue == value)
            #expect(!input.isHiddenOrHasHiddenAncestor)
            #expect(fixture.host.bounds.contains(input.convert(input.bounds, to: fixture.host)))
        }
        model.undo()
        #expect(model.project == project && !model.canUndo)
    }

    @Test(arguments: [0.0, 10.0])
    func addingFromACollapsedCaptionSectionRevealsTheNewText(time: Double) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-caption-header-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Header", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        let model = ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.install(project, directory: root)
        model.seek(to: time)
        let canvasSelection = CanvasSelectionState()
        // Exercise delayed view removal consistently across macOS versions.
        let fixture = Fixture(CaptionCanvasHost(model: model, selection: canvasSelection).frame(width: 296)
            .transaction { $0.animation = .linear(duration: 0.25) }, language: .english)
        defer { fixture.window.close() }
        fixture.window.setFrameOrigin(.init(x: -100_000, y: -100_000))
        fixture.window.orderFrontRegardless()
        await fixture.settle()
        let expandedHeight = fixture.host.fittingSize.height
        let disclosure = try #require(fixture.control(AppLocalization.text("字幕"), role: .disclosureTriangle))
        let disclosureObject = try #require(disclosure as? NSObject)
        #expect((disclosureObject.value(forKey: "accessibilityValue") as? NSNumber)?.boolValue == true)
        try fixture.press(disclosure)
        await fixture.settle()
        #expect((disclosureObject.value(forKey: "accessibilityValue") as? NSNumber)?.boolValue == false)
        #expect(fixture.host.fittingSize.height < expandedHeight)
        let add = try #require(fixture.element("screenRecording.addCaption"))
        try fixture.press(add)
        await fixture.settle()
        if time == project.duration {
            #expect(model.project == project && !model.canUndo)
            #expect(fixture.editableFields().isEmpty)
            return
        }
        let caption = try #require(model.project?.captions.first)
        #expect(model.project?.captions.count == 1)
        #expect(fixture.element("screenRecording.caption." + caption.id.uuidString) != nil)
        let input = try #require(fixture.editableFields().first { $0.stringValue == caption.text })
        #expect(!input.isHiddenOrHasHiddenAncestor)
        #expect(fixture.host.bounds.contains(input.convert(input.bounds, to: fixture.host)))
        #expect(canvasSelection.value == .caption(caption.id))
        try fixture.press(try #require(fixture.control(AppLocalization.text("字幕"), role: .disclosureTriangle)))
        await fixture.settle(until: { fixture.editableFields().isEmpty })
        #expect(fixture.editableFields().isEmpty)
        canvasSelection.value = nil
        await fixture.settle()
        canvasSelection.value = .caption(caption.id)
        await fixture.settle()
        let selectedInput = try #require(fixture.editableFields().first { $0.stringValue == caption.text },
                                        "Selecting a caption on the canvas must reopen its collapsed inspector")
        #expect(!selectedInput.isHiddenOrHasHiddenAncestor)
        model.undo()
        #expect(model.project == project && !model.canUndo)
    }

    private func section(expanded: Bool) -> some View {
        ScreenRecordingInspectorSection("Canvas", symbol: "rectangle", expanded: expanded) {
            ScreenRecordingParameterRow(title: "Padding", value: .constant(0.06), range: 0...0.3, identifier: "padding")
            ScreenRecordingParameterRow(title: "Corner Radius", value: .constant(0.02), range: 0...0.2, identifier: "corner")
            ScreenRecordingParameterRow(title: "Shadow", value: .constant(0.3), range: 0...1, identifier: "shadow")
        }.frame(width: 296)
    }

    private final class CanvasSelectionState: ObservableObject {
        @Published var value: RecordingCanvasSelection?
    }

    private struct CaptionCanvasHost: View {
        let model: ScreenRecordingStudioModel
        @ObservedObject var selection: CanvasSelectionState

        var body: some View {
            ScreenRecordingCaptionsView(model: model).environment(\.recordingCanvasSelection, $selection.value)
        }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let host: NSView

        init<Content: View>(_ content: Content, language: AppLanguage) {
            let hosting = NSHostingView(rootView: content.environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
            host = hosting
            window = NSPanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
        }

        func settle(until isReady: () -> Bool = { true }) async {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            repeat {
                for _ in 0..<3 {
                    window.setContentSize(host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
                }
                if isReady() || ContinuousClock.now >= deadline { return }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { continuation.resume() }
                }
            } while true
        }

        func editableFields(in view: NSView? = nil) -> [NSTextField] {
            let view = view ?? host
            if let field = view as? NSTextField, field.isEditable { return [field] }
            return view.subviews.flatMap { editableFields(in: $0) }
        }

        func menuFrames() -> [CGRect] {
            accessibilityObjects(host).compactMap { object in
                guard object.responds(to: NSSelectorFromString("accessibilityRole")),
                      object.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.popUpButton.rawValue,
                      let element = object as? any NSAccessibilityElementProtocol else { return nil }
                return frame(element)
            }
        }

        func element(_ identifier: String) -> (any NSAccessibilityElementProtocol)? {
            accessibilityObjects(host).first {
                $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
            } as? any NSAccessibilityElementProtocol
        }

        func control(_ title: String, role: NSAccessibility.Role) -> (any NSAccessibilityElementProtocol)? {
            accessibilityObjects(host).first { object in
                object.responds(to: NSSelectorFromString("accessibilityRole"))
                    && object.value(forKey: "accessibilityRole") as? String == role.rawValue
                    && ["accessibilityLabel", "accessibilityValue"].contains { key in
                        object.responds(to: NSSelectorFromString(key)) && object.value(forKey: key) as? String == title
                    }
            } as? any NSAccessibilityElementProtocol
        }

        func textValues() -> Set<String> {
            Set(accessibilityObjects(host).flatMap { object in
                ["accessibilityLabel", "accessibilityValue"].compactMap {
                    object.responds(to: NSSelectorFromString($0)) ? object.value(forKey: $0) as? String : nil
                }
            })
        }

        private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return [object] }
            return [object] + (object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [])
                .flatMap { accessibilityObjects($0) }
        }

        func frame(_ element: any NSAccessibilityElementProtocol) -> CGRect {
            host.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
        }

        func press(_ element: any NSAccessibilityElementProtocol) throws {
            let object = try #require(element as? NSObject)
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(object.responds(to: action))
            object.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
        }

        func click(_ frame: CGRect) throws {
            let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
            }
        }
    }
}
