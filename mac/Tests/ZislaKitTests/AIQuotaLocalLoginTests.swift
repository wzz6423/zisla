import Darwin
import Foundation
import SQLite3
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIQuotaLocalLoginTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIQuotaLocalLoginTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test(arguments: [AIQuotaProvider.claudeCode, .codex, .grok, .openCodeGo, .commandCode])
    func readsOnlyExplicitTemporaryOfficialLoginFiles(_ provider: AIQuotaProvider) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("auth.json")
            let payload: String
            switch provider {
            case .claudeCode: payload = #"{"claudeAiOauth":{"accessToken":"fictional-token","expiresAt":1800000000000}}"#
            case .codex: payload = #"{"tokens":{"access_token":"fictional-token","account_id":"fictional-account"}}"#
            case .grok: payload = #"{"old":{"key":"old-token","expires_at":"2020-01-01T00:00:00Z"},"issuer":{"key":"fictional-token","expires_at":"2030-01-01T00:00:00Z"}}"#
            case .openCodeGo: payload = #"{"opencode-go":{"key":"fictional-token"}}"#
            case .commandCode: payload = #"{"apiKey":"fictional-token"}"#
            default: fatalError("Unexpected fixture provider")
            }
            try Data(payload.utf8).write(to: url)
            var configuration = AIQuotaConfiguration(provider: provider)
            configuration.localPath = url.path
            let result = try AIQuotaLocalLogin(home: directory).read(configuration, now: AIQuotaFixtures.now)
            #expect(result.0.token == "fictional-token")
            #expect(result.1 == (provider == .codex ? "fictional-account" : nil))
            #expect(try Data(contentsOf: url) == Data(payload.utf8))
        }
    }

    @Test
    func expiredClaudeCredentialsAndMalformedJSONAreRejected() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("auth.json")
            var configuration = AIQuotaConfiguration(provider: .claudeCode)
            configuration.localPath = url.path
            try Data(#"{"claudeAiOauth":{"accessToken":"fictional-token","expiresAt":1000}}"#.utf8).write(to: url)
            #expect(throws: AIQuotaError.credentialRejected) { try AIQuotaLocalLogin(home: directory).read(configuration, now: AIQuotaFixtures.now) }
            try Data("{broken".utf8).write(to: url)
            #expect(throws: AIQuotaError.invalidResponse) { try AIQuotaLocalLogin(home: directory).read(configuration, now: AIQuotaFixtures.now) }
        }
    }

    @Test(arguments: [false, true])
    func cursorSQLiteLoginSupportsUTF8AndUTF16WithoutWritingTheDatabase(_ utf16: Bool) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("state.vscdb")
            let token = try jwt(expiry: AIQuotaFixtures.now.timeIntervalSince1970 + 3_600)
            try createDatabase(url, value: token.data(using: utf16 ? .utf16LittleEndian : .utf8)!)
            let before = try Data(contentsOf: url)
            #expect(try AIQuotaLocalLogin.cursorToken(url) == token)
            #expect(try AIQuotaLocalLogin.cursorCookie(token, now: AIQuotaFixtures.now) == "WorkosCursorSessionToken=account_1%3A%3A\(token)")
            #expect(try Data(contentsOf: url) == before)
            #expect(openDescriptors(for: url).isEmpty)
        }
    }

    @Test
    func cursorTokensNeedAValidSubjectAndMoreThanSixtySecondsRemaining() throws {
        #expect(throws: AIQuotaError.credentialRejected) { try AIQuotaLocalLogin.cursorCookie(jwt(expiry: AIQuotaFixtures.now.timeIntervalSince1970 + 59), now: AIQuotaFixtures.now) }
        #expect(throws: AIQuotaError.credentialInvalid) { try AIQuotaLocalLogin.cursorCookie("not-a-jwt", now: AIQuotaFixtures.now) }
    }

    @Test
    func FIFOsDirectoriesAndOversizedFilesFailWithoutBlocking() throws {
        try withDirectory { directory in
            let fifo = directory.appendingPathComponent("login.fifo")
            #expect(mkfifo(fifo.path, 0o600) == 0)
            let start = ContinuousClock.now
            #expect(throws: AIQuotaError.credentialUnavailable) { try AIQuotaLocalLogin.readFile(fifo) }
            #expect(throws: AIQuotaError.credentialUnavailable) { try AIQuotaLocalLogin.cursorToken(fifo) }
            #expect(ContinuousClock.now - start < .seconds(1))
            #expect(throws: AIQuotaError.credentialUnavailable) { try AIQuotaLocalLogin.readFile(directory) }
            let large = directory.appendingPathComponent("large.json")
            try Data(repeating: 32, count: 1_024 * 1_024 + 1).write(to: large)
            #expect(throws: AIQuotaError.responseTooLarge) { try AIQuotaLocalLogin.readFile(large) }
            #expect(openDescriptors(for: large).isEmpty)
        }
    }

    @Test
    func sqlitePrepareFailuresDoNotLeakFileDescriptors() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("wrong-schema.vscdb")
            var database: OpaquePointer?
            #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
            #expect(sqlite3_exec(database, "CREATE TABLE OtherTable (value TEXT)", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(database)
            for _ in 0..<32 {
                #expect(throws: AIQuotaError.credentialUnavailable) { try AIQuotaLocalLogin.cursorToken(url) }
            }
            #expect(openDescriptors(for: url).isEmpty)
        }
    }

    private func jwt(expiry: Double) throws -> String {
        let claims = try AIQuotaFixtures.json(["sub": "provider|account_1", "exp": expiry])
        let encoded = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func createDatabase(_ url: URL, value: Data) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT, value BLOB)", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', ?)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        value.withUnsafeBytes { bytes in
            #expect(sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
        }
    }

    private func openDescriptors(for url: URL) -> [Int32] {
        (0..<1_024).compactMap { index in
            let descriptor = Int32(index)
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let status = path.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
            let decoded = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard status == 0, decoded == url.path else { return nil }
            return descriptor
        }
    }
}
