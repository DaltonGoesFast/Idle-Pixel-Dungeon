#!/usr/bin/env bash
# Runs the test suites, then exports Android (debug-signed APK), Linux and Windows builds into builds/.
# Usage: tools/build.sh [version-name]   (version code is read from export_presets.cfg)
set -euo pipefail
cd "$(dirname "$0")/.."

# Override with GODOT=/path/to/Godot_v4.7.2-stable_win64.exe when `godot` is not on PATH.
GODOT_BIN="${GODOT:-godot}"

# Gradle Android export needs res://android/build from the 4.7.2 export templates (gitignored).
# Mirrors Project > Install Android Build Template: Godot refuses a Gradle export unless
# android/.build_version names this engine version ("no version info for it exists"), DECISIONS #140.
ANDROID_TEMPLATE_VERSION="4.7.2.stable"
ensure_android_template() {
  if [ -d android/build ]; then
    local have
    have="$(head -n1 android/.build_version 2>/dev/null || true)"
    if [ -z "$have" ]; then
      # unpacked by an older build.sh (zip only): stamp it so Godot accepts it
      printf '%s\n' "$ANDROID_TEMPLATE_VERSION" > android/.build_version
      echo "Stamped android/.build_version ($ANDROID_TEMPLATE_VERSION) for the existing android/build"
    elif [ "$have" != "$ANDROID_TEMPLATE_VERSION" ]; then
      echo "android/build is for Godot $have, not $ANDROID_TEMPLATE_VERSION. Reinstall it (Project > Install Android Build Template, or delete android/) -> FAIL"
      exit 1
    fi
    return
  fi
  local zip="${GODOT_ANDROID_SOURCE:-}"
  if [ -z "$zip" ]; then
    local d
    for d in \
      "${HOME}/.local/share/godot/export_templates/4.7.2.stable" \
      "${HOME}/Library/Application Support/Godot/export_templates/4.7.2.stable" \
      "${APPDATA:-}/Godot/export_templates/4.7.2.stable"; do
      if [ -f "$d/android_source.zip" ]; then zip="$d/android_source.zip"; break; fi
    done
  fi
  if [ -z "${zip}" ] || [ ! -f "$zip" ]; then
    echo "Missing android_source.zip (Godot 4.7.2 export templates / Install Android Build Template) -> FAIL"
    exit 1
  fi
  mkdir -p android/build
  unzip -q "$zip" -d android/build
  printf '%s\n' "$ANDROID_TEMPLATE_VERSION" > android/.build_version
  : > android/build/.gdignore
  echo "Installed Android build template ($ANDROID_TEMPLATE_VERSION) into android/build from $zip"
}

"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
# fail the build on any GDScript runtime error, even if the suite itself reported PASS
"$GODOT_BIN" --headless --path . res://tests/run_tests.tscn > /tmp/spd_tests.log 2>&1; grep "TESTS:.*-> PASS" /tmp/spd_tests.log
"$GODOT_BIN" --headless --path . res://tests/ui_smoke.tscn > /tmp/spd_smoke.log 2>&1 || true
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
ensure_android_template
"$GODOT_BIN" --headless --path . --export-debug "Android" "builds/spd-tactics-v$VER.apk"
"$GODOT_BIN" --headless --path . --export-debug "Linux" "builds/linux/spd-tactics.x86_64"
"$GODOT_BIN" --headless --path . --export-debug "Windows Desktop" "builds/windows/spd-tactics.exe"
GODOT="$GODOT_BIN" tools/verify_apk.sh "builds/spd-tactics-v$VER.apk"
echo "Built builds/spd-tactics-v$VER.apk"
# screenshots: non-blocking but reported (needs xvfb-run; full plan, cover + inner)
if command -v xvfb-run >/dev/null; then
  if timeout 600 xvfb-run -a "$GODOT_BIN" --path . --rendering-driver opengl3 res://tests/screenshots.tscn > /tmp/spd_shots.log 2>&1; then :; fi
  NERR=$(grep -c "SCRIPT ERROR" /tmp/spd_shots.log || true)
  NSHOT=$(find /workspace/builds/shots -name '*.png' -newer "builds/spd-tactics-v$VER.apk" | wc -l)
  if [ "$NERR" = "0" ]; then echo "SCREENSHOTS: OK ($NSHOT png in /workspace/builds/shots)"; else echo "SCREENSHOTS: WARN $NERR script errors ($NSHOT png) - see /tmp/spd_shots.log"; fi
else echo "SCREENSHOTS: SKIPPED (no xvfb-run)"; fi
