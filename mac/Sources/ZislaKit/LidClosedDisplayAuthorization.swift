import Darwin
import Foundation

final class LidClosedDisplayAuthorization: @unchecked Sendable {
    static let shared = LidClosedDisplayAuthorization()

    private let lock = NSLock()
    private let userID: uid_t
    private let ownerID: uid_t
    private let directory: String
    private let install: @Sendable (uid_t) throws -> Void

    init(
        userID: uid_t = getuid(),
        ownerID: uid_t = 0,
        directory: String = "/private/etc/sudoers.d",
        install: @escaping @Sendable (uid_t) throws -> Void = { try LidClosedDisplayAuthorization.install(userID: $0) }
    ) {
        self.userID = userID
        self.ownerID = ownerID
        self.directory = directory
        self.install = install
    }

    func authorize() throws {
        try lock.withLock {
            guard userID != 0 else { throw CocoaError(.fileWriteNoPermission) }
            if try !isInstalled() {
                try install(userID)
                guard try isInstalled() else { throw CocoaError(.fileWriteUnknown) }
            }
        }
    }

    private func isInstalled() throws -> Bool {
        var metadata = stat()
        let path = directory + "/zisla-keep-awake-\(userID)"
        guard lstat(path, &metadata) == 0 else {
            if errno == ENOENT { return false }
            throw CocoaError(.fileReadNoPermission)
        }
        // The root-owned policy is authoritative across app launches and reboots.
        guard metadata.st_uid == ownerID,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o7777 == 0o440,
              metadata.st_nlink == 1
        else { throw CocoaError(.fileReadNoPermission) }
        return true
    }

    static func install(
        userID: uid_t,
        launch: (uid_t) -> (Int32, UnsafeMutablePointer<FILE>?) = {
            BatteryPowerModeAuthorizationSession.shared.installLidClosedDisplayPermission(userID: $0)
        }
    ) throws {
        let (status, pipe) = launch(userID)
        guard status == 0, let pipe else { throw CocoaError(.userCancelled) }
        defer { fclose(pipe) }
        let descriptor = fileno(pipe)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        else { throw CocoaError(.fileReadUnknown) }
        var response = [CChar](repeating: 0, count: 32)
        guard fgets(&response, Int32(response.count), pipe) != nil,
              String(decoding: response.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == "installed\n"
        else { throw CocoaError(.fileWriteUnknown) }
    }

    static let installationScript = #"""
    set -eu
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
    [ "$#" = 1 ] || exit 1
    case "$1" in ''|0*|*[!0-9]*) exit 1 ;; esac
    directory=/private/etc/sudoers.d
    [ -d "$directory" ] && [ ! -L "$directory" ] || exit 1
    name="zisla-keep-awake-$1"
    rule="$directory/$name"
    [ ! -e "$rule" ] && [ ! -L "$rule" ] || exit 1
    umask 077
    temporary=$(/usr/bin/mktemp "$directory/.zisla-keep-awake.XXXXXX")
    installed=0
    trap 'if [ "$installed" = 1 ]; then /bin/rm -f "$rule"; fi; /bin/rm -f "$temporary"' EXIT
    printf '#%s ALL=(root) NOPASSWD: NOSETENV: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$1" > "$temporary"
    /usr/sbin/visudo -c -f "$temporary" >/dev/null
    /usr/sbin/chown root:wheel "$temporary"
    /bin/chmod 0440 "$temporary"
    /bin/ln "$temporary" "$rule"
    installed=1
    /bin/rm -f "$temporary"
    validation=$(/usr/sbin/visudo -c)
    case "$validation" in *"/$name: parsed OK"*) ;; *) exit 1 ;; esac
    installed=0
    printf 'installed\n'
    """#
}
