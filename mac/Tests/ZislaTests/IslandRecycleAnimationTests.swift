import Foundation
import SwiftUI
import Testing
@testable import Zisla

/// The island used to blink out of existence: the reveal mask animated back into the pill while the
/// surface's opacity snapped to zero in the same frame, so nobody ever saw the fold. These tests pin
/// the two halves of the recycle to the same clock and keep the fold's geometry anchored to the notch.
struct IslandRecycleAnimationTests {
    @Test
    func theFoldAndTheDissolveShareOneClock() {
        // Equal durations are the whole point: a dissolve that outruns the fold reads as a blink,
        // one that lags leaves a ghost pill sitting on the notch.
        #expect(ZislaMotion.islandRecycle == .smooth(duration: 0.22))
        #expect(ZislaMotion.islandRecycleFade == .easeIn(duration: 0.22))
        #expect(ZislaMotion.islandReveal == .snappy(duration: 0.28, extraBounce: 0.05))
    }

    @Test
    func theRevealMaskFoldsBackWithTheRecycleToken() throws {
        let source = try Self.source(of: "IslandSurface.swift")
        let maskStart = try #require(source.range(of: ".mask {"))
        let maskEnd = try #require(source[maskStart.upperBound...].range(of: "// MARK: - Island surface"))
        let mask = source[maskStart.lowerBound..<maskEnd.lowerBound]

        #expect(mask.contains("? ZislaMotion.islandRecycle"))
        #expect(mask.contains(": ZislaMotion.islandReveal"))
        #expect(mask.contains("collapsedCenterOffsetX: collapsedCenterOffsetX"))
    }

    @Test
    func onlyTheRecycleIsAnimatedSoRevealsStillSnapIn() throws {
        let source = try Self.source(of: "IslandRootView.swift")

        #expect(source.contains("reduceMotion || !hidesIslandSurface ? nil : ZislaMotion.islandRecycleFade"))
        #expect(source.contains("value: hidesIslandSurface"))
        // The fade must stay on the surface itself; hoisting it above the frames would animate the
        // panel geometry instead of the dissolve.
        #expect(source.contains(".opacity(hidesIslandSurface ? 0 : 1)"))
    }

    /// The pet slot widens the panel on one side, so the surface hugs that edge. Releasing the slot
    /// on collapse snapped the surface back to the panel center on the fold's first frame — the
    /// island jumped sideways before it ever reached the notch.
    @Test
    func collapsingKeepsThePetSlotReservedAndTheFoldAimedAtTheNotch() throws {
        let source = try Self.source(of: "IslandRootView.swift")
        let slotStart = try #require(source.range(of: "let reservesPetSlot ="))
        let slotEnd = try #require(source[slotStart.upperBound...].range(of: "let voiceRecordingGeometry"))
        let slot = source[slotStart.lowerBound..<slotEnd.lowerBound]

        #expect(!slot.contains("isIslandCollapsed"))
        #expect(slot.contains("let collapsedCenterOffsetX = petSlotWidth / 2"))
        #expect(source.contains("collapsedCenterOffsetX: collapsedCenterOffsetX"))
        // The overlay itself still leaves with the island; only its reserved width stays behind.
        #expect(source.contains("if petSlotWidth == ExpandedPetLayout.sideSlotWidth, !isIslandCollapsed {"))

        let alignmentStart = try #require(source.range(of: "private var islandSurfaceAlignment: Alignment {"))
        let alignmentEnd = try #require(source[alignmentStart.upperBound...].range(of: "\n    }"))
        #expect(!source[alignmentStart.lowerBound..<alignmentEnd.lowerBound].contains("isIslandCollapsed"))
    }

    private static func source(of fileName: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla")
            .appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
