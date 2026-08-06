import ZislaCore

public enum ApplicationIconTheme: Sendable, Equatable {
    case day
    case night

    public static func resolve(mode: AppearanceMode, systemIsDark: Bool) -> Self {
        switch mode {
        case .system: systemIsDark ? .night : .day
        case .light: .day
        case .dark: .night
        }
    }
}
