import Darwin
import Foundation

// Chromium 157 stores active downloads as DownloadDBEntry protos in LevelDB client 21.
// Read its immutable tables and append-only log without opening or locking the browser's database.
enum BrowserDownloadMetadataReader {
    enum ReadError: Error { case malformed, unavailable, tooLarge, unsupported }

    private static let maximumBytes = 16 * 1024 * 1024
    private static let downloadPrefix = Array("21_download,".utf8)

    private struct Record {
        var sequence: UInt64
        var value: [UInt8]?
    }

    static func rows(at directory: URL, currentPaths: Set<String>) throws -> [[String: String]]? {
        var budget = 64 * 1024 * 1024
        let current = try read(directory.appendingPathComponent("CURRENT"), budget: &budget)
        guard let manifestName = String(bytes: current, encoding: .utf8),
            manifestName.range(of: #"^MANIFEST-[0-9]+\n$"#, options: .regularExpression) != nil
        else { throw ReadError.malformed }
        let manifest = try read(directory.appendingPathComponent(String(manifestName.dropLast())), budget: &budget)
        var tables: Set<UInt64> = []
        var logNumber: UInt64?
        var previousLog: UInt64 = 0
        for edit in try logRecords(manifest) {
            var cursor = Cursor(edit)
            while cursor.remaining > 0 {
                switch try cursor.varint() {
                case 1: _ = try cursor.lengthPrefixed()
                case 2: logNumber = try cursor.varint()
                case 3, 4: _ = try cursor.varint()
                case 5:
                    _ = try cursor.varint()
                    _ = try cursor.lengthPrefixed()
                case 6:
                    _ = try cursor.varint()
                    tables.remove(try cursor.varint())
                case 7:
                    _ = try cursor.varint()
                    tables.insert(try cursor.varint())
                    _ = try cursor.varint()
                    _ = try cursor.lengthPrefixed()
                    _ = try cursor.lengthPrefixed()
                case 9: previousLog = try cursor.varint()
                default: throw ReadError.unsupported
                }
            }
        }
        guard let logNumber else { throw ReadError.malformed }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var remainingTables = tables
        var records: [[UInt8]: Record] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let number = UInt64(file.deletingPathExtension().lastPathComponent) else { continue }
            switch file.pathExtension {
            case "log" where number >= logNumber || number == previousLog:
                for batch in try logRecords(read(file, budget: &budget)) {
                    var cursor = Cursor(batch)
                    let sequence = try cursor.integer(count: 8)
                    let count = try cursor.integer(count: 4)
                    guard count <= UInt64(cursor.remaining / 2),
                        sequence <= 0x00ff_ffff_ffff_ffff - count
                    else { throw ReadError.malformed }
                    for index in 0..<count {
                        let kind = try cursor.integer(count: 1)
                        guard kind <= 1 else { throw ReadError.unsupported }
                        let key = try cursor.lengthPrefixed()
                        let value = kind == 1 ? try cursor.lengthPrefixed() : nil
                        try merge(key, record: Record(sequence: sequence + index, value: value), into: &records)
                    }
                    guard cursor.remaining == 0 else { throw ReadError.malformed }
                }
            case "ldb" where tables.contains(number):
                let data = try read(file, budget: &budget)
                guard data.count >= 48 else { throw ReadError.malformed }
                var footer = Cursor(data, offset: data.count - 48)
                _ = try footer.varint()
                _ = try footer.varint()
                let indexOffset = try footer.varint()
                let indexSize = try footer.varint()
                var magic = Cursor(data, offset: data.count - 8)
                guard try magic.integer(count: 8) == 0xdb47_7524_8b80_fb57 else { throw ReadError.malformed }
                let index = try block(data, offset: indexOffset, size: indexSize, budget: &budget)
                for (_, handle) in try blockEntries(index) {
                    var cursor = Cursor(handle)
                    let offset = try cursor.varint()
                    let size = try cursor.varint()
                    guard cursor.remaining == 0 else { throw ReadError.malformed }
                    for (internalKey, value) in try blockEntries(block(data, offset: offset, size: size, budget: &budget)) {
                        guard internalKey.count >= 8 else { throw ReadError.malformed }
                        var trailer = Cursor(internalKey, offset: internalKey.count - 8)
                        let version = try trailer.integer(count: 8)
                        let kind = version & 0xff
                        guard kind <= 1 else { throw ReadError.unsupported }
                        try merge(Array(internalKey.dropLast(8)),
                            record: Record(sequence: version >> 8, value: kind == 1 ? value : nil), into: &records)
                    }
                }
                remainingTables.remove(number)
            default: continue
            }
        }
        guard remainingTables.isEmpty else { throw ReadError.unavailable }
        guard !records.isEmpty else { return nil }
        return try records.values.compactMap { record in
            guard let value = record.value,
                case let .bytes(info)? = try fields(value)[1],
                case let .bytes(progress)? = try fields(info)[4]
            else { return nil }
            let fields = try fields(progress)
            guard case .integer(0)? = fields[21],
                case let .bytes(current)? = fields[13]
            else { return nil }
            let currentPath = try path(current)
            guard currentPaths.contains(currentPath), case let .bytes(target)? = fields[14] else { return nil }
            return ["current_path": currentPath, "target_path": try path(target)]
        }
    }

