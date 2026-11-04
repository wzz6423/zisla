import Foundation
import ZislaCore

public enum DailyBriefingPNGExport {
    public static func fileName(for date: Date, language: AppLanguage, calendar: Calendar) -> String {
        let title = AppLocalization.string("每日简报", language: language).lowercased()
        let suffix = title.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined().split(separator: "-").joined(separator: "-")
        return "zisla-\(DailyBriefingDay.dateKey(date, calendar: calendar))-\(suffix).png"
    }

    @discardableResult
    public static func write(_ data: Data, for date: Date, language: AppLanguage, calendar: Calendar, directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(fileName(for: date, language: language, calendar: calendar))
        guard let validated = DownloadOutputPathValidator.normalizedFileURL(destination, within: directory) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        // Retrying after a successful image write but a failed history write updates one daily file.
        try data.write(to: validated, options: .atomic)
        return validated
    }
}
