## SaveSystem: versioned JSON save in user://save.json, with atomic write + migration hook.
## On PS Vita that directory is ux0:/data/idlepd-saves/ (project.godot feature override).
extends Node

const SAVE_VERSION := 2
var path := "user://save.json"
var autosave := true

func _ready() -> void:
	# Vita loads the save after DB.reload() on the loading scene. Other platforms load as before.
	if not VitaBoot.on_device():
		load_game()
	GameState.changed.connect(_on_changed)

## Android may kill a backgrounded app at any time: save whenever we lose focus or are asked to quit.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if autosave: save_game()

func _on_changed() -> void:
	if autosave: save_game()

func save_game() -> bool:
	var data := {"version": SAVE_VERSION, "saved_at": Time.get_unix_time_from_system(), "state": GameState.to_dict()}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write " + tmp); return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(path): return false
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not d.has("state"):
		push_warning("SaveSystem: unreadable save, starting fresh"); return false
	d = migrate(d)
	var was := autosave; autosave = false
	GameState.from_dict(d.state)
	autosave = was
	return true

## Upgrade old save layouts here. Each step bumps d.version by one.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 2:
		# v0.6.0: meta-progression stats. Back-fill boss kill counters from the per-class boss list so
		# existing players get their Goo milestone; everything else starts at 0.
		var st: Dictionary = d.state.get("stats", {})
		var goo := 0
		for c in d.state.get("boss_kills", {}): if "sewers" in d.state.boss_kills[c]: goo += 1
		st["goo_kills"] = maxi(int(st.get("goo_kills", 0)), goo)
		d.state.stats = st
		v = 2
	d.version = v
	return d

func wipe() -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.new_game(); GameState.touch()
