## Live Editor: desktop second window for camp/UI layout, content text, and balance (DECISIONS #233).
## Open from Settings → Developer tools. Writes res://data/*.json when Save succeeds.
extends Window

const LiveEditorScript := preload("res://scripts/ui/live_editor.gd")

## Hover help for Balance / Text field keys (and a few layout keys).
const FIELD_TIPS := {
	"ht": "Hit points (max HP). How much damage the mob can take before it dies.",
	"hp": "Hit points. Same idea as ht on mobs.",
	"dmg": "Attack damage dealt per hit (fixed; no RNG roll in combat).",
	"dr": "Damage reduction / armor. Subtracted from incoming hits before HP is lost.",
	"delay": "Action speed. 1.0 = normal turn rate; lower = acts more often (SPD: 1/baseSpeed).",
	"exp": "Experience the hero gains when this mob dies.",
	"loot": "Gold (or loot value) dropped when the mob dies.",
	"fw": "Sprite frame width in pixels (how the sheet is sliced). Visual only — does not affect combat.",
	"fh": "Sprite frame height in pixels. Visual only — does not affect combat.",
	"sprite": "Sprite sheet file under assets/sprites (without .png).",
	"name": "Display name shown in UI, inspect, and codex.",
	"spd": "Short SPD reference note (not used by combat rules).",
	"spd_desc": "Longer flavor / SPD description text shown when identified.",
	"desc": "Description shown in Camp / facility UI.",
	"tier": "Item tier (1–5). Drives forge unlock level, upgrade costs, and weapon scaling.",
	"str": "Strength required to use this gear at +0 (lowered by upgrades like SPD).",
	"acc": "Accuracy multiplier (1.0 = normal). Higher hits more often vs evasion.",
	"reach": "Melee reach in tiles (1 = adjacent). Higher can hit farther.",
	"surprise_pct": "Bonus chance / strength of surprise (backstab) damage for dagger-family weapons.",
	"block": "Shield-style block DR as [base, per level]. Contributes armor when blocking.",
	"max": "For weapons: [base max damage, damage gained per upgrade level].",
	"delay_weapon": "Weapon attack delay (turns between swings). Lower = faster attacks.",
	"dr_per_lvl": "Extra armor DR added per upgrade level on this armor.",
	"barrier_per_lvl": "Barrier (overshield) gained per armor upgrade level.",
	"upgrade_cost": "Materials spent to raise this facility one level (scaled by current level in code).",
	"cost": "Crafting / recipe material costs paid when you forge or brew this.",
	"reward": "Items or materials granted when this milestone is claimed.",
	"min_level": "Facility level required before this recipe appears at the vendor.",
	"max_facility": "Highest facility level (Scroll-of-Upgrade cap ceiling).",
	"cap_scrolls": "Scrolls of Upgrade needed to raise the facility cap at each step.",
	"pack_cap": "Guild pack size (rations/torches slots) by facility level.",
	"fuel": "Primary material this facility consumes for upgrades / crafts.",
	"goal": "How many of the tracked stat you need to unlock this milestone.",
	"badge": "Index into assets/ui/badges.png for the Journal icon.",
	"title": "Title on a tutorial tip card.",
	"text": "Body copy on a tutorial tip card.",
	"label": "Short label drawn under a Camp NPC / spot.",
	"fire_y": "Campfire height as a fraction of the ground (0 = horizon, 1 = bottom).",
	"x": "Horizontal position (0–1 across the clearing, or UI offset fraction).",
	"y": "Vertical position (ground fraction for camp, or UI offset fraction).",
	"x_tiles": "Hero seat offset from the fire, in tile widths (negative = left).",
	"dx": "UI chrome horizontal nudge as a fraction of min(viewport size).",
	"dy": "UI chrome vertical nudge as a fraction of min(viewport size).",
	"out": "Item id produced by this recipe.",
	"id": "Stable id used in saves and code (do not rename lightly).",
	"type": "Item type: weapon, armor, ring, wand, artifact, etc.",
	"icon": "Icon key into the items sprite sheet / icons.json.",
	"cat": "Milestone category tab in the Journal.",
	"stat": "Which GameState counter this milestone tracks (see GameState.stat_value).",
}

static var instance: Window = null

