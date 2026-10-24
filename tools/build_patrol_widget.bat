@echo off
REM Build the PatrolWidget AARs. Needs JDK 17+, ANDROID_HOME with Android SDK 35, and gradlew in the plugin dir.
REM Does not sign the game. Export the APK from Godot on this PC; the debug keystore is unchanged.
setlocal
cd /d "%~dp0..\addons\patrol_widget\android"
if not exist gradlew.bat (
	echo Gradle wrapper missing. In this folder run: gradle wrapper --gradle-version 8.10.2
	exit /b 1
)
call gradlew.bat assemble
if errorlevel 1 exit /b 1
copy /Y build\outputs\aar\PatrolWidget-debug.aar ..\bin\debug\PatrolWidget-debug.aar
if errorlevel 1 exit /b 1
copy /Y build\outputs\aar\PatrolWidget-release.aar ..\bin\release\PatrolWidget-release.aar
if errorlevel 1 exit /b 1
echo PatrolWidget AARs are in addons\patrol_widget\bin
echo Export the Android preset in Godot. Gradle build is already on. Signing is unchanged.
exit /b 0
