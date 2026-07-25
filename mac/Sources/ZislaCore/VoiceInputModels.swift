import Foundation

/// 语音输入的触发方式。
public enum VoiceInputMode: String, Codable, CaseIterable, Sendable {
    /// 按一下快捷键开始录音，再按一次结束。
    case toggle
    /// 按住快捷键说话，松开结束。
    case pushToTalk

    public var displayName: String {
        switch self {
        case .toggle: "切换模式"
        case .pushToTalk: "按住说话"
        }
    }

    public var detail: String {
        switch self {
        case .toggle: "按下快捷键开始录音，再按一次结束"
        case .pushToTalk: "按住快捷键说话，松开结束"
        }
    }
}

/// 物理修饰键位置，用于区分键盘左右两侧的同类按键。
public enum VoiceInputModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case leftShift
    case rightShift

    /// macOS 虚拟键码（参考 Events.h）。
    public var keyCode: UInt32 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        }
    }

    public var carbonModifier: UInt32 {
        switch self {
        case .leftCommand, .rightCommand: 0x0100
        case .leftShift, .rightShift: 0x0200
        case .leftOption, .rightOption: 0x0800
        case .leftControl, .rightControl: 0x1000
        }
    }

    public var displayName: String {
        switch self {
        case .leftControl: "左⌃"
        case .rightControl: "右⌃"
        case .leftOption: "左⌥"
        case .rightOption: "右⌥"
        case .leftCommand: "左⌘"
        case .rightCommand: "右⌘"
        case .leftShift: "左⇧"
        case .rightShift: "右⇧"
        }
    }

    public init?(keyCode: UInt32) {
        guard let modifier = Self.allCases.first(where: { $0.keyCode == keyCode }) else {
            return nil
        }
        self = modifier
    }
}

/// 语音输入的全局快捷键，可由用户录制任意带修饰键的组合。
///
/// 兼容旧版 JSON 中的单字符串 `"optionSpace"` / `"controlSpace"` / `"commandShiftV"`；
/// 新编码使用结构化字段保存虚拟键码、Carbon 修饰键掩码、显示用键名与可选的左右修饰键位置。
public struct VoiceInputHotkeyPreset: Codable, Equatable, Sendable {
    /// Carbon 虚拟键码（参考 Events.h）。
    public let keyCode: UInt32
    /// Carbon 修饰键掩码（参考 Events.h）。
    public let carbonModifiers: UInt32
    /// 显示用主键名（不含修饰键符号）。
    public let keyDisplayName: String
    /// 非空时要求精确匹配每个物理修饰键；`nil` 保持旧版通用修饰键语义。
    public let modifierSides: Set<VoiceInputModifier>?

    public init(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        keyDisplayName: String,
        modifierSides: Set<VoiceInputModifier>? = nil
    ) {
        self.keyCode = keyCode
        self.carbonModifiers = modifierSides.map(Self.carbonModifiers(for:)) ?? carbonModifiers
        self.keyDisplayName = keyDisplayName
        self.modifierSides = modifierSides
    }

    /// ⌥ Space
    public static let optionSpace = VoiceInputHotkeyPreset(
        keyCode: 49,              // kVK_Space
        carbonModifiers: 0x0800,  // optionKey
        keyDisplayName: "Space"
    )

    /// ⌃ Space
    public static let controlSpace = VoiceInputHotkeyPreset(
        keyCode: 49,              // kVK_Space
        carbonModifiers: 0x1000,  // controlKey
        keyDisplayName: "Space"
    )

    /// ⌘⇧ V
    public static let commandShiftV = VoiceInputHotkeyPreset(
        keyCode: 9,                         // kVK_ANSI_V
        carbonModifiers: 0x0100 | 0x0200,   // cmdKey | shiftKey
        keyDisplayName: "V"
    )

    /// 设置页默认可选列表（与旧 enum `CaseIterable` 调用契约兼容）。
    public static var allCases: [VoiceInputHotkeyPreset] {
        [.optionSpace, .controlSpace, .commandShiftV]
    }

    /// 以 macOS 菜单常用符号展示修饰键 + 主键名。
    public var displayName: String {
        if let modifierSides, !modifierSides.isEmpty {
            if isModifierOnly, let modifier = modifierSides.first {
                return modifier.displayName
            }
            let names = VoiceInputModifier.allCases
                .filter(modifierSides.contains)
                .map(\.displayName)
            return (names + [keyDisplayName]).joined(separator: " + ")
        }
        let symbols = Self.modifierSymbols(carbonModifiers: carbonModifiers)
        return symbols.isEmpty ? keyDisplayName : "\(symbols) \(keyDisplayName)"
    }

    public var requiresInputMonitoring: Bool {
        guard let modifierSides else { return false }
        return !modifierSides.isEmpty
    }

    /// 独立修饰键没有普通的 keyDown 事件，需由 flagsChanged 触发。
    public var isModifierOnly: Bool {
        guard let modifierSides, modifierSides.count == 1, let modifier = modifierSides.first else {
            return false
        }
        return modifier.keyCode == keyCode
    }

    /// 检查主键与当前按下的物理修饰键是否和录制值完全一致。
    public func matches(keyCode: UInt32, modifierSides: Set<VoiceInputModifier>) -> Bool {
        guard self.keyCode == keyCode, let requiredModifierSides = self.modifierSides else {
            return false
        }
        return requiredModifierSides == modifierSides
    }

    public static func carbonModifiers(for modifierSides: Set<VoiceInputModifier>) -> UInt32 {
        modifierSides.reduce(0) { $0 | $1.carbonModifier }
    }

    /// macOS 风格修饰键符号串（⌃⌥⇧⌘）。
    public static func modifierSymbols(carbonModifiers: UInt32) -> String {
        var symbols = ""
        if carbonModifiers & 0x1000 != 0 { symbols += "⌃" }  // controlKey
        if carbonModifiers & 0x0800 != 0 { symbols += "⌥" }  // optionKey
        if carbonModifiers & 0x0100 != 0 { symbols += "⌘" }  // cmdKey
        if carbonModifiers & 0x0200 != 0 { symbols += "⇧" }  // shiftKey
        return symbols
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case carbonModifiers
        case keyDisplayName
        case modifierSides
    }

    private enum LegacyName: String {
        case optionSpace
        case controlSpace
        case commandShiftV
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch LegacyName(rawValue: raw) {
            case .optionSpace:
                self = .optionSpace
            case .controlSpace:
                self = .controlSpace
            case .commandShiftV:
                self = .commandShiftV
            case .none:
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "Unknown VoiceInputHotkeyPreset legacy value: \(raw)"
                )
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        carbonModifiers = try container.decode(UInt32.self, forKey: .carbonModifiers)
        keyDisplayName = try container.decode(String.self, forKey: .keyDisplayName)
        modifierSides = try container.decodeIfPresent(
            Set<VoiceInputModifier>.self,
            forKey: .modifierSides
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(carbonModifiers, forKey: .carbonModifiers)
        try container.encode(keyDisplayName, forKey: .keyDisplayName)
        try container.encodeIfPresent(modifierSides, forKey: .modifierSides)
    }
}



/// 模型发现的状态，用于设置页面展示连接测试进度与结果。
public enum VoiceModelDiscoveryState: Equatable, Sendable {
    case idle
    case testing
    case success(Int)
    case failed(String)

    public var isTesting: Bool {
        if case .testing = self { return true }
        return false
    }
}
