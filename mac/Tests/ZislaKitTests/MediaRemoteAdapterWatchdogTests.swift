import Darwin
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct MediaRemoteAdapterWatchdogTests {
    @Test
    func adapterEnvironmentIncludesParentLifecycleKey() {
        let environment = MediaRemoteAdapterClient.parentLifecycleEnvironment()

        #expect(environment[MediaRemoteAdapterClient.parentLifecycleEnvironmentKey] == "1")
        #expect(environment.count >= ProcessInfo.processInfo.environment.count)
    }

    @Test
    func adapterStreamArgumentsIncludeExpectedFlags() {
        let arguments = MediaRemoteAdapterClient.streamArguments()

        #expect(arguments.contains("stream"))
        #expect(arguments.contains("--no-diff"))
        #expect(arguments.contains("--no-artwork"))
        #expect(arguments.contains { $0.hasPrefix("--debounce=") })
    }

    @Test
    func parentLifecycleEnvironmentKeyMatchesPerlScript() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/MediaRemoteAdapter/mediaremote-adapter.pl")

        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)

        // 验证 Perl 脚本中的环境变量键名一致
        #expect(scriptContent.contains("MEDIAREMOTEADAPTER_PARENT_LIFECYCLE"))
        #expect(scriptContent.contains("start_parent_lifecycle_watchdog"))
    }

    @Test
    func watchdogMechanismUsesSTDINForLifecycleDetection() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/MediaRemoteAdapter/mediaremote-adapter.pl")

        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)

        // 验证 watchdog 监听 STDIN
        #expect(scriptContent.contains("my $input_fd = fileno(STDIN)"))
        #expect(scriptContent.contains("sysread(STDIN, $buffer, 4_096)"))

        // 验证父进程检测
        #expect(scriptContent.contains("while (getppid() == $adapter_pid)"))

        // 验证清理机制
        #expect(scriptContent.contains("kill 'TERM', $adapter_pid"))
        #expect(scriptContent.contains("kill 'KILL', $adapter_pid"))
    }

    @Test
    func adapterClientClosesLifecyclePipeOnStop() {
        let client = MediaRemoteAdapterClient()

        // 验证 stop 方法存在并可调用
        client.stop()

        #expect(!client.isListening)
    }
}
