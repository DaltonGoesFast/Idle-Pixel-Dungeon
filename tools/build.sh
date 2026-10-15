#!/usr/bin/env bash
# Runs the test suites, then exports Android (debug-signed APK), Linux and Windows builds into builds/.
# Usage: tools/build.sh [version-name]   (version code is read from export_presets.cfg)
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1 || true
# fail the build on any GDScript runtime error, even if the suite itself reported PASS
godot --headless --path . res://tests/run_tests.tscn > /tmp/spd_tests.log 2>&1; grep "TESTS:.*-> PASS" /tmp/spd_tests.log
godot --headless --path . res://tests/ui_smoke.tscn > /tmp/spd_smoke.log 2>&1 || true
grep "UI SMOKE: PASS" /tmp/spd_smoke.log
if grep -q "SCRIPT ERROR" /tmp/spd_tests.log /tmp/spd_smoke.log; then grep -m5 -A2 "SCRIPT ERROR" /tmp/spd_tests.log /tmp/spd_smoke.log; echo "SCRIPT ERRORS -> FAIL"; exit 1; fi
mkdir -p builds/linux builds/windows
VER="$(grep -m1 '^version/name=' export_presets.cfg | cut -d'"' -f2)"
godot --headless --path . --export-debug "Android" "builds/spd-tactics-v$VER.apk"
godot --headless --path . --export-debug "Linux" "builds/linux/spd-tactics.x86_64"
godot --headless --path . --export-debug "Windows Desktop" "builds/windows/spd-tactics.exe"
tools/verify_apk.sh "builds/spd-tactics-v$VER.apk"
echo "Built builds/spd-tactics-v$VER.apk"
