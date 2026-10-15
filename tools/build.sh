#!/usr/bin/env bash
# Runs the test suites, then exports Android (debug-signed APK), Linux and Windows builds into builds/.
# Usage: tools/build.sh [version-name]   (version code is read from export_presets.cfg)
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . res://tests/run_tests.tscn | tail -1
godot --headless --path . res://tests/ui_smoke.tscn | grep "UI SMOKE"
mkdir -p builds/linux builds/windows
VER="$(grep -m1 '^version/name=' export_presets.cfg | cut -d'"' -f2)"
godot --headless --path . --export-debug "Android" "builds/spd-tactics-v$VER.apk"
godot --headless --path . --export-debug "Linux" "builds/linux/spd-tactics.x86_64"
godot --headless --path . --export-debug "Windows Desktop" "builds/windows/spd-tactics.exe"
tools/verify_apk.sh "builds/spd-tactics-v$VER.apk"
echo "Built builds/spd-tactics-v$VER.apk"
