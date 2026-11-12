import Foundation
import ZislaCore

public enum AIUsageHistoryExport {
    public static let fileExtension = "xlsx"

    public static func defaultFileName(now: Date, timeZone: TimeZone = .current) -> String {
        SystemMetricsHistoryExport.defaultFileName(now: now, timeZone: timeZone)
            .replacingOccurrences(of: "zisla-metrics-", with: "zisla-ai-usage-")
    }

    /// Exports daily totals and complete model splits as text-safe OOXML, excluding private source identifiers.
    public static func workbookData(history: AIUsageHistory, timeZone: TimeZone = .current,
        modificationDate: Date = Date()) throws -> Data {
        try Task.checkCancellation()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = AIUsageAnalytics.dailyModelUsage(history: history,
            endingAt: (history.usageSamples + history.modelUsageSamples).map(\.timestamp).max() ?? modificationDate,
            calendar: calendar).reversed()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var totalRows = [row(1, [.text("date"), .text("input_tokens"), .text("output_tokens"), .text("total_tokens")])]
        var modelRows = [row(1, [.text("date"), .text("provider"), .text("model"), .text("input_tokens"),
            .text("output_tokens"), .text("total_tokens")])]
        for day in days {
            try Task.checkCancellation()
            let date = formatter.string(from: day.date)
            totalRows.append(row(totalRows.count + 1, [.text(date), .count(day.inputTokens), .count(day.outputTokens), .count(day.totalTokens)]))
            for model in day.models {
                modelRows.append(row(modelRows.count + 1, [.text(date), .text(model.provider?.rawValue ?? ""),
                    .text(model.model ?? ""), .count(model.inputTokens), .count(model.outputTokens), .count(model.totalTokens)]))
            }
        }
        return StoredZIPArchive.data(entries: [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Daily Totals" sheetId="1" r:id="rId1"/><sheet name="Models" sheetId="2" r:id="rId2"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>
            """),
            ("xl/worksheets/sheet1.xml", sheet(totalRows)),
            ("xl/worksheets/sheet2.xml", sheet(modelRows)),
        ], modificationDate: modificationDate)
    }

    private enum Cell {
        case text(String), count(Int)
    }

    private static func row(_ index: Int, _ cells: [Cell]) -> String {
        let content = cells.enumerated().map { column, cell in
            let reference = "\(SystemMetricsHistoryExport.columnName(column + 1))\(index)"
            switch cell {
            case let .text(value):
                return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            case let .count(value):
                return "<c r=\"\(reference)\"><v>\(value)</v></c>"
            }
        }.joined()
        return "<row r=\"\(index)\">\(content)</row>"
    }

    private static func sheet(_ rows: [String]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
            + rows.joined() + "</sheetData></worksheet>"
    }

    /// XML 1.0 excludes control scalars even inside inline strings; formula-like model names remain plain text.
    private static func escape(_ text: String) -> String {
        let clean = String(text.unicodeScalars.filter { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13
                || (0x20...0xD7FF).contains(scalar.value) || (0xE000...0xFFFD).contains(scalar.value)
                || (0x10000...0x10FFFF).contains(scalar.value)
        })
        return clean.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
