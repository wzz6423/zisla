/// Independent reasons the side-notice panels stay hidden.
///
/// They must not share a single flag: expanding the island also dismisses the clipboard
/// assistant, so a shared flag would let that dismissal clear the hidden state and re-show
/// the collapsed status bar on top of the open panel.
public struct SideNoticeSuppression: Equatable, Sendable {
    public var isIslandExpanded = false
    public var isVoiceRecording = false
    public var isClipboardAssistantVisible = false

    public init() {}

    public var hidesNotices: Bool {
        isIslandExpanded || isVoiceRecording || isClipboardAssistantVisible
    }
}
