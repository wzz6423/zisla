import Darwin
import Foundation

protocol LidClosedDisplaySession: AnyObject, Sendable {
    func stop() throws
    func cancel()
}

final class PMSetLidClosedDisplaySession: LidClosedDisplaySession, @unchecked Sendable {
    private let lock = NSLock()
    private var pipe: UnsafeMutablePointer<FILE>?

    static func start() throws -> PMSetLidClosedDisplaySession {
        let (status, pipe) = BatteryPowerModeAuthorizationSession.shared.openLidClosedDisplaySession()
        guard status == 0, let pipe else {
            throw CocoaError(.userCancelled)
        }
        return try PMSetLidClosedDisplaySession(pipe: pipe)
    }

    init(pipe: UnsafeMutablePointer<FILE>) throws {
        self.pipe = pipe
        let descriptor = fileno(pipe)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        // Children must not inherit the lease and keep sleep disabled after the app exits.
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              try readLine(from: descriptor) == "ready"
        else {
            throw CocoaError(.executableRuntimeMismatch)
        }
    }

    deinit {
        if let pipe { fclose(pipe) }
    }

    func stop() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let pipe else { return }
        let sent = "stop\n".withCString { send(fileno(pipe), $0, 5, MSG_NOSIGNAL) }
        guard sent == 5, try readLine(from: fileno(pipe)) == "restored" else {
            throw CocoaError(.executableRuntimeMismatch)
        }
        fclose(pipe)
        self.pipe = nil
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if let pipe { fclose(pipe) }
        pipe = nil
    }

    private func readLine(from descriptor: Int32) throws -> String {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            var byte: UInt8 = 0
            guard recv(descriptor, &byte, 1, 0) == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    // The privileged process owns the original setting. EOF restores it even if the app crashes.
    // sh -p ignores shell startup files; only fixed system executables run with elevated privileges.
    static let script = #"""
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
    read_state() {
        settings=$(/usr/bin/pmset -g) || return 1
        printf '%s\n' "$settings" | /usr/bin/awk '
            /^System-wide power settings:$/ { header = 1; next }
            /^Currently in use:$/ { exit }
            header && $1 == "SleepDisabled" {
                if (seen++ || NF != 2 || $2 !~ /^[01]$/) { invalid = 1; exit }
                value = $2
            }
            END { if (!header || invalid) exit 1; print seen ? value : 0 }
        '
    }
    original=$(read_state) || exit 1
    changed=0
    restore() {
        [ "$changed" = 1 ] || return 0
        /usr/bin/pmset -a disablesleep "$original" >/dev/null
        current=$(read_state) || return 1
        [ "$current" = "$original" ] || return 1
        changed=0
    }
    trap 'restore' EXIT
    if [ "$original" = 0 ]; then
        changed=1
        /usr/bin/pmset -a disablesleep 1 >/dev/null || exit 1
    fi
    current=$(read_state) || exit 1
    [ "$current" = 1 ] || exit 1
    printf 'ready\n'
    while IFS= read -r request; do
        [ "$request" = stop ] || exit 1
        if restore; then
            printf 'restored\n'
            exit 0
        fi
        printf 'failed\n'
    done
    """#
}
