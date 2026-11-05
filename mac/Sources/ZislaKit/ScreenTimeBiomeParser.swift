import Foundation
import zlib

// Adapted from nichtlegacy/screentime and CCL Forensics' ccl_segb, both MIT licensed.
// Source revision and notices ship in ThirdPartyLicenses/ScreenTime.txt.
enum ScreenTimeBiomeParser {
    struct Transition: Equatable, Sendable {
        var date: Date
        var bundleID: String
        var gainedFocus: Bool
    }

    enum ParseError: Error { case malformed, unsupported, tooLarge }

    static func transitions(in data: Data) throws -> [Transition] {
        guard data.count <= 16 * 1024 * 1024 else { throw ParseError.tooLarge }
        let bytes = [UInt8](data)
        let records: [Data]
        if bytes.count >= 56, Array(bytes[52..<56]) == Array("SEGB".utf8) {
            records = try versionOne(bytes)
        } else if bytes.count >= 32, Array(bytes[0..<4]) == Array("SEGB".utf8) {
            records = try versionTwo(bytes)
        } else {
            throw ParseError.unsupported
        }
        return records.compactMap(transition)
    }

    private static func versionOne(_ bytes: [UInt8]) throws -> [Data] {
        let limit = Int(try integer(bytes, at: 0, count: 4))
        guard limit >= 56, limit <= bytes.count else { throw ParseError.malformed }
        var offset = 56
        var records: [Data] = []
        while offset < limit {
            guard offset <= limit - 32 else { throw ParseError.malformed }
            let size = Int(try integer(bytes, at: offset, count: 4))
            let state = try integer(bytes, at: offset + 4, count: 4)
            let checksum = try integer(bytes, at: offset + 24, count: 4)
            let start = offset + 32
            guard size <= limit - start else { throw ParseError.malformed }
            let payload = Data(bytes[start..<(start + size)])
            if state == 1, crc(payload) == checksum { records.append(payload) }
            offset = (start + size + 7) & ~7
        }
        return records
    }

    private static func versionTwo(_ bytes: [UInt8]) throws -> [Data] {
        let count = Int(try integer(bytes, at: 4, count: 4))
        guard count <= (bytes.count - 32) / 16 else { throw ParseError.malformed }
        let trailer = bytes.count - count * 16
        var states: [Int: UInt64] = [:]
        for index in 0..<count {
            let entry = trailer + index * 16
            let end = Int(try integer(bytes, at: entry, count: 4)) + 32
            let state = try integer(bytes, at: entry + 4, count: 4)
            if state == 0 || state == 4 { continue }
            guard end <= trailer, end >= 40 else { throw ParseError.malformed }
            // A deletion invalidates every trailer reference to the same record.
            states[end] = states[end] == 3 ? 3 : state
        }
        var offset = 32
        var records: [Data] = []
        for end in states.keys.sorted() {
            if end < offset + 8 { continue }
            let checksum = try integer(bytes, at: offset, count: 4)
            let payload = Data(bytes[(offset + 8)..<end])
            if states[end] == 1, crc(payload) == checksum { records.append(payload) }
            offset = (end + 3) & ~3
        }
        return records
    }

    static func transition(_ data: Data) -> Transition? {
        let bytes = [UInt8](data)
        var offset = 0
        var focus: UInt64?
        var timestamp: Double?
        var bundle: String?
        do {
            while offset < bytes.count {
                let key = try varint(bytes, offset: &offset)
                let number = key >> 3
                guard number > 0 else { return nil }
                switch key & 7 {
                case 0:
                    let value = try varint(bytes, offset: &offset)
                    if number == 3 { focus = value }
                case 1:
                    let value = try integer(bytes, at: offset, count: 8)
                    offset += 8
                    if number == 4 { timestamp = Double(bitPattern: value) }
                case 2:
                    let size = try varint(bytes, offset: &offset)
                    guard size <= UInt64(bytes.count - offset) else { return nil }
                    if number == 6 {
                        guard size <= 512 else { return nil }
                        bundle = String(bytes: bytes[offset..<(offset + Int(size))], encoding: .utf8)
                    }
                    offset += Int(size)
                case 5:
                    _ = try integer(bytes, at: offset, count: 4)
                    offset += 4
                default: return nil
                }
            }
        } catch { return nil }
        guard let timestamp, timestamp.isFinite, (0...4_000_000_000).contains(timestamp),
              let bundle, !bundle.isEmpty, let focus, focus <= 1 else { return nil }
        return Transition(date: Date(timeIntervalSinceReferenceDate: timestamp), bundleID: bundle, gainedFocus: focus == 1)
    }

    private static func varint(_ bytes: [UInt8], offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 70, by: 7) {
            guard offset < bytes.count else { throw ParseError.malformed }
            let byte = bytes[offset]
            offset += 1
            guard shift < 63 || byte <= 1 else { throw ParseError.malformed }
            value |= UInt64(byte & 0x7f) << shift
            if byte < 0x80 { return value }
        }
        throw ParseError.malformed
    }

    private static func integer(_ bytes: [UInt8], at offset: Int, count: Int) throws -> UInt64 {
        guard offset >= 0, offset <= bytes.count - count else { throw ParseError.malformed }
        var value: UInt64 = 0
        for index in 0..<count { value |= UInt64(bytes[offset + index]) << (index * 8) }
        return value
    }

    private static func crc(_ data: Data) -> UInt64 {
        data.withUnsafeBytes { buffer in
            UInt64(crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
    }
}
