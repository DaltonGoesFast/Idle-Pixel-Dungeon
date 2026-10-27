## First autoload. On PS Vita, writes user://vita_boot.log as soon as GDScript starts.
## That path is ux0:/data/idlepd-saves/vita_boot.log. The loader log is a different file,
## ux0:data/logs/godot_loader.log, written by eboot.bin before this script exists.
## Engine logs land in ux0:data/idlepd/logs/ only after libgodot.so reaches main().
extends Node

const LOG := "user://vita_boot.log"

## The real handheld. Startup skips (DB load, the save) use this, not the desktop proxy.
static func on_device(vita_feature: bool = OS.has_feature("vita"), os_name: String = OS.get_name()) -> bool:
	return vita_feature or os_name == "Vita"

## True on the Vita runtime (feature "vita", OS name "Vita"). Desktop, Android, and web stay false
## unless IDLEPD_VITA=1, which forces a default call true so a desktop window can run the Vita
## draw path. Explicit args such as runs_on_vita(false, "Android") stay false. The env does not
## make on_device() true, so a proxy still loads db.gd and the save.
static func runs_on_vita(vita_feature: bool = OS.has_feature("vita"), os_name: String = OS.get_name()) -> bool:
	if on_device(vita_feature, os_name):
		return true
	if OS.get_environment("IDLEPD_VITA") == "1" and vita_feature == OS.has_feature("vita") and os_name == OS.get_name():
		return true
	return false

## Microseconds accumulated since the last tick line. Printed by mark_tick, then cleared.
static var _us := {}
## Call counts for the same window (delve_bake_n, grid_bake_n, ...).
static var _n := {}

## No-op off Vita. Names show up on the 2s tick line (delve_proc, grid_draw, ...).
static func add_us(bucket: String, us: int) -> void:
	if us <= 0 or not runs_on_vita():
		return
	_us[bucket] = int(_us.get(bucket, 0)) + us

## No-op off Vita. Pair with add_us so a tick can show how many times a bake ran, not only how long.
static func add_n(bucket: String, n: int = 1) -> void:
	if n <= 0 or not runs_on_vita():
		return
	_n[bucket] = int(_n.get(bucket, 0)) + n

static func take_report() -> String:
	if _us.is_empty() and _n.is_empty():
		return ""
	var keys: Array = _us.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d" % [String(k), int(_us[k])])
	var nk: Array = _n.keys()
	nk.sort()
	for k in nk:
		parts.append("%s=%d" % [String(k), int(_n[k])])
	_us.clear()
	_n.clear()
	return " ".join(parts)

var _log: FileAccess

func _init() -> void:
	mark("init")

func _ready() -> void:
	# Stable handheld target: chasing 60 then hitching to ~7 FPS feels worse than a flat 30.
	if runs_on_vita():
		Engine.max_fps = 30
	mark("ready")

## Boot stages. Opens the save log once and keeps it. Memory figures belong here, not on the 2s tick.
func mark(stage: String) -> void:
	if not runs_on_vita():
		return
	var line := "%s static=%d peak=%d user=%s\n" % [stage, OS.get_static_memory_usage(), OS.get_static_memory_peak_usage(), OS.get_user_data_dir()]
	printerr("[vita-boot] " + line.strip_edges())
	_ensure_log()
	if _log == null:
		return
	_log.store_string(line)
	_log.flush()

## The 2s frame line. stderr only: reopening user:// and walking memory was a ~140 ms hitch every window.
func mark_tick(stage: String) -> void:
	if not runs_on_vita():
		return
	printerr("[vita-boot] " + stage)

func _ensure_log() -> void:
	if _log != null:
		return
	_log = FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if _log != null:
		_log.seek_end()
