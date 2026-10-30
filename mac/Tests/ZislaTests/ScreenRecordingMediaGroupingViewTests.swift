import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMediaGroupingViewTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func groupingControlsChangeOnlyTheLibraryPresentation(_ language: AppLanguage) throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let assets = [
            RecordingMediaAsset(name: "Audio", file: "sound.wav", kind: .audio, duration: 2,
                importedAt: now, capturedAt: now),
            RecordingMediaAsset(name: "Image", file: "image.png", kind: .image, duration: 2, width: 64, height: 48,
                importedAt: now.addingTimeInterval(-7_200)),
            RecordingMediaAsset(name: "Video", file: "video.mp4", kind: .video, duration: 2, width: 64, height: 48,
                importedAt: now.addingTimeInterval(-40 * 86_400), capturedAt: now.addingTimeInterval(-400 * 86_400)),
        ]
        var project = fixture.project()
        project.videoFile = ""
        project.edits.segments = []
        project.timeline = .init(assets: assets, tracks: [.init(id: "track")])
        model.install(project, directory: fixture.directory)
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let view = NSHostingView(rootView: ScreenRecordingMediaLibraryView(model: model)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        view.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 260, height: 900),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        settle(view)
        let picker = try #require(element("screenRecording.mediaGrouping", in: view))
        #expect(value(picker, "accessibilityValue") as? String == AppLocalization.text("不分组"))
        #expect(element("screenRecording.mediaTimeGranularity", in: view) == nil)
        #expect(groupTitles(in: view).isEmpty)
        for asset in assets { #expect(element("screenRecording.mediaAsset." + asset.id.uuidString, in: view) != nil) }
        try choose(AppLocalization.text("按类型"), id: "screenRecording.mediaGrouping", in: view,
            options: RecordingMediaGrouping.allCases.map { AppLocalization.text($0.title) })
        #expect(groupTitles(in: view) == ["视频", "图片", "音频"].map { AppLocalization.text($0) })
        #expect(element("screenRecording.mediaTimeGranularity", in: view) == nil)
        for grouping in [RecordingMediaGrouping.importedAt, .capturedAt] {
            try choose(AppLocalization.text(grouping.title), id: "screenRecording.mediaGrouping", in: view,
                options: RecordingMediaGrouping.allCases.map { AppLocalization.text($0.title) })
            for unit in RecordingMediaTimeGranularity.allCases {
                try choose(AppLocalization.text(unit.title), id: "screenRecording.mediaTimeGranularity", in: view,
                    options: RecordingMediaTimeGranularity.allCases.map { AppLocalization.text($0.title) })
                let expected = RecordingMediaLibraryGrouping.groups(assets: assets, grouping: grouping, granularity: unit)
                let expectedTitles = expected.map { group in
                    if let date = group.date { return dateTitle(date, unit: unit, locale: language.locale) }
                    return AppLocalization.text(group.title!)
                }
                #expect(groupTitles(in: view) == expectedTitles)
                if grouping == .capturedAt {
                    #expect(groupTitles(in: view).last == AppLocalization.text("未知拍摄时间"))
                }
                for asset in assets { #expect(element("screenRecording.mediaAsset." + asset.id.uuidString, in: view) != nil) }
                #expect(model.project == project && !model.isDirty && !model.canUndo)
            }
        }
        try choose(AppLocalization.text("不分组"), id: "screenRecording.mediaGrouping", in: view,
            options: RecordingMediaGrouping.allCases.map { AppLocalization.text($0.title) })
        #expect(groupTitles(in: view).isEmpty && element("screenRecording.mediaTimeGranularity", in: view) == nil)
        #expect(model.mediaAssets == assets && model.project == project && !model.isDirty && !model.canUndo)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isKeyWindow)
    }

    @Test
    func missingMenuStopsWaitingAndItsObserverIsRemoved() {
        let selection = MenuSelection(title: "Missing menu fixture")
        NotificationCenter.default.addObserver(selection, selector: #selector(MenuSelection.began(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(selection) }
        let clock = ContinuousClock()
        let started = clock.now
        let selected = selection.waitForSelection {}
        #expect(!selected && started.duration(to: clock.now) >= .seconds(3))
        NotificationCenter.default.removeObserver(selection)
        let menu = NSMenu()
        menu.addItem(withTitle: selection.title, action: nil, keyEquivalent: "")
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        #expect(selection.titles.isEmpty, "A removed observer must not react to later menus")
    }

    private func choose(_ title: String, id: String, in view: NSView, options: [String]) throws {
        let picker = try #require(element(id, in: view))
        let selection = MenuSelection(title: title)
        NotificationCenter.default.addObserver(selection, selector: #selector(MenuSelection.began(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(selection) }
        let action = NSSelectorFromString("accessibilityPerformPress")
        try #require(picker.responds(to: action))
        let selected = selection.waitForSelection { press(picker) }
        settle(view)
        #expect(selection.titles == options)
        try #require(selected, "The native picker must select the requested localized option before its deadline")
        #expect(value(try #require(element(id, in: view)), "accessibilityValue") as? String == title)
    }

    private func press(_ picker: NSObject) {
        picker.performSelector(onMainThread: NSSelectorFromString("accessibilityPerformPress"), with: nil, waitUntilDone: true)
    }

    private func dateTitle(_ date: Date, unit: RecordingMediaTimeGranularity, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let templates: [RecordingMediaTimeGranularity: String] = [.hour: "yMMMdj", .day: "yMMMd", .month: "yMMMM", .year: "y"]
        formatter.setLocalizedDateFormatFromTemplate(templates[unit]!)
        return formatter.string(from: date)
    }

    private func element(_ id: String, in view: NSView) -> NSObject? {
        objects(view).first { value($0, "accessibilityIdentifier") as? String == id }
            ?? view.subviews.lazy.compactMap { element(id, in: $0) }.first
    }

    private func groupTitles(in view: NSView) -> [String] {
        objects(view).compactMap { object in
            guard let id = value(object, "accessibilityIdentifier") as? String,
                  id.hasPrefix("screenRecording.mediaGroup.") else { return nil }
            return value(object, "accessibilityValue") as? String ?? value(object, "accessibilityLabel") as? String
        }
    }

    private func objects(_ root: NSObject) -> [NSObject] {
        [root] + (value(root, "accessibilityChildren") as? [NSObject] ?? []).flatMap(objects)
    }

    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    private func settle(_ view: NSView) {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.001))
        }
    }
}

@MainActor private final class MenuSelection: NSObject {
    let title: String
    var titles: [String] = []
    private var selected = false

    init(title: String) { self.title = title }

    func waitForSelection(perform action: () -> Void) -> Bool {
        action()
        let deadline = Date().addingTimeInterval(3)
        while !selected && Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
        return selected
    }

    @objc func began(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              let index = menu.items.firstIndex(where: { $0.title == title }) else { return }
        titles = menu.items.map(\.title)
        RunLoop.main.perform(inModes: [.eventTracking]) {
            menu.cancelTrackingWithoutAnimation()
            menu.performActionForItem(at: index)
            self.selected = true
        }
    }
}
