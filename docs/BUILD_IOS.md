# Building for iOS (TestFlight)

A PC or a Mac can export the Xcode project. A Mac with Xcode and the Apple Developer account signs it and uploads to TestFlight. This repo does not store certificates or the Team ID.

The preset is `iOS` in `export_presets.cfg`. It matches the Android package id, version name, and version code. `application/export_project_only=true`, so the export stops at an `.xcodeproj` and does not archive or upload. Release export method is App Store. Devices are iPhone and iPad, arm64, iOS 14+. The icon is scaled with nearest-neighbor so the pixel art stays sharp. `ITSAppUsesNonExemptEncryption` is false (no custom crypto). Godot 4.7's iOS Info.plist template already writes that key, so `application/additional_plist_content` stays empty: anything put there is appended verbatim, and a key the template already has ends up in the plist twice (DECISIONS #136, `test_export_presets`).

`application/short_version` must stay equal to `version/name` and `project.godot`'s `config/version`. `application/version` must stay equal to Android `version/code` and must go up for every TestFlight upload. `tools/build.sh` fails if those drift.

Godot refuses to export while `application/app_store_team_id` is empty. Paste the 10-character Team ID from [developer.apple.com](https://developer.apple.com) (the code next to the account name, not the display name). Set it locally and leave it out of git. You can also pass `APPLE_TEAM_ID` to the upload script without writing the preset.

There is no in-app update check on iOS. Testers get new builds from the TestFlight app after App Store Connect finishes processing.

## PC (Windows)

1. Install Godot **4.7.2 stable** (standard, not .NET).
2. Editor > Manage Export Templates > Download and Install. That places `ios.zip` in `%APPDATA%\Godot\export_templates\4.7.2.stable\`. Official templates only.
3. Paste the Team ID into `application/app_store_team_id` in `export_presets.cfg`. The Mac account holder has this code.
4. Export a release build. In PowerShell, from the repo root (`godot` must be on PATH, or call `Godot_v4.7.2-stable_win64_console.exe` by its full path):

```powershell
New-Item -ItemType Directory -Force -Path builds\ios
godot --headless --path . --export-release "iOS" "builds/ios/spd-tactics.xcodeproj"
```

The editor path is the same result: Project > Export > iOS > Export Project, with Export With Debug off, to `builds/ios/spd-tactics.xcodeproj`.

Windows writes `builds/ios/spd-tactics.xcodeproj` and the `builds/ios/spd-tactics/` payload (engine, pack, icons, privacy manifest). Zip `builds/ios` and send that folder to the Mac. Sending the repo alone is enough when the Mac will export it.

## Mac

1. Install Godot **4.7.2 stable** and the iOS export templates the same way. They land in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip`. Xcode needs the developer account signed in.
2. In [App Store Connect](https://appstoreconnect.apple.com), create an app with bundle ID `com.daltongoesfast.spdtactics` (same id as the Android package) if it does not exist yet. Xcode automatic signing can register that App ID when the account is allowed to.
3. Paste the Team ID into `application/app_store_team_id` if this clone does not already have it, or export `APPLE_TEAM_ID`.
4. Export when this Mac is starting from the repo rather than from a `builds/ios` folder the PC already sent:

```bash
mkdir -p builds/ios
godot --headless --path . --export-release "iOS" "builds/ios/spd-tactics.xcodeproj"
```

On a Mac, Godot also codesigns the shipped dylibs with **Apple Distribution**. A missing Apple Distribution certificate stops the export at that step. A project exported on Windows arrives with those libraries unsigned; Xcode signs them during Archive. If Archive rejects them, run the export command above on the Mac.

5. Upload to TestFlight with the script (scheme `spd-tactics`, Release, App Store Connect):

```bash
tools/upload_testflight.sh
```

It archives `builds/ios/spd-tactics.xcodeproj` (exports first if the project is missing), then uploads. Auth is the Apple ID already signed into Xcode, or an App Store Connect API key via `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_PATH` (`.p8` outside the repo). Apple rejects a repeat of `application/version`; bump it with the Android `version/code` before each upload.

Manual path if you need it: open the `.xcodeproj`, Signing & Capabilities → Team + Automatically manage signing, Product → Archive → Distribute App → App Store Connect → Upload.

After processing, internal TestFlight testers see the build. The first external group is still a one-time click in App Store Connect.

## What to check on a phone

The layout is the same aspect split as the Fold: tall screens stack, wide screens sit side by side, and the notch and home indicator are inset. Camp should be on screen at launch. A black screen on launch is a renderer problem (the project uses the Compatibility renderer, which Godot 4.7 runs on iOS through ANGLE) and is the first thing to report.
