import Foundation
import Testing

@testable import ZislaKit

struct BrowserDownloadMetadataFixture {
    enum Storage: CaseIterable { case log, table, snappyOne, snappyTwo, snappyFour }
    struct Record {
        var key: String = "21_download,synthetic-guid"
        var sequence: UInt64 = 1
        var value: Data?
    }

    let history: BrowserDownloadHistoryFixture
    let directory: URL

    init(profile: String = "Google/Chrome/Default") throws {
        history = try BrowserDownloadHistoryFixture(historyPath: "\(profile)/History")
        directory = history.databaseURL.deletingLastPathComponent().appendingPathComponent("shared_proto_db", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ records: [Record], storage: Storage = .log) throws {
        try Data("MANIFEST-000001\n".utf8).write(to: directory.appendingPathComponent("CURRENT"))
        var manifest = Data([2, 2])
        if storage == .log {
            try Self.log(records.map(Self.batch)).write(to: directory.appendingPathComponent("000002.log"))
        } else {
            let table = Self.table(records, storage: storage)
            try table.write(to: directory.appendingPathComponent("000003.ldb"))
            manifest += Self.newTable(number: 3, size: table.count)
            try Data().write(to: directory.appendingPathComponent("000002.log"))
        }
        try Self.log([manifest]).write(to: directory.appendingPathComponent("MANIFEST-000001"))
    }

    static func download(current: String, target: String, state: UInt64 = 0, extra: Data = Data()) -> Data {
        let progress = field(13, pickle(current)) + field(14, pickle(target))
            + varint(21 << 3) + varint(state) + extra
        return field(1, field(1, Data("synthetic-guid".utf8)) + field(4, progress))
    }

    static func fixed(_ value: UInt64, count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    static func varint(_ value: UInt64) -> Data {
        var result = Data()
        var value = value
        while value >= 128 {
            result.append(UInt8(value & 127) | 128)
            value >>= 7
        }
        result.append(UInt8(value))
        return result
    }

    static func field(_ number: Int, _ data: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(data.count)) + data
    }

    static func pickle(_ path: String) -> Data {
        let bytes = Data(path.utf8)
        let payload = fixed(UInt64(bytes.count), count: 4) + bytes
            + Data(repeating: 0, count: (4 - bytes.count % 4) % 4)
        return fixed(UInt64(payload.count), count: 4) + payload
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = ~0
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0x82f6_3b78 : 0) }
        }
        crc = ~crc
        return ((crc >> 15) | (crc << 17)) &+ 0xa282_ead8
    }

    static func physical(_ data: Data, kind: UInt8 = 1) -> Data {
        fixed(UInt64(checksum(Data([kind]) + data)), count: 4)
            + fixed(UInt64(data.count), count: 2) + Data([kind]) + data
    }

    static func log(_ payloads: [Data]) -> Data {
        var result = Data()
        for payload in payloads {
            var offset = 0
            repeat {
                var available = 32768 - result.count % 32768
                if available < 7 {
                    result += Data(repeating: 0, count: available)
                    available = 32768
                }
                let length = min(available - 7, payload.count - offset)
                let first = offset == 0
                let last = offset + length == payload.count
                let kind: UInt8 = first ? (last ? 1 : 2) : (last ? 4 : 3)
                result += physical(payload.subdata(in: offset..<(offset + length)), kind: kind)
                offset += length
            } while offset < payload.count
        }
        return result
    }

    static func batch(_ record: Record) -> Data {
        let key = Data(record.key.utf8)
        var batch = fixed(record.sequence, count: 8) + fixed(1, count: 4)
            + Data([record.value == nil ? 0 : 1]) + varint(UInt64(key.count)) + key
        if let value = record.value { batch += varint(UInt64(value.count)) + value }
        return batch
    }

    static func newTable(number: UInt64, size: Int) -> Data {
        let boundary = Data("boundary".utf8) + fixed(1, count: 8)
        return Data([7, 0]) + varint(number) + varint(UInt64(size))
            + varint(UInt64(boundary.count)) + boundary + varint(UInt64(boundary.count)) + boundary
    }

    static func table(_ records: [Record], storage: Storage = .table) -> Data {
        var result = Data()
        var index: [(Data, Data)] = []
        // Multiple data blocks exercise index traversal and prefix-compressed keys.
        for start in stride(from: 0, to: records.count, by: 3) {
            let entries = records[start..<min(start + 3, records.count)].map { record in
                (Data(record.key.utf8) + fixed((record.sequence << 8) | (record.value == nil ? 0 : 1), count: 8), record.value ?? Data())
            }
            let data = block(entries)
            let encoded = storage == .table ? data : snappy(data, storage: storage)
            let kind: UInt8 = storage == .table ? 0 : 1
            let handle = varint(UInt64(result.count)) + varint(UInt64(encoded.count))
            result += encoded + Data([kind]) + fixed(UInt64(checksum(encoded + Data([kind]))), count: 4)
            index.append((entries.last!.0, handle))
        }
        let meta = block([])
        let metaHandle = varint(UInt64(result.count)) + varint(UInt64(meta.count))
        result += meta + Data([0]) + fixed(UInt64(checksum(meta + Data([0]))), count: 4)
        let indexBlock = block(index)
        let indexHandle = varint(UInt64(result.count)) + varint(UInt64(indexBlock.count))
        result += indexBlock + Data([0]) + fixed(UInt64(checksum(indexBlock + Data([0]))), count: 4)
        let handles = metaHandle + indexHandle
        result += handles + Data(repeating: 0, count: 40 - handles.count) + fixed(0xdb47_7524_8b80_fb57, count: 8)
        return result
    }

    private static func block(_ entries: [(Data, Data)]) -> Data {
        var result = Data()
        var previous = Data()
        for (key, value) in entries {
            let shared = zip(previous, key).prefix(while: { $0 == $1 }).count
            result += varint(UInt64(shared)) + varint(UInt64(key.count - shared)) + varint(UInt64(value.count))
                + key.dropFirst(shared) + value
            previous = key
        }
        return result + fixed(0, count: 4) + fixed(1, count: 4)
    }

    private static func snappy(_ data: Data, storage: Storage) -> Data {
        let bytes = [UInt8](data)
        var result = varint(UInt64(bytes.count))
        func literal(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            let code = range.count - 1
            if code < 60 {
                result.append(UInt8(code << 2))
            } else {
                let size = (Int.bitWidth - code.leadingZeroBitCount + 7) / 8
                result.append(UInt8((59 + size) << 2))
                result += fixed(UInt64(code), count: size)
            }
            result += Data(bytes[range])
        }
        var pending = 0
        var offset = 0
        while offset < bytes.count {
            var end = offset + 1
            while end < bytes.count && bytes[end] == bytes[offset] { end += 1 }
            if end - offset >= 5 {
                literal(pending..<(offset + 1))
                offset += 1
                while end - offset >= 4 {
                    let length = min(end - offset, storage == .snappyOne ? 11 : 64)
                    switch storage {
                    case .snappyOne: result += Data([UInt8((length - 4) << 2 | 1), 1])
                    case .snappyTwo: result += Data([UInt8((length - 1) << 2 | 2), 1, 0])
                    default: result += Data([UInt8((length - 1) << 2 | 3), 1, 0, 0, 0])
                    }
                    offset += length
                }
                pending = offset
            }
            offset = end
        }
        literal(pending..<bytes.count)
        return result
    }
}

