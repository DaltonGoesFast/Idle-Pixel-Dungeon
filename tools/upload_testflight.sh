#!/usr/bin/env bash
# Archive the iOS Xcode export and upload it to App Store Connect (TestFlight).
# Mac only. Team ID / API key stay out of git.
#
# Env (optional):
#   APPLE_TEAM_ID
#   APP_STORE_CONNECT_API_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_API_KEY_PATH
#   GODOT  (path to Godot 4.7.2 binary; default: godot on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "upload_testflight.sh runs on macOS only (needs xcodebuild)."
  exit 1
fi
if ! command -v xcodebuild >/dev/null; then
  echo "xcodebuild not on PATH. Install Xcode."
  exit 1
fi

TEAM_ID="${APPLE_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(grep -m1 '^application/app_store_team_id=' export_presets.cfg | cut -d'"' -f2 || true)"
fi
if [ -z "$TEAM_ID" ]; then
  echo "Set APPLE_TEAM_ID or paste application/app_store_team_id into export_presets.cfg locally (leave it out of git)."
  exit 1
fi

IOS_CODE="$(grep -m1 '^application/version=' export_presets.cfg | cut -d'"' -f2)"
IOS_VER="$(grep -m1 '^application/short_version=' export_presets.cfg | cut -d'"' -f2)"
if [ -z "$IOS_CODE" ] || [ -z "$IOS_VER" ]; then
  echo "Missing application/version or application/short_version in export_presets.cfg."
  exit 1
fi
echo "Uploading Idle PD $IOS_VER ($IOS_CODE) to App Store Connect…"

PROJ="builds/ios/spd-tactics.xcodeproj"
if [ ! -d "$PROJ" ]; then
  GODOT_BIN="${GODOT:-godot}"
  mkdir -p builds/ios
  echo "Exporting iOS Xcode project with $GODOT_BIN…"
  "$GODOT_BIN" --headless --path . --export-release "iOS" "$PROJ"
fi
if [ ! -d "$PROJ" ]; then
  echo "Missing $PROJ after export."
  exit 1
fi

ARCHIVE="builds/ios/spd-tactics.xcarchive"
rm -rf "$ARCHIVE"
echo "Archiving…"
xcodebuild \
  -project "$PROJ" \
  -scheme spd-tactics \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

EXPORT_PLIST="$(mktemp -t spd-tf-export).plist"
cleanup() { rm -f "$EXPORT_PLIST"; }
trap cleanup EXIT
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF

AUTH_ARGS=()
if [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ] && [ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" ] && [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
  AUTH_ARGS=(
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
    -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
  )
  echo "Using App Store Connect API key…"
else
  echo "Using the Apple ID signed into Xcode…"
fi

EXPORT_DIR="builds/ios/export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
echo "Uploading archive…"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"

echo "Upload finished. App Store Connect will process the build; TestFlight shows it for internal testers when ready."
echo "External groups still need a one-time enable in App Store Connect if you have not done that yet."
