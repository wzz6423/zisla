import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct MailMarkAllReadButtonTests {
    @Test(arguments: AppLanguage.allCases)
    func bulkReadButtonUsesTheRequestedLanguageAndAllowsUnloadedUnreadMessages(language: AppLanguage) async throws {
        let mail = makeService { _, _ in .success(.snapshot(snapshot(isRead: true))) }
        await mail.refresh(checkForNewMail: false)
        var presses = 0
        let fixture = Fixture(mail: mail, accountName: "work", language: language) { accountName in
            #expect(accountName == "work")
            presses += 1
        }
        defer { fixture.close() }
        await fixture.layout()
        let button = try fixture.button()
        #expect(button.value(forKey: "accessibilityLabel") as? String == AppLocalization.string("全部标记为已读", language: language))
        #expect(try fixture.isEnabled(), "The first loaded page being read must not prevent marking older inbox messages")
        #expect(try fixture.press())
        await fixture.layout()
        #expect(presses == 1)
        #expect(!fixture.window.isVisible)
    }

    @Test
    func repeatedPressesBeforeTheTaskStartsSubmitOnlyOneBulkAction() async throws {
        let mail = makeService { _, _ in .success(.snapshot(snapshot())) }
        await mail.refresh(checkForNewMail: false)
        let gate = MailMarkAllReadButtonTestGate()
        let submitted = AsyncStream<Void>.makeStream()
        defer { submitted.continuation.finish() }
        var presses = 0
        let fixture = Fixture(mail: mail, accountName: "work", language: .english) { _ in
            presses += 1
            submitted.continuation.yield()
            await gate.wait()
        }
        defer { gate.open(); fixture.close() }
        await fixture.layout()

        _ = try fixture.press()
        _ = try fixture.press()
        for await _ in submitted.stream { break }
        #expect(presses == 1, "Two events in the same run-loop turn must not start duplicate bulk writes")
        await fixture.layout()
        #expect(try !fixture.isEnabled())
        gate.open()
        await fixture.layout()
        #expect(try fixture.isEnabled())
    }

    @Test(arguments: ["loading", "mutating", "missing", "empty"])
    func unavailableScopeAndBusyMailDisableTheBulkReadButton(state: String) async throws {
        let gate = MailMarkAllReadButtonTestGate()
        let started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        var shouldWait = false
        let mail = makeService { _, expectsSnapshot in
            if shouldWait {
                started.continuation.yield()
                await gate.wait()
            }
            return expectsSnapshot ? .success(.snapshot(snapshot())) : .success(.succeeded)
        }
        if state != "empty" { await mail.refresh(checkForNewMail: false) }
        let fixture = Fixture(mail: mail, accountName: state == "missing" ? "missing" : "work", language: .english) { _ in }
        defer {
            shouldWait = false
            gate.open()
            fixture.close()
            mail.stop()
        }
        await fixture.layout()
        let enabledInk = state == "loading" ? try fixture.renderedInk() : nil
        var pending: Task<Void, Never>?
        if state == "loading" || state == "mutating" {
            shouldWait = true
            pending = Task {
                if state == "loading" { await mail.refresh(checkForNewMail: false) }
                else { _ = await mail.markAllRead(accountName: "work") }
            }
            for await _ in started.stream { break }
        }
        await fixture.layout()
        #expect(try !fixture.isEnabled())
        if let enabledInk {
            #expect(try fixture.renderedInk() < enabledInk * 0.6, "The disabled toolbar action must visibly dim")
        }
        shouldWait = false
        gate.open()
        await pending?.value
        await fixture.layout()
        #expect(try fixture.isEnabled() == (state == "loading" || state == "mutating"))
    }

    private func makeService(
        _ runner: @escaping (String, Bool) async -> Result<MailScriptOutput, MailScriptError>
    ) -> MailService {
        MailService(
            commandRunner: runner,
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
    }

    private func snapshot(isRead: Bool = false) -> MailSnapshot {
        MailSnapshot(
            accounts: [MailScriptAccount(name: "work", emailAddresses: ["work@example.com"])],
            messages: [MailScriptRow(
                accountName: "work", messageID: "1", sender: "sender@example.com",
                subject: "Fixture", body: "Body", receivedAt: .distantPast, isRead: isRead
            )],
            hasMore: true
        )
    }

    @MainActor
    private final class Fixture {
        let window: NSPanel
        let host: NSView
        let releaseAccessibility: @MainActor () -> Void

        init(mail: MailService, accountName: String?, language: AppLanguage, action: @escaping @MainActor (String?) async -> Void) {
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSPanel(
                contentRect: CGRect(x: -100_000, y: -100_000, width: 32, height: 32),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView:
                MailMarkAllReadButton(mail: mail, accountName: accountName, action: action)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
                    .preferredColorScheme(.dark)
                    .frame(width: 32, height: 32)
                    .background(Color.black)
            )
            hosting.sizingOptions = []
            host = hosting
            window.contentView = host
        }

        func close() {
            window.contentView = nil
            window.close()
            releaseAccessibility()
        }

        func layout() async {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func button() throws -> NSObject {
            func objects(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(objects)
            }
            return try #require(objects(host).first {
                $0.responds(to: NSSelectorFromString("accessibilityRole"))
                    && $0.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
            })
        }

        func isEnabled() throws -> Bool {
            try #require(button().value(forKey: "isAccessibilityEnabled") as? Bool)
        }

        func renderedInk() throws -> Double {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var total = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    total += (color.redComponent + color.greenComponent + color.blueComponent) * color.alphaComponent
                }
            }
            return total
        }

        func press() throws -> Bool {
            let button = try button()
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: selector))
            let action = unsafeBitCast(button.method(for: selector), to: (@convention(c) (NSObject, Selector) -> ObjCBool).self)
            return action(button, selector).boolValue
        }
    }
}

@MainActor
private final class MailMarkAllReadButtonTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