var _tabs: TabContainer
var _status: Label
var _layout_body: VBoxContainer
var _text_body: VBoxContainer
var _balance_body: VBoxContainer
var _edit_on: CheckButton
var _sel_label: Label
var _x_spin: SpinBox
var _y_spin: SpinBox
var _cat: OptionButton
var _entry: OptionButton
var _form: VBoxContainer
## Working copies of data files (full dicts including _note / _materials).
var _files: Dictionary = {}
var _dirty := false
var _filling := false

static func open() -> void:
	if not LiveLayout.desktop_allowed():
		GameState.toast.emit("Live Editor is desktop-only.")
		return
	if instance != null and is_instance_valid(instance):
		instance.grab_focus()
		instance.move_to_foreground()
		return
	# Godot embeds Window nodes inside the game viewport by default — that made the
	# editor a tiny in-game panel. Turn embedding off so this is a real OS window.
	var root := Engine.get_main_loop().root as Window
	root.gui_embed_subwindows = false
	var w: Window = LiveEditorScript.new()
	instance = w
	root.add_child(w)

static func close_editor() -> void:
	if instance != null and is_instance_valid(instance):
		instance.queue_free()
	instance = null
	LiveLayout.set_editing(false)

func _ready() -> void:
	title = "SPD Live Editor"
	transient = false
	exclusive = false
	unresizable = false
	always_on_top = false
	# Native window size in screen pixels (not scaled by the game's tall phone viewport).
	size = Vector2i(960, 1000)
	min_size = Vector2i(720, 640)
	initial_position = WINDOW_INITIAL_POSITION_ABSOLUTE
	_place_beside_main()
	close_requested.connect(_on_close)
	theme = UIKit.make_theme(22)
	_load_files()
	_build()
	LiveLayout.selection_changed.connect(_on_selection)
	LiveLayout.layout_changed.connect(_on_layout_changed)
	visibility_changed.connect(func():
		if not visible:
			LiveLayout.set_editing(false))
	# Ensure the native window is visible and focused after the first frame.
	call_deferred("_show_native")

func _place_beside_main() -> void:
	var main_pos := DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID)
	var main_size := DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	var screen := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pos := Vector2i(main_pos.x + main_size.x + 12, main_pos.y)
	if pos.x + size.x > usable.end.x:
		pos.x = maxi(usable.position.x, main_pos.x - size.x - 12)
	if pos.y + size.y > usable.end.y:
		pos.y = maxi(usable.position.y, usable.end.y - size.y)
	position = pos

func _show_native() -> void:
	# popup() shows a native OS window when subwindows are not embedded.
	var keep := position
	popup()
	position = keep
	grab_focus()
	move_to_foreground()

