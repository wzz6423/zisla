import Foundation
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct ClipboardAssistantCalendarPresentationTests {
    private let draft = ClipboardCalendarDraft(
        title: "项目例会",
        startDate: Date(timeIntervalSince1970: 1_800_000_000),
        endDate: Date(timeIntervalSince1970: 1_800_003_600),
        location: "会议室 A",
        notes: "讨论发布计划"
    )

    @Test(.timeLimit(.minutes(1)))
    func meetingAutomaticallyOpensItsDraftAfterPresentation() async throws {
        let controller = makeController()
        defer { controller.dismiss() }
        let (stream, continuation) = AsyncStream<ClipboardAssistantAction>.makeStream()
        defer { continuation.finish() }
        controller.onPerformAction = { continuation.yield($0) }
        _ = try #require(controller.present(meeting, visualStyle: .transparent))

        var actions = stream.makeAsyncIterator()
        #expect(await actions.next() == .editCalendarEvent(draft))
    }

    @Test
    func meetingPresentsItsCompleteDraftOnce() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let generation = try #require(controller.present(meeting, visualStyle: .transparent))

        controller.performPendingCalendarDraft(for: generation)
        controller.performPendingCalendarDraft(for: generation)

        #expect(actions == [.editCalendarEvent(draft)])
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func newerClipboardContentInvalidatesAnOlderMeetingDraft() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let generation = try #require(controller.present(meeting, visualStyle: .transparent))
        _ = controller.present(
            ClipboardAssistantDetection(kind: .text, title: "other text", actions: [.search("other text")]),
            visualStyle: .transparent
        )

        controller.performPendingCalendarDraft(for: generation)

        #expect(actions.isEmpty)
        #expect(controller.presentation.detection?.title == "other text")
    }

    @Test
    func anOldQueuedActionCannotOpenANewerMeeting() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let oldGeneration = try #require(controller.present(meeting, visualStyle: .transparent))
        var revisedDraft = draft
        revisedDraft.title = "Updated meeting"
        let generation = try #require(controller.present(
            ClipboardAssistantDetection(
                kind: .meeting, title: revisedDraft.title, actions: [.editCalendarEvent(revisedDraft)]
            ),
            visualStyle: .transparent
        ))

        controller.performPendingCalendarDraft(for: oldGeneration)
        #expect(actions.isEmpty)
        controller.performPendingCalendarDraft(for: generation)
        #expect(actions == [.editCalendarEvent(revisedDraft)])
    }

    @Test
    func screenshotCaptureSuppressesAPendingDraft() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let generation = try #require(controller.present(meeting, visualStyle: .transparent))
        controller.setScreenshotActive(true)

        controller.performPendingCalendarDraft(for: generation)

        #expect(actions.isEmpty)
    }

    @Test
    func lockingTheScreenDiscardsAPendingDraft() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let generation = try #require(controller.present(meeting, visualStyle: .transparent))
        controller.setScreenLocked(true)

        controller.performPendingCalendarDraft(for: generation)

        #expect(actions.isEmpty)
        #expect(controller.present(meeting, visualStyle: .transparent) == nil)
    }

    @Test
    func lookupActionsWaitForTheUser() throws {
        let controller = makeController()
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let url = try #require(URL(string: "https://www.google.com/maps/search/?api=1&query=Paris"))
        let generation = try #require(controller.present(
            ClipboardAssistantDetection(
                kind: .address, title: "Paris", actions: [.openService(service: .googleMaps, url: url)]
            ),
            visualStyle: .transparent
        ))

        controller.performPendingCalendarDraft(for: generation)

        #expect(actions.isEmpty)
    }

    private var meeting: ClipboardAssistantDetection {
        ClipboardAssistantDetection(kind: .meeting, title: draft.title, actions: [.editCalendarEvent(draft)])
    }

    private func makeController() -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.displayDuration = .never
        return controller
    }
}
