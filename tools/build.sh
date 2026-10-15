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
PVER="$(grep -m1 '^config/version=' project.godot | cut -d'"' -f2)"
if [ "$VER" != "$PVER" ]; then echo "VERSION MISMATCH export_presets=$VER project.godot=$PVER -> FAIL"; exit 1; fi
IOS_VER="$(grep -m1 '^application/short_version=' export_presets.cfg | cut -d'"' -f2)"
IOS_CODE="$(grep -m1 '^application/version=' export_presets.cfg | cut -d'"' -f2)"
CODE="$(grep -m1 '^version/code=' export_presets.cfg | cut -d'=' -f2)"
if [ "$IOS_VER" != "$VER" ] || [ "$IOS_CODE" != "$CODE" ]; then echo "VERSION MISMATCH ios=$IOS_VER ($IOS_CODE) android=$VER ($CODE) -> FAIL"; exit 1; fi
godot --headless --path . --export-debug "Android" "builds/spd-tactics-v$VER.apk"
godot --headless --path . --export-debug "Linux" "builds/linux/spd-tactics.x86_64"
godot --headless --path . --export-debug "Windows Desktop" "builds/windows/spd-tactics.exe"
tools/verify_apk.sh "builds/spd-tactics-v$VER.apk"
echo "Built builds/spd-tactics-v$VER.apk"
# screenshots: non-blocking but reported (needs xvfb-run; full plan, cover + inner)
if command -v xvfb-run >/dev/null; then
  if timeout 600 xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn > /tmp/spd_shots.log 2>&1; then :; fi
  NERR=$(grep -c "SCRIPT ERROR" /tmp/spd_shots.log || true)
  NSHOT=$(find /workspace/builds/shots -name '*.png' -newer "builds/spd-tactics-v$VER.apk" | wc -l)
  if [ "$NERR" = "0" ]; then echo "SCREENSHOTS: OK ($NSHOT png in /workspace/builds/shots)"; else echo "SCREENSHOTS: WARN $NERR script errors ($NSHOT png) - see /tmp/spd_shots.log"; fi
else echo "SCREENSHOTS: SKIPPED (no xvfb-run)"; fi
