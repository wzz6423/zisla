/// Independent reasons the side-notice panels stay hidden.
///
/// They must not share a single flag: expanding the island also dismisses the clipboard
/// assistant, so a shared flag would let that dismissal clear the hidden state and re-show
/// the collapsed status bar on top of the open panel.
public struct SideNoticeSuppression: Equatable, Sendable {
    public var isIslandExpanded = false
    public var islandDisplayID: UInt32?
    public var isVoiceRecording = false
    public var voiceDisplayID: UInt32?
    public var isClipboardAssistantVisible = false
    public var clipboardDisplayID: UInt32?
    public var isScreenLocked = false
    /// The island's own transient message replaces the collapsed pill's row, just like recording.
    public var isTransientNoticePresented = false
    public var transientDisplayID: UInt32?

    public init() {}

    public var hidesNotices: Bool {
        isIslandExpanded
            || isVoiceRecording
            || isClipboardAssistantVisible
            || isScreenLocked
            || isTransientNoticePresented
    }

    public func scoped(to displayID: UInt32) -> Self {
        var value = self
        value.isIslandExpanded = isIslandExpanded && (islandDisplayID == nil || islandDisplayID == displayID)
        value.isVoiceRecording = isVoiceRecording && (voiceDisplayID == nil || voiceDisplayID == displayID)
        value.isClipboardAssistantVisible = isClipboardAssistantVisible && (clipboardDisplayID == nil || clipboardDisplayID == displayID)
        value.isTransientNoticePresented = isTransientNoticePresented && (transientDisplayID == nil || transientDisplayID == displayID)
        return value
    }
}
