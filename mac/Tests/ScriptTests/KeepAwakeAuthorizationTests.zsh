#!/bin/zsh
set -euo pipefail

python3 - "${0:A:h:h:h}/Sources/ZislaKit/LidClosedDisplayAuthorization.swift" <<'PYTHON'
import pathlib
import shlex
import subprocess
import sys
import tempfile
import textwrap
import unittest

source = pathlib.Path(sys.argv[1]).read_text()
script = textwrap.dedent(source.split('static let installationScript = #"""\n', 1)[1].split('"""#', 1)[0])


class AuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zisla-keep-awake-permission-")
        self.root = pathlib.Path(self.temp.name)
        self.rules = self.root / "sudoers.d"
        self.rules.mkdir()
        self.rule = self.rules / "zisla-keep-awake-501"
        self.visudo = self.root / "visudo"
        self.visudo.write_text(textwrap.dedent('''\
            #!/bin/sh
            root=$(/usr/bin/dirname "$0")
            if [ "$#" = 3 ]; then
                [ ! -f "$root/syntax-fail" ] || exit 1
                /usr/sbin/visudo "$@" || exit 1
                if [ -f "$root/concurrent-install" ]; then
                    printf 'concurrent rule\n' > "$root/sudoers.d/zisla-keep-awake-501"
                fi
                exit 0
            fi
            [ ! -f "$root/policy-fail" ] || exit 1
            if [ ! -f "$root/not-included" ]; then
                for rule in "$root/sudoers.d"/zisla-keep-awake-*; do
                    [ ! -f "$rule" ] || printf '%s: parsed OK\n' "$rule"
                done
            fi
            '''))
        self.visudo.chmod(0o700)
        chown = self.root / "chown"
        chown.write_text('#!/bin/sh\n[ "$1" = root:wheel ] && [ -f "$2" ]\n')
        chown.chmod(0o700)
        self.script = (script.replace("/private/etc/sudoers.d", str(self.rules))
                      .replace("/usr/sbin/visudo", shlex.quote(str(self.visudo)))
                      .replace("/usr/sbin/chown", shlex.quote(str(chown))))

    def tearDown(self):
        self.temp.cleanup()

    def install(self, *arguments):
        return subprocess.run(["/bin/sh", "-p", "-c", self.script, "zisla-keep-awake", *arguments],
                              capture_output=True, text=True, timeout=5)

    def test_installs_only_the_two_exact_commands_for_one_numeric_user(self):
        result = self.install("501")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "installed\n")
        self.assertEqual(self.rule.read_text(),
                         "#501 ALL=(root) NOPASSWD: NOSETENV: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n")
        self.assertEqual(self.rule.stat().st_mode & 0o777, 0o440)
        self.assertEqual(self.rule.stat().st_nlink, 1)
        self.assertEqual(list(self.rules.iterdir()), [self.rule])

    def test_rejects_missing_root_negative_or_injected_user_ids(self):
        for arguments in [(), ("0",), ("00",), ("-1",), ("501 extra",), ("501", "502"), ("501; touch injected",)]:
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.install(*arguments).returncode, 0)
                self.assertEqual(list(self.rules.iterdir()), [])

    def test_does_not_overwrite_an_existing_rule_or_symlink(self):
        target = self.root / "untouched"
        target.write_text("untouched")
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                if symlink:
                    self.rule.symlink_to(target)
                else:
                    self.rule.write_text("existing rule")
                self.assertNotEqual(self.install("501").returncode, 0)
                self.assertEqual(self.rule.read_text(), "untouched" if symlink else "existing rule")
                self.assertEqual(target.read_text(), "untouched")
                self.rule.unlink()

    def test_failed_validation_or_inactive_include_rolls_back_the_rule(self):
        for failure in ("syntax-fail", "policy-fail", "not-included"):
            with self.subTest(failure=failure):
                flag = self.root / failure
                flag.touch()
                self.assertNotEqual(self.install("501").returncode, 0)
                self.assertEqual(list(self.rules.iterdir()), [])
                flag.unlink()

    def test_concurrent_installation_cannot_replace_the_winning_rule(self):
        (self.root / "concurrent-install").touch()
        self.assertNotEqual(self.install("501").returncode, 0)
        self.assertEqual(self.rule.read_text(), "concurrent rule\n")
        self.assertEqual(list(self.rules.iterdir()), [self.rule])

    def test_refuses_a_symlinked_policy_directory(self):
        self.rules.rmdir()
        target = self.root / "redirected"
        target.mkdir()
        self.rules.symlink_to(target, target_is_directory=True)
        self.assertNotEqual(self.install("501").returncode, 0)
        self.assertEqual(list(target.iterdir()), [])


unittest.main(argv=[sys.argv[0]])
PYTHON
