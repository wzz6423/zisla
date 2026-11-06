#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
python3 - "$MAC_ROOT" <<'PYTHON'
from pathlib import Path
import json
import os
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import uuid

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="zisla-fresh-profile-tests.") as directory:
    temporary = Path(directory)
    swift = temporary / "main.swift"
    swift.write_text('''import Foundation

let manager = FileManager.default
let defaults = UserDefaults.standard
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "cleanup" {
    defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    defaults.synchronize()
} else {
    if CommandLine.arguments.count > 1 {
        defaults.set(CommandLine.arguments[1], forKey: "fixture-choice")
        defaults.set(Data(CommandLine.arguments[1].utf8), forKey: "feature-settings-v1")
        defaults.synchronize()
    }
    let support = LegacyAppDataMigration.applicationSupport
    try manager.createDirectory(at: support, withIntermediateDirectories: true)
    let onboarding = FirstLaunchOnboardingState(hasExistingInstallation: defaults.data(forKey: "feature-settings-v1") != nil)
    let paths: [String: Any] = [
        "home": manager.homeDirectoryForCurrentUser.path,
        "support": support.path,
        "database": support.appendingPathComponent("clipboard-history.sqlite").path,
        "downloads": manager.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path,
        "bundle": Bundle.main.bundleIdentifier!,
        "choice": defaults.string(forKey: "fixture-choice") ?? "missing",
        "onboarding": onboarding.shouldPresent,
        "debug": LegacyAppDataMigration.isDebugBuild,
    ]
    print(String(data: try JSONSerialization.data(withJSONObject: paths), encoding: .utf8)!)
}
''')
    executable = temporary / "profile-probe"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-module-cache-path", str(temporary / "ModuleCache"),
        str(swift), str(root / "Sources/ZislaCore/FirstLaunchOnboardingState.swift"),
        str(root / "Sources/ZislaCore/LegacyAppDataMigration.swift"), "-o", str(executable)], check=True)

    # Use fixture-only identities, never the user's debug or release preference domain.
    old_home = temporary / "saved-home"
    old_home.mkdir()
    saved_app = temporary / "saved/Probe.app"
    fresh_app = temporary / "fresh/Probe.app"
    identities = {}
    fixture_prefix = "dev.wzz.zisla.debug.fresh.fixture-" + str(uuid.uuid4())
    identity = fixture_prefix + "-saved"
    fixture_domains = {"dev.wzz.zisla.debug": identity}

    def prepare(app, bundle):
        assert bundle.startswith(fixture_prefix + "-"), "Probes must never access a production preference domain"
        (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
        binary = app / "Contents/MacOS/profile-probe"
        binary.write_bytes(executable.read_bytes())
        binary.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "profile-probe", "CFBundleIdentifier": bundle,
            "ZislaApplicationSupportDirectory": "zisla-debug"}))

    prepare(saved_app, identity)
    identities[identity] = saved_app
    environment = {key: value for key, value in os.environ.items()
        if key not in ("CFFIXED_USER_HOME", "ZISLA_FIRST", "ZISLA_FRESH_START", "ZISLA_DEBUG_BUNDLE_ID")}
    environment["CFFIXED_USER_HOME"] = str(old_home)

    def probe(app, launch_environment, *arguments):
        domain = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
        assert domain.startswith(fixture_prefix + "-"), "Only this fixture's randomized domains may be read or changed"
        probe_environment = dict(environment, **launch_environment)
        assert Path(probe_environment["CFFIXED_USER_HOME"]).resolve().is_relative_to(temporary.resolve()), "Probes must stay inside this test's temporary home"
        result = subprocess.run([str(app / "Contents/MacOS/profile-probe"), *arguments],
            env=probe_environment, capture_output=True, text=True, timeout=10, check=True)
        return json.loads(result.stdout) if result.stdout else None

    def record(database, value):
        with sqlite3.connect(database) as connection:
            connection.execute("CREATE TABLE IF NOT EXISTS history (value TEXT)")
            connection.execute("INSERT INTO history VALUES (?)", (value,))

    def values(database):
        with sqlite3.connect(database) as connection:
            return connection.execute("SELECT value FROM history").fetchall()

    try:
        saved = probe(saved_app, {"CFFIXED_USER_HOME": str(old_home), "ZISLA_FIRST": "0"}, "saved-choice")
        record(saved["database"], "important-history")

        # Keep real launchd and the running app untouched; execute the real start path with stubs.
        scripts = temporary / "mac/Scripts"
        scripts.mkdir(parents=True)
        (scripts / "build-app.sh").write_text('''#!/bin/zsh
set -euo pipefail
mkdir -p "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS"
cp "$TEST_PROBE_BINARY" "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
plutil -create xml1 "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "$ZISLA_DEBUG_BUNDLE_ID" "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
''')
        (scripts / "build-app.sh").chmod(0o755)
        shell = '''set -euo pipefail
source "$SOURCE_DEV_SERVICE"
ROOT="$TEST_ROOT/mac"
APP_DIRECTORY="$TEST_ROOT/dist"
APP="$APP_DIRECTORY/zisla-debug.app"
APP_BINARY="$APP/Contents/MacOS/zisla"
SERVICE_LOCK="$TEST_ROOT/cache/service.lock"
LAUNCH_AGENT="$TEST_ROOT/LaunchAgents/service.plist"
OUT_LOG="$TEST_ROOT/logs/stdout.log"
ERROR_LOG="$TEST_ROOT/logs/stderr.log"
function resolve_dev_code_sign_identity() { print -r -- TEST_IDENTITY }
function service_is_loaded() { return 1 }
function matching_app_pids() { return 0 }
function wait_for_processes_to_exit() { return 0 }
function wait_for_service_to_run() { print -r -- 4242 }
function launchctl() { return 0 }
run_service_command run
'''
        service_environment = dict(environment, SOURCE_DEV_SERVICE=str(root / "Scripts/dev-service.sh"),
            TEST_ROOT=str(temporary), TEST_PROBE_BINARY=str(executable), ZISLA_FIRST="0")

        def launch(value):
            subprocess.run(["zsh", "-c", shell], env=dict(service_environment, ZISLA_FRESH_START=value),
                capture_output=True, text=True, timeout=10, check=True)
            agent = plistlib.loads((temporary / "LaunchAgents/service.plist").read_bytes())
            bundle = plistlib.loads((temporary / "dist/zisla-debug.app/Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
            return agent["EnvironmentVariables"], bundle

        def fixture_domain(bundle):
            if bundle not in fixture_domains:
                fixture_domains[bundle] = fixture_prefix + "-" + str(len(fixture_domains))
            return fixture_domains[bundle]

        first_environment, first_bundle = launch("1")
        assert first_bundle.startswith("dev.wzz.zisla.debug.fresh."), "Fresh launch requires an isolated preference domain"
        first_domain = fixture_domain(first_bundle)
        prepare(fresh_app, first_domain)
        identities[first_domain] = fresh_app
        first = probe(fresh_app, first_environment)
        assert first["choice"] == "missing" and first["onboarding"] and first["debug"], first
        assert first["bundle"] != saved["bundle"], "Fresh preferences must not share the saved domain"
        assert first["home"] == first_environment["CFFIXED_USER_HOME"], first
        assert first["support"] == str(Path(first["home"]) / "Library/Application Support/zisla-debug"), first
        assert first["downloads"] == str(Path(first["home"]) / "Downloads"), first
        assert first["database"] != saved["database"] and not Path(first["database"]).exists(), "Fresh database must start empty"
        record(first["database"], "test-history")
        probe(fresh_app, first_environment, "test-choice")
        restarted = probe(fresh_app, first_environment)
        assert restarted["choice"] == "test-choice" and values(restarted["database"]) == [("test-history",)], "KeepAlive restart must preserve this test session"

        second_environment, second_bundle = launch("1")
        assert second_bundle.startswith("dev.wzz.zisla.debug.fresh."), "Repeated fresh launch requires an isolated preference domain"
        second_app = temporary / "second/Probe.app"
        second_domain = fixture_domain(second_bundle)
        prepare(second_app, second_domain)
        identities[second_domain] = second_app
        second = probe(second_app, second_environment)
        assert second["choice"] == "missing" and second["onboarding"], second
        assert second["home"] != first["home"] and second_bundle != first_bundle, "Every explicit fresh run must isolate previous tests"
        assert not Path(second["database"]).exists(), "The next fresh run must not reuse the previous database"

        normal_environment, normal_bundle = launch("0")
        assert normal_bundle == "dev.wzz.zisla.debug" and "CFFIXED_USER_HOME" not in normal_environment, "Normal launch must restore the regular identity and home"
        restored = probe(saved_app, dict(normal_environment, CFFIXED_USER_HOME=str(old_home)))
        assert not restored["onboarding"] and restored["choice"] == "saved-choice", restored
        assert values(restored["database"]) == [("important-history",)], "Original history must remain unchanged"
        print("PASS: 5 fresh profile system cases: clean launch, defaults/database isolation, same-session restart, fresh rerun, saved-data restoration")
    finally:
        for bundle, app in identities.items():
            # The probe removes only the exact randomized domain owned by this fixture.
            prepare(app, bundle)
            probe(app, {"CFFIXED_USER_HOME": str(temporary)}, "cleanup")
PYTHON
