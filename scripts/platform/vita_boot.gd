## First autoload. On PS Vita, writes user://vita_boot.log as soon as GDScript starts.
## That path is ux0:/data/idlepd-saves/vita_boot.log. The loader log is a different file,
## ux0:data/logs/godot_loader.log, written by eboot.bin before this script exists.
## Engine logs land in ux0:data/idlepd/logs/ only after libgodot.so reaches main().
extends Node

const LOG := "user://vita_boot.log"

## True on the Vita runtime (feature "vita", OS name "Vita"). Desktop, Android, and web stay false.
static func runs_on_vita(vita_feature: bool = OS.has_feature("vita"), os_name: String = OS.get_name()) -> bool:
	return vita_feature or os_name == "Vita"

func _init() -> void:
	mark("init")

func _ready() -> void:
	mark("ready")

func mark(stage: String) -> void:
	if not runs_on_vita():
		return
	var line := "%s static=%d peak=%d user=%s\n" % [stage, OS.get_static_memory_usage(), OS.get_static_memory_peak_usage(), OS.get_user_data_dir()]
	printerr("[vita-boot] " + line.strip_edges())
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(line)
	f.close()
