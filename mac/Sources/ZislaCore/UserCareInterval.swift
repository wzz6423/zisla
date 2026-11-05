import Foundation

public enum UserCareInterval {
    public static let defaultSeconds: TimeInterval = 45 * 60
    public static let maximumSeconds: TimeInterval = 99 * 3_600 + 59 * 60 + 59

    public static func normalized(_ seconds: TimeInterval) -> TimeInterval {
        return min(maximumSeconds, max(1, seconds.rounded(.down)))
    }

    public static func seconds(hours: Int, minutes: Int, seconds: Int) -> TimeInterval? {
        guard (0...99).contains(hours), (0...59).contains(minutes), (0...59).contains(seconds) else {
            return nil
        }
        let total = hours * 3_600 + minutes * 60 + seconds
        return total > 0 ? TimeInterval(total) : nil
    }
}
