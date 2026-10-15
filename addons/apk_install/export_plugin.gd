@tool
extends EditorPlugin

## Injects android.permission.REQUEST_INSTALL_PACKAGES into Gradle Android exports.
## Install itself is done from GDScript via JavaClassWrapper + AndroidRuntime (no AAR).

var _export_plugin: ApkInstallExportPlugin

func _enter_tree() -> void:
	_export_plugin = ApkInstallExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class ApkInstallExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "ApkInstall"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n'
