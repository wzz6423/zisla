import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct VoiceRecordingIslandLayoutTests {
    @Test
    func modulePagesShareTheCompactWidthWithAndWithoutThePet() {
        for module in IslandModule.allCases {
            let layout = IslandModuleLayout.resolved(
                for: module,
                dashboardCardCount: 0
            )

            #expect(layout.islandSize.width == 776)
            #expect(layout.panelSize.width == 776)
            #expect(ExpandedPetLayout.panelSize(for: layout.panelSize, includesPet: false).width == 776)
            #expect(ExpandedPetLayout.panelSize(for: layout.panelSize, includesPet: true).width == 820)
        }
    }

    @Test
    func voiceRecordingKeepsCollapsedWidthWithOneTranscriptRow() {
        let layout = IslandModuleLayout.voiceRecording

        #expect(layout.islandSize == CGSize(width: 240, height: 54))
        #expect(layout.panelSize == CGSize(width: 240, height: 58))
    }

    @Test
    func persistentPetDoesNotReserveHiddenStatusWingsDuringRecording() {
        let aiNotice = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)
        let voiceNotice = IslandNotice(
            id: "voice-processing-left",
            title: "正在整理语音",
            side: .left,
            style: .status
        )
        let notices = [aiNotice, voiceNotice]

        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: true,
            voiceDisplayID: 2,
            displayID: 1
        ).isEmpty)
        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: false,
            voiceDisplayID: 2,
            displayID: 1
        ) == [aiNotice])
        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: false,
            voiceDisplayID: 2,
            displayID: 2
        ) == notices)
    }

    @Test(arguments: IslandEdge.allCases)
    func compactRecordingExpandsBesideThePillAndKeepsItsIconArea(edge: IslandEdge) {
        let collapsed = edge.isVertical ? CGSize(width: 32, height: 70) : CGSize(width: 70, height: 32)
        let layout = IslandModuleLayout.compactSurface(collapsedSize: collapsed, overflowWidth: 70, edge: edge)
        let expected = edge.isVertical ? CGSize(width: 320, height: 80) : CGSize(width: 70, height: 52)
        #expect(layout.islandSize == expected)
        #expect(layout.panelSize == (edge.isVertical ? expected : CGSize(width: 70, height: 56)))
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: collapsed, availableSize: layout.islandSize, edge: edge)
        let icon = geometry.topRowFrame
        let text = geometry.transcriptRowFrame
        #expect(icon.intersection(text).isEmpty)
        #expect(icon.union(text) == CGRect(origin: .zero, size: expected))
        switch edge {
        case .top:
            #expect(icon.minY == 0 && text.minY == 32)
        case .bottom:
            #expect(icon.maxY == expected.height && text.minY == 0)
        case .left:
            #expect(icon.minX == 0 && text.minX == 32)
        case .right:
            #expect(icon.maxX == expected.width && text.minX == 0)
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func emptyAndSmallRecordingSurfacesHaveNoNegativeRows(edge: IslandEdge) {
        for available in [CGSize.zero, CGSize(width: 8, height: 10), CGSize(width: -1, height: -1)] {
            let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 32, height: 70),
                availableSize: available, edge: edge)
            #expect(geometry.surfaceSize.width >= 0 && geometry.surfaceSize.height >= 0)
            for frame in [geometry.topRowFrame, geometry.transcriptRowFrame] {
                #expect(frame.width >= 0 && frame.height >= 0)
            }
        }
    }

    @Test
    func recordingGeometryKeepsLegacyNotchWingsAndOneTranscriptRow() {
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 240, height: 34),
            availableSize: CGSize(width: 320, height: 58))
        #expect(geometry.surfaceSize == CGSize(width: 320, height: 54))
        #expect(geometry.topRowFrame == CGRect(x: 0, y: 0, width: 320, height: 34))
        #expect(geometry.transcriptRowFrame == CGRect(x: 0, y: 34, width: 320, height: 20))
    }

    @Test
    func panelRestoreDelayOutlastsTheFold() {
        #expect(ZislaMotion.islandRecycleSettleDelay > .milliseconds(220))
    }

    @Test(arguments: [IslandEdge.top, .bottom])
    func recordingFromAnIdleCustomCircleHasRoomForBothIconsAndItsTranscript(edge: IslandEdge) {
        let layout = IslandModuleLayout.compactSurface(collapsedSize: CGSize(width: 32, height: 32),
            overflowWidth: 32, edge: edge)
        #expect(layout.islandSize.width >= 70,
                "The idle 32pt circle cannot fit the mic, waveform and padded transcript")
    }

    @Test
    @MainActor
    func customRecordingIconsStayAdjacentWhileCameraWingsKeepTheirClearance() throws {
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 32, height: 32),
            availableSize: CGSize(width: 180, height: 52))
        func iconSpan(adjacent: Bool) throws -> Int {
            let renderer = ImageRenderer(content: VoiceTranscriptionView(voiceInput: VoiceInputController(),
                geometry: geometry, keepsIconsAdjacent: adjacent)
                .frame(width: 180, height: 52).background(.black))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let columns = (0..<bitmap.pixelsWide).filter { x in
                (0..<32).contains { y in
                    (bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.2
                }
            }
            return try #require(columns.last) - #require(columns.first)
        }
        #expect(try iconSpan(adjacent: true) < 45,
                "Custom pills need only the mic, a small gap and waveform")
        #expect(try iconSpan(adjacent: false) > 140,
                "Camera and notch rows must continue to reserve their original center space")
    }

}
