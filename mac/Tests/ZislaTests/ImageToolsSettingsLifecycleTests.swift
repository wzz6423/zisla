import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ImageToolsSettingsLifecycleTests {
    @Test
    func searchAndSidebarNavigationPreserveEditsResultsAndTheSelectedOperation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.obscure))
        input.imageTools.inputs = [fixture.source]
        await fixture.layout()
        await input.imageTools.recordEdit(fixture.image, for: fixture.source)?.value
        let edit = try #require(input.imageTools.editedImageURLs[fixture.source])
        await input.imageTools.start(service: fixture.service, options: .init(), rasterTransform: { image, _ in image })?.value
        let batch = try #require(input.imageTools.batch)
        let output = try #require(batch.items.first?.outputs.first?.url)
        let bytes = try Data(contentsOf: output)

        await fixture.search("PNG")
        await fixture.layout()
        #expect(!fixture.hasButton(ImageToolOperation.obscure.title))
        try await fixture.selectImageSidebar()
        #expect(fixture.hasButton(ImageToolOperation.obscure.title))
        #expect(input.selectedImageOperation == .obscure)
        #expect(input.imageTools.inputs == [fixture.source])
        #expect(input.imageTools.editedImageURLs[fixture.source] == edit)
        #expect(FileManager.default.fileExists(atPath: edit.path))
        #expect(input.imageTools.batch?.directoryURL == batch.directoryURL)
        #expect(try Data(contentsOf: output) == bytes)

        input.select(.general)
        await fixture.layout()
        input.navigate(backward: true, settings: .default)
        await fixture.layout()
        #expect(input.selectedImageOperation == .obscure)
        #expect(input.imageTools.editedImageURLs[fixture.source] == edit)
        #expect(try Data(contentsOf: output) == bytes)
        #expect(try Data(contentsOf: fixture.source) == fixture.original)
    }

    @Test
    func searchingAndSelectingAnotherImageDestinationDoesNotCancelAnActiveEncoder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.obscure))
        input.imageTools.inputs = [fixture.source]
        await fixture.layout()
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let startedTask = input.imageTools.start(service: fixture.service, options: .init(), rasterTransform: { image, _ in
            started.continuation.yield()
            for await _ in resume.stream { break }
            return image
        })
        let pending = try #require(startedTask)
        for await _ in started.stream { break }

        await fixture.search("JPEG")
        #expect(input.imageTools.isProcessing)
        input.select(.imageTools, searchTarget: .imageOperation(.convert))
        await fixture.layout()
        #expect(input.imageTools.isProcessing && input.selectedImageOperation == .obscure)
        #expect(input.searchTarget == .imageOperation(.obscure))
        #expect(input.imageTools.inputs == [fixture.source])
        resume.continuation.yield()
        await pending.value
        #expect(!input.imageTools.isProcessing)
        let batch = try #require(input.imageTools.batch)
        #expect(batch.failures.isEmpty && batch.items.count == 1)
        input.select(.general)
        input.navigate(backward: true, settings: .default)
        #expect(input.selectedImageOperation == .obscure)
        #expect(input.imageTools.batch?.directoryURL == batch.directoryURL)
        #expect(try Data(contentsOf: fixture.source) == fixture.original)
    }

    @Test
    func recognitionWorkAndFailuresSurviveSearchAndCanBeReopened() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.recognize))
        input.imageTools.inputs = [fixture.source]
        await fixture.layout()
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let image = fixture.image
        let startedTask = input.imageRecognition.start(urls: [fixture.source], service: fixture.service,
            loadImage: { _ in image }, recognizeImage: { _, _ in
                started.continuation.yield()
                for await _ in resume.stream { break }
                return [ScreenshotRecognizedFragment(text: "Retained text", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))]
            })
        let pending = try #require(startedTask)
        for await _ in started.stream { break }
        await fixture.search("OCR")
        #expect(input.imageRecognition.isProcessing)
        input.select(.imageTools, searchTarget: .imageOperation(.convert))
        #expect(input.selectedImageOperation == .recognize)
        #expect(input.searchTarget == .imageOperation(.recognize))
        try await fixture.selectImageSidebar()
        #expect(input.imageRecognition.isProcessing && input.selectedImageOperation == .recognize)
        resume.continuation.yield()
        await pending.value
        #expect(input.imageRecognition.results.first?.text == "Retained text")
        input.select(.general)
        await fixture.layout()
        input.select(.imageTools)
        await fixture.layout()
        #expect(input.imageRecognition.results.first?.text == "Retained text")

        await input.imageRecognition.start(urls: [fixture.source], service: fixture.service,
            loadImage: { _ in throw ImageProcessingError.invalidOutput })?.value
        let failures = input.imageRecognition.failures
        let message = input.imageRecognition.message
        #expect(failures.count == 1)
        input.settingsQuery = "PNG"
        await fixture.layout()
        input.select(.imageTools)
        await fixture.layout()
        #expect(input.imageRecognition.failures == failures && input.imageRecognition.message == message)
        #expect(try Data(contentsOf: fixture.source) == fixture.original)
    }

    @Test(arguments: [false, true])
    func explicitOperationChangesStillDiscardResultsAndEdits(fromSearch: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.obscure))
        input.imageTools.inputs = [fixture.source]
        await fixture.layout()
        await input.imageTools.recordEdit(fixture.image, for: fixture.source)?.value
        let editDirectory = try #require(input.imageTools.editedImageURLs[fixture.source]?.deletingLastPathComponent())
        await input.imageTools.start(service: fixture.service, options: .init(), rasterTransform: { image, _ in image })?.value
        let directory = try #require(input.imageTools.batch?.directoryURL)
        await fixture.layout()
        try await fixture.press(.obscure)
        #expect(input.imageTools.batch?.directoryURL == directory)
        if fromSearch {
            input.select(.imageTools, searchTarget: .imageOperation(.convert))
            await fixture.layout()
        } else { try await fixture.press(.convert) }
        #expect(input.selectedImageOperation == .convert && input.imageTools.inputs == [fixture.source])
        #expect(input.imageTools.batch == nil && input.imageTools.editedImageURLs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!FileManager.default.fileExists(atPath: editDirectory.path))
        #expect(try Data(contentsOf: fixture.source) == fixture.original)
    }

    @Test
    func pendingOptionsSurviveSearchSidebarAndHistoryWithTheirControls() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.resize))
        input.imageOptions.formats = [.jpeg, .webp]
        input.imageOptions.quality = 37
        input.imageOptions.resizeMethod = .fit
        input.imageOptions.preserveMetadata = true
        input.imageOptions.background = "#112233"
        input.imageOptions.transform = .init(rotation: .clockwise90, flipHorizontal: true, flipVertical: true)
        input.imageOptions.watermark = .init(content: .text("Retained watermark"))
        input.imageOptions.extractionMode = .lasso
        await fixture.layout()
        try await fixture.editTextField("宽度（像素）", value: "640")
        try await fixture.editTextField("高度（像素）", value: "360")
        #expect(input.imageOptions.width == "640" && input.imageOptions.height == "360")
        let expected = input.imageOptions
        #expect(fixture.hasTextFieldValue("640") && fixture.hasTextFieldValue("360"))

        await fixture.search("PNG")
        #expect(!fixture.hasTextFieldValue("640"))
        try await fixture.selectImageSidebar()
        #expect(input.imageOptions == expected)
        #expect(fixture.hasTextFieldValue("640") && fixture.hasTextFieldValue("360"))
        input.select(.general)
        await fixture.layout()
        input.navigate(backward: true, settings: .default)
        await fixture.layout()
        #expect(input.imageOptions == expected)
        #expect(fixture.hasTextFieldValue("640") && fixture.hasTextFieldValue("360"))
        try await fixture.press(.watermark)
        #expect(fixture.hasTextFieldValue("Retained watermark"))
        #expect(input.imageOptions == expected)
    }

    @Test
    func manualOperationChangesUpdateTheRecordedSearchDestination() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        let input = try #require(fixture.input)
        input.select(.imageTools, searchTarget: .imageOperation(.obscure))
        await fixture.layout()
        try await fixture.press(.convert)
        #expect(input.searchTarget == .imageOperation(.convert))
        input.select(.general)
        await fixture.layout()
        input.navigate(backward: true, settings: .default)
        await fixture.layout()
        #expect(input.selectedImageOperation == .convert)
        #expect(input.searchTarget == .imageOperation(.convert))
        #expect(fixture.hasButton(ImageToolOperation.convert.title))
    }

    @Test
    func releasingTheSettingsOwnerCleansRetainedResultsAndEdits() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await fixture.layout()
        var input: SettingsInput? = fixture.input
        try #require(input != nil)
        input?.select(.imageTools, searchTarget: .imageOperation(.obscure))
        input?.imageTools.inputs = [fixture.source]
        await fixture.layout()
        await input?.imageTools.recordEdit(fixture.image, for: fixture.source)?.value
        let editDirectory = try #require(input?.imageTools.editedImageURLs[fixture.source]?.deletingLastPathComponent())
        await input?.imageTools.start(service: fixture.service, options: .init(), rasterTransform: { image, _ in image })?.value
        let directory = try #require(input?.imageTools.batch?.directoryURL)
        weak let store = input?.imageTools
        weak let recognition = input?.imageRecognition
        input = nil
        fixture.close()
        await fixture.layout()
        #expect(fixture.input == nil && store == nil && recognition == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!FileManager.default.fileExists(atPath: editDirectory.path))
        #expect(try Data(contentsOf: fixture.source) == fixture.original)
    }

    @Test
    func settingsViewBindsTheRetainedOwnerInsteadOfUsingOperationIdentity() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: package.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        #expect(source.contains("@StateObject private var input = SettingsInput()"))
        #expect(source.contains("store: input.imageTools"))
        #expect(source.contains("recognition: input.imageRecognition"))
        #expect(source.contains("set: { input.selectImageOperation($0) }"))
        #expect(source.contains("pending: $input.imageOptions"))
        #expect(!source.contains(".id(input.selectedImageOperation)"))
    }

    private struct Host: View {
        @StateObject private var input = SettingsInput()
        let tools: ManagedToolService
        let saveLocations: SaveLocationStore
        let settingsStore: FeatureSettingsStore
        let mounted: @MainActor (SettingsInput) -> Void

        var body: some View {
            VStack {
                Button("Image sidebar") { input.select(.imageTools) }.accessibilityIdentifier("image-settings-sidebar")
                SettingsSearchScrollView(target: input.searchTarget, resetID: input.isSearching ? input.settingsQuery : "") {
                    if input.isSearching { Text("Search") }
                    else if input.selection == .imageTools {
                        ImageToolsModuleView(tools: tools, saveLocations: saveLocations, settingsStore: settingsStore,
                                             store: input.imageTools, recognition: input.imageRecognition,
                                             operation: Binding(get: { input.selectedImageOperation }, set: { input.selectImageOperation($0) }),
                                             pending: $input.imageOptions)
                            .id(input.selection)
                    } else { Text("Settings") }
                }
            }
            .onAppear { mounted(input) }
        }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let source: URL
        let image: CGImage
        let original: Data
        let service = ImageProcessingService(executableURL: nil)
        let window: NSPanel
        weak var input: SettingsInput?
        private var host: NSHostingView<Host>?
        private let defaults: UserDefaults
        private let suite: String
        private let releaseAccessibility: @MainActor () -> Void

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-settings-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            source = root.appendingPathComponent("source.png")
            let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            image = try #require(context.makeImage())
            let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            try #require(CGImageDestinationFinalize(destination))
            original = try Data(contentsOf: source)
            suite = "zisla-image-settings-\(UUID())"
            defaults = try #require(UserDefaults(suiteName: suite))
            for location in SaveLocation.allCases {
                if location != .download { defaults.set(root.path, forKey: "save-location-\(location.rawValue)-path") }
            }
            let tools = ManagedToolService(toolsDirectory: root.appendingPathComponent("tools"),
                applicationsDirectory: root.appendingPathComponent("applications"), bundleURL: root, defaults: defaults,
                releaseLoader: { _ in Data() }, executableResolver: { _ in nil }, homebrewRunner: { _, _ in "" })
            let saveLocations = SaveLocationStore(defaults: defaults)
            let settingsStore = FeatureSettingsStore(defaults: defaults)
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSPanel(contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 700),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: Host(tools: tools, saveLocations: saveLocations, settingsStore: settingsStore,
                mounted: { [weak self] input in self?.input = input }))
            host.sizingOptions = []
            self.host = host
            window.contentView = host
        }

        func layout() async {
            for _ in 0..<12 {
                host?.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func hasButton(_ title: String) -> Bool { button(title) != nil }

        func hasTextFieldValue(_ value: String) -> Bool {
            accessibilityObjects().contains { object in
                object.responds(to: NSSelectorFromString("accessibilityRole"))
                    && object.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.textField.rawValue
                    && object.responds(to: NSSelectorFromString("accessibilityValue"))
                    && object.value(forKey: "accessibilityValue") as? String == value
            }
        }

        func editTextField(_ placeholder: String, value: String) async throws {
            func fields(_ view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? [] + view.subviews.flatMap(fields)
            }
            let host = try #require(host)
            let field = try #require(fields(host).first { $0.placeholderString == AppLocalization.text(placeholder) })
            field.stringValue = value
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            await layout()
        }

        func search(_ query: String) async {
            input?.settingsQuery = query
            await layout()
            #expect(input?.settingsQuery == query)
        }

        func selectImageSidebar() async throws {
            let button = try #require(accessibilityObjects().first { object in
                object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && object.value(forKey: "accessibilityIdentifier") as? String == "image-settings-sidebar"
            })
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: selector))
            _ = button.perform(selector)
            await layout()
        }

        func press(_ operation: ImageToolOperation) async throws {
            let control = try #require(button(operation.title))
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(control.responds(to: selector))
            _ = control.perform(selector)
            await layout()
        }

        private func button(_ title: String) -> NSObject? {
            return accessibilityObjects().first { object in
                object.responds(to: NSSelectorFromString("accessibilityPerformPress"))
                    && object.responds(to: NSSelectorFromString("accessibilityLabel"))
                    && object.value(forKey: "accessibilityLabel") as? String == AppLocalization.text(title)
            }
        }

        private func accessibilityObjects() -> [NSObject] {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            guard let host else { return [] }
            return descendants(host)
        }

        func close() {
            window.contentView = nil
            host = nil
            window.close()
        }

        func remove() {
            close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            releaseAccessibility()
        }
    }
}
