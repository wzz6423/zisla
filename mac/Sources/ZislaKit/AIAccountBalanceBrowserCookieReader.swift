import CryptoKit
import Darwin
import Foundation
import SQLite3
import ZislaCore

struct AIAccountBalanceBrowserCookie: Sendable {
    var domain: String
    var name: String
    var value: String
    var path: String
    var expires: TimeInterval?

    func applies(to website: AIAccountBalanceWebsite, now: Date) -> Bool {
        let domain = domain.lowercased()
        let bareDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard bareDomain == website.cookieDomain || bareDomain.hasSuffix("." + website.cookieDomain),
              path.hasPrefix("/"), expires.map({ $0.isFinite && $0 > now.timeIntervalSince1970 }) ?? true else { return false }
        return website.cookieRequestURLs.allSatisfy { url in
            guard let host = url.host?.lowercased() else { return false }
            let matchesDomain = host == bareDomain || (domain.hasPrefix(".") && host.hasSuffix("." + bareDomain))
            let matchesPath = url.path == path || (url.path.hasPrefix(path)
                && (path.hasSuffix("/") || url.path.dropFirst(path.count).hasPrefix("/")))
            return matchesDomain && matchesPath
        }
    }
}

struct AIAccountBalanceBrowserCookieReader: Sendable {
    static let maximumDatabaseBytes = 64 * 1_024 * 1_024
    static let maximumCookies = 256
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory
    var now: @Sendable () -> Date = Date.init
    var keychainRead: @Sendable (String, String) throws -> Data? = { service, account in
        try AISubscriptionCredentials.readKeychainCredentialWithoutPrompt(service: service, account: account)?.data
    }
    var readFile: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int = { Darwin.read($0, $1, $2) }

    func header(from source: AIAccountBalanceBrowserCookieSource, website: AIAccountBalanceWebsite) throws -> String {
        do {
            let time = now()
            let cookies: [AIAccountBalanceBrowserCookie]
            if source.browser == .safari {
                cookies = try safariCookies(regularData(source.databaseURL, maximumBytes: 16 * 1_024 * 1_024), website: website)
            } else {
                cookies = try sqliteCookies(source, website: website, time: time)
            }
            let selected = cookies.filter { $0.applies(to: website, now: time) }.sorted {
                if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
                return $0.name < $1.name
            }
            guard !selected.isEmpty else { throw AIAccountBalanceBrowserCookieError.cookiesNotFound }
            return try AIAccountBalanceCookieStore.normalizedCookie(selected.map { $0.name + "=" + $0.value }.joined(separator: "; "), website: website)
        } catch let error as AIAccountBalanceBrowserCookieError { throw error }
        catch { throw AIAccountBalanceBrowserCookieError.accessFailed }
    }

