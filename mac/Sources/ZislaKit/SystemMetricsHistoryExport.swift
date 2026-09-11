import Foundation

// MARK: - Spreadsheet export

/// Writes the recorded samples as a real `.xlsx` workbook without depending on Microsoft Office,
/// LibreOffice, or a third-party package: the minimal SpreadsheetML parts are generated directly
/// and packed with `StoredZIPArchive`.
public enum SystemMetricsHistoryExport {
    public static let fileExtension = "xlsx"

    public static func defaultFileName(now: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "zisla-metrics-\(formatter.string(from: now)).\(fileExtension)"
    }

    public static func workbookData(
        records: [SystemMetricsRecord],
        sheetName: String = "Zisla Metrics",
        timeZone: TimeZone = .current,
        modificationDate: Date = Date()
    ) -> Data {
        let columns = MetricsSheetColumns(records: records)
        let sheet = sheetXML(records: records, columns: columns, timeZone: timeZone)
        return StoredZIPArchive.data(
            entries: [
                ("[Content_Types].xml", contentTypesXML),
                ("_rels/.rels", rootRelationshipsXML),
                ("xl/workbook.xml", workbookXML(sheetName: sheetName)),
                ("xl/_rels/workbook.xml.rels", workbookRelationshipsXML),
                ("xl/styles.xml", stylesXML),
                ("xl/worksheets/sheet1.xml", sheet),
            ],
            modificationDate: modificationDate
        )
    }

    // MARK: Columns

    private struct Column {
        var header: String
        var value: (SystemMetricsRecord) -> MetricsSheetCell
    }

    private struct MetricsSheetColumns {
        var columns: [Column]

        init(records: [SystemMetricsRecord]) {
            let fanCount = records.map(\.fanRPMs.count).max() ?? 0
            var columns: [Column] = [
                Column(header: "timestamp") { .dateSerial($0.timestamp) },
                Column(header: "cpu_usage") { .number($0.cpuUsage) },
                Column(header: "cpu_user") { .number($0.cpuUser) },
                Column(header: "cpu_system") { .number($0.cpuSystem) },
                Column(header: "cpu_idle") { .number($0.cpuIdle) },
                Column(header: "cpu_temperature_celsius") { .optionalNumber($0.cpuTemperatureCelsius) },
                Column(header: "gpu_usage") { .optionalNumber($0.gpuUsage) },
                Column(header: "gpu_renderer") { .optionalNumber($0.gpuRenderer) },
                Column(header: "gpu_tiler") { .optionalNumber($0.gpuTiler) },
                Column(header: "gpu_temperature_celsius") { .optionalNumber($0.gpuTemperatureCelsius) },
                Column(header: "memory_used_bytes") { .number(Double($0.memoryUsedBytes)) },
                Column(header: "memory_total_bytes") { .number(Double($0.memoryTotalBytes)) },
                Column(header: "memory_usage_ratio") { .number($0.memoryUsageRatio) },
                Column(header: "memory_pressure_ratio") { .number($0.memoryPressureRatio) },
                Column(header: "disk_used_bytes") { .number(Double($0.diskUsedBytes)) },
                Column(header: "disk_total_bytes") { .number(Double($0.diskTotalBytes)) },
                Column(header: "disk_usage_ratio") { .number($0.diskUsageRatio) },
                Column(header: "disk_read_bytes_per_second") { .optionalNumber($0.diskReadBytesPerSecond) },
                Column(header: "disk_write_bytes_per_second") { .optionalNumber($0.diskWriteBytesPerSecond) },
                Column(header: "disk_temperature_celsius") { .optionalNumber($0.diskTemperatureCelsius) },
            ]
            columns.append(
                contentsOf: (0..<fanCount).map { index in
                    Column(header: "fan_\(index + 1)_rpm") { record in
                        index < record.fanRPMs.count ? .number(record.fanRPMs[index]) : .blank
                    }
                }
            )
            columns.append(
                contentsOf: [
                    Column(header: "network_receive_bytes_per_second") {
                        .number($0.networkReceiveBytesPerSecond)
                    },
                    Column(header: "network_send_bytes_per_second") {
                        .number($0.networkSendBytesPerSecond)
                    },
                    Column(header: "network_received_bytes") { .number(Double($0.networkReceivedBytes)) },
                    Column(header: "network_sent_bytes") { .number(Double($0.networkSentBytes)) },
                ]
            )
            self.columns = columns
        }
    }

    private enum MetricsSheetCell {
        case text(String)
        case number(Double)
        case optionalNumber(Double?)
        case dateSerial(Date)
        case blank
    }

    private enum CellStyle {
        /// Header row: bold.
        static let header = 1
        /// Excel date serial with `yyyy-mm-dd hh:mm:ss`.
        static let date = 2
        static let regular = 0
    }

    // MARK: Sheet XML