func _on_close() -> void:
	LiveLayout.set_editing(false)
	instance = null
	queue_free()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_%s" % m, 10)
	add_child(pad)
	pad.add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var b_reload := UIKit.button("Reload", _reload_all)
	b_reload.tooltip_text = "Discard unsaved form edits and re-read data/*.json from disk."
	bar.add_child(b_reload)
	var b_save := UIKit.button("Save to disk", _save_all)
	b_save.tooltip_text = "Write mobs/items/facilities/recipes/tutorial/milestones and camp/UI layout JSON into the project."
	bar.add_child(b_save)
	var b_apply := UIKit.button("Apply live", _apply_live)
	b_apply.tooltip_text = "Push current edits into the running game without saving files yet."
	bar.add_child(b_apply)
	_status = UIKit.label("Ready", 0.8, Color("9a8f7c"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_layout_body = _tab_vbox("Layout")
	_text_body = _tab_vbox("Text")
	_balance_body = _tab_vbox("Balance")
	_build_layout_tab()
	_build_content_tab(_text_body, false)
	_build_content_tab(_balance_body, true)

func _tab_vbox(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return v

func _build_layout_tab() -> void:
	UIKit.clear(_layout_body)
	_layout_body.add_child(UIKit.label(
		"Toggle Edit layout, then drag camp NPCs / heroes / fire, or named Camp chrome (top bar, frame, side, buttons).",
		0.75, Color("9a8f7c")))
	_edit_on = CheckButton.new()
	_edit_on.text = "Edit layout on game window"
	_edit_on.tooltip_text = "When on, drag Camp NPCs, hero seats, the fire, or named Camp chrome in the game window."
	_edit_on.button_pressed = LiveLayout.editing
	_edit_on.toggled.connect(func(on: bool):
		LiveLayout.set_editing(on)
		_set_status("Layout edit %s" % ("ON — drag in the game window" if on else "off")))
	_layout_body.add_child(_edit_on)
	_sel_label = UIKit.label("Selection: (none)", 0.85, Color("ffd27a"))
	_layout_body.add_child(_sel_label)
	var row := HBoxContainer.new()
	_layout_body.add_child(row)
	row.add_child(UIKit.label("X", 0.8))
	_x_spin = _spin(-20.0, 20.0, 0.01)
	_x_spin.value_changed.connect(func(v): _layout_spin(true, v))
	row.add_child(_x_spin)
	row.add_child(UIKit.label("Y", 0.8))
	_y_spin = _spin(-20.0, 20.0, 0.01)
	_y_spin.value_changed.connect(func(v): _layout_spin(false, v))
	row.add_child(_y_spin)
	_layout_body.add_child(UIKit.button("Save layout JSON", func():
		var err := LiveLayout.save_layouts()
		_set_status("Layout saved." if err == "" else err)
		if err == "": GameState.toast.emit("Camp / UI layout saved")))
	_layout_body.add_child(UIKit.label(
		"Camp: data/camp_layout.json. UI offsets: data/ui_layout.json (fractions of min viewport).",
		0.7, Color("9a8f7c")))
	_refresh_layout_spins()

func _spin(mn: float, mx: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 100
	return s

func _on_selection(_kind: String, _id: String) -> void:
	_refresh_layout_spins()

func _on_layout_changed() -> void:
	if _filling: return
	_refresh_layout_spins()

func _refresh_layout_spins() -> void:
	if _sel_label == null: return
	_filling = true
	var kind := LiveLayout.sel_kind
	var id := LiveLayout.sel_id
	if kind == "":
		_sel_label.text = "Selection: (none)"
		_x_spin.editable = false
		_y_spin.editable = false
		_filling = false
		return
	_sel_label.text = "Selection: %s / %s" % [kind, id]
	_x_spin.editable = true
	_y_spin.editable = true
	match kind:
		"spot":
			for s in LiveLayout.spots:
				if s[0] == id:
					_x_spin.value = float(s[4]); _y_spin.value = float(s[5]); break
		"seat":
			for s in LiveLayout.seats:
				if s[0] == id:
					_x_spin.value = float(s[1]); _y_spin.value = float(s[2]); break
		"fire":
			_x_spin.editable = false
			_x_spin.value = 0.5
			_y_spin.value = LiveLayout.fire_y
		"ui":
			var o: Dictionary = LiveLayout.ui_offsets.get(id, {"dx": 0.0, "dy": 0.0})
			_x_spin.value = float(o.get("dx", 0.0))
			_y_spin.value = float(o.get("dy", 0.0))
	_filling = false

func _layout_spin(is_x: bool, v: float) -> void:
	if _filling: return
	var kind := LiveLayout.sel_kind
	var id := LiveLayout.sel_id
	if kind == "": return
	match kind:
		"spot":
			var x := v if is_x else _x_spin.value
			var y := v if not is_x else _y_spin.value
			# keep the other from spin
			if is_x: y = _y_spin.value
			else: x = _x_spin.value
			LiveLayout.set_spot_xy(id, x, y)
		"seat":
			var xt := v if is_x else _x_spin.value
			var y2 := v if not is_x else _y_spin.value
			if is_x: y2 = _y_spin.value
			else: xt = _x_spin.value
			LiveLayout.set_seat_xy(id, xt, y2)
		"fire":
			if not is_x:
				LiveLayout.set_fire_y(v)
		"ui":
			var dx := v if is_x else _x_spin.value
			var dy := v if not is_x else _y_spin.value
			if is_x: dy = _y_spin.value
			else: dx = _x_spin.value
			LiveLayout.set_ui_offset(id, dx, dy)
			var main := LiveLayout.find_main()
			if main: LiveLayout.apply_tree(main)

func _build_content_tab(body: VBoxContainer, balance: bool) -> void:
	UIKit.clear(body)
	body.add_child(UIKit.label(
		"Balance numbers" if balance else "Names, descriptions, tip text",
		0.75, Color("9a8f7c")))
	var row := HBoxContainer.new()
	body.add_child(row)
	_cat = OptionButton.new()
	_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in (["mobs", "items", "materials", "facilities", "recipes"] if balance \
			else ["mobs", "items", "materials", "facilities", "tips", "milestones"]):
		_cat.add_item(t)
	_cat.item_selected.connect(func(_i): _refill_entries(body, balance))
	row.add_child(_cat)
	_entry = OptionButton.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.item_selected.connect(func(_i): _fill_form(body, balance))
	row.add_child(_entry)
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 4)
	body.add_child(_form)
	# Store which tab owns which widgets via meta on body
	body.set_meta("balance", balance)
	body.set_meta("cat", _cat)
	body.set_meta("entry", _entry)
	body.set_meta("form", _form)
	_refill_entries(body, balance)

func _refill_entries(body: VBoxContainer, balance: bool) -> void:
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	entry_btn.clear()
	var cat := cat_btn.get_item_text(cat_btn.selected)
	var ids: Array = _ids_for(cat)
	ids.sort()
	for id in ids:
		entry_btn.add_item(String(id))
	if entry_btn.item_count > 0:
		entry_btn.select(0)
	_fill_form(body, balance)

func _ids_for(cat: String) -> Array:
	match cat:
		"mobs":
			return _files.mobs.keys().filter(func(k): return not String(k).begins_with("_"))
		"items":
			var it: Dictionary = _files.get("items", {})
			return it.keys().filter(func(k): return not String(k).begins_with("_"))
		"materials":
			var mats: Dictionary = _files.get("items", {}).get("_materials", {})
			return mats.keys()
		"facilities":
			return _files.facilities.keys().filter(func(k): return not String(k).begins_with("_"))
		"recipes":
			var out := []
			var rec: Dictionary = _files.get("recipes", {})
			for fac in rec:
				if String(fac).begins_with("_"): continue
				var arr: Variant = rec[fac]
				if arr is Array:
					for r in arr:
						if r is Dictionary and r.has("id"):
							out.append("%s/%s" % [fac, r.id])
			return out
		"tips":
			return _files.get("tutorial", {}).get("tips", {}).keys()
		"milestones":
			var out2 := []
			for m in _files.get("milestones", {}).get("milestones", []):
				if m is Dictionary and m.has("id"):
					out2.append(String(m.id))
			return out2
	return []

func _fill_form(body: VBoxContainer, balance: bool) -> void:
	var form: VBoxContainer = body.get_meta("form")
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	UIKit.clear(form)
	if entry_btn.item_count == 0: return
	var cat := cat_btn.get_item_text(cat_btn.selected)
	var id := entry_btn.get_item_text(entry_btn.selected)
	var data := _entry_data(cat, id)
	if data.is_empty():
		form.add_child(UIKit.label("(missing)", 0.8, Color("ff8888")))
		return
	var text_keys := ["name", "label", "desc", "spd_desc", "spd", "title", "text"]
	var num_keys := ["ht", "dmg", "dr", "delay", "exp", "loot", "tier", "str", "acc", "reach", "surprise_pct",
		"fw", "fh", "max", "goal", "badge", "min_level", "fire_y"]
	for k in data.keys():
		if String(k).begins_with("_"): continue
		var v: Variant = data[k]
		if balance:
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				_add_num_field(form, cat, id, String(k), float(v))
			elif typeof(v) == TYPE_ARRAY and (v as Array).size() > 0 and typeof((v as Array)[0]) in [TYPE_INT, TYPE_FLOAT]:
				_add_array_num_field(form, cat, id, String(k), v)
			elif typeof(v) == TYPE_DICTIONARY and String(k) in ["cost", "upgrade_cost", "reward"]:
				_add_cost_fields(form, cat, id, String(k), v)
			elif String(k) in num_keys and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
				_add_num_field(form, cat, id, String(k), float(v))
		else:
			if typeof(v) == TYPE_STRING and (String(k) in text_keys or String(k).ends_with("_desc")):
				_add_text_field(form, cat, id, String(k), String(v))
			elif String(k) == "pages" and v is Array:
				_add_tip_pages(form, cat, id, v)
	if form.get_child_count() == 0:
		form.add_child(UIKit.label("No editable %s fields on this entry." % ("number" if balance else "text"), 0.75, Color("9a8f7c")))

func _field_tip(key: String) -> String:
	return String(FIELD_TIPS.get(key, "Data field \"%s\" from the JSON entry." % key))

func _tip(ctrl: Control, key: String) -> void:
	ctrl.tooltip_text = _field_tip(key)
	if ctrl is Label:
		ctrl.mouse_filter = Control.MOUSE_FILTER_STOP

func _add_text_field(form: VBoxContainer, cat: String, id: String, key: String, val: String) -> void:
	var hdr := UIKit.label(key, 0.75, Color("bdb3a0"))
	_tip(hdr, key)
	form.add_child(hdr)
	var te := TextEdit.new()
	te.text = val
	te.custom_minimum_size = Vector2(0, 72 if val.length() > 60 else 40)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_tip(te, key)
	te.text_changed.connect(func():
		_set_entry_field(cat, id, key, te.text)
		_dirty = true)
	form.add_child(te)

func _add_tip_pages(form: VBoxContainer, cat: String, id: String, pages: Array) -> void:
	for i in pages.size():
		var p: Variant = pages[i]
		if not (p is Dictionary): continue
		form.add_child(UIKit.label("page %d title" % i, 0.75, Color("bdb3a0")))
		var title_e := LineEdit.new()
		title_e.text = String(p.get("title", ""))
		title_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ii := i
		title_e.text_changed.connect(func(t):
			var tips: Dictionary = _files.tutorial.tips
			var tip: Dictionary = tips[id]
			var pg: Array = tip.pages
			pg[ii].title = t
			_dirty = true)
		form.add_child(title_e)
		form.add_child(UIKit.label("page %d text" % i, 0.75, Color("bdb3a0")))
		var body_e := TextEdit.new()
		body_e.text = String(p.get("text", ""))
		body_e.custom_minimum_size = Vector2(0, 80)
		body_e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		body_e.text_changed.connect(func():
			var tips2: Dictionary = _files.tutorial.tips
			tips2[id].pages[ii].text = body_e.text
			_dirty = true)
		form.add_child(body_e)

func _add_num_field(form: VBoxContainer, cat: String, id: String, key: String, val: float) -> void:
	var row := HBoxContainer.new()
	_tip(row, key)
	form.add_child(row)
	var l := UIKit.label(key, 0.8, Color("bdb3a0"))
	l.custom_minimum_size.x = 120
	_tip(l, key)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = -99999
	s.max_value = 99999
	s.step = 0.05 if absf(val - roundf(val)) > 0.001 else 1.0
	s.allow_greater = true
	s.allow_lesser = true
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip(s, key)
	s.value_changed.connect(func(v):
		var out: Variant = int(v) if s.step >= 1.0 else v
		_set_entry_field(cat, id, key, out)
		_dirty = true)
	row.add_child(s)

func _add_array_num_field(form: VBoxContainer, cat: String, id: String, key: String, arr: Array) -> void:
	var hdr := UIKit.label(key, 0.75, Color("bdb3a0"))
	_tip(hdr, key)
	form.add_child(hdr)
	var row := HBoxContainer.new()
	_tip(row, key)
	form.add_child(row)
	var parts := [
		"First value (base / level 1).",
		"Second value (per level or next step).",
		"Third value.",
		"Fourth value.",
		"Fifth value.",
	]
	for i in arr.size():
		var s := SpinBox.new()
		s.min_value = -99999; s.max_value = 99999; s.allow_greater = true; s.allow_lesser = true
		s.step = 1.0
		s.value = float(arr[i])
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tip := _field_tip(key)
		if i < parts.size():
			tip = "%s\n%s" % [tip, parts[i]]
		s.tooltip_text = tip
		var ii := i
		s.value_changed.connect(func(v):
			var data := _entry_data(cat, id)
			if data.has(key) and data[key] is Array:
				data[key][ii] = int(v) if absf(v - roundf(v)) < 0.001 else v
				_dirty = true)
		row.add_child(s)

func _add_cost_fields(form: VBoxContainer, cat: String, id: String, key: String, cost: Dictionary) -> void:
	var hdr := UIKit.label(key, 0.75, Color("bdb3a0"))
	_tip(hdr, key)
	form.add_child(hdr)
	for mk in cost.keys():
		var row := HBoxContainer.new()
		form.add_child(row)
		var mat := String(mk)
		var l := UIKit.label(mat, 0.75)
		l.custom_minimum_size.x = 120
		var tip := "%s\nAmount of %s required." % [_field_tip(key), mat]
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(l)
		var s := SpinBox.new()
		s.min_value = 0; s.max_value = 999999; s.step = 1; s.allow_greater = true
		s.value = float(cost[mk])
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.tooltip_text = tip
		s.value_changed.connect(func(v):
			var data := _entry_data(cat, id)
			if data.has(key) and data[key] is Dictionary:
				data[key][mat] = int(v)
				_dirty = true)
		row.add_child(s)

func _entry_data(cat: String, id: String) -> Dictionary:
	match cat:
		"mobs":
			return _files.mobs.get(id, {})
		"items":
			return _files.items.get(id, {})
		"materials":
			return _files.items.get("_materials", {}).get(id, {})
		"facilities":
			return _files.facilities.get(id, {})
		"recipes":
			var parts := id.split("/", false, 1)
			if parts.size() != 2: return {}
			var arr: Variant = _files.recipes.get(parts[0], [])
			if arr is Array:
				for r in arr:
					if r is Dictionary and String(r.get("id", "")) == parts[1]:
						return r
			return {}
		"tips":
			return _files.tutorial.get("tips", {}).get(id, {})
		"milestones":
			for m in _files.milestones.get("milestones", []):
				if m is Dictionary and String(m.get("id", "")) == id:
					return m
	return {}

func _set_entry_field(cat: String, id: String, key: String, val: Variant) -> void:
	var data := _entry_data(cat, id)
	if data.is_empty(): return
	data[key] = val

func _load_files() -> void:
	_files = {
		"mobs": _read("res://data/mobs.json"),
		"items": _read("res://data/items.json"),
		"facilities": _read("res://data/facilities.json"),
		"recipes": _read("res://data/recipes.json"),
		"tutorial": _read("res://data/tutorial.json"),
		"milestones": _read("res://data/milestones.json"),
	}
	_dirty = false

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

func _reload_all() -> void:
	_load_files()
	LiveLayout.reload()
	DB.reload()
	GameState.touch()
	_dirty = false
	# Rebuild content tabs
	_build_content_tab(_text_body, false)
	_build_content_tab(_balance_body, true)
	_set_status("Reloaded from disk.")

func _apply_live() -> void:
	_push_to_db()
	GameState.touch()
	_set_status("Applied in memory (not saved to disk yet)." if _dirty else "Applied.")

func _save_all() -> void:
	var paths := {
		"mobs": "res://data/mobs.json",
		"items": "res://data/items.json",
		"facilities": "res://data/facilities.json",
		"recipes": "res://data/recipes.json",
		"tutorial": "res://data/tutorial.json",
		"milestones": "res://data/milestones.json",
	}
	for k in paths:
		var err := LiveLayout.write_json(paths[k], _files[k])
		if err != "":
			_set_status(err)
			GameState.toast.emit(err)
			return
	var lerr := LiveLayout.save_layouts()
	if lerr != "":
		_set_status(lerr)
		GameState.toast.emit(lerr)
		return
	_push_to_db()
	GameState.touch()
	_dirty = false
	_set_status("Saved data/*.json.")
	GameState.toast.emit("Live Editor saved")

func _push_to_db() -> void:
	# Apply working copies into DB without requiring a disk write first.
	DB.mobs = _strip_keys(_files.mobs)
	var it: Dictionary = _files.items
	DB.materials = it.get("_materials", {})
	DB.items = _strip_keys(it)
	DB.facilities = _strip_keys(_files.facilities)
	DB.recipes = _strip_keys(_files.recipes)
	var ms: Dictionary = _files.milestones
	DB.milestones = ms.get("milestones", [])
	DB.milestone_categories = ms.get("categories", [])
	DB.tips = _files.tutorial.get("tips", {})

static func _strip_keys(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		if not String(k).begins_with("_"):
			o[k] = d[k]
	return o

func _set_status(t: String) -> void:
	if _status: _status.text = t
