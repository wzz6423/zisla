import AppKit
import ApplicationServices
import Testing

@testable import ZislaKit

@MainActor
struct VoiceTranscriptDeliveryTests {
    @Test
    func productionPasteEventsUseCompleteCommandVSequence() throws {
        let events = try #require(VoiceTranscriptDelivery.commandVEvents())

        #expect(events.commandDown.type == .flagsChanged)
        #expect(events.vDown.type == .keyDown)
        #expect(events.vUp.type == .keyUp)
        #expect(events.commandUp.type == .flagsChanged)
        #expect(events.commandDown.flags.contains(.maskCommand))
        #expect(events.vDown.flags.contains(.maskCommand))
        #expect(events.vUp.flags.contains(.maskCommand))
        #expect(events.commandDown.getIntegerValueField(.keyboardEventKeycode) == 55)
        #expect(events.vDown.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(events.vUp.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(events.commandUp.getIntegerValueField(.keyboardEventKeycode) == 55)
    }

    @Test
    func directInsertionReplacesTheUTF16SelectionWithoutDroppingSurroundingText() {
        #expect(VoiceTranscriptDelivery.replacingSelection(
            in: "你好🙂 world",
            location: 2,
            length: 2,
            with: "语音"
        ) == "你好语音 world")
        #expect(VoiceTranscriptDelivery.replacingSelection(
            in: "hello",
            location: 4,
            length: 2,
            with: "!"
        ) == nil)
    }

    @Test
    func hoveredTargetPastesOnlyWhenAlreadyFocusedAndFrontmost() {
        var postedPID: pid_t?

        let delivered = VoiceTranscriptDelivery.deliverToHoveredTarget(
            processIdentifier: 4_242,
            isFrontmost: true,
            isFocused: true,
            postPaste: { pid in
                postedPID = pid
                return true
            }
        )

        #expect(delivered)
        #expect(postedPID == 4_242)
    }

    @Test
    func hoveredTargetDoesNotPasteWhenItIsUnfocusedOrInTheBackground() {
        var postCount = 0
        let postPaste: (pid_t) -> Bool = { _ in
            postCount += 1
            return true
        }

        let unfocused = VoiceTranscriptDelivery.deliverToHoveredTarget(
            processIdentifier: 4_242,
            isFrontmost: true,
            isFocused: false,
            postPaste: postPaste
        )
        let background = VoiceTranscriptDelivery.deliverToHoveredTarget(
            processIdentifier: 4_242,
            isFrontmost: false,
            isFocused: true,
            postPaste: postPaste
        )

        #expect(!unfocused)
        #expect(!background)
        #expect(postCount == 0)
    }

    @Test
    func writesClipboardBeforePostingPasteToTargetProcess() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var postedPID: pid_t?
        var textObservedWhilePosting: String?
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in .noInput },
            postPaste: { pid in
                postedPID = pid
                textObservedWhilePosting = pasteboard.string(forType: .string)
                return true
            }
        )

        let outcome = delivery.deliver("明天十点开会", to: 4_242)

        #expect(outcome == .copiedAndPasted)
        #expect(postedPID == 4_242)
        #expect(textObservedWhilePosting == "明天十点开会")
        #expect(pasteboard.string(forType: .string) == "明天十点开会")
    }

    @Test
    func prefersTargetProcessOverHoveredInput() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var hoveredTranscript: String?
        var postedPID: pid_t?
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { transcript in
                hoveredTranscript = transcript
                return .pasted
            },
            postPaste: { pid in
                postedPID = pid
                return true
            }
        )

        let outcome = delivery.deliver("直接输入这里", to: 4_242)

        #expect(outcome == .copiedAndPasted)
        #expect(hoveredTranscript == nil)  // 有 targetPID 时不使用 hovered input
        #expect(postedPID == 4_242)        // 直接发送到目标进程
        #expect(pasteboard.string(forType: .string) == "直接输入这里")
    }

    @Test
    func usesHoveredInputWhenNoTargetProcess() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var hoveredInputAttempts = 0
        var postedPID: pid_t?
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in
                hoveredInputAttempts += 1
                return .pasted
            },
            postPaste: { pid in
                postedPID = pid
                return true
            }
        )

        let outcome = delivery.deliver("回退输入", to: nil)

        #expect(outcome == .copiedAndPasted)
        #expect(hoveredInputAttempts == 1)  // 没有 targetPID 时使用 hovered input
        #expect(postedPID == nil)
        #expect(pasteboard.string(forType: .string) == "回退输入")
    }

    @Test
    func usesHoveredInputWithoutAnOriginalTargetProcess() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var hoveredInputAttempts = 0
        var didPostFallback = false
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in
                hoveredInputAttempts += 1
                return .pasted
            },
            postPaste: { _ in
                didPostFallback = true
                return true
            }
        )

        let outcome = delivery.deliver("悬停输入", to: nil)

        #expect(outcome == .copiedAndPasted)
        #expect(hoveredInputAttempts == 1)
        #expect(!didPostFallback)
        #expect(pasteboard.string(forType: .string) == "悬停输入")
    }

    @Test
    func blockedHoveredInputStillPastesToKnownTargetProcess() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var hoveredInputCalled = false
        var postedPID: pid_t?
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in
                hoveredInputCalled = true
                return .blocked
            },
            postPaste: { pid in
                postedPID = pid
                return true
            }
        )

        let outcome = delivery.deliver("已知目标进程", to: 4_242)

        // 有明确目标进程时，直接发送到该进程，不检查 hovered input
        #expect(outcome == .copiedAndPasted)
        #expect(!hoveredInputCalled)
        #expect(postedPID == 4_242)
        #expect(pasteboard.string(forType: .string) == "已知目标进程")
    }

    @Test
    func editableTextInputPolicyAcceptsOnlyEnabledNonSecureTextControls() {
        #expect(VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXTextFieldRole as String,
            subrole: nil,
            isEnabled: true
        ))
        #expect(VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXTextAreaRole as String,
            subrole: nil,
            isEnabled: true
        ))
        #expect(VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXComboBoxRole as String,
            subrole: nil,
            isEnabled: true
        ))
        #expect(!VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            isEnabled: true
        ))
        #expect(!VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXButtonRole as String,
            subrole: nil,
            isEnabled: true
        ))
        #expect(!VoiceTranscriptDelivery.isEditableTextInput(
            role: kAXTextFieldRole as String,
            subrole: nil,
            isEnabled: false
        ))
    }

    @Test
    func focusedPasteTargetPolicyAcceptsStandardAndObservedCustomEditors() {
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXTextAreaRole as String,
            subrole: nil,
            isEnabled: true,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXGroupRole as String,
            subrole: "iOSContentGroup",
            isEnabled: nil,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXUnknownRole as String,
            subrole: nil,
            isEnabled: true,
            belongsToHitProcess: true,
            containsPointer: true
        ))
    }

    @Test
    func focusedPasteTargetPolicyRejectsUnsafeOrUnrelatedElements() {
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXButtonRole as String,
            subrole: nil,
            isEnabled: true,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            isEnabled: true,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXUnknownRole as String,
            subrole: nil,
            isEnabled: false,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXGroupRole as String,
            subrole: "iOSContentGroup",
            isEnabled: false,
            belongsToHitProcess: true,
            containsPointer: true
        ))
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXUnknownRole as String,
            subrole: nil,
            isEnabled: true,
            belongsToHitProcess: false,
            containsPointer: true
        ))
        #expect(!VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXUnknownRole as String,
            subrole: nil,
            isEnabled: true,
            belongsToHitProcess: true,
            containsPointer: false
        ))
    }

    @Test
    func keepsTranscriptOnClipboardWhenPasteCannotBePosted() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in .noInput },
            postPaste: { _ in false }
        )

        let outcome = delivery.deliver("保留在剪贴板", to: 4_242)

        #expect(outcome == .copiedOnly)
        #expect(pasteboard.string(forType: .string) == "保留在剪贴板")
    }

    @Test
    func copiesWithoutPostingWhenThereIsNoTargetProcess() {
        let pasteboard = NSPasteboard(name: .init("VoiceTranscriptDeliveryTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var didPost = false
        let delivery = VoiceTranscriptDelivery(
            pasteboard: pasteboard,
            pasteIntoHoveredInput: { _ in .noInput },
            postPaste: { _ in
                didPost = true
                return true
            }
        )

        let outcome = delivery.deliver("只有剪贴板", to: nil)

        #expect(outcome == .copiedOnly)
        #expect(!didPost)
        #expect(pasteboard.string(forType: .string) == "只有剪贴板")
    }

    @Test
    func focusedPasteTargetAcceptsUnknownRoleWithNilEnabled() {
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXUnknownRole as String,
            subrole: nil,
            isEnabled: nil,
            belongsToHitProcess: true,
            containsPointer: true
        ))
    }

    @Test
    func focusedPasteTargetAcceptsGroupWithNilEnabled() {
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXGroupRole as String,
            subrole: "iOSContentGroup",
            isEnabled: nil,
            belongsToHitProcess: true,
            containsPointer: true
        ))
    }

    @Test
    func focusedPasteTargetAcceptsStandardTextFieldWithNilEnabled() {
        #expect(VoiceTranscriptDelivery.isFocusedPasteTarget(
            role: kAXTextFieldRole as String,
            subrole: nil,
            isEnabled: nil,
            belongsToHitProcess: true,
            containsPointer: true
        ))
    }

    @Test
    func postCommandVTargetsTheProcessDirectlyRegardlessOfKeyWindowState() {
        var capturedPID: pid_t?

        let result = VoiceTranscriptDelivery.postCommandVWithStrategy(
            to: 4_242,
            hasPostEventAccess: true,
            postToPID: { pid in
                capturedPID = pid
                return true
            }
        )

        // 直投目标进程:录音面板可能短暂持有 key window,tap 路由的按键
        // 会落到面板;postToPid 事件总是进入目标应用。
        #expect(result)
        #expect(capturedPID == 4_242)
    }

    @Test
    func postCommandVPropagatesPostingFailure() {
        let result = VoiceTranscriptDelivery.postCommandVWithStrategy(
            to: 4_242,
            hasPostEventAccess: true,
            postToPID: { _ in false }
        )

        #expect(!result)
    }

    @Test
    func postCommandVDoesNotPostWithoutEventSynthesisAccess() {
        var didPost = false

        let result = VoiceTranscriptDelivery.postCommandVWithStrategy(
            to: 4_242,
            hasPostEventAccess: false,
            postToPID: { _ in
                didPost = true
                return true
            }
        )

        #expect(!result)
        #expect(!didPost)
    }

    @Test
    func eventSynthesisAccessIsRequestedOnlyWhenMissingAndNotRequestedThisLaunch() {
        #expect(VoiceTranscriptDelivery.shouldRequestEventSynthesisAccess(
            hasAccess: false,
            hasRequestedInCurrentLaunch: false
        ))
        #expect(!VoiceTranscriptDelivery.shouldRequestEventSynthesisAccess(
            hasAccess: true,
            hasRequestedInCurrentLaunch: false
        ))
        #expect(!VoiceTranscriptDelivery.shouldRequestEventSynthesisAccess(
            hasAccess: false,
            hasRequestedInCurrentLaunch: true
        ))
    }

    @Test
    func missingEventSynthesisAccessUsesTheMatchingSystemRequest() {
        var requestCount = 0

        let granted = VoiceTranscriptDelivery.requestEventSynthesisAccess(
            hasAccess: false,
            requestAccess: {
                requestCount += 1
                return true
            }
        )

        #expect(granted)
        #expect(requestCount == 1)
    }

}