    private static func sheetXML(
        records: [SystemMetricsRecord],
        columns: MetricsSheetColumns,
        timeZone: TimeZone
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        """
        xml += rowXML(
            index: 1,
            cells: columns.columns.map { .text($0.header) },
            style: CellStyle.header
        )
        for (offset, record) in records.enumerated() {
            var cells: [MetricsSheetCell] = []
            cells.reserveCapacity(columns.columns.count)
            for column in columns.columns {
                cells.append(column.value(record))
            }
            xml += rowXML(index: offset + 2, cells: cells, style: nil, timeZone: timeZone)
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func rowXML(
        index: Int,
        cells: [MetricsSheetCell],
        style: Int?,
        timeZone: TimeZone = .current
    ) -> String {
        var xml = "<row r=\"\(index)\">"
        for (columnIndex, cell) in cells.enumerated() {
            let reference = "\(columnName(columnIndex + 1))\(index)"
            switch cell {
            case let .text(text):
                let resolvedStyle = style ?? CellStyle.regular
                xml += "<c r=\"\(reference)\" s=\"\(resolvedStyle)\" t=\"inlineStr\"><is><t>"
                xml += escape(text)
                xml += "</t></is></c>"
            case let .number(value):
                xml += "<c r=\"\(reference)\" s=\"\(style ?? CellStyle.regular)\"><v>"
                xml += numberText(value)
                xml += "</v></c>"
            case let .optionalNumber(value):
                guard let value, value.isFinite else { continue }
                xml += "<c r=\"\(reference)\" s=\"\(style ?? CellStyle.regular)\"><v>"
                xml += numberText(value)
                xml += "</v></c>"
            case let .dateSerial(date):
                xml += "<c r=\"\(reference)\" s=\"\(CellStyle.date)\"><v>"
                xml += numberText(excelSerial(for: date, timeZone: timeZone))
                xml += "</v></c>"
            case .blank:
                continue
            }
        }
        xml += "</row>"
        return xml
    }

    /// Days since 1899-12-30 in the workbook's 1900 date system. The timezone offset is folded in so
    /// Excel renders local wall-clock time rather than UTC, and the sample is rounded to a whole second.
    static func excelSerial(for date: Date, timeZone: TimeZone) -> Double {
        // 1899-12-30T00:00:00Z is two days before 1900-01-01, the day Excel numbers as serial 2.
        let secondsFrom1899 = 2_209_161_600.0
        let offset = Double(timeZone.secondsFromGMT(for: date))
        return (date.timeIntervalSince1970.rounded() + offset + secondsFrom1899) / 86_400
    }

    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? "0" : text
    }

    /// A1 notation; column 1 is `A`, column 27 is `AA`.
    static func columnName(_ index: Int) -> String {
        var remaining = max(1, index)
        var name = ""
        while remaining > 0 {
            let digit = (remaining - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + digit))) + name
            remaining = (remaining - 1) / 26
        }
        return name
    }

    private static func escape(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }

    // MARK: Workbook parts

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets><sheet name="\(escape(sheetName))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """

    /// Three cell formats: default, bold header, and the datetime serial format.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm:ss"/></numFmts>\
    <fonts count="2">\
    <font><sz val="11"/><name val="Calibri"/></font>\
    <font><b/><sz val="11"/><name val="Calibri"/></font>\
    </fonts>\
    <fills count="2">\
    <fill><patternFill patternType="none"/></fill>\
    <fill><patternFill patternType="gray125"/></fill>\
    </fills>\
    <borders count="1"><border/></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="3">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """
}

// MARK: - ZIP writer

/// Minimal ZIP writer using stored (uncompressed) entries, which keeps the `.xlsx` a valid OOXML
/// package without pulling in a compression library. Every reader that accepts ZIP, including
/// Excel and Numbers, accepts stored entries.
enum StoredZIPArchive {
    static func data(entries: [(path: String, content: String)], modificationDate: Date) -> Data {
        let (dosTime, dosDate) = dosTimestamp(modificationDate)
        var archive = Data()
        var directory = Data()
        var entryCount = 0

        for entry in entries {
            let payload = Data(entry.content.utf8)
            guard let nameData = entry.path.data(using: .utf8) else { continue }
            entryCount += 1
            let checksum = crc32(payload)
            let offset = UInt32(archive.count)

            archive.appendUInt32(0x0403_4B50)          // local file header
            archive.appendUInt16(20)                   // version needed
            archive.appendUInt16(0x0800)               // UTF-8 file names
            archive.appendUInt16(0)                    // stored
            archive.appendUInt16(dosTime)
            archive.appendUInt16(dosDate)
            archive.appendUInt32(checksum)
            archive.appendUInt32(UInt32(payload.count))
            archive.appendUInt32(UInt32(payload.count))
            archive.appendUInt16(UInt16(nameData.count))
            archive.appendUInt16(0)
            archive.append(nameData)
            archive.append(payload)

            directory.appendUInt32(0x0201_4B50)        // central directory header
            directory.appendUInt16(20)                 // version made by
            directory.appendUInt16(20)                 // version needed
            directory.appendUInt16(0x0800)
            directory.appendUInt16(0)
            directory.appendUInt16(dosTime)
            directory.appendUInt16(dosDate)
            directory.appendUInt32(checksum)
            directory.appendUInt32(UInt32(payload.count))
            directory.appendUInt32(UInt32(payload.count))
            directory.appendUInt16(UInt16(nameData.count))
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt32(0)
            directory.appendUInt32(offset)
            directory.append(nameData)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendUInt32(0x0605_4B50)              // end of central directory
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entryCount))
        archive.appendUInt16(UInt16(entryCount))
        archive.appendUInt32(UInt32(directory.count))
        archive.appendUInt32(directoryOffset)
        archive.appendUInt16(0)
        return archive
    }

    /// MS-DOS date/time pair, in local time as the format requires.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current,
            from: date
        )
        let year = max(1980, parts.year ?? 1980)
        let month = min(12, max(1, parts.month ?? 1))
        let day = min(31, max(1, parts.day ?? 1))
        let hour = min(23, max(0, parts.hour ?? 0))
        let minute = min(59, max(0, parts.minute ?? 0))
        let second = min(59, max(0, parts.second ?? 0))
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return (dosTime, dosDate)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
