#!/usr/bin/env bash
# Unpacks an exported APK's game files and checks they load with desktop Godot (headless).
# Usage: tools/verify_apk.sh path/to/game.apk
set -euo pipefail
APK="${1:?apk path}"
SDK="${ANDROID_HOME:-$HOME/Android/sdk}"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
"$BT/apksigner" verify "$APK" && echo "ok apksigner"
TMP="$(mktemp -d)"
unzip -q "$APK" 'assets/*' -d "$TMP"
cp "$(dirname "$0")/verify_pack.gd" "$TMP/assets/"
godot --headless --path "$TMP/assets" -s verify_pack.gd
rm -rf "$TMP"