struct BrowserDownloadMetadataReaderTests {
    @Test(arguments: [
        (BrowserDownloadAgent.chrome, "Google/Chrome/Profile 1"),
        (.edge, "Microsoft Edge/Default"),
        (.brave, "BraveSoftware/Brave-Browser/Default"),
        (.arc, "Arc/User Data/Default"),
        (.vivaldi, "Vivaldi/Default"),
        (.opera, "com.operasoftware.Opera"),
    ])
    func chromiumFamilyProfilesResolveCurrentMetadata(agent: BrowserDownloadAgent, profile: String) throws {
        let fixture = try BrowserDownloadMetadataFixture(profile: profile)
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/Cursor.dmg"))])
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: agent])[fixture.history.temporaryURL] == "Cursor.dmg")
    }

    @Test(arguments: BrowserDownloadMetadataFixture.Storage.allCases)
    func currentChromeDownloadUsesItsTargetBeforeHistoryIsWritten(storage: BrowserDownloadMetadataFixture.Storage) throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let current = fixture.history.temporaryURL
        let target = fixture.history.root.appendingPathComponent("Downloads/Cursor-darwin-arm64.dmg").path
        let extra = BrowserDownloadMetadataFixture.field(1, Data(repeating: 120, count: 800))
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(current: current.path, target: target, extra: extra))], storage: storage)
        let before = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let contents = try before.map { try Data(contentsOf: $0) }
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home, temporaryDirectory: fixture.history.root)
            .fileNames(for: [current: .chrome])
        #expect(names[current] == "Cursor-darwin-arm64.dmg")
        #expect(!FileManager.default.fileExists(atPath: fixture.history.databaseURL.path))
        #expect(try before.map { try Data(contentsOf: $0) } == contents)
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).count == before.count)
    }

    @Test(arguments: [false, true])
    func latestRecordsAndTombstonesOverrideOlderTableAndHistory(deleted: Bool) throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let current = fixture.history.temporaryURL
        try fixture.history.insertDownload(targetPath: "/Downloads/stale-history.dmg")
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/stale-table.dmg"))], storage: .snappyTwo)
        let latest = BrowserDownloadMetadataFixture.Record(sequence: 20,
            value: deleted ? nil : BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/Cursor.dmg"))
        let old = BrowserDownloadMetadataFixture.Record(sequence: 3,
            value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/stale-log.dmg"))
        try BrowserDownloadMetadataFixture.log([BrowserDownloadMetadataFixture.batch(latest), BrowserDownloadMetadataFixture.batch(old)])
            .write(to: fixture.directory.appendingPathComponent("000002.log"))
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home).fileNames(for: [current: .chrome])
        #expect(names[current] == (deleted ? nil : "Cursor.dmg"))
    }

    @Test(arguments: [1, 2, 3, 4])
    func terminalRecordsCannotReviveStaleActiveHistory(state: UInt64) throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.history.insertDownload(targetPath: "/Downloads/stale.dmg")
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/old.dmg", state: state))])
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
    }

    @Test
    func unrelatedClientsDoNotPreventLegacyHistoryResolution() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.history.insertDownload(targetPath: "/Downloads/Cursor.dmg")
        try fixture.write([.init(key: "20_other-client", value: Data([255, 255]))])
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome])[fixture.history.temporaryURL] == "Cursor.dmg")
    }

    @Test
    func anotherLevelDBClientCannotSupplyADownloadName() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.write([.init(key: "20_other-client", value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/unrelated.dmg"))])
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
    }

    @Test
    func unrelatedDownloadTargetsAreNotDecodedOrReturned() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let current = fixture.history.temporaryURL
        let malformedProgress = BrowserDownloadMetadataFixture.field(13, BrowserDownloadMetadataFixture.pickle("/Other/Unconfirmed.crdownload"))
            + BrowserDownloadMetadataFixture.field(14, Data([255])) + Data([168, 1, 0])
        try fixture.write([
            .init(value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/Cursor.dmg")),
            .init(key: "21_download,other-guid", sequence: 2,
                value: BrowserDownloadMetadataFixture.field(1, BrowserDownloadMetadataFixture.field(4, malformedProgress))),
        ])
        let rows = try BrowserDownloadMetadataReader.rows(at: fixture.directory, currentPaths: [current.path])
        #expect(rows == [["current_path": current.path, "target_path": "/Downloads/Cursor.dmg"]])
    }

    @Test
    func concurrentUnicodeDownloadsKeepExactPathsAcrossMultipleDataBlocks() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        var records: [BrowserDownloadMetadataFixture.Record] = []
        var downloads: [URL: BrowserDownloadAgent] = [:]
        var expected: [URL: String] = [:]
        for index in 0..<8 {
            let current = fixture.history.temporaryURL.deletingLastPathComponent().appendingPathComponent("未确认 '\(index)'😺.crdownload")
            let target = "学习资料 '\(index)'😺.zip"
            records.append(.init(key: "21_download,guid-\(index)", sequence: UInt64(index + 1),
                value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/\(target)")))
            downloads[current] = .chrome
            expected[current] = target
        }
        records.append(.init(key: "20_other", value: Data([0xff])))
        try fixture.write(records, storage: .snappyOne)
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home).fileNames(for: downloads) == expected)
    }

    @Test
    func fragmentedLogAndPartiallyAppendedTailKeepCompletedRecords() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let record = BrowserDownloadMetadataFixture.Record(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/Cursor.dmg",
            extra: BrowserDownloadMetadataFixture.field(1, Data(repeating: 120, count: 90_000))))
        try fixture.write([record])
        let log = fixture.directory.appendingPathComponent("000002.log")
        let tail = BrowserDownloadMetadataFixture.physical(BrowserDownloadMetadataFixture.batch(.init(sequence: 50, value: nil)))
        let original = try Data(contentsOf: log)
        try (original + tail.prefix(12)).write(to: log)
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome])[fixture.history.temporaryURL] == "Cursor.dmg")
        try (original + tail).write(to: log)
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
    }

    @Test
    func manifestDeletionIgnoresObsoleteTablesAndOldLogs() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let current = fixture.history.temporaryURL
        try fixture.write([.init(sequence: 99, value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/obsolete.dmg"))], storage: .table)
        let live = BrowserDownloadMetadataFixture.table([.init(sequence: 5,
            value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/Cursor.dmg"))])
        try live.write(to: fixture.directory.appendingPathComponent("000004.ldb"))
        let initial = Data([2, 2]) + BrowserDownloadMetadataFixture.newTable(number: 3, size: 1)
        let edit = Data([6, 0, 3, 2, 6]) + BrowserDownloadMetadataFixture.newTable(number: 4, size: live.count)
        try BrowserDownloadMetadataFixture.log([initial, edit]).write(to: fixture.directory.appendingPathComponent("MANIFEST-000001"))
        try BrowserDownloadMetadataFixture.log([BrowserDownloadMetadataFixture.batch(.init(sequence: 100,
            value: BrowserDownloadMetadataFixture.download(current: current.path, target: "/Downloads/obsolete-log.dmg")))])
            .write(to: fixture.directory.appendingPathComponent("000002.log"))
        try Data().write(to: fixture.directory.appendingPathComponent("000006.log"))
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home).fileNames(for: [current: .chrome])[current] == "Cursor.dmg")
    }

    @Test
    func missingTableRejectsAnIncompleteDatabaseSnapshot() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/older.dmg"))], storage: .table)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("000003.ldb"))
        try BrowserDownloadMetadataFixture.log([BrowserDownloadMetadataFixture.batch(.init(sequence: 5,
            value: BrowserDownloadMetadataFixture.download(current: fixture.history.temporaryURL.path, target: "/Downloads/Cursor.dmg")))])
            .write(to: fixture.directory.appendingPathComponent("000002.log"))
        #expect(throws: BrowserDownloadMetadataReader.ReadError.self) {
            try BrowserDownloadMetadataReader.rows(at: fixture.directory, currentPaths: [fixture.history.temporaryURL.path])
        }
    }

    @Test(arguments: ["", "relative.dmg", "/", "/Downloads/Unconfirmed 1.crdownload", "/Downloads/\u{0}hidden.dmg"])
    func invalidTargetsCannotReplaceTheTemporaryName(target: String) throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.write([.init(value: BrowserDownloadMetadataFixture.download(current: fixture.history.temporaryURL.path, target: target))])
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
    }

    @Test(arguments: ["checksum", "tableChecksum", "missingTable", "badProto", "badVarint", "badCount", "badFragment", "manifestPath", "symlink"])
    func malformedOrUnavailableMetadataDoesNotWriteToTheBrowser(failure: String) throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let record = BrowserDownloadMetadataFixture.Record(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/Cursor.dmg"))
        try fixture.write([record], storage: failure == "tableChecksum" || failure == "missingTable" ? .snappyTwo : .log)
        let log = fixture.directory.appendingPathComponent("000002.log")
        switch failure {
        case "checksum":
            var data = try Data(contentsOf: log)
            data[0] ^= 1
            try data.write(to: log)
        case "tableChecksum":
            let table = fixture.directory.appendingPathComponent("000003.ldb")
            var data = try Data(contentsOf: table)
            data[data.count - 49] ^= 1
            try data.write(to: table)
        case "missingTable": try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("000003.ldb"))
        case "badProto": try fixture.write([.init(value: Data([10, 255]))])
        case "badVarint": try BrowserDownloadMetadataFixture.physical(Data(repeating: 255, count: 20)).write(to: fixture.directory.appendingPathComponent("MANIFEST-000001"))
        case "badCount":
            var batch = BrowserDownloadMetadataFixture.batch(record)
            batch[8] = 2
            try BrowserDownloadMetadataFixture.physical(batch).write(to: log)
        case "badFragment": try BrowserDownloadMetadataFixture.physical(BrowserDownloadMetadataFixture.batch(record), kind: 4).write(to: log)
        case "manifestPath":
            try BrowserDownloadMetadataFixture.physical(Data([2, 2]))
                .write(to: fixture.directory.deletingLastPathComponent().appendingPathComponent("outside"))
            try Data("../outside\n".utf8).write(to: fixture.directory.appendingPathComponent("CURRENT"))
        case "symlink":
            let outside = fixture.history.root.appendingPathComponent("outside.log")
            try FileManager.default.moveItem(at: log, to: outside)
            try FileManager.default.createSymbolicLink(at: log, withDestinationURL: outside)
        default: Issue.record("Unknown failure fixture")
        }
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let before = try files.map { try Data(contentsOf: $0) }
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home, temporaryDirectory: fixture.history.root)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).count == files.count)
    }

    @Test
    func oversizedMetadataFailsWithinTheReadBudget() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        try fixture.write([])
        let file = try FileHandle(forWritingTo: fixture.directory.appendingPathComponent("000002.log"))
        try file.truncate(atOffset: 16 * 1024 * 1024 + 1)
        try file.close()
        #expect(throws: BrowserDownloadMetadataReader.ReadError.self) {
            try BrowserDownloadMetadataReader.rows(at: fixture.directory, currentPaths: [fixture.history.temporaryURL.path])
        }
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
            .fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
    }

    @Test
    func seededMutationsAreRejectedWithoutCrashingOrWritingFiles() throws {
        let fixture = try BrowserDownloadMetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.history.root) }
        let resolver = BrowserDownloadFileNameResolver(homeDirectory: fixture.history.home)
        let record = BrowserDownloadMetadataFixture.Record(value: BrowserDownloadMetadataFixture.download(
            current: fixture.history.temporaryURL.path, target: "/Downloads/Cursor.dmg"))
        try fixture.write([record])
        let batch = BrowserDownloadMetadataFixture.batch(record)
        let log = fixture.directory.appendingPathComponent("000002.log")
        var seed: UInt64 = 0x569731
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let length = Int((seed >> 32) % UInt64(batch.count))
            let truncated = BrowserDownloadMetadataFixture.physical(Data(batch.prefix(length)))
            try truncated.write(to: log)
            #expect(resolver.fileNames(for: [fixture.history.temporaryURL: .chrome]).isEmpty)
            #expect(try Data(contentsOf: log) == truncated)
        }
    }
}
