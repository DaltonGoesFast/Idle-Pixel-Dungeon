# Building for Android

## Prerequisites (already set up on the build box)
- Godot **4.7.2 stable** (standard) + export templates in `~/.local/share/godot/export_templates/4.7.2.stable/` (must include `android_source.zip`).
- **JDK 17** (Temurin) - box: `/workspace/tools/jdk17`.
- **Android SDK**: platform-tools, build-tools 35.0.1 + 36.0.0, platforms 35 + 36 (Godot 4.7 targets SDK 36) - box: `~/Android/sdk`.
- **NDK r28b** (`ndk;28.1.13356709`) and **CMake 3.10.2.4988404** — required for Gradle exports.
- Editor settings (`~/.config/godot/editor_settings-4.7.tres`): `export/android/java_sdk_path`, `android_sdk_path`, `debug_keystore` (+ user `androiddebugkey`, pass `android`). `tools/verify_apk.sh` reads the same `java_sdk_path` for `apksigner` when `java` is not on `PATH` and `JAVA_HOME` is unset (DECISIONS #150).
- Debug keystore: `keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`. **Never commit keystores** (`.gitignore` covers `*.keystore`).

## On your own machine
1. Install the above, open the project in Godot, Editor > Editor Settings > Export > Android: set Java SDK path, Android SDK path and the debug keystore.
2. First Gradle export: Project > Install Android Build Template… (or let `tools/build.sh` unpack `android_source.zip` into `android/build/`, which is gitignored).
3. Project > Export > Android > Export Project (debug) or run `tools/build.sh`.

## Preset notes (`export_presets.cfg`)
- **Preset (`export_presets.cfg`):** `preset.0` (`Android`), arm64-v8a only, `screen/immersive_mode=true`, `edge_to_edge=true`, orientation **sensor** (project setting `display/window/handheld/orientation=6`). Gradle build **on** (`gradle_build/use_gradle_build=true` — still the official engine template; `custom_template/*` stays empty; see DECISIONS.md #2, #135, #140). `tools/build.sh` unpacks `android_source.zip` into `android/build/` and writes `android/.build_version` (`4.7.2.stable`) and `android/build/.gdignore` when needed.
- `include_filter="data/*.json"` is required: JSON isn't a Godot resource and is otherwise left out of the pack.
- Bump `version/code` (integer, must increase) and `version/name` for every release. Keep the iOS preset's `application/short_version` and `application/version` in step with those (see `docs/BUILD_IOS.md`).

## Installing
Sideload: copy the APK to the phone and open it (allow "install unknown apps"), or `adb install -r builds/spd-tactics-vX.apk`. Updates only install over each other when they are signed with the same key. `tools/verify_apk.sh` fails any APK whose certificate differs from `tools/release_cert.sha256`, the certificate of the published releases (DECISIONS #141). Releases v0.27.0+ use the Godot-generated debug key (`c18cebfa…`). The box's `~/Android/debug.keystore` (`73a874e9…`) only matches v0.26.0. A release build needs a real keystore (Project > Export > Release keystore) and `--export-release`.

From a build that already has the updater: the game checks GitHub on launch and when you bring it back from the background. Camp shows a red badge on Settings (and an Update button in the top bar) when a newer APK is ready; Settings → Update downloads it and opens Android's Install screen. Idle PD needs "Install unknown apps" allowed for that flow.

## iOS
See [BUILD_IOS.md](BUILD_IOS.md). A PC or a Mac exports the Xcode project; the Mac signs it and uploads to TestFlight (`tools/upload_testflight.sh`).
