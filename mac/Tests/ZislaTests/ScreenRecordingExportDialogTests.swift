import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ScreenRecordingExportDialogTests {
    @Test func exportPromptsWithSettingsAndDestinationInOnePanel() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.export()
        let panel = try #require(fixture.panels.presented.first?.panel)

        #expect(panel.title == AppLocalization.text("导出设置"))
        #expect(panel.prompt == AppLocalization.text("导出录屏"))
        let accessory = try #require(panel.accessoryView as? NSHostingView<ScreenRecordingExportSettingsView>,
            "Format, resolution and frame rate must be available in the destination panel")
        #expect(accessory.rootView.settings.configuration == fixture.model.exportConfiguration)
        #expect(accessory.frame.width > 0 && accessory.frame.height > 0)
        #expect(panel.directoryURL?.standardizedFileURL == fixture.root.standardizedFileURL)
        #expect(panel.nameFieldStringValue == "Output.mp4")
        #expect(panel.allowedContentTypes == [.mpeg4Movie])
        #expect(panel.canCreateDirectories)
        #expect(fixture.model.isChoosingFile && !fixture.model.isBusy)
        #expect(fixture.model.operationTask == nil && fixture.notices.screenRecordingOperations.isEmpty)

        fixture.model.export()
        fixture.model.saveCopy()
        #expect(fixture.panels.presented.count == 1, "Repeated commands must reuse the single pending destination decision")
        fixture.panels.presented[0].complete(nil)
        #expect(fixture.model.canExport && !fixture.model.isChoosingFile)
    }

    @Test(arguments: RecordingExportFormat.allCases)
    func panelUsesTheChosenFormatAndDefaultDownloadsWithoutWritingThere(_ format: RecordingExportFormat) throws {
        let fixture = try Fixture(customDirectory: false)
        defer { fixture.close() }
        fixture.model.exportConfiguration.format = format
        fixture.model.export()
        let panel = try #require(fixture.panels.presented.first?.panel)
        #expect(panel.directoryURL == AppPaths.downloads)
        #expect(panel.nameFieldStringValue == "Output." + format.rawValue)
        #expect(panel.allowedContentTypes == [format.contentType])
        #expect(fixture.model.directory == fixture.directory)
        fixture.panels.presented[0].complete(nil)
        #expect(fixture.notices.screenRecordingOperations.isEmpty)
    }

    @Test(arguments: RecordingExportFormat.allCases)
    func eachFixedFormatHasAContentTypeWithItsOwnExtension(_ format: RecordingExportFormat) throws {
        let type = format.contentType
        if format == .livePhoto {
            #expect(type.conforms(to: .package))
            #expect(type.tags[.filenameExtension]?.contains("livephoto") == true)
        } else {
            let resolved = try #require(UTType(tag: format.fileExtension, tagClass: .filenameExtension,
                conformingTo: format.isAudioOnly ? .audio : format == .gif ? .image : .movie))
            #expect(type == resolved)
            #expect(resolved.tags[.filenameExtension]?.map { $0.lowercased() }.contains(format.fileExtension) == true)
        }
    }

    @Test func theAppDeclaresLivePhotoResourcesAsAPackage() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: package.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let livePhoto = try #require(types.first { $0["UTTypeIdentifier"] as? String == "dev.wzz.zisla.livephoto" })
        #expect(livePhoto["UTTypeConformsTo"] as? [String] == ["com.apple.package"])
        let tags = try #require(livePhoto["UTTypeTagSpecification"] as? [String: [String]])
        #expect(tags["public.filename-extension"] == ["livephoto"])
    }

    @Test func cancellingDiscardsSettingsAndPreservesTheUnsavedProject() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.update { $0.name = "Unsaved" }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let originalManifest = try Data(contentsOf: manifest)
        let originalConfiguration = fixture.model.exportConfiguration
        fixture.model.export()
        let panel = try #require(fixture.panels.presented.first?.panel)
        let settings = try settings(in: panel)
        settings.configuration = .init(format: .gif, resolution: .ultraHD, frameRate: 15)
        panel.nameFieldStringValue = "New file.gif"
        panel.directoryURL = fixture.directory
        #expect(fixture.model.exportConfiguration == originalConfiguration)
        fixture.panels.presented[0].complete(nil)

        #expect(fixture.model.exportConfiguration == originalConfiguration)
        #expect(fixture.model.project?.name == "Unsaved" && fixture.model.isDirty)
        #expect(try Data(contentsOf: manifest) == originalManifest)
        #expect(fixture.model.directory == fixture.directory && fixture.model.recordingOutputDirectory == fixture.root)
        #expect(fixture.model.operationTask == nil && fixture.notices.screenRecordingOperations.isEmpty)
        #expect(panel.accessoryView == nil && fixture.model.canExport)
    }

    @Test func formatChangesRetainTheUserFileStemAndRepairIncompatibleFrameRates() throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Presentation.v2.MP4"
        let settings = ScreenRecordingExportSettings(configuration: .init(frameRate: 60), panel: panel, duration: 1)
        settings.configuration.format = .gif
        #expect(settings.frameRates == [10, 15, 30] && settings.configuration.frameRate == 30)
        #expect(panel.allowedContentTypes == [.gif] && panel.nameFieldStringValue == "Presentation.v2.gif")
        settings.configuration.frameRate = 15
        panel.nameFieldStringValue = "Renamed final.gif"
        settings.configuration.format = .mp4
        #expect(settings.frameRates == [30, 60] && settings.configuration.frameRate == 30)
        #expect(panel.allowedContentTypes == [.mpeg4Movie] && panel.nameFieldStringValue == "Renamed final.mp4")
        panel.nameFieldStringValue = "Already chosen"
        settings.configuration.format = .gif
        #expect(panel.nameFieldStringValue == "Already chosen.gif")
        panel.nameFieldStringValue = "Notes.txt"
        settings.configuration.format = .mp4
        #expect(panel.nameFieldStringValue == "Notes.txt.mp4", "Unrelated dots are part of the user filename")
    }

    @Test func qualityChangesKeepTheUserFilenameUntouchedUntilTheFormatChanges() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Output.mp4"
        let settings = ScreenRecordingExportSettings(configuration: .init(), panel: panel, duration: 1)
        panel.nameFieldStringValue = "Renamed without extension"
        settings.configuration.resolution = .quadHD
        settings.configuration.frameRate = 60
        #expect(panel.nameFieldStringValue == "Renamed without extension")
        settings.configuration.format = .gif
        #expect(panel.nameFieldStringValue == "Renamed without extension.gif")
    }

    @Test(arguments: RecordingExportFormat.allCases, [-1, 0, 6, 120])
    func invalidInitialFrameRatesBecomeAnAvailableThirtyFPSOption(_ format: RecordingExportFormat, _ frameRate: Int) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Output." + format.rawValue
        let settings = ScreenRecordingExportSettings(configuration: .init(format: format, frameRate: frameRate), panel: panel, duration: 1)
        #expect(settings.configuration.frameRate == 30 && settings.frameRates.contains(settings.configuration.frameRate))
    }

    @Test(arguments: RecordingExportResolution.allCases,
          [(RecordingExportFormat.mp4, 30), (.mp4, 60), (.gif, 10), (.gif, 15), (.gif, 30)])
    func confirmingCommitsTheFinalDialogOptionsBeforeTheOutputTask(_ resolution: RecordingExportResolution,
                                                                _ selection: (RecordingExportFormat, Int)) async throws {
        let fixture = try Fixture(write: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        defer { fixture.close() }
        fixture.model.export()
        let panel = try #require(fixture.panels.presented.first?.panel)
        let settings = try settings(in: panel)
        let configuration = RecordingExportConfiguration(format: selection.0, resolution: resolution, frameRate: selection.1)
        settings.configuration = configuration
        let destination = fixture.root.appendingPathComponent("Final name." + selection.0.rawValue)
        panel.nameFieldStringValue = destination.lastPathComponent
        fixture.panels.presented[0].complete(destination)

        #expect(fixture.panels.presented.count == 1)
        #expect(fixture.model.exportConfiguration == configuration)
        #expect(!fixture.model.isChoosingFile && fixture.model.isBusy && fixture.model.operationTask != nil)
        #expect(fixture.notices.screenRecordingOperations.first?.detail == destination.lastPathComponent)
        #expect(fixture.notices.screenRecordingOperations.first?.kind == .info)
        #expect(panel.accessoryView == nil)
        await fixture.model.operationTask?.value
        #expect(fixture.model.canExport && fixture.notices.screenRecordingOperations.first?.kind == .error)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(arguments: [false, true], [false, true])
    func cancelledResponsesCannotCompleteALaterOutputPanel(_ firstCopy: Bool, _ nextCopy: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        if firstCopy { fixture.model.saveCopy() } else { fixture.model.export() }
        let first = try #require(fixture.panels.presented.first)
        first.complete(nil)
        if nextCopy { fixture.model.saveCopy() } else { fixture.model.export() }
        let next = try #require(fixture.panels.presented.last)
        first.complete(fixture.root.appendingPathComponent("Stale.mp4"))

        #expect(fixture.panels.presented.count == 2 && fixture.model.isChoosingFile)
        #expect(fixture.model.operationTask == nil && fixture.notices.screenRecordingOperations.isEmpty)
        #expect(next.panel.accessoryView != nil || nextCopy)
        next.complete(nil)
        #expect(fixture.model.canExport)
    }

    @Test func shutdownReleasesTheAccessoryAndSuppressesLateConfirmation() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.export()
        let presented = try #require(fixture.panels.presented.first)
        fixture.model.shutdown()
        #expect(presented.panel.accessoryView == nil)
        presented.complete(fixture.root.appendingPathComponent("Late.mp4"))
        #expect(!fixture.model.isChoosingFile && !fixture.model.isBusy)
        #expect(fixture.model.operationTask == nil && fixture.notices.screenRecordingOperations.isEmpty)
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func theAccessoryExposesAllThreeSettingsAndUpdatesTheirSelectedValues(_ language: AppLanguage) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.export()
        let presented = try #require(fixture.panels.presented.first)
        let host = try #require(presented.panel.accessoryView as? NSHostingView<ScreenRecordingExportSettingsView>)
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close(); presented.complete(nil) }
        await settle(host)

        for identifier in ["screenRecording.exportFormat", "screenRecording.exportResolution", "screenRecording.exportFrameRate"] {
            let control = try #require(element(identifier, in: host), "The destination accessory must expose \(identifier)")
            let frame = try #require((control.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue)
            #expect(frame.width > 0 && frame.height > 0)
        }
        host.rootView.settings.configuration = .init(format: .gif, resolution: .quadHD, frameRate: 15)
        await settle(host)
        let format = try #require(element("screenRecording.exportFormat", in: host))
        let resolution = try #require(element("screenRecording.exportResolution", in: host))
        let frameRate = try #require(element("screenRecording.exportFrameRate", in: host))
        #expect(format.value(forKey: "accessibilityValue") as? String == "GIF")
        #expect(resolution.value(forKey: "accessibilityValue") as? String == "1440p")
        #expect(frameRate.value(forKey: "accessibilityValue") as? String == "15 FPS")
        #expect(!window.isVisible, "The synthetic accessory fixture must never show a user window")
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func contentControlsDisableLongLivePhotoAndAudioModeHidesVideoQuality(_ language: AppLanguage) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Output.mp4"
        let settings = ScreenRecordingExportSettings(configuration: .init(), panel: panel, duration: 4)
        let host = NSHostingView(rootView: ScreenRecordingExportSettingsView(settings: settings))
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        await settle(host)
        let livePhoto = try #require(element("screenRecording.exportContent.livePhoto", in: host))
        #expect((livePhoto.value(forKey: "accessibilityEnabled") as? NSNumber)?.boolValue == false)
        #expect(element("screenRecording.livePhotoDurationLimit", in: host) != nil)
        let audio = try #require(element("screenRecording.exportContent.audioOnly", in: host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(audio.responds(to: press))
        pressControl(audio, selector: press)
        await settle(host)
        #expect(settings.content == .audioOnly && settings.configuration.format == .m4a)
        #expect(element("screenRecording.exportResolution", in: host) == nil)
        #expect(element("screenRecording.exportFrameRate", in: host) == nil)
        #expect(element("screenRecording.exportFormat", in: host) != nil)
        #expect(panel.prompt == AppLocalization.string("导出音频", language: language))
        #expect(panel.nameFieldStringValue == "Output.m4a" && !window.isVisible)
    }

    @Test func confirmingAudioOnlyUsesTheAudioOperationTitleAndKeepsTheStudioOpen() async throws {
        let fixture = try Fixture(write: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        defer { fixture.close() }
        fixture.model.export()
        let presented = try #require(fixture.panels.presented.first)
        let settings = try settings(in: presented.panel)
        settings.content = .audioOnly
        settings.configuration.format = .wav
        let destination = fixture.root.appendingPathComponent("Sound.wav")
        presented.complete(destination)
        let notice = try #require(fixture.notices.screenRecordingOperations.first)
        #expect(notice.title == AppLocalization.text("导出音频") && notice.symbolName == "waveform")
        #expect(notice.detail == "Sound.wav" && fixture.model.exportConfiguration.format == .wav)
        await fixture.model.operationTask?.value
        #expect(fixture.model.canEdit && fixture.model.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(arguments: AppLanguage.allCases)
    func exportSettingsKeysArePresentInEveryApplicationLanguage(_ language: AppLanguage) throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: package.appendingPathComponent("Resources/Localization/" + language.rawValue
            + ".lproj/Localizable.strings"))
        let table = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        #expect(AppLanguage.allCases.count == 17)
        for key in ["导出设置", "导出录屏", "导出音频", "导出内容", "仅音频", "视频", "Live Photo", "Live Photo 最长支持 3 秒，请缩短时间线", "格式", "分辨率", "帧率", "原始分辨率", "1080p", "1440p", "4K"] {
            let value = try #require(table[key], "\(language.rawValue) is missing export key \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
        }
    }

    @Test(arguments: [3.0, 3.0.nextUp, 6.0])
    func livePhotoAvailabilityUsesTheEditedDurationWithoutClipping(_ duration: Double) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Output.mp4"
        let settings = ScreenRecordingExportSettings(configuration: .init(), panel: panel, duration: duration)
        #expect(settings.canSelect(.livePhoto) == (duration <= 3))
        settings.content = .livePhoto
        #expect(settings.configuration.format == .livePhoto)
        #expect(settings.validationMessage == (duration <= 3 ? nil : AppLocalization.text("Live Photo 最长支持 3 秒，请缩短时间线")))
        #expect(settings.canConfirm == (duration <= 3), "The panel must reject a long Live Photo rather than truncating it")
        #expect(panel.nameFieldStringValue == "Output.livephoto")
        #expect(panel.allowedContentTypes.first?.conforms(to: .package) == true)
        let delegate = try #require(panel.delegate as? ScreenRecordingExportSettings)
        #expect(delegate === settings)
        if duration > 3 {
            #expect(throws: RecordingLivePhotoExportError.durationExceeded) {
                try delegate.panel(panel, validate: URL(fileURLWithPath: "/tmp/unused-output.livephoto"))
            }
        } else {
            try delegate.panel(panel, validate: URL(fileURLWithPath: "/tmp/unused-output.livephoto"))
        }
        settings.content = .video
        #expect(settings.validationMessage == nil && settings.canConfirm)
        #expect(settings.configuration.format == .mp4 && panel.nameFieldStringValue == "Output.mp4")
    }

    @Test func aLongSourceEditedBelowTheLimitCanExportLivePhoto() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.update { project in
            project.duration = 12
            project.edits.segments = [.init(start: 4, end: 8, speed: 2)]
        }
        fixture.model.export()
        let panel = try #require(fixture.panels.presented.first?.panel)
        let settings = try settings(in: panel)
        settings.content = .livePhoto
        #expect(settings.canSelect(.livePhoto) && settings.canConfirm)
        #expect(fixture.model.project?.duration == 12 && fixture.model.project?.outputDuration == 2)
        fixture.panels.presented[0].complete(nil)
    }

    @Test func audioOnlyModeRetainsTheDestinationAndExposesOnlyAudioFormats() throws {
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
        panel.nameFieldStringValue = "Presentation.v2.mp4"
        let settings = ScreenRecordingExportSettings(configuration: .init(resolution: .ultraHD, frameRate: 60), panel: panel, duration: 4)
        settings.content = .audioOnly
        #expect(settings.configuration.format == .m4a && settings.formats.allSatisfy(\.isAudioOnly))
        #expect(!settings.showsVideoSettings && settings.canConfirm)
        #expect(panel.nameFieldStringValue == "Presentation.v2.m4a" && panel.prompt == AppLocalization.text("导出音频"))
        settings.configuration.format = .wav
        #expect(panel.nameFieldStringValue == "Presentation.v2.wav")
        #expect(settings.configuration.resolution == .ultraHD && settings.configuration.frameRate == 60)
        settings.content = .video
        #expect(settings.showsVideoSettings && settings.formats.allSatisfy { !$0.isAudioOnly && $0 != .livePhoto })
        #expect(panel.nameFieldStringValue == "Presentation.v2.mp4")
        #expect(panel.directoryURL == URL(fileURLWithPath: "/tmp", isDirectory: true))
    }

    @Test func confirmingAnOverlongLivePhotoDoesNotSaveOrStartAnOutputTask() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.update { project in
            project.duration = 6
            project.edits.segments = [.init(start: 0, end: 6)]
        }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let original = try Data(contentsOf: manifest)
        let configuration = fixture.model.exportConfiguration
        fixture.model.export()
        let presented = try #require(fixture.panels.presented.first)
        let settings = try settings(in: presented.panel)
        settings.content = .livePhoto
        presented.complete(fixture.root.appendingPathComponent("Overlong.livephoto"))
        #expect(fixture.model.operationTask == nil && fixture.notices.screenRecordingOperations.isEmpty)
        #expect(fixture.model.exportConfiguration == configuration && fixture.model.isDirty)
        #expect(fixture.model.errorMessage == AppLocalization.text("Live Photo 最长支持 3 秒，请缩短时间线"))
        #expect(try Data(contentsOf: manifest) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Overlong.livephoto").path))
    }

    private func pressControl(_ control: NSObject, selector: Selector) {
        control.performSelector(onMainThread: selector, with: nil, waitUntilDone: true)
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func element(_ identifier: String, in object: NSObject) -> NSObject? {
        if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
           object.value(forKey: "accessibilityIdentifier") as? String == identifier { return object }
        guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
        for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] {
            if let result = element(identifier, in: child) { return result }
        }
        return nil
    }

    private func settings(in panel: NSSavePanel) throws -> ScreenRecordingExportSettings {
        try #require((panel.accessoryView as? NSHostingView<ScreenRecordingExportSettingsView>)?.rootView.settings)
    }

    @MainActor private final class Panels {
        struct Presented {
            let panel: NSSavePanel
            let complete: (URL?) -> Void
        }
        var presented: [Presented] = []
        func present(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
            presented.append(Presented(panel: panel, complete: completion))
        }
    }

    @MainActor private final class Fixture {
        let root: URL
        let directory: URL
        let store: ScreenRecordingProjectStore
        let model: ScreenRecordingStudioModel
        let panels = Panels()
        let notices = SideNoticeQueue()
        let defaults: UserDefaults
        let suite = "zisla-export-dialog-test-" + UUID().uuidString

        init(customDirectory: Bool = true,
             write: (@Sendable (ScreenRecordingProject, URL, URL?) throws -> Void)? = nil) throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            store = ScreenRecordingProjectStore(root: root)
            directory = try store.createDirectory()
            try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
            let project = ScreenRecordingProject(name: "Output", videoFile: "screen.mp4", duration: 1, width: 16, height: 16)
            try store.save(project, in: directory)
            let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let preview = try #require(context.makeImage())
            let directoryStore = ScreenRecordingOutputDirectoryStore(defaults: defaults)
            if customDirectory { try directoryStore.setDirectory(root) }
            model = ScreenRecordingStudioModel(outputDirectoryStore: directoryStore,
                renderPreview: { _, _, _ in preview }, presentExportPanel: panels.present,
                notices: notices, writeProjectFiles: write ?? { project, directory, _ in
                    try ScreenRecordingProjectStore(root: directory).save(project, in: directory)
                })
            model.install(project, directory: directory)
        }

        func close() {
            model.shutdown()
            notices.removeAll()
            panels.presented.removeAll()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