    private static func merge(_ key: [UInt8], record: Record, into records: inout [[UInt8]: Record]) throws {
        guard key.starts(with: downloadPrefix) else { return }
        if let previous = records[key] {
            if previous.sequence >= record.sequence { return }
        }
        records[key] = record
    }

    private static func read(_ url: URL, budget: inout Int) throws -> [UInt8] {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ReadError.unavailable }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { throw ReadError.unavailable }
        guard metadata.st_size >= 0, metadata.st_size <= maximumBytes, metadata.st_size <= budget else { throw ReadError.tooLarge }
        let size = Int(metadata.st_size)
        budget -= size
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).read(upToCount: size) ?? Data()
        guard data.count == size else { throw ReadError.unavailable }
        return [UInt8](data)
    }

    private static func logRecords(_ data: [UInt8]) throws -> [[UInt8]] {
        var offset = 0
        var fragment: [UInt8]?
        var records: [[UInt8]] = []
        while offset < data.count {
            let blockRemaining = 32768 - offset % 32768
            if blockRemaining < 7 { offset += blockRemaining; continue }
            // A running browser may still be appending the last physical record.
            if data.count - offset < 7 { break }
            var cursor = Cursor(data, offset: offset)
            let checksum = try cursor.integer(count: 4)
            let length = Int(try cursor.integer(count: 2))
            let kind = try cursor.integer(count: 1)
            if kind == 0 && length == 0 {
                let end = min(offset + blockRemaining, data.count)
                guard data[offset..<end].allSatisfy({ $0 == 0 }) else { throw ReadError.malformed }
                offset = end
                continue
            }
            guard length <= blockRemaining - 7 else { throw ReadError.malformed }
            if length > cursor.remaining { break }
            let end = offset + 7 + length
            guard UInt64(maskedCRC(data[(offset + 6)..<end])) == checksum else { throw ReadError.malformed }
            let payload = Array(data[(offset + 7)..<end])
            switch kind {
            case 1:
                guard fragment == nil else { throw ReadError.malformed }
                records.append(payload)
            case 2:
                guard fragment == nil else { throw ReadError.malformed }
                fragment = payload
            case 3, 4:
                guard fragment != nil else { throw ReadError.malformed }
                fragment?.append(contentsOf: payload)
                if kind == 4 { records.append(fragment!); fragment = nil }
            default: throw ReadError.unsupported
            }
            offset = end
        }
        return records
    }

    private static func block(_ data: [UInt8], offset: UInt64, size: UInt64, budget: inout Int) throws -> [UInt8] {
        guard data.count >= 53, offset <= UInt64(data.count - 53),
            size <= UInt64(data.count - 53) - offset
        else { throw ReadError.malformed }
        let start = Int(offset)
        let end = start + Int(size)
        var checksum = Cursor(data, offset: end + 1)
        guard UInt64(maskedCRC(data[start...end])) == (try checksum.integer(count: 4)) else { throw ReadError.malformed }
        switch data[end] {
        case 0: return Array(data[start..<end])
        case 1:
            var cursor = Cursor(Array(data[start..<end]))
            let expected = try cursor.varint()
            guard expected <= maximumBytes, expected <= budget else { throw ReadError.tooLarge }
            budget -= Int(expected)
            var output: [UInt8] = []
            while cursor.remaining > 0 {
                let tag = try cursor.integer(count: 1)
                let code = tag >> 2
                if tag & 3 == 0 {
                    let length = code < 60 ? code + 1 : try cursor.integer(count: Int(code - 59)) + 1
                    guard length <= expected - UInt64(output.count) else { throw ReadError.malformed }
                    output += try cursor.bytes(count: length)
                } else {
                    let length = tag & 3 == 1 ? 4 + ((tag >> 2) & 7) : code + 1
                    let distance = tag & 3 == 1
                        ? ((tag & 0xe0) << 3) | (try cursor.integer(count: 1))
                        : try cursor.integer(count: tag & 3 == 2 ? 2 : 4)
                    guard distance > 0, distance <= output.count, length <= expected - UInt64(output.count)
                    else { throw ReadError.malformed }
                    for _ in 0..<length { output.append(output[output.count - Int(distance)]) }
                }
            }
            guard output.count == expected else { throw ReadError.malformed }
            return output
        default: throw ReadError.unsupported
        }
    }

    private static func blockEntries(_ data: [UInt8]) throws -> [([UInt8], [UInt8])] {
        guard data.count >= 4 else { throw ReadError.malformed }
        var trailer = Cursor(data, offset: data.count - 4)
        let count = try trailer.integer(count: 4)
        guard count <= (data.count - 4) / 4 else { throw ReadError.malformed }
        var cursor = Cursor(data, limit: data.count - 4 - Int(count) * 4)
        var key: [UInt8] = []
        var entries: [([UInt8], [UInt8])] = []
        while cursor.remaining > 0 {
            let shared = try cursor.varint()
            let unshared = try cursor.varint()
            let valueLength = try cursor.varint()
            guard shared <= key.count else { throw ReadError.malformed }
            key = Array(key.prefix(Int(shared))) + (try cursor.bytes(count: unshared))
            entries.append((key, try cursor.bytes(count: valueLength)))
        }
        return entries
    }

    private enum Field { case bytes([UInt8]), integer(UInt64) }

    private static func fields(_ data: [UInt8]) throws -> [UInt64: Field] {
        var cursor = Cursor(data)
        var fields: [UInt64: Field] = [:]
        while cursor.remaining > 0 {
            let key = try cursor.varint()
            guard key >> 3 > 0 else { throw ReadError.malformed }
            switch key & 7 {
            case 0: fields[key >> 3] = .integer(try cursor.varint())
            case 1: _ = try cursor.integer(count: 8)
            case 2: fields[key >> 3] = .bytes(try cursor.lengthPrefixed())
            case 5: _ = try cursor.integer(count: 4)
            default: throw ReadError.unsupported
            }
        }
        return fields
    }

    private static func path(_ data: [UInt8]) throws -> String {
        var cursor = Cursor(data)
        let payloadSize = try cursor.integer(count: 4)
        guard payloadSize == cursor.remaining else { throw ReadError.malformed }
        let length = try cursor.integer(count: 4)
        let bytes = try cursor.bytes(count: length)
        guard cursor.remaining == (4 - Int(length) % 4) % 4,
            !bytes.contains(0), let path = String(bytes: bytes, encoding: .utf8)
        else { throw ReadError.malformed }
        return path
    }

    private struct Cursor {
        let data: [UInt8]
        var offset: Int
        let limit: Int
        var remaining: Int { limit - offset }

        init(_ data: [UInt8], offset: Int = 0, limit: Int? = nil) {
            self.data = data
            self.offset = offset
            self.limit = limit ?? data.count
        }

        mutating func integer(count: Int) throws -> UInt64 {
            guard remaining >= count else { throw ReadError.malformed }
            var value: UInt64 = 0
            for index in 0..<count { value |= UInt64(data[offset + index]) << (index * 8) }
            offset += count
            return value
        }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 70, by: 7) {
                let byte = try integer(count: 1)
                guard shift < 63 || byte <= 1 else { throw ReadError.malformed }
                value |= (byte & 127) << shift
                if byte < 128 { return value }
            }
            throw ReadError.malformed
        }

        mutating func bytes(count: UInt64) throws -> [UInt8] {
            guard count <= remaining else { throw ReadError.malformed }
            defer { offset += Int(count) }
            return Array(data[offset..<(offset + Int(count))])
        }

        mutating func lengthPrefixed() throws -> [UInt8] {
            let count = try varint()
            return try bytes(count: count)
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { byte in
        var value = UInt32(byte)
        for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0x82f6_3b78 : 0) }
        return value
    }

    private static func maskedCRC(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = ~0
        for byte in bytes { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        crc = ~crc
        return ((crc >> 15) | (crc << 17)) &+ 0xa282_ead8
    }
}
