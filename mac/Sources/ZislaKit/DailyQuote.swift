import Foundation

/// Offline daily quotes selected deterministically by date without network access.
public struct DailyQuote: Equatable, Sendable {
    public var text: String
    public var author: String?

    public init(text: String, author: String? = nil) {
        self.text = text
        self.author = author
    }

    /// Built-in offline quotes with stable ordering and no randomness.
    public static let library: [DailyQuote] = [
        DailyQuote(text: "今天也要好好生活。"),
        DailyQuote(text: "慢慢来，比较快。"),
        DailyQuote(text: "把每一件小事做好。"),
        DailyQuote(text: "山高路远，看世界也看自己。"),
        DailyQuote(text: "先完成，再完美。"),
        DailyQuote(text: "热爱可抵岁月漫长。"),
        DailyQuote(text: "保持好奇，保持热爱。"),
        DailyQuote(text: "所有的努力都不会白费。"),
        DailyQuote(text: "星光不问赶路人。"),
        DailyQuote(text: "把日子过成想要的样子。"),
        DailyQuote(text: "别急，好的事情正在发生。"),
        DailyQuote(text: "认真的人最好看。"),
        DailyQuote(text: "一步一个脚印，走稳当下。"),
        DailyQuote(text: "愿你眼里有光，心中有暖。"),
        DailyQuote(text: "简单的事重复做，就是专家。"),
        DailyQuote(text: "允许一切如其所是。"),
        DailyQuote(text: "生活明朗，万物可爱。"),
        DailyQuote(text: "专注当下，答案自现。"),
        DailyQuote(text: "做难而正确的事。"),
        DailyQuote(text: "心之所向，素履以往。"),
        DailyQuote(text: "念念不忘，必有回响。"),
        DailyQuote(text: "从容一点，日子很长。"),
        DailyQuote(text: "把复杂留给自己，把简单交给使用者。"),
        DailyQuote(text: "今天的坚持，是明天的底气。"),
        DailyQuote(text: "少即是多，慢即是稳。"),
        DailyQuote(text: "向前走，别回头。"),
        DailyQuote(text: "把注意力放在可以改变的事上。"),
        DailyQuote(text: "早安，愿今天温柔待你。"),
        DailyQuote(text: "所遇皆是温柔，所求皆能如愿。"),
        DailyQuote(text: "认真生活的人，运气都不会太差。"),
    ]

    /// Selects a daily quote deterministically, returning the same quote throughout a day and rotating across days.
    public static func quote(
        for date: Date,
        calendar: Calendar = .current,
        library: [DailyQuote] = DailyQuote.library
    ) -> DailyQuote {
        guard !library.isEmpty else { return DailyQuote(text: "") }
        let index = dayOrdinal(for: date, calendar: calendar) % library.count
        return library[index]
    }

    /// Returns an era-based day ordinal that changes only at the start of a new calendar day.
    static func dayOrdinal(for date: Date, calendar: Calendar) -> Int {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return max(0, ordinal)
    }
}
