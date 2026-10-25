## LiveLayout: camp clearing + named UI chrome overlays for the desktop Live Editor (DECISIONS #233).
## Loads data/camp_layout.json and data/ui_layout.json. When `editing`, CampScene and Main accept drags.
extends Node

signal layout_changed
signal selection_changed(kind: String, id: String)

const CAMP_PATH := "res://data/camp_layout.json"
const UI_PATH := "res://data/ui_layout.json"

const _DEFAULT_SPOTS := [
	["Forge", "blacksmith", 13, 16, 0.15, 0.30, "Forge"],
	["Enchanter", "wandmaker", 12, 14, 0.85, 0.30, "Enchanter"],
	["Alchemy", "_pot", 16, 16, 0.16, 0.97, "Alchemy"],
	["Guild", "shopkeeper", 14, 14, 0.84, 0.97, "Guild"],
	["Stash", "_chest", 16, 16, 0.50, 0.97, "Stash"],
]
const _DEFAULT_SEATS := [
	["warrior", 1.55, 0.50],
	["mage", -1.70, 0.50],
	["rogue", 2.65, 0.72],
	["huntress", -2.75, 0.72],
]
const _DEFAULT_FIRE_Y := 0.48

## Stable Control names that can be nudged in layout edit mode.
const UI_TARGETS := [
	"CampTopBar", "ResourceStrip", "CampFrame", "CampSide", "DelveGo",
	"JournalButton", "SettingsButton",
]

var editing := false
var fire_y: float = _DEFAULT_FIRE_Y
## Array form for CampScene / tests: [page, sprite, fw, fh, x, y, label]
var spots: Array = []
## [class, x_tiles, y_frac]
var seats: Array = []
## name -> {dx, dy} fractions of min(viewport)
var ui_offsets: Dictionary = {}
var sel_kind := ""
var sel_id := ""

var _camp_raw: Dictionary = {}
var _ui_raw: Dictionary = {}
var _drag_kind := ""
var _drag_id := ""
var _drag_start := Vector2.ZERO
var _drag_orig := Vector2.ZERO

func _ready() -> void:
	reload()

func _process(_d: float) -> void:
	if ui_offsets.is_empty() and not editing:
		return
	var main := find_main()
	if main:
		apply_tree(main)

static func desktop_allowed() -> bool:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return false
	var n := OS.get_name()
	return n == "Windows" or n == "Linux" or n == "macOS" or n == "FreeBSD"

func reload() -> void:
	_camp_raw = _load_dict(CAMP_PATH)
	_ui_raw = _load_dict(UI_PATH)
	_apply_camp_raw()
	ui_offsets = {}
	var off: Variant = _ui_raw.get("offsets", {})
	if off is Dictionary:
		for k in off:
			if String(k).begins_with("_"): continue
			var v: Variant = off[k]
			if v is Dictionary:
				ui_offsets[String(k)] = {
					"dx": float(v.get("dx", 0.0)),
					"dy": float(v.get("dy", 0.0)),
				}
	layout_changed.emit()

func _apply_camp_raw() -> void:
	fire_y = float(_camp_raw.get("fire_y", _DEFAULT_FIRE_Y))
	spots = []
	var sp: Variant = _camp_raw.get("spots", [])
	if sp is Array and not sp.is_empty():
		for s in sp:
			if s is Dictionary:
				spots.append([
					String(s.get("page", "")),
					String(s.get("sprite", "")),
					int(s.get("fw", 16)),
					int(s.get("fh", 16)),
					float(s.get("x", 0.5)),
					float(s.get("y", 0.5)),
					String(s.get("label", s.get("page", ""))),
				])
	if spots.is_empty():
		spots = _DEFAULT_SPOTS.duplicate(true)
	seats = []
	var st: Variant = _camp_raw.get("seats", [])
	if st is Array and not st.is_empty():
		for s in st:
			if s is Dictionary:
				seats.append([
					String(s.get("class", "")),
					float(s.get("x_tiles", 0.0)),
					float(s.get("y", 0.5)),
				])
	if seats.is_empty():
		seats = _DEFAULT_SEATS.duplicate(true)

func camp_to_raw() -> Dictionary:
	var out := {
		"_note": String(_camp_raw.get("_note",
			"Camp clearing layout (DECISIONS #233). Edited by the Live Editor.")),
		"fire_y": fire_y,
		"spots": [],
		"seats": [],
	}
	for s in spots:
		out.spots.append({
			"page": s[0], "sprite": s[1], "fw": s[2], "fh": s[3],
			"x": s[4], "y": s[5], "label": s[6],
		})
	for s in seats:
		out.seats.append({"class": s[0], "x_tiles": s[1], "y": s[2]})
	return out

func ui_to_raw() -> Dictionary:
	return {
		"_note": String(_ui_raw.get("_note",
			"Named UI chrome offsets (DECISIONS #233). Fractions of min(viewport).")),
		"offsets": ui_offsets.duplicate(true),
	}

