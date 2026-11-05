import Foundation
import SQLite3
import Testing
import zlib
import ZislaCore
@testable import ZislaKit

struct DailyBriefingScreenTimeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 815_500_000)

    private func integer(_ value: UInt64, bytes: Int) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private func payload(at date: Date, bundle: String = "com.example.editor", gained: Bool = true) -> Data {
        let name = Data(bundle.utf8)
        return Data([24, gained ? 1 : 0, 33])
            + integer(date.timeIntervalSinceReferenceDate.bitPattern, bytes: 8)
            + Data([50, UInt8(name.count)]) + name
    }

    private func checksum(_ data: Data) -> UInt64 {
        data.withUnsafeBytes { UInt64(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
    }

    private func segment(_ payloads: [Data], version: Int = 2, states: [UInt64]? = nil) -> Data {
        if version == 1 {
            var result = Data(repeating: 0, count: 52) + Data("SEGB".utf8)
            for (index, payload) in payloads.enumerated() {
                result += integer(UInt64(payload.count), bytes: 4)
                    + integer(states?[index] ?? 1, bytes: 4)
                    + Data(repeating: 0, count: 16)
                    + integer(checksum(payload), bytes: 4) + Data(repeating: 0, count: 4) + payload
                while !result.count.isMultiple(of: 8) { result.append(0) }
            }
            result.replaceSubrange(0..<4, with: integer(UInt64(result.count), bytes: 4))
            return result
        }
        var result = Data("SEGB".utf8) + integer(UInt64(payloads.count), bytes: 4) + Data(repeating: 0, count: 24)
        var trailer = Data()
        for (index, payload) in payloads.enumerated() {
            result += integer(checksum(payload), bytes: 4) + Data(repeating: 0, count: 4) + payload
            trailer += integer(UInt64(result.count - 32), bytes: 4)
                + integer(states?[index] ?? 1, bytes: 4) + Data(repeating: 0, count: 8)
            while !result.count.isMultiple(of: 4) { result.append(0) }
        }
        return result + trailer
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-system-time-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [1, 2])
    func segbVersionsReadOnlyWrittenChecksummedRecords(version: Int) throws {
        let gain = payload(at: start)
        let loss = payload(at: start.addingTimeInterval(60), gained: false)
        let data = segment([gain, loss, gain], version: version, states: [1, 1, 3])
        let transitions = try ScreenTimeBiomeParser.transitions(in: data)
        #expect(transitions.count == 2)
        #expect(transitions.first?.bundleID == "com.example.editor")
        #expect(transitions.last?.gainedFocus == false)
        let intervals = DailyBriefingScreenTimeReader.intervals(from: transitions, deviceID: "phone")
        #expect(intervals == [.init(deviceID: "phone", bundleID: "com.example.editor", start: start, end: start.addingTimeInterval(60))])
        var damaged = segment([gain], version: version)
        damaged[version == 1 ? 88 : 40] ^= 1
        #expect(try ScreenTimeBiomeParser.transitions(in: damaged).isEmpty)
    }

    @Test
    func repeatedGainsAndUnmatchedLossesDoNotInventActivity() {
        let a = ScreenTimeBiomeParser.Transition(date: start, bundleID: "A", gainedFocus: true)
        let repeated = ScreenTimeBiomeParser.Transition(date: start.addingTimeInterval(10), bundleID: "A", gainedFocus: true)
        let unrelated = ScreenTimeBiomeParser.Transition(date: start.addingTimeInterval(20), bundleID: "B", gainedFocus: false)
        let switched = ScreenTimeBiomeParser.Transition(date: start.addingTimeInterval(30), bundleID: "B", gainedFocus: true)
        let intervals = DailyBriefingScreenTimeReader.intervals(from: [a, repeated, unrelated, switched], deviceID: "phone")
        #expect(intervals.count == 1)
        #expect(intervals.first?.start == start)
        #expect(intervals.first?.end == switched.date)
    }

    @Test
    func malformedLengthsVarintsAndFloatingPointValuesAreRejected() {
        #expect(ScreenTimeBiomeParser.transition(Data(repeating: 255, count: 20)) == nil)
        #expect(ScreenTimeBiomeParser.transition(Data([50, 255, 255, 255])) == nil)
        #expect(ScreenTimeBiomeParser.transition(payload(at: Date(timeIntervalSinceReferenceDate: .nan))) == nil)
        #expect(ScreenTimeBiomeParser.transition(Data([0])) == nil)
        #expect(throws: (any Error).self) { try ScreenTimeBiomeParser.transitions(in: Data("SEGB".utf8)) }
        var data = segment([payload(at: start)])
        data.replaceSubrange(4..<8, with: Data(repeating: 255, count: 4))
        #expect(throws: (any Error).self) { try ScreenTimeBiomeParser.transitions(in: data) }
        #expect(throws: (any Error).self) { try ScreenTimeBiomeParser.transitions(in: Data(repeating: 0, count: 16 * 1024 * 1024 + 1)) }
    }

    @Test
    func boundedSeededFuzzRejectsTruncatedAndArbitrarySegmentsWithoutTrapping() {
        var state: UInt64 = 0x5a17
        func random() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 32)
        }
        let valid = segment([payload(at: start), payload(at: start.addingTimeInterval(30), gained: false)])
        for length in 0..<valid.count {
            _ = try? ScreenTimeBiomeParser.transitions(in: valid.prefix(length))
        }
        for index in 0..<2048 {
            var bytes = Data((0..<(index % 512)).map { _ in random() })
            if bytes.count >= 4, index.isMultiple(of: 2) { bytes.replaceSubrange(0..<4, with: Data("SEGB".utf8)) }
            let result = try? ScreenTimeBiomeParser.transitions(in: bytes)
            #expect(result == nil || result!.allSatisfy { $0.date.timeIntervalSinceReferenceDate.isFinite })
            _ = ScreenTimeBiomeParser.transition(bytes)
        }
    }

    @Test
    func overlappingRowsAreDeduplicatedPerDeviceAndClippedToTheDay() {
        let range = DateInterval(start: start, duration: 100)
        let intervals = ScreenTimeUsageInterval.normalized([
            .init(deviceID: "mac", bundleID: "A", start: start.addingTimeInterval(-10), end: start.addingTimeInterval(60)),
            .init(deviceID: "mac", bundleID: "A", start: start, end: start.addingTimeInterval(80)),
            .init(deviceID: "mac", bundleID: "B", start: start.addingTimeInterval(40), end: start.addingTimeInterval(120)),
            .init(deviceID: "phone", bundleID: "A", start: start, end: start.addingTimeInterval(20)),
        ], within: range)
        #expect(intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == 120)
        #expect(intervals.filter { $0.deviceID == "mac" }.count == 2)
        #expect(intervals.allSatisfy { $0.start >= range.start && $0.end <= range.end })
    }

    @Test
    func localReaderIncludesLiveWALWithoutChangingAppleOwnedFiles() throws {
        let library = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let folder = library.appendingPathComponent("Application Support/Knowledge")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("knowledgeC.db")
        var database: OpaquePointer?
        #expect(sqlite3_open(path.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
            PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;
            CREATE TABLE ZSOURCE (Z_PK INTEGER, ZDEVICEID TEXT);
            CREATE TABLE ZOBJECT (ZVALUESTRING TEXT, ZSTARTDATE REAL, ZENDDATE REAL, ZSTREAMNAME TEXT, ZSOURCE INTEGER);
            INSERT INTO ZSOURCE VALUES (1, NULL), (2, 'remote');
            INSERT INTO ZOBJECT VALUES ('com.example.editor', \(start.timeIntervalSinceReferenceDate - 30), \(start.timeIntervalSinceReferenceDate + 60), '/app/usage', 1);
            INSERT INTO ZOBJECT VALUES ('remote.app', \(start.timeIntervalSinceReferenceDate), \(start.timeIntervalSinceReferenceDate + 60), '/app/usage', 2);
            """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        let wal = URL(fileURLWithPath: path.path + "-wal")
        let beforeDB = try Data(contentsOf: path)
        let beforeWAL = try Data(contentsOf: wal)
        let intervals = try DailyBriefingScreenTimeReader(library: library).readLocal(within: DateInterval(start: start, duration: 120))
        #expect(intervals == [.init(deviceID: "local", bundleID: "com.example.editor", start: start, end: start.addingTimeInterval(60))])
        #expect(try Data(contentsOf: path) == beforeDB)
        #expect(try Data(contentsOf: wal) == beforeWAL)
    }

    @Test
    func remoteReaderUsesOnlyClosedIntervalsAndMissingSourcesStayUnavailable() throws {
        let library = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let reader = DailyBriefingScreenTimeReader(library: library)
        let range = DateInterval(start: start, duration: 3600)
        #expect(reader.read(within: range).local == nil)
        #expect(reader.read(within: range).allDeviceSeconds == nil)
        let device = library.appendingPathComponent("Biome/streams/restricted/App.InFocus/remote/00000000-0000-0000-0000-000000000001")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let file = device.appendingPathComponent(String(Int64(start.timeIntervalSinceReferenceDate * 1_000_000)))
        try segment([payload(at: start), payload(at: start.addingTimeInterval(120), gained: false),
            payload(at: start.addingTimeInterval(180))]).write(to: file)
        let remote = try reader.readRemote(within: range)
        #expect(remote.count == 1)
        #expect(remote.first?.end == start.addingTimeInterval(120))
        let local = [ScreenTimeUsageInterval(deviceID: "local", bundleID: "editor", start: start, end: start.addingTimeInterval(60))]
        #expect(DailyBriefingScreenTimeResult(local: local, remote: remote).allDeviceSeconds == 180)
        try Data("corrupt".utf8).write(to: file)
        #expect(reader.read(within: range).remote == nil)
        #expect(DailyBriefingScreenTimeResult(local: local, remote: nil).allDeviceSeconds == nil)
    }

    @Test
    func remoteSymlinksCannotEscapeTheExpectedStream() throws {
        let library = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let root = library.appendingPathComponent("Biome/streams/restricted/App.InFocus/remote")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("00000000-0000-0000-0000-000000000001"), withDestinationURL: library)
        #expect(throws: (any Error).self) {
            try DailyBriefingScreenTimeReader(library: library).readRemote(within: DateInterval(start: start, duration: 100))
        }
    }
}
