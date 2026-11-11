import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized) @MainActor
struct SystemMonitorPageLayoutTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [CGFloat(560), 752])
    func monitorCardsStayCenteredWhenTheScrollBarAppears(
        language: AppLanguage, width: CGFloat
    ) async throws {
        _ = NSApplication.shared
        let service = SystemMonitorService(
            volumeURL: URL(fileURLWithPath: "/synthetic-monitor-layout"),
            dateProvider: { Date(timeIntervalSince1970: 0) },
            publicIPProvider: PagePublicIPProvider(),
            privateIPv4AddressProvider: { nil },
            hardwareInfoProvider: { .unavailable },
            historyPersistence: PageHistoryPersistence()
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 401),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: SystemMonitorView(service: service, onCleanupRequested: {}, onTransientMessage: { _ in })
            .background(.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: width, height: 401)
        for height: CGFloat in [401, 800, 220, 401] {
            window.setContentSize(CGSize(width: width, height: height))
            host.frame = CGRect(x: 0, y: 0, width: width, height: height)
            for _ in 0..<20 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / width
            let y = Int(20 * scale)
            var columns: [Int] = []
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.03 && color.redComponent < 0.3 { columns.append(x) }
            }
            let first = try #require(columns.first)
            let last = try #require(columns.last)
            let center = CGFloat(first + last + 1) / (2 * scale)
            #expect(abs(center - width / 2) <= 1,
                    "Monitor cards must stay centered at \(width)×\(height) in \(language.rawValue)")
            #expect(abs(CGFloat(first) / scale - 12) <= 1,
                    "The leading card edge must keep its original inset")
            #expect(abs(width - CGFloat(last + 1) / scale - 12) <= 1,
                    "The trailing card edge must match the leading inset")
        }
        #expect(!window.isVisible)
    }
}

private struct PagePublicIPProvider: PublicIPProviding {
    func publicIPAddress() async -> PublicIPLookupResult { .absent }
    func publicIPv6Address() async -> PublicIPLookupResult { .absent }
}

private struct PageHistoryPersistence: SystemMetricsHistoryPersisting {
    func loadRecords() -> [SystemMetricsRecord] { [] }
    func appendRecord(_ record: SystemMetricsRecord, capacity: Int?) {}
    func removeAll() {}
}