## Write camp + ui layout JSON. Returns error message or "".
func save_layouts() -> String:
	var err := write_json(CAMP_PATH, camp_to_raw())
	if err != "": return err
	err = write_json(UI_PATH, ui_to_raw())
	if err != "": return err
	_camp_raw = camp_to_raw()
	_ui_raw = ui_to_raw()
	return ""

static func write_json(path: String, data: Dictionary) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Cannot write %s — run from the Godot editor / project folder so res://data is writable." % path
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return ""

func set_editing(on: bool) -> void:
	editing = on
	if not on:
		_drag_kind = ""
	layout_changed.emit()

func select(kind: String, id: String) -> void:
	sel_kind = kind
	sel_id = id
	selection_changed.emit(kind, id)

func set_spot_xy(page: String, x: float, y: float) -> void:
	for s in spots:
		if s[0] == page:
			s[4] = clampf(x, 0.02, 0.98)
			s[5] = clampf(y, 0.02, 0.98)
			layout_changed.emit()
			return

func set_seat_xy(c: String, x_tiles: float, y: float) -> void:
	for s in seats:
		if s[0] == c:
			s[1] = x_tiles
			s[2] = clampf(y, 0.02, 0.98)
			layout_changed.emit()
			return

func set_fire_y(y: float) -> void:
	fire_y = clampf(y, 0.05, 0.95)
	layout_changed.emit()

func set_ui_offset(name: String, dx: float, dy: float) -> void:
	ui_offsets[name] = {"dx": dx, "dy": dy}
	layout_changed.emit()

func clear_ui_offset(name: String) -> void:
	ui_offsets.erase(name)
	layout_changed.emit()

## Restore the current selection (spot / seat / fire) to baked defaults.
func reset_selected() -> bool:
	match sel_kind:
		"fire":
			set_fire_y(_DEFAULT_FIRE_Y)
			return true
		"spot":
			for d in _DEFAULT_SPOTS:
				if d[0] == sel_id:
					set_spot_xy(sel_id, float(d[4]), float(d[5]))
					return true
		"seat":
			for d in _DEFAULT_SEATS:
				if d[0] == sel_id:
					set_seat_xy(sel_id, float(d[1]), float(d[2]))
					return true
		"ui":
			clear_ui_offset(sel_id)
			return true
	return false

## Re-apply named Control offsets under `root`.
func apply_tree(root: Node) -> void:
	if root == null: return
	var vs := Vector2(968, 2376)
	if root is Control and (root as Control).is_inside_tree():
		vs = (root as Control).get_viewport_rect().size
	var scale := minf(vs.x, vs.y)
	for name in UI_TARGETS:
		var n := find_named(root, name)
		if n == null or not (n is Control): continue
		var c: Control = n
		var off: Dictionary = ui_offsets.get(name, {"dx": 0.0, "dy": 0.0})
		var px := Vector2(float(off.get("dx", 0.0)), float(off.get("dy", 0.0))) * scale
		var old: Vector2 = c.get_meta("_live_off", Vector2.ZERO)
		var base: Vector2 = c.position - old
		c.set_meta("_live_base", base)
		c.set_meta("_live_off", px)
		if c.position.distance_to(base + px) > 0.25:
			c.position = base + px

## CampScene local input. Returns true if handled (blocks open-page).
func camp_input(scene: Control, e: InputEvent) -> bool:
	if not editing or scene == null:
		return false
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var moving := false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseMotion and _drag_kind != "" and _drag_kind != "ui":
		pos = e.position
		moving = true
	elif e is InputEventScreenDrag and _drag_kind != "" and _drag_kind != "ui":
		pos = e.position
		moving = true
	else:
		return false

	if pressed:
		var fire := Vector2(scene.size.x * 0.5, scene.ground_y(fire_y))
		if pos.distance_to(fire) < 16.0 * scene.k() * 1.2:
			_drag_kind = "fire"; _drag_id = "fire"
			_drag_start = pos; _drag_orig = Vector2(0, fire_y)
			select("fire", "fire")
			return true
		var hc := _seat_at(scene, pos)
		if hc != "":
			_drag_kind = "seat"; _drag_id = hc
			_drag_start = pos
			for s in seats:
				if s[0] == hc:
					_drag_orig = Vector2(float(s[1]), float(s[2])); break
			select("seat", hc)
			return true
		var page: String = scene.spot_at(pos)
		if page != "":
			_drag_kind = "spot"; _drag_id = page
			_drag_start = pos
			for s in spots:
				if s[0] == page:
					_drag_orig = Vector2(float(s[4]), float(s[5])); break
			select("spot", page)
			return true
		return false

	if moving and _drag_kind != "" and _drag_kind != "ui":
		_camp_drag_to(scene, pos)
		return true

	if released and _drag_kind != "" and _drag_kind != "ui":
		_camp_drag_to(scene, pos)
		_drag_kind = ""
		return true
	return false

