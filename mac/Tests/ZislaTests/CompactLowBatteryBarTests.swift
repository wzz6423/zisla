import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct CompactLowBatteryBarTests {
    @Test(arguments: [CGFloat(0), 80, 180], [false, true])
    func batteryIdentityAndPercentageStayOutsideTheNotch(centerInset: CGFloat, accessory: Bool) throws {
        let notice = IslandNotice(
            id: accessory ? "battery-low:bluetooth:keyboard" : "battery-low",
            title: "电池电量低",
            detail: "20%",
            batteryLevels: accessory ? [NoticeBatteryLevel(
                label: String(repeating: "Magic Keyboard 键盘 ", count: 8), level: 20
            )] : nil
        )
        let width = centerInset + (accessory ? 300 : 160)
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: CompactLowBatteryBar(
            notice: notice, height: 34, centerInset: centerInset
        )
            .frame(width: width, height: 34)
            .background(.black)
            .clipped()
            .environment(\.locale, Locale(identifier: "ar"))
            .environment(\.layoutDirection, .rightToLeft))
        renderer.scale = scale
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let leftEdge = (width - centerInset) / 2 * scale
        let rightEdge = (width + centerInset) / 2 * scale
        var notchPixels = 0
        var iconPixels = 0
        var leftTextBounds: CGRect?
        var rightTextPixels = 0

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                let isText = min(color.redComponent, color.greenComponent, color.blueComponent) > 0.8
                let isIcon = color.redComponent > 0.7 && color.greenComponent < 0.5 && color.blueComponent < 0.5
                if CGFloat(x) >= leftEdge, CGFloat(x) < rightEdge, isText || isIcon {
                    notchPixels += 1
                }
                if CGFloat(x) < leftEdge {
                    if isIcon { iconPixels += 1 }
                    if isText {
                        let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                        leftTextBounds = leftTextBounds.map { $0.union(pixel) } ?? pixel
                    }
                }
                if CGFloat(x) >= rightEdge, isText { rightTextPixels += 1 }
            }
        }

        #expect(notchPixels == 0, "Battery content must not overlap the physical notch")
        #expect(iconPixels > 0)
        #expect(rightTextPixels > 0)
        if accessory {
            let label = try #require(leftTextBounds, "The warning must identify the Bluetooth device")
            #expect(label.height <= 16 * scale, "Long device names must remain on one line")
        } else {
            #expect(leftTextBounds == nil)
        }
    }
}
