# Building for Android

## Prerequisites (already set up on the build box)
- Godot **4.7.2 stable** (standard) + export templates in `~/.local/share/godot/export_templates/4.7.2.stable/`.
- **JDK 17** (Temurin) - box: `/workspace/tools/jdk17`.
- **Android SDK**: platform-tools, build-tools 35.0.1 + 36.0.0, platforms 35 + 36 (Godot 4.7 targets SDK 36) - box: `~/Android/sdk`.
- Editor settings (`~/.config/godot/editor_settings-4.7.tres`): `export/android/java_sdk_path`, `android_sdk_path`, `debug_keystore` (+ user `androiddebugkey`, pass `android`).
- Debug keystore: `keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`. **Never commit keystores** (`.gitignore` covers `*.keystore`).

## On your own machine
1. Install the above, open the project in Godot, Editor > Editor Settings > Export > Android: set Java SDK path, Android SDK path and the debug keystore.
2. Project > Export > Android > Export Project (debug) or run `tools/build.sh`.

## Preset notes (`export_presets.cfg`)
- arm64-v8a only, `screen/immersive_mode=true`, `edge_to_edge=true`, orientation **sensor** (project setting `display/window/handheld/orientation=6`).
- Gradle build **off** (plain APK from the official template). `custom_template/*` must stay empty - see DECISIONS.md #2.
- `include_filter="data/*.json"` is required: JSON isn't a Godot resource and is otherwise left out of the pack.
- Bump `version/code` (integer, must increase) and `version/name` for every release. Keep the iOS preset's `application/short_version` and `application/version` in step with those (see `docs/BUILD_IOS.md`).

## Installing
Sideload: copy the APK to the phone and open it (allow "install unknown apps"), or `adb install -r builds/spd-tactics-vX.apk`. Builds are signed with the same debug key, so updates install over each other. A release build needs a real keystore (Project > Export > Release keystore) and `--export-release`.

## iOS
See [BUILD_IOS.md](BUILD_IOS.md). Export produces an Xcode project; signing and TestFlight happen on a Mac.
