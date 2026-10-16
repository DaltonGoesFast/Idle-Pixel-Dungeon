#!/usr/bin/env bash
# Unpacks an exported APK's game files and checks they load with desktop Godot (headless).
# Usage: tools/verify_apk.sh path/to/game.apk
set -euo pipefail
APK="${1:?apk path}"
SDK="${ANDROID_HOME:-$HOME/Android/sdk}"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
"$BT/apksigner" verify "$APK" && echo "ok apksigner"
# Same signing certificate as the published releases, or Android refuses to update in place
# (the in-game updater and sideloads fail with "App not installed"). DECISIONS #141.
CERT_FILE="$(dirname "$0")/release_cert.sha256"
if [ -f "$CERT_FILE" ]; then
  WANT="$(grep -v '^#' "$CERT_FILE" | head -n1 | tr -d '[:space:]' | tr 'A-F' 'a-f')"
  GOT="$("$BT/apksigner" verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n1 | tr 'A-F' 'a-f')"
  if [ "$GOT" = "$WANT" ]; then
    echo "ok signing certificate matches the published releases"
  elif [ "${ALLOW_NEW_SIGNING_KEY:-0}" = "1" ]; then
    echo "WARN signing certificate $GOT differs from the releases ($WANT); phones must uninstall first (ALLOW_NEW_SIGNING_KEY=1)"
  else
    echo "SIGNING KEY MISMATCH: APK is signed by $GOT but published releases use $WANT."
    echo "  Phones with a release installed cannot update to this APK (the in-game updater shows Android's 'App not installed')."
    echo "  Point export/android/debug_keystore at the release keystore, or set ALLOW_NEW_SIGNING_KEY=1 and update tools/release_cert.sha256 on purpose -> FAIL"
    exit 1
  fi
fi
TMP="$(mktemp -d)"
unzip -q "$APK" 'assets/*' -d "$TMP"
cp "$(dirname "$0")/verify_pack.gd" "$TMP/assets/"
"${GODOT:-godot}" --headless --path "$TMP/assets" -s verify_pack.gd
rm -rf "$TMP"
