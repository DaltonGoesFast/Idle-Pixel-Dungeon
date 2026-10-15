# Building for iOS (TestFlight)

Godot on any machine can write an Xcode project. Signing and the upload to TestFlight happen on a Mac with Xcode and an Apple Developer account. This repo does not store certificates or the Team ID.

The preset is `iOS` in `export_presets.cfg`. It matches the Android package id, version name, and version code. `application/export_project_only=true`, so the export stops at an `.xcodeproj` and does not archive or upload. Release export method is App Store. Devices are iPhone and iPad, arm64, iOS 14+. The icon is scaled with nearest-neighbor so the pixel art stays sharp. `ITSAppUsesNonExemptEncryption` is false (no custom crypto).

## Before the first export

1. Install Godot **4.7.2 stable** and the matching iOS export templates (`ios.zip` in the export templates folder). Official templates only, same rule as Android.
2. In [App Store Connect](https://appstoreconnect.apple.com), create an app with bundle ID `com.daltongoesfast.spdtactics` (same id as the Android package). Xcode automatic signing can register the App ID if the account is allowed to.
3. Copy the 10-character Team ID from [developer.apple.com](https://developer.apple.com) (the code next to the account name, not the display name) into `application/app_store_team_id`. Godot refuses to export while that field is empty. Leave the Team ID out of git if this checkout is shared; set it locally before exporting.

`application/short_version` must stay equal to `version/name` and `project.godot`'s `config/version`. `application/version` must stay equal to Android `version/code` and must go up for every TestFlight upload. `tools/build.sh` fails if those drift.

## Export

```bash
mkdir -p builds/ios
godot --headless --path . --export-release "iOS" "builds/ios/spd-tactics.xcodeproj"
```

That writes `builds/ios/spd-tactics.xcodeproj` and a `builds/ios/spd-tactics/` payload (engine, pack, icons, privacy manifest). On a Mac, Godot also codesigns the shipped dylibs with **Apple Distribution**. If that step fails, the Apple Distribution certificate is missing from the keychain.

## Upload

Open the `.xcodeproj` in Xcode (or point the existing pipeline at it):

- Signing & Capabilities: the Team from the developer account, Automatically manage signing.
- Product > Archive, then Distribute App > App Store Connect > Upload.
- The build shows up in TestFlight after processing.

A pipeline that already archives an Xcode project and uploads to App Store Connect can take this project as-is. Scheme name is `spd-tactics`. Configuration for a store build is Release.

## What to check on a phone

The layout is the same aspect split as the Fold: tall screens stack, wide screens sit side by side, and the notch and home indicator are inset. Camp should be on screen at launch. A black screen on launch is a renderer problem (the project uses the Compatibility renderer, which Godot 4.7 runs on iOS through ANGLE) and is the first thing to report.
