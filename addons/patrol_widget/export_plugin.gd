@tool
extends EditorPlugin

## v2 Android plugin (Godot 4.2+). The AAR is produced by tools/build_patrol_widget.sh into bin/.
## A missing AAR does not fail the export: the game runs, and the widget is simply not in that APK.

var _export_plugin: PatrolWidgetExport

func _enter_tree() -> void:
	_export_plugin = PatrolWidgetExport.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class PatrolWidgetExport extends EditorExportPlugin:
	var _plugin_name := "PatrolWidget"

	func _get_name() -> String:
		return _plugin_name

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var rel := "patrol_widget/bin/debug/PatrolWidget-debug.aar" if debug else "patrol_widget/bin/release/PatrolWidget-release.aar"
		if FileAccess.file_exists("res://addons/" + rel):
			return PackedStringArray([rel])
		push_warning("PatrolWidget AAR missing (addons/%s). Run tools/build_patrol_widget.sh (or the .bat) before this Android export, or the home-screen widget will not be in the APK." % rel)
		return PackedStringArray()

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray()

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
"""

	## Godot writes this into the app manifest. The AAR also declares it; both are required so a
	## merger that drops library application meta-data still registers the v2 singleton.
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """<meta-data android:name="org.godotengine.plugin.v2.PatrolWidget" android:value="com.daltongoesfast.spdtactics.patrol.PatrolWidgetPlugin" />
"""
