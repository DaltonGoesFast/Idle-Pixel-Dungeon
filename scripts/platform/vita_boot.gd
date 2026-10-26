## First autoload. On PS Vita, writes user://vita_boot.log as soon as GDScript starts.
## That path is ux0:/data/idlepd-saves/vita_boot.log. The loader log is a different file,
## ux0:data/logs/godot_loader.log, written by eboot.bin before this script exists.
## Engine logs land in ux0:data/idlepd/logs/ only after libgodot.so reaches main().
extends Node

const LOG := "user://vita_boot.log"

func _init() -> void:
	_mark("init")

func _ready() -> void:
	_mark("ready")

func _mark(stage: String) -> void:
	if OS.get_name() != "Vita":
		return
	var line := "%s static=%d peak=%d user=%s\n" % [stage, OS.get_static_memory_usage(), OS.get_static_memory_peak_usage(), OS.get_user_data_dir()]
	printerr("[vita-boot] " + line.strip_edges())
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(line)
	f.close()