func _camp_drag_to(scene: Control, pos: Vector2) -> void:
	var sky_h: float = float(scene.sky_height())
	var ground_h: float = maxf(1.0, scene.size.y - sky_h)
	match _drag_kind:
		"fire":
			set_fire_y((pos.y - sky_h) / ground_h)
			scene.queue_redraw()
		"spot":
			var x: float = pos.x / maxf(1.0, scene.size.x)
			var y: float = _unpack_y(scene, (pos.y - sky_h) / ground_h)
			set_spot_xy(_drag_id, x, y)
			scene.queue_redraw()
		"seat":
			var fire := Vector2(scene.size.x * 0.5, float(scene.ground_y(fire_y)))
			var cs: float = 16.0 * float(scene.k())
			var x_tiles: float = (pos.x - fire.x) / maxf(1.0, cs)
			var y2: float = _unpack_y(scene, (pos.y - sky_h) / ground_h, 0.35)
			set_seat_xy(_drag_id, x_tiles, y2)
			scene.queue_redraw()

## Seat under point for layout edit (includes locked / on-patrol heroes).
func _seat_at(scene: Control, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	var pad: float = float(UIKit.font_size) * 0.25
	for s in seats:
		var c: String = s[0]
		var r: Rect2 = scene.hero_rect(c) as Rect2
		# hero_rect is empty when locked — synthesize from seat data for editing
		if not r.has_area():
			var kk: float = float(scene.k())
			var cs: float = 16.0 * kk
			var fire := Vector2(scene.size.x * 0.5, float(scene.ground_y(fire_y)))
			var hz := Vector2(12, 15) * kk * 2.0
			var feet := Vector2(fire.x + float(s[1]) * cs,
				float(scene.ground_y(float(scene.pack_y(float(s[2]), 0.35)))) + kk * 6.0)
			r = Rect2((feet - Vector2(hz.x / 2.0, hz.y)).floor(), hz)
		if not r.grow(pad).has_point(p): continue
		var d := r.get_center().distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best

## Approximate inverse of CampScene.pack_y for storing layout fractions.
func _unpack_y(scene: Control, packed_fy: float, strength := 1.0) -> float:
	var gh: float = scene.size.y - float(scene.sky_height())
	var aspect: float = gh / maxf(1.0, scene.size.x)
	var pack := clampf((aspect - 0.78) / 0.55, 0.0, 1.0) * clampf(strength, 0.0, 1.0)
	if pack <= 0.0:
		return packed_fy
	var t := lerpf(1.0, 0.58, pack)
	if absf(t) < 0.001:
		return fire_y
	return fire_y + (packed_fy - fire_y) / t

## Viewport-level input for named chrome (call from Main._input while editing).
## Uses canvas mouse position so it works even when children would eat _gui_input.
func ui_input(main: Control, e: InputEvent) -> bool:
	if not editing or main == null:
		return false
	var pressed := false
	var released := false
	var moving := false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseMotion and _drag_kind == "ui":
		moving = true
	else:
		return false

	var gpos := main.get_viewport().get_mouse_position()
	# Camp clearing handles its own drags via CampScene._gui_input.
	var scene := find_named(main, "CampScene")
	if scene is Control and (scene as Control).get_global_rect().has_point(gpos):
		if pressed or (_drag_kind != "" and _drag_kind != "ui"):
			return false

	if pressed:
		var hit := _hit_ui_target(main, gpos)
		if hit == null:
			return false
		_drag_kind = "ui"
		_drag_id = String(hit.name)
		_drag_start = gpos
		var cur: Dictionary = ui_offsets.get(_drag_id, {"dx": 0.0, "dy": 0.0})
		_drag_orig = Vector2(float(cur.get("dx", 0.0)), float(cur.get("dy", 0.0)))
		select("ui", _drag_id)
		return true

	if moving and _drag_kind == "ui":
		_ui_drag_to(main, gpos)
		return true

	if released and _drag_kind == "ui":
		_ui_drag_to(main, gpos)
		_drag_kind = ""
		return true
	return false

func _ui_drag_to(main: Control, gpos: Vector2) -> void:
	var vs := main.get_viewport_rect().size
	var scale := maxf(1.0, minf(vs.x, vs.y))
	var delta := (gpos - _drag_start) / scale
	set_ui_offset(_drag_id, _drag_orig.x + delta.x, _drag_orig.y + delta.y)
	apply_tree(main)

func _hit_ui_target(root: Node, global_pos: Vector2) -> Control:
	var best: Control = null
	var best_area := INF
	for name in UI_TARGETS:
		var n := find_named(root, name)
		if n is Control:
			var c: Control = n
			if not c.is_visible_in_tree(): continue
			var r := c.get_global_rect()
			if r.has_point(global_pos):
				var a := r.get_area()
				if a < best_area:
					best_area = a
					best = c
	return best

func find_main() -> Node:
	var tree := get_tree()
	if tree == null: return null
	return _find_main(tree.root)

func _find_main(n: Node) -> Node:
	if n.get_script() != null:
		var p := String(n.get_script().resource_path)
		if p.ends_with("main.gd"):
			return n
	for c in n.get_children():
		var f := _find_main(c)
		if f: return f
	return null

func find_named(root: Node, name: String) -> Node:
	if root == null: return null
	if String(root.name) == name:
		return root
	for c in root.get_children():
		var f := find_named(c, name)
		if f: return f
	return null

func _load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}
