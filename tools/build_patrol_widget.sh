#!/usr/bin/env bash
# Build the PatrolWidget Android library (Godot v2 plugin) into addons/patrol_widget/bin.
# Needs JDK 17 or newer, ANDROID_HOME (SDK platform 35), and the Gradle wrapper in the plugin dir.
# Does not sign the game. Release APKs are still exported on your PC with the debug keystore.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/addons/patrol_widget/android"
if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
	echo "Set ANDROID_HOME to an Android SDK with platforms;android-35." >&2
	exit 1
fi
cd "$ANDROID"
if [[ ! -x ./gradlew ]]; then
	echo "Gradle wrapper missing. From addons/patrol_widget/android run: gradle wrapper --gradle-version 8.10.2" >&2
	exit 1
fi
./gradlew assemble
cp -f build/outputs/aar/PatrolWidget-debug.aar "$ROOT/addons/patrol_widget/bin/debug/PatrolWidget-debug.aar"
cp -f build/outputs/aar/PatrolWidget-release.aar "$ROOT/addons/patrol_widget/bin/release/PatrolWidget-release.aar"
echo "Wrote addons/patrol_widget/bin/debug/PatrolWidget-debug.aar"
echo "Wrote addons/patrol_widget/bin/release/PatrolWidget-release.aar"
echo "Export the Android preset in Godot (Gradle build is already on). The PatrolWidget plugin is enabled in project.godot."
