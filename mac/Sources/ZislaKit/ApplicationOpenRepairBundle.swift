import CryptoKit
import Darwin
import Foundation

// Adapted from Peck's descriptor-based snapshot and quarantine-only processing.
// See Resources/ThirdPartyLicenses/Peck-NOTICE.txt for the pinned source and license.
struct ApplicationOpenRepairBundle: Sendable {
    static let quarantineAttribute = "com.apple.quarantine"
    let url: URL
    var entries: [Entry]

    struct Entry: Equatable, Sendable {
        let path: String
        let device: Int32
        let inode: UInt64
        let mode: UInt16
        let owner: UInt32
        let links: UInt16
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let digest: Data
        let linkTarget: String?
        var attributes: [String: Data]

        var isLink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    }

    static func applicationURL(_ input: URL) throws -> URL {
        guard input.isFileURL, input.pathExtension.lowercased() == "app",
              !input.path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw ApplicationOpenRepairError.invalidApplication
        }
        // Foundation normalizes /private/var back to /var; realpath keeps the physical path for O_NOFOLLOW.
        guard let resolved = realpath(input.path, nil) else { throw ApplicationOpenRepairError.readFailed }
        defer { free(resolved) }
        let url = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        guard url.pathExtension.lowercased() == "app",
              !url.path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw ApplicationOpenRepairError.invalidApplication
        }
        guard !["/System/", "/Library/Apple/", "/usr/", "/bin/", "/sbin/"].contains(where: url.path.hasPrefix) else {
            throw ApplicationOpenRepairError.protectedApplication
        }
        return url
    }

    static func capture(at url: URL, isCancelled: @Sendable () -> Bool) throws -> Self {
        let root = try openRoot(url)
        defer { close(root) }
        var filesystem = statfs()
        guard fstatfs(root, &filesystem) == 0 else { throw ApplicationOpenRepairError.readFailed }
        guard filesystem.f_flags & UInt32(MNT_RDONLY) == 0 else { throw ApplicationOpenRepairError.readOnly }

        var entries: [Entry] = []
        var totalBytes: Int64 = 0
        var infoData = Data()
        func walk(_ descriptor: Int32, path: String, linkTarget: String? = nil) throws {
            guard !isCancelled() else { throw CancellationError() }
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw ApplicationOpenRepairError.readFailed }
            totalBytes += status.st_size
            guard entries.count < 100_000, totalBytes <= 16 * 1_024 * 1_024 * 1_024 else {
                throw ApplicationOpenRepairError.inspectionLimit
            }
            let entry = try readEntry(descriptor, path: path, linkTarget: linkTarget, isCancelled: isCancelled,
                infoData: &infoData)
            guard entries.first.map({ $0.device == entry.device }) ?? true else {
                throw ApplicationOpenRepairError.unsupportedBundle
            }
            entries.append(entry)
            guard entry.mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { return }
            for name in try childNames(descriptor) {
                var childStatus = stat()
                guard fstatat(descriptor, name, &childStatus, AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw ApplicationOpenRepairError.readFailed
                }
                let isLink = childStatus.st_mode & UInt16(S_IFMT) == UInt16(S_IFLNK)
                let child = openat(descriptor, name, O_RDONLY | O_CLOEXEC | O_NONBLOCK | (isLink ? O_SYMLINK : O_NOFOLLOW))
                guard child >= 0 else { throw ApplicationOpenRepairError.readFailed }
                defer { close(child) }
                let relative = path == "." ? name : path + "/" + name
                let target = isLink ? try readLink(descriptor, name: name) : nil
                try walk(child, path: relative, linkTarget: target)
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0, status.st_ino == after.st_ino,
                  status.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  status.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw ApplicationOpenRepairError.applicationChanged }
        }
        try walk(root, path: ".")
        guard let plist = entries.first(where: { $0.path == "Contents/Info.plist" }),
              plist.mode & UInt16(S_IFMT) == UInt16(S_IFREG),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              executable != ".", executable != "..", !executable.contains("/"),
              !executable.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              let main = entries.first(where: { $0.path == "Contents/MacOS/" + executable }),
              main.mode & UInt16(S_IFMT) == UInt16(S_IFREG), main.mode & 0o111 != 0 else {
            throw ApplicationOpenRepairError.invalidApplication
        }
        let bundle = Self(url: url, entries: entries)
        try bundle.validateLinks()
        return bundle
    }

    func matches(_ other: Self) -> Bool {
        url == other.url && entries.count == other.entries.count
            && zip(entries, other.entries).allSatisfy { Self.sameEntry($0, $1) }
    }

    private static func sameEntry(_ first: Entry, _ second: Entry) -> Bool {
        // macOS updates provenance independently of quarantine; preserve it without authorizing other changes.
        var first = first
        var second = second
        first.attributes.removeValue(forKey: "com.apple.provenance")
        second.attributes.removeValue(forKey: "com.apple.provenance")
        return first == second
    }

    func removeQuarantine(
        isCancelled: @Sendable () -> Bool,
        remove: @Sendable (Int32) throws -> Void
    ) throws -> Self {
        let root = try Self.openRoot(url)
        defer { close(root) }
        var expected = self
        for (index, entry) in entries.enumerated() where entry.attributes[Self.quarantineAttribute] != nil {
            guard !isCancelled() else { throw CancellationError() }
            let descriptor = try Self.openEntry(entry, root: root)
            defer { close(descriptor) }
            var ignored = Data()
            // Symlink targets cannot change in place; the checked inode pins the link itself.
            let current = try Self.readEntry(descriptor, path: entry.path, linkTarget: entry.linkTarget,
                isCancelled: isCancelled, infoData: &ignored)
            guard Self.sameEntry(entry, current) else { throw ApplicationOpenRepairError.applicationChanged }
            try remove(descriptor)
            guard fgetxattr(descriptor, Self.quarantineAttribute, nil, 0, 0, 0) < 0, errno == ENOATTR else {
                throw ApplicationOpenRepairError.quarantineRemovalFailed
            }
            expected.entries[index].attributes.removeValue(forKey: Self.quarantineAttribute)
        }
        return expected
    }

    private func validateLinks() throws {
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        for link in entries where link.isLink {
            var pending = link.path.components(separatedBy: "/")
            var resolved: [String] = []
            var hops = 0
            while !pending.isEmpty {
                let part = pending.removeFirst()
                if part.isEmpty || part == "." { continue }
                if part == ".." {
                    guard !resolved.isEmpty else { throw ApplicationOpenRepairError.unsupportedBundle }
                    resolved.removeLast()
                    continue
                }
                guard let entry = byPath[(resolved + [part]).joined(separator: "/")] else {
                    throw ApplicationOpenRepairError.unsupportedBundle
                }
                if entry.isLink {
                    hops += 1
                    guard hops <= 32, var target = entry.linkTarget, !target.isEmpty else {
                        throw ApplicationOpenRepairError.unsupportedBundle
                    }
                    if target.hasPrefix("/") {
                        guard target == url.path || target.hasPrefix(url.path + "/") else {
                            throw ApplicationOpenRepairError.unsupportedBundle
                        }
                        target = String(target.dropFirst(url.path.count))
                        resolved = []
                    }
                    pending = target.components(separatedBy: "/") + pending
                } else {
                    guard pending.isEmpty || entry.mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else {
                        throw ApplicationOpenRepairError.unsupportedBundle
                    }
                    resolved.append(part)
                }
            }
        }
    }

    private static func openRoot(_ url: URL) throws -> Int32 {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ApplicationOpenRepairError.readFailed }
        for part in url.path.split(separator: "/") {
            let next = openat(descriptor, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { throw ApplicationOpenRepairError.readFailed }
            descriptor = next
        }
        return descriptor
    }

    private static func openEntry(_ entry: Entry, root: Int32) throws -> Int32 {
        var descriptor = dup(root)
        guard descriptor >= 0 else { throw ApplicationOpenRepairError.readFailed }
        if entry.path == "." { return descriptor }
        let parts = entry.path.components(separatedBy: "/")
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK
                | (isLast && entry.isLink ? O_SYMLINK : O_NOFOLLOW) | (isLast ? 0 : O_DIRECTORY)
            let next = openat(descriptor, part, flags)
            close(descriptor)
            guard next >= 0 else { throw ApplicationOpenRepairError.applicationChanged }
            descriptor = next
        }
        return descriptor
    }

    private static func childNames(_ descriptor: Int32) throws -> [String] {
        let copy = dup(descriptor)
        guard copy >= 0 else { throw ApplicationOpenRepairError.readFailed }
        guard let directory = fdopendir(copy) else {
            close(copy)
            throw ApplicationOpenRepairError.readFailed
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw ApplicationOpenRepairError.readFailed }
                return names.sorted()
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
        }
    }

    private static func readLink(_ parent: Int32, name: String) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = readlinkat(parent, name, &bytes, bytes.count)
        guard count > 0, count < bytes.count, let target = String(bytes: bytes.prefix(count), encoding: .utf8) else {
            throw ApplicationOpenRepairError.unsupportedBundle
        }
        return target
    }

    private static func readEntry(
        _ descriptor: Int32, path: String, linkTarget: String?, isCancelled: @Sendable () -> Bool,
        infoData: inout Data
    ) throws -> Entry {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw ApplicationOpenRepairError.readFailed }
        let kind = status.st_mode & UInt16(S_IFMT)
        guard [UInt16(S_IFDIR), UInt16(S_IFREG), UInt16(S_IFLNK)].contains(kind),
              kind == UInt16(S_IFDIR) || status.st_nlink == 1 else { throw ApplicationOpenRepairError.unsupportedBundle }
        let attributes = try readAttributes(descriptor)
        var digest = Data()
        if kind == UInt16(S_IFREG) {
            guard status.st_size <= 16 * 1_024 * 1_024 * 1_024,
                  path != "Contents/Info.plist" || status.st_size <= 1_024 * 1_024 else {
                throw ApplicationOpenRepairError.inspectionLimit
            }
            var hash = SHA256()
            var bytes = [UInt8](repeating: 0, count: 128 * 1_024)
            var offset: Int64 = 0
            while offset < status.st_size {
                guard !isCancelled() else { throw CancellationError() }
                let count = pread(descriptor, &bytes, min(bytes.count, Int(status.st_size - offset)), offset)
                guard count > 0 else { throw ApplicationOpenRepairError.readFailed }
                let data = Data(bytes.prefix(count))
                hash.update(data: data)
                if path == "Contents/Info.plist" { infoData.append(data) }
                offset += Int64(count)
            }
            digest = Data(hash.finalize())
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, status.st_ino == after.st_ino, status.st_size == after.st_size,
              status.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              status.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              status.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              status.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              status.st_mode == after.st_mode, status.st_nlink == after.st_nlink else {
            throw ApplicationOpenRepairError.applicationChanged
        }
        return Entry(path: path, device: status.st_dev, inode: status.st_ino, mode: status.st_mode,
            owner: status.st_uid, links: status.st_nlink, size: status.st_size,
            modifiedSeconds: status.st_mtimespec.tv_sec, modifiedNanoseconds: status.st_mtimespec.tv_nsec,
            digest: digest, linkTarget: linkTarget, attributes: attributes)
    }

    private static func readAttributes(_ descriptor: Int32) throws -> [String: Data] {
        let size = flistxattr(descriptor, nil, 0, 0)
        guard size >= 0 else { throw ApplicationOpenRepairError.readFailed }
        guard size <= 1_024 * 1_024 else { throw ApplicationOpenRepairError.inspectionLimit }
        var bytes = [UInt8](repeating: 0, count: size)
        let count = flistxattr(descriptor, &bytes, bytes.count, 0)
        guard count >= 0 else { throw ApplicationOpenRepairError.readFailed }
        var attributes: [String: Data] = [:]
        for nameBytes in bytes.prefix(count).split(separator: 0) {
            guard let name = String(bytes: nameBytes, encoding: .utf8) else { throw ApplicationOpenRepairError.readFailed }
            let size = fgetxattr(descriptor, name, nil, 0, 0, 0)
            guard size >= 0 else { throw ApplicationOpenRepairError.readFailed }
            guard size <= 8 * 1_024 * 1_024 else { throw ApplicationOpenRepairError.inspectionLimit }
            var value = [UInt8](repeating: 0, count: size)
            let count = fgetxattr(descriptor, name, &value, value.count, 0, 0)
            guard count >= 0 else { throw ApplicationOpenRepairError.readFailed }
            attributes[name] = Data(value.prefix(count))
        }
        return attributes
    }
}
