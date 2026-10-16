#!/usr/bin/env bash
# Unpacks an exported APK's game files and checks they load with desktop Godot (headless).
# Usage: tools/verify_apk.sh path/to/game.apk
set -euo pipefail
APK="${1:?apk path}"
SDK="${ANDROID_HOME:-$HOME/Android/sdk}"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"

# apksigner is a Java program. Godot's Android export finds Java through its own editor setting
# (export/android/java_sdk_path), so a machine that exports fine can still lack `java` on PATH.
# Look in PATH, then JAVA_HOME, then that editor setting (DECISIONS #150).
find_java_home() {
  if [ -n "${JAVA_HOME:-}" ] && { [ -x "$JAVA_HOME/bin/java" ] || [ -x "$JAVA_HOME/bin/java.exe" ]; }; then
    printf '%s\n' "$JAVA_HOME"; return 0
  fi
  local dir f j
  for dir in "${XDG_CONFIG_HOME:-$HOME/.config}/godot" "$HOME/Library/Application Support/Godot" "${APPDATA:-}/Godot"; do
    [ -d "$dir" ] || continue
    # newest editor version first; read line by line so "Application Support" (a space) is safe
    while IFS= read -r f; do
      j="$(sed -n 's/^export\/android\/java_sdk_path = "\(.*\)"$/\1/p' "$f" | head -n1)"
      if [ -n "$j" ] && { [ -x "$j/bin/java" ] || [ -x "$j/bin/java.exe" ]; }; then
        printf '%s\n' "$j"; return 0
      fi
    done < <(ls -1 "$dir"/editor_settings-4*.tres 2>/dev/null | sort -rV)
  done
  return 1
}
if ! command -v java >/dev/null 2>&1; then
  if JH="$(find_java_home)"; then
    export JAVA_HOME="$JH"; export PATH="$JH/bin:$PATH"
    echo "ok java from $JH"
  else
    echo "JAVA NOT FOUND: apksigner needs Java to check the APK signature."
    echo "  Put java on PATH, set JAVA_HOME, or set Editor Settings > Export > Android > Java SDK Path -> FAIL"
    exit 1
  fi
fi

if ! "$BT/apksigner" verify "$APK"; then
  echo "apksigner could not verify $APK -> FAIL"
  exit 1
fi
echo "ok apksigner"
# Same signing certificate as the published releases, or Android refuses to update in place
# (the in-game updater and sideloads fail with "App not installed"). DECISIONS #141.
CERT_FILE="$(dirname "$0")/release_cert.sha256"
if [ -f "$CERT_FILE" ]; then
  WANT="$(grep -v '^#' "$CERT_FILE" | head -n1 | tr -d '[:space:]' | tr 'A-F' 'a-f')"
  GOT="$("$BT/apksigner" verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n1 | tr 'A-F' 'a-f')"
  if [ -z "$GOT" ]; then
    echo "Could not read the signing certificate of $APK (apksigner verify --print-certs) -> FAIL"
    exit 1
  elif [ "$GOT" = "$WANT" ]; then
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