    private func sqliteCookies(_ source: AIAccountBalanceBrowserCookieSource, website: AIAccountBalanceWebsite,
                               time: Date) throws -> [AIAccountBalanceBrowserCookie] {
        // Browser locks and WAL state require an isolated snapshot; decrypted values never leave memory.
        var template = temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("zisla-quota-cookies-XXXXXX").path.utf8CString
        guard template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress!) != nil })
        else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        let directory = URL(fileURLWithPath: template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("Cookies")
        let wal = URL(fileURLWithPath: source.databaseURL.path + "-wal")
        guard let databaseVersion = try fileVersion(source.databaseURL) else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        let walVersion = try fileVersion(wal)
        var budget = Self.maximumDatabaseBytes
        try copyRegularFile(source.databaseURL, to: copy, budget: &budget, expected: databaseVersion)
        if let walVersion {
            try copyRegularFile(wal, to: URL(fileURLWithPath: copy.path + "-wal"), budget: &budget, expected: walVersion)
        }
        guard try fileVersion(source.databaseURL) == databaseVersion, try fileVersion(wal) == walVersion
        else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database = connection else { sqlite3_close(connection); throw AIAccountBalanceBrowserCookieError.accessFailed }
        defer { sqlite3_close(database) }
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, 64 * 1_024)
        let firefox = source.browser == .firefox
        let table = firefox ? "moz_cookies" : "cookies"
        let columns = try columnNames(database, table: table)
        let hostColumn = firefox ? "host" : "host_key"
        let required = firefox ? ["host", "name", "value", "path", "expiry"]
            : ["host_key", "name", "value", "encrypted_value", "path", "expires_utc"]
        let domains = Set(website.cookieRequestURLs.compactMap(\.host) + [website.cookieDomain])
        let hosts = domains.flatMap { [$0, "." + $0] }.sorted()
        let placeholders = hosts.map { _ in "?" }.joined(separator: ",")
        let optionalColumns = firefox ? ["originAttributes", "isSession"] : ["top_frame_site_key", "has_expires", "is_persistent"]
        let fields = required + optionalColumns.filter(columns.contains)
        let sql = "SELECT " + fields.joined(separator: ",") + " FROM " + table
            + " WHERE " + hostColumn + " IN (" + placeholders + ")"
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, host) in hosts.enumerated() {
            guard host.withCString({ sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }) == SQLITE_OK
            else { throw AIAccountBalanceBrowserCookieError.invalidData }
        }
        let version = try self.databaseVersion(database, firefox: firefox)
        guard !firefox || (0...17).contains(version) else { throw AIAccountBalanceBrowserCookieError.invalidData }
        var cookies: [AIAccountBalanceBrowserCookie] = []
        var count = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return cookies }
            guard result == SQLITE_ROW, count < Self.maximumCookies else { throw AIAccountBalanceBrowserCookieError.invalidData }
            count += 1
            func index(_ name: String) -> Int32 { Int32(fields.firstIndex(of: name)!) }
            let attributes = firefox ? "originAttributes" : "top_frame_site_key"
            if fields.contains(attributes), try text(statement, index(attributes)) != "" { continue }
            let rawExpiry = try number(statement, index(firefox ? "expiry" : "expires_utc"))
            var expires: Double? = rawExpiry == 0 ? nil
                : firefox ? rawExpiry / (version >= 16 ? 1_000 : 1) : rawExpiry / 1_000_000 - 11_644_473_600
            for flag in firefox ? ["isSession"] : ["has_expires", "is_persistent"] where fields.contains(flag) {
                let value = try boolean(statement, index(flag))
                if firefox ? value : !value { expires = nil }
            }
            var cookie = AIAccountBalanceBrowserCookie(domain: try text(statement, index(hostColumn)),
                name: try text(statement, index("name")), value: "", path: try text(statement, index("path")), expires: expires)
            guard cookie.applies(to: website, now: time) else { continue }
            let encryptedIndex = firefox ? nil : index("encrypted_value")
            if let encryptedIndex, sqlite3_column_bytes(statement, encryptedIndex) > 0 {
                guard let account = source.keychainAccount else { throw AIAccountBalanceBrowserCookieError.unsupportedBrowser }
                guard let data = try keychainRead(account + " Safe Storage", account),
                      let password = String(data: data, encoding: .utf8), !password.isEmpty else {
                    throw AIAccountBalanceBrowserCookieError.accessFailed
                }
                let size = Int(sqlite3_column_bytes(statement, encryptedIndex))
                guard size <= 32 * 1_024, let bytes = sqlite3_column_blob(statement, encryptedIndex),
                      var decrypted = AISubscriptionCredentials.decryptChromiumData(Data(bytes: bytes, count: size), password: password)
                else { throw AIAccountBalanceBrowserCookieError.invalidData }
                if version >= 24 {
                    let hash = Data(SHA256.hash(data: Data(cookie.domain.utf8)))
                    guard decrypted.starts(with: hash) else { throw AIAccountBalanceBrowserCookieError.invalidData }
                    decrypted = Data(decrypted.dropFirst(hash.count))
                }
                guard let value = String(data: decrypted, encoding: .utf8) else { throw AIAccountBalanceBrowserCookieError.invalidData }
                cookie.value = value
            } else { cookie.value = try text(statement, index("value")) }
            cookies.append(cookie)
        }
    }

    private struct FileVersion: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
            size = metadata.st_size
            modifiedSeconds = metadata.st_mtimespec.tv_sec
            modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
            changedSeconds = metadata.st_ctimespec.tv_sec
            changedNanoseconds = metadata.st_ctimespec.tv_nsec
        }
    }

    private func fileVersion(_ source: URL) throws -> FileVersion? {
        guard source.standardizedFileURL == source.resolvingSymlinksInPath() else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        var metadata = stat()
        if lstat(source.path, &metadata) != 0 {
            if errno == ENOENT { return nil }
            throw AIAccountBalanceBrowserCookieError.accessFailed
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        return FileVersion(metadata)
    }

    private func copyRegularFile(_ source: URL, to destination: URL, budget: inout Int, expected: FileVersion) throws {
        guard source.standardizedFileURL == source.resolvingSymlinksInPath() else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, FileVersion(metadata) == expected,
              metadata.st_size >= 0, metadata.st_size <= budget else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        defer { close(output) }
        let expectedSize = Int(metadata.st_size)
        var copied = 0
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { readFile(descriptor, $0.baseAddress!, $0.count) }
            guard count >= 0, count <= budget else { throw AIAccountBalanceBrowserCookieError.accessFailed }
            if count == 0 { break }
            budget -= count
            copied += count
            try buffer.withUnsafeBytes { bytes in
                var written = 0
                while written < count {
                    let size = write(output, bytes.baseAddress!.advanced(by: written), count - written)
                    guard size > 0 else { throw AIAccountBalanceBrowserCookieError.accessFailed }
                    written += size
                }
            }
        }
        guard copied == expectedSize else { throw AIAccountBalanceBrowserCookieError.accessFailed }
    }

    private func regularData(_ source: URL, maximumBytes: Int) throws -> Data {
        guard source.standardizedFileURL == source.resolvingSymlinksInPath() else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= maximumBytes else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { readFile(descriptor, $0.baseAddress!, $0.count) }
            guard count >= 0, count <= maximumBytes - data.count else { throw AIAccountBalanceBrowserCookieError.accessFailed }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == metadata.st_size else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        return data
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let result = statement else {
            sqlite3_finalize(statement); throw AIAccountBalanceBrowserCookieError.invalidData
        }
        return result
    }

    private func columnNames(_ database: OpaquePointer, table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(" + table + ")", database: database)
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW { names.insert(try text(statement, 1)) }
        return names
    }

    private func databaseVersion(_ database: OpaquePointer, firefox: Bool) throws -> Int {
        let statement = try prepare(firefox ? "PRAGMA user_version" : "SELECT value FROM meta WHERE key = 'version' LIMIT 1", database: database)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AIAccountBalanceBrowserCookieError.invalidData }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        let size = Int(sqlite3_column_bytes(statement, index))
        guard size <= 32 * 1_024, sqlite3_column_type(statement, index) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, index),
              let value = String(data: Data(bytes: bytes, count: size), encoding: .utf8), !value.contains("\0") else {
            throw AIAccountBalanceBrowserCookieError.invalidData
        }
        return value
    }

    private func boolean(_ statement: OpaquePointer, _ index: Int32) throws -> Bool {
        let value = sqlite3_column_int(statement, index)
        guard sqlite3_column_type(statement, index) == SQLITE_INTEGER, value == 0 || value == 1
        else { throw AIAccountBalanceBrowserCookieError.invalidData }
        return value == 1
    }

    private func number(_ statement: OpaquePointer, _ index: Int32) throws -> Double {
        let type = sqlite3_column_type(statement, index)
        let value = sqlite3_column_double(statement, index)
        guard (type == SQLITE_INTEGER || type == SQLITE_FLOAT), value.isFinite, value >= 0 else {
            throw AIAccountBalanceBrowserCookieError.invalidData
        }
        return value
    }

    func safariCookies(_ data: Data, website: AIAccountBalanceWebsite) throws -> [AIAccountBalanceBrowserCookie] {
        let bytes = [UInt8](data)
        func integer(_ offset: Int, bigEndian: Bool = false, count: Int = 4) throws -> UInt64 {
            guard offset >= 0, offset <= bytes.count - count else { throw AIAccountBalanceBrowserCookieError.invalidData }
            return (0..<count).reduce(0) { value, index in
                value | UInt64(bytes[offset + index]) << ((bigEndian ? count - 1 - index : index) * 8)
            }
        }
        guard bytes.count >= 8, bytes.starts(with: "cook".utf8) else { throw AIAccountBalanceBrowserCookieError.invalidData }
        let pages = Int(try integer(4, bigEndian: true))
        guard pages <= (bytes.count - 8) / 4 else { throw AIAccountBalanceBrowserCookieError.invalidData }
        var pageOffset = 8 + pages * 4
        var cookies: [AIAccountBalanceBrowserCookie] = []
        for page in 0..<pages {
            let size = Int(try integer(8 + page * 4, bigEndian: true))
            guard size >= 8, size <= bytes.count - pageOffset,
                  try integer(pageOffset) == 0x0001_0000 else { throw AIAccountBalanceBrowserCookieError.invalidData }
            let count = Int(try integer(pageOffset + 4))
            guard count <= (size - 8) / 4 else { throw AIAccountBalanceBrowserCookieError.invalidData }
            for index in 0..<count {
                let recordOffset = Int(try integer(pageOffset + 8 + index * 4))
                guard recordOffset >= 8 + count * 4, recordOffset <= size - 56 else { throw AIAccountBalanceBrowserCookieError.invalidData }
                let start = pageOffset + recordOffset
                let length = Int(try integer(start))
                guard length >= 56, length <= size - recordOffset else { throw AIAccountBalanceBrowserCookieError.invalidData }
                func string(_ field: Int) throws -> String {
                    let offset = Int(try integer(start + field))
                    guard offset >= 56, offset < length,
                          let end = bytes[(start + offset)..<(start + length)].firstIndex(of: 0),
                          end - start - offset <= 32 * 1_024,
                          let value = String(bytes: bytes[(start + offset)..<end], encoding: .utf8) else {
                        throw AIAccountBalanceBrowserCookieError.invalidData
                    }
                    return value
                }
                let domain = try string(16)
                let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
                guard bare == website.cookieDomain || bare.hasSuffix("." + website.cookieDomain) else { continue }
                guard cookies.count < Self.maximumCookies else { throw AIAccountBalanceBrowserCookieError.invalidData }
                let expiration = Double(bitPattern: try integer(start + 40, count: 8))
                cookies.append(AIAccountBalanceBrowserCookie(domain: domain, name: try string(20), value: try string(28),
                    path: try string(24),
                    expires: expiration + Date.timeIntervalBetween1970AndReferenceDate))
            }
            pageOffset += size
        }
        return cookies
    }
}
