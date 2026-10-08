#!/bin/zsh
set -euo pipefail

python3 - "${0:A:h:h:h}/Sources/ZislaKit/LidClosedDisplaySession.swift" <<'PYTHON'
import pathlib
import os
import select
import shlex
import socket
import subprocess
import sys
import tempfile
import textwrap
import unittest

source = pathlib.Path(sys.argv[1]).read_text()
script = textwrap.dedent(source.split('static let script = #"""\n', 1)[1].split('"""#', 1)[0])


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zisla-lid-session-test-")
        self.root = pathlib.Path(self.temp.name)
        self.state = self.root / "state"
        self.state.write_text("0")
        self.process = None
        fake = self.root / "fake-pmset"
        fake.write_text(textwrap.dedent('''\
            #!/bin/sh
            root=$(/usr/bin/dirname "$0")
            if [ "$*" = '-g' ]; then
                [ ! -f "$root/read-fail" ] || exit 1
                if [ -f "$root/output" ]; then /bin/cat "$root/output"; exit; fi
                printf 'System-wide power settings:\n'
                value=$(/bin/cat "$root/state")
                if [ "$value" != missing ]; then printf ' SleepDisabled    %s\n' "$value"; fi
                printf 'Currently in use:\n sleep 1\n displaysleep 10\n'
                [ ! -f "$root/read-output-fail" ] || exit 1
                exit 0
            fi
            [ "$1 $2" = '-a disablesleep' ] || exit 2
            printf '%s\n' "$*" >> "$root/writes"
            if [ -f "$root/chatter" ]; then printf 'pmset notice\n'; fi
            if [ "$3" = 1 ]; then
                [ ! -f "$root/enable-fail" ] || exit 1
                [ ! -f "$root/enable-noop" ] || exit 0
                printf 1 > "$root/state"
                if [ -p "$root/enable-gate" ]; then
                    printf 'changed\n' >&2
                    IFS= read -r ready < "$root/enable-gate"
                fi
                [ ! -f "$root/enable-partial-fail" ] || exit 1
            else
                [ ! -f "$root/restore-fail" ] || exit 1
                [ ! -f "$root/restore-noop" ] || exit 0
                printf '%s' "$3" > "$root/state"
            fi
            '''))
        fake.chmod(0o700)
        self.script = script.replace("/usr/bin/pmset", shlex.quote(str(fake)))

    def tearDown(self):
        if self.process:
            if not self.process.stdin.closed:
                self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process.stdout.close()
            self.process.stderr.close()
        self.temp.cleanup()

    def start(self):
        self.process = subprocess.Popen(
            ["/bin/sh", "-p", "-c", self.script],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )

    def line(self):
        self.assertTrue(select.select([self.process.stdout], [], [], 5)[0], "helper response timed out")
        return self.process.stdout.readline().strip()

    def stop(self):
        self.process.stdin.write("stop\n")
        self.process.stdin.flush()
        return self.line()

    def assert_restored(self):
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.state.read_text(), "0")

    def test_enable_and_disable_restore_the_original_setting(self):
        self.start()
        self.assertEqual(self.line(), "ready")
        self.assertEqual(self.state.read_text(), "1")
        self.assertEqual(self.stop(), "restored")
        self.assert_restored()
        self.assertEqual((self.root / "writes").read_text().splitlines(), ["-a disablesleep 1", "-a disablesleep 0"])

    def test_an_existing_disabled_sleep_setting_is_never_overwritten(self):
        self.state.write_text("1")
        self.start()
        self.assertEqual(self.line(), "ready")
        self.assertEqual(self.stop(), "restored")
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.state.read_text(), "1")
        self.assertFalse((self.root / "writes").exists())

    def test_unset_setting_means_normal_sleep(self):
        self.state.write_text("missing")
        self.start()
        self.assertEqual(self.line(), "ready")
        self.assertEqual(self.stop(), "restored")
        self.assert_restored()

    def test_command_output_cannot_be_mistaken_for_a_session_response(self):
        (self.root / "chatter").touch()
        self.start()
        self.assertEqual(self.line(), "ready")
        self.assertEqual(self.stop(), "restored")
        self.assert_restored()

    def test_app_disconnect_restores_sleep_without_another_authorization(self):
        self.start()
        self.assertEqual(self.line(), "ready")
        self.process.stdin.close()
        self.assert_restored()

    def test_helper_termination_restores_sleep(self):
        self.start()
        self.assertEqual(self.line(), "ready")
        self.process.terminate()
        self.process.wait(timeout=5)
        self.assertEqual(self.state.read_text(), "0")

    def test_app_crash_before_ready_still_restores_sleep(self):
        gate = self.root / "enable-gate"
        os.mkfifo(gate)
        parent, child = socket.socketpair()
        process = subprocess.Popen(
            ["/bin/sh", "-p", "-c", self.script],
            stdin=child, stdout=child, stderr=subprocess.PIPE, text=True,
        )
        child.close()
        try:
            self.assertTrue(select.select([process.stderr], [], [], 5)[0])
            self.assertEqual(process.stderr.readline().strip(), "changed")
            parent.close()
            with gate.open("w") as stream:
                stream.write("continue\n")
            process.wait(timeout=5)
            self.assertEqual(self.state.read_text(), "0", f"exit={process.returncode}: {process.stderr.read()}")
        finally:
            parent.close()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            process.stderr.close()

    def test_invalid_command_cannot_be_executed_and_restores_sleep(self):
        self.start()
        self.assertEqual(self.line(), "ready")
        self.process.stdin.write("touch " + str(self.root / "injected") + "\n")
        self.process.stdin.flush()
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertFalse((self.root / "injected").exists())
        self.assertEqual(self.state.read_text(), "0")

    def test_failed_read_never_changes_power_settings(self):
        for failure in ["read-fail", "read-output-fail"]:
            with self.subTest(failure=failure):
                flag = self.root / failure
                flag.touch()
                self.start()
                self.assertEqual(self.line(), "")
                self.assertNotEqual(self.process.wait(timeout=5), 0)
                self.assertFalse((self.root / "writes").exists())
                flag.unlink()
                for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
                    stream.close()

    def test_malformed_settings_cannot_become_shell_arguments(self):
        for value in ["2", "-1", "01", "1 extra", "$(touch injected)", "0\n SleepDisabled 1"]:
            with self.subTest(value=value):
                self.state.write_text(value)
                self.start()
                self.assertEqual(self.line(), "")
                self.assertNotEqual(self.process.wait(timeout=5), 0)
                self.assertFalse((self.root / "writes").exists())
                for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
                    stream.close()

    def test_missing_system_header_is_not_assumed_to_mean_normal_sleep(self):
        (self.root / "output").write_text("Currently in use:\n sleep 0\n")
        self.start()
        self.assertEqual(self.line(), "")
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertFalse((self.root / "writes").exists())

    def test_failed_enable_including_a_partial_write_is_rolled_back(self):
        for failure in ["enable-fail", "enable-partial-fail", "enable-noop"]:
            with self.subTest(failure=failure):
                flag = self.root / failure
                flag.touch()
                self.start()
                self.assertEqual(self.line(), "")
                self.assertNotEqual(self.process.wait(timeout=5), 0)
                self.assertEqual(self.state.read_text(), "0")
                flag.unlink()
                for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
                    stream.close()

    def test_restore_failure_keeps_the_session_available_for_retry(self):
        self.start()
        self.assertEqual(self.line(), "ready")
        for failure in ["restore-fail", "restore-noop"]:
            flag = self.root / failure
            flag.touch()
            self.assertEqual(self.stop(), "failed")
            self.assertIsNone(self.process.poll())
            self.assertEqual(self.state.read_text(), "1")
            flag.unlink()
        self.assertEqual(self.stop(), "restored")
        self.assert_restored()


unittest.main(argv=[sys.argv[0]])
PYTHON
