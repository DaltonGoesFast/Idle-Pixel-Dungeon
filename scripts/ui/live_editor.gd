## Live Editor: desktop second window for camp/UI layout, content text, and balance (DECISIONS #233).
## Open from Settings → Developer tools. Writes res://data/*.json when Save succeeds.
extends Window

const LiveEditorScript := preload("res://scripts/ui/live_editor.gd")

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
	"max": "For weapons: [base max damage, damage gained per upgrade level]. Facility: level cap.",
	"dr_per_lvl": "Extra armor DR added per upgrade level on this armor.",
	"barrier_per_lvl": "Barrier (overshield) gained per armor upgrade level.",
	"upgrade_cost": "Materials spent to raise this facility one level (scaled by current level in code).",
	"cost": "Crafting / recipe material costs paid when you forge or brew this.",
	"reward": "Items or materials granted when this milestone is claimed.",
	"min_level": "Facility level required before this recipe appears at the vendor.",
	"cap_scrolls": "Scrolls of Upgrade needed to raise the facility cap at each step.",
	"pack_cap": "Guild pack size (rations/torches slots) by facility level.",
	"fuel": "Primary material this facility consumes for upgrades / crafts.",
	"goal": "How many of the tracked stat you need to unlock this milestone.",
	"badge": "Index into assets/ui/badges.png for the Journal icon.",
	"title": "Title on a tutorial tip card.",
	"text": "Body copy on a tutorial tip card.",
	"label": "Short label drawn under a Camp NPC / spot.",
	"rec_level": "Recommended hero level for this biome.",
	"str_gate": "Minimum Strength suggested / gated for the biome.",
	"boss_floor": "Floor number of the biome boss.",
	"patrol_curio_every_hours": "Hours of patrol between curio drops.",
	"event_weights": "Relative odds of combat / door / special events while delving.",
	"patrol_yield_per_hour": "Materials gained per hour on patrol in this biome.",
	"secret_cache": "Loot in the biome's secret cache.",
	"floors": "Inclusive floor range [first, last] for this biome.",
}

const COMBAT_KEYS := {
	"ht": true, "hp": true, "dmg": true, "dr": true, "delay": true, "exp": true, "loot": true,
	"acc": true, "reach": true, "surprise_pct": true, "block": true, "tier": true, "str": true,
	"dr_per_lvl": true, "barrier_per_lvl": true, "rec_level": true, "str_gate": true, "boss_floor": true,
}
const VISUAL_KEYS := {"fw": true, "fh": true, "sprite": true, "icon": true, "badge": true}
const COST_KEYS := {
	"cost": true, "upgrade_cost": true, "reward": true, "min_level": true, "cap_scrolls": true,
	"pack_cap": true, "fuel": true, "event_weights": true, "patrol_yield_per_hour": true,
	"secret_cache": true, "patrol_curio_every_hours": true,
}
const KEEP_ON_COPY := {"id": true, "sprite": true, "icon": true, "page": true, "class": true}
const TEXT_KEYS := {"name": true, "label": true, "desc": true, "spd_desc": true, "spd": true, "title": true, "text": true}
const FILE_PATHS := {
	"mobs": "res://data/mobs.json",
	"items": "res://data/items.json",
	"facilities": "res://data/facilities.json",
	"recipes": "res://data/recipes.json",
	"tutorial": "res://data/tutorial.json",
	"milestones": "res://data/milestones.json",
	"biomes": "res://data/biomes.json",
}
const UNDO_CAP := 20
const DIFF_CAP := 40

static var instance: Window = null

var _tabs: TabContainer
var _status: Label
var _layout_body: VBoxContainer
var _text_body: VBoxContainer
var _balance_body: VBoxContainer
var _ui_list: VBoxContainer
var _edit_on: CheckButton
var _sel_label: Label
var _x_spin: SpinBox
var _y_spin: SpinBox
var _confirm_host: Control
var _files: Dictionary = {}
var _baseline: Dictionary = {}
var _undo: Array = []
var _dirty := false
var _filling := false
var _active_balance := true

static func open() -> void:
	if not LiveLayout.desktop_allowed():
		GameState.toast.emit("Live Editor is desktop-only.")
		return
	if instance != null and is_instance_valid(instance):
		instance.grab_focus()
		instance.move_to_foreground()
		return
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
	_add_bar_btn(bar, "Reload", "Discard unsaved edits and re-read data/*.json.", _reload_all)
	_add_bar_btn(bar, "Save to disk", "Validate, show a diff, then write all JSON files.", _request_save_all)
	_add_bar_btn(bar, "Save this entry", "Write only the selected Text/Balance entry to disk.", _save_this_entry)
	_add_bar_btn(bar, "Apply live", "Push edits into the running game without saving files.", _apply_live)
	_add_bar_btn(bar, "Undo", "Revert the last field edit.", _undo_last)
	_status = UIKit.label("Ready", 0.8, Color("9a8f7c"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)

	_confirm_host = Control.new()
	_confirm_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_host.visible = false
	pad.add_child(_confirm_host)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_layout_body = _tab_vbox("Layout")
	_text_body = _tab_vbox("Text")
	_balance_body = _tab_vbox("Balance")
	_build_layout_tab()
	_build_content_tab(_text_body, false)
	_build_content_tab(_balance_body, true)

func _add_bar_btn(bar: HBoxContainer, text: String, tip: String, cb: Callable) -> void:
	var b := UIKit.button(text, cb)
	b.tooltip_text = tip
	bar.add_child(b)

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

# --- Layout tab ---------------------------------------------------------------

func _build_layout_tab() -> void:
	UIKit.clear(_layout_body)
	_layout_body.add_child(UIKit.label(
		"Toggle Edit layout, then drag camp NPCs / heroes / fire, or named Camp chrome.",
		0.75, Color("9a8f7c")))
	_edit_on = CheckButton.new()
	_edit_on.text = "Edit layout on game window"
	_edit_on.tooltip_text = "When on, drag Camp NPCs, hero seats, the fire, or named Camp chrome."
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
	var acts := HBoxContainer.new()
	_layout_body.add_child(acts)
	acts.add_child(UIKit.button("Reset selected", func():
		if LiveLayout.reset_selected():
			_dirty = true
			_refresh_layout_spins()
			_rebuild_ui_list()
			_set_status("Reset %s / %s" % [LiveLayout.sel_kind, LiveLayout.sel_id])
		else:
			_set_status("Nothing selected to reset.")))
	acts.add_child(UIKit.button("Save layout JSON", func():
		var err := LiveLayout.save_layouts()
		_set_status("Layout saved." if err == "" else err)
		if err == "": GameState.toast.emit("Camp / UI layout saved")))
	_layout_body.add_child(UIKit.label("Named UI chrome (fractions of min viewport)", 0.85, Color("ffd27a")))
	_ui_list = VBoxContainer.new()
	_ui_list.add_theme_constant_override("separation", 4)
	_layout_body.add_child(_ui_list)
	_rebuild_ui_list()
	_refresh_layout_spins()

func _rebuild_ui_list() -> void:
	if _ui_list == null: return
	UIKit.clear(_ui_list)
	for target in LiveLayout.UI_TARGETS:
		var n: String = String(target)
		var row := HBoxContainer.new()
		_ui_list.add_child(row)
		var pick := UIKit.button(n, func():
			LiveLayout.select("ui", n)
			_refresh_layout_spins())
		pick.custom_minimum_size.x = 160
		row.add_child(pick)
		var o: Dictionary = LiveLayout.ui_offsets.get(n, {"dx": 0.0, "dy": 0.0})
		var dx := _spin(-2.0, 2.0, 0.005)
		dx.value = float(o.get("dx", 0.0))
		var dy := _spin(-2.0, 2.0, 0.005)
		dy.value = float(o.get("dy", 0.0))
		dx.value_changed.connect(func(v):
			if _filling: return
			LiveLayout.set_ui_offset(n, v, dy.value)
			var main := LiveLayout.find_main()
			if main: LiveLayout.apply_tree(main)
			_dirty = true)
		dy.value_changed.connect(func(v):
			if _filling: return
			LiveLayout.set_ui_offset(n, dx.value, v)
			var main := LiveLayout.find_main()
			if main: LiveLayout.apply_tree(main)
			_dirty = true)
		row.add_child(dx)
		row.add_child(dy)
		row.add_child(UIKit.button("Reset", func():
			LiveLayout.clear_ui_offset(n)
			_rebuild_ui_list()
			var main := LiveLayout.find_main()
			if main: LiveLayout.apply_tree(main)
			_dirty = true))

func _spin(mn: float, mx: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 90
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
			LiveLayout.set_spot_xy(id, v if is_x else _x_spin.value, _y_spin.value if is_x else v)
		"seat":
			LiveLayout.set_seat_xy(id, v if is_x else _x_spin.value, _y_spin.value if is_x else v)
		"fire":
			if not is_x: LiveLayout.set_fire_y(v)
		"ui":
			LiveLayout.set_ui_offset(id, v if is_x else _x_spin.value, _y_spin.value if is_x else v)
			var main := LiveLayout.find_main()
			if main: LiveLayout.apply_tree(main)
	_dirty = true
	_mark_dirty_status()

# --- Text / Balance tabs ------------------------------------------------------

func _build_content_tab(body: VBoxContainer, balance: bool) -> void:
	UIKit.clear(body)
	body.add_child(UIKit.label(
		"Balance numbers (mobs, items, facilities, recipes, biomes)" if balance \
			else "Names, descriptions, tip text",
		0.75, Color("9a8f7c")))
	var cat := OptionButton.new()
	cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in _cats_for(balance):
		cat.add_item(t)
	var search := LineEdit.new()
	search.placeholder_text = "Search id or name…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry := OptionButton.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var copy_btn := OptionButton.new()
	copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_btn.tooltip_text = "Copy editable fields from another entry in this category."
	var blurb := UIKit.label("", 0.8, Color("ffd27a"))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 4)
	var row1 := HBoxContainer.new()
	body.add_child(row1)
	row1.add_child(cat)
	row1.add_child(search)
	var row2 := HBoxContainer.new()
	body.add_child(row2)
	row2.add_child(entry)
	row2.add_child(copy_btn)
	body.add_child(blurb)
	body.add_child(form)
	if balance:
		_add_cheat_footer(body)
	body.set_meta("balance", balance)
	body.set_meta("cat", cat)
	body.set_meta("search", search)
	body.set_meta("entry", entry)
	body.set_meta("copy", copy_btn)
	body.set_meta("blurb", blurb)
	body.set_meta("form", form)
	cat.item_selected.connect(func(_i): _refill_entries(body))
	search.text_changed.connect(func(_t): _refill_entries(body, false))
	entry.item_selected.connect(func(_i): _fill_form(body))
	copy_btn.item_selected.connect(func(i): _copy_from(body, i))
	_refill_entries(body)

func _add_cheat_footer(body: VBoxContainer) -> void:
	body.add_child(UIKit.label("Stash cheat (save only — not JSON)", 0.85, Color("ffd27a")))
	var row := HBoxContainer.new()
	body.add_child(row)
	var mat := OptionButton.new()
	mat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mats: Dictionary = _files.get("items", {}).get("_materials", {})
	var keys: Array = mats.keys()
	keys.sort()
	for k in keys:
		mat.add_item(String(k))
	row.add_child(mat)
	var n := _spin(1, 9999, 1)
	n.value = 10
	n.custom_minimum_size.x = 80
	row.add_child(n)
	row.add_child(UIKit.button("Add to stash", func():
		if mat.item_count == 0: return
		var id := mat.get_item_text(mat.selected)
		GameState.add_mat(id, int(n.value))
		GameState.touch()
		_set_status("Added %d %s to stash." % [int(n.value), id])))

func _cats_for(balance: bool) -> Array:
	if balance:
		return ["mobs", "items", "facilities", "recipes", "biomes"]
	return ["mobs", "items", "materials", "facilities", "tips", "milestones", "biomes"]

func _refill_entries(body: VBoxContainer, reset_sel := true) -> void:
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	var search: LineEdit = body.get_meta("search")
	var copy_btn: OptionButton = body.get_meta("copy")
	var prev := ""
	if entry_btn.item_count > 0 and entry_btn.selected >= 0:
		prev = entry_btn.get_item_text(entry_btn.selected)
	entry_btn.clear()
	copy_btn.clear()
	copy_btn.add_item("Copy from…")
	if cat_btn.item_count == 0: return
	var cat := cat_btn.get_item_text(cat_btn.selected)
	var q := search.text.strip_edges().to_lower()
	var ids: Array = _ids_for(cat)
	ids.sort()
	var keep := []
	for id in ids:
		var sid := String(id)
		if q != "" and not _matches_search(cat, sid, q):
			continue
		keep.append(sid)
		entry_btn.add_item(sid)
		copy_btn.add_item(sid)
	if entry_btn.item_count == 0:
		_fill_form(body)
		return
	var idx := 0
	if not reset_sel and prev != "":
		for i in entry_btn.item_count:
			if entry_btn.get_item_text(i) == prev:
				idx = i; break
	entry_btn.select(idx)
	_fill_form(body)

func _matches_search(cat: String, id: String, q: String) -> bool:
	if id.to_lower().contains(q): return true
	var data := _entry_data(cat, id)
	var nm := String(data.get("name", "")).to_lower()
	return nm.contains(q)

func _ids_for(cat: String) -> Array:
	match cat:
		"mobs":
			return _files.mobs.keys().filter(func(k): return not String(k).begins_with("_"))
		"items":
			return _files.items.keys().filter(func(k): return not String(k).begins_with("_"))
		"materials":
			return _files.items.get("_materials", {}).keys()
		"facilities":
			return _files.facilities.keys().filter(func(k): return not String(k).begins_with("_"))
		"biomes":
			return _files.biomes.keys().filter(func(k): return not String(k).begins_with("_"))
		"recipes":
			var out := []
			for fac in _files.recipes:
				if String(fac).begins_with("_"): continue
				var arr: Variant = _files.recipes[fac]
				if arr is Array:
					for r in arr:
						if r is Dictionary and r.has("id"):
							out.append("%s/%s" % [fac, r.id])
			return out
		"tips":
			return _files.tutorial.get("tips", {}).keys()
		"milestones":
			var out2 := []
			for m in _files.milestones.get("milestones", []):
				if m is Dictionary and m.has("id"):
					out2.append(String(m.id))
			return out2
	return []

func _fill_form(body: VBoxContainer) -> void:
	var form: VBoxContainer = body.get_meta("form")
	var blurb: Label = body.get_meta("blurb")
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	var balance: bool = body.get_meta("balance")
	_active_balance = balance
	UIKit.clear(form)
	if entry_btn.item_count == 0:
		blurb.text = ""
		form.add_child(UIKit.label("No entries match.", 0.75, Color("9a8f7c")))
		return
	var cat := cat_btn.get_item_text(cat_btn.selected)
	var id := entry_btn.get_item_text(entry_btn.selected)
	var data := _entry_data(cat, id)
	if data.is_empty():
		blurb.text = ""
		form.add_child(UIKit.label("(missing)", 0.8, Color("ff8888")))
		return
	blurb.text = _entry_blurb(cat, id, data)
	var groups := {"Combat": [], "Visual": [], "Costs": [], "Other": []}
	for k in data.keys():
		if String(k).begins_with("_"): continue
		if String(k) in ["traps", "music_tracks", "strength_potions_at"]:
			continue
		if String(k) == "encounter_sets":
			if balance: groups.Other.append(k)
			continue
		if String(k) == "pages":
			if not balance: groups.Other.append(k)
			continue
		var v: Variant = data[k]
		if balance:
			if not _is_balance_field(k, v): continue
			groups[_group_for(String(k))].append(k)
		else:
			if typeof(v) == TYPE_STRING and (TEXT_KEYS.has(String(k)) or String(k).ends_with("_desc")):
				groups.Other.append(k)
			elif String(k) == "pages":
				groups.Other.append(k)
	var any := false
	for gname in ["Combat", "Visual", "Costs", "Other"]:
		var keys: Array = groups[gname]
		if keys.is_empty(): continue
		any = true
		form.add_child(UIKit.label(gname, 0.9, Color("c9a96e")))
		for k in keys:
			_add_field(form, cat, id, String(k), data[k], balance)
	if balance and cat == "mobs":
		var preview := UIKit.label(_mob_preview(data), 0.8, Color("88cc88"))
		preview.name = "MobPreview"
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form.add_child(preview)
		form.set_meta("mob_preview", preview)
		form.set_meta("mob_id", id)
	if not any:
		form.add_child(UIKit.label(
			"No editable %s fields on this entry." % ("number" if balance else "text"),
			0.75, Color("9a8f7c")))

func _is_balance_field(k: String, v: Variant) -> bool:
	if typeof(v) in [TYPE_FLOAT, TYPE_INT]: return true
	if typeof(v) == TYPE_ARRAY and (v as Array).size() > 0 and typeof((v as Array)[0]) in [TYPE_INT, TYPE_FLOAT]:
		return true
	if typeof(v) == TYPE_DICTIONARY:
		return String(k) in ["cost", "upgrade_cost", "reward", "event_weights", "patrol_yield_per_hour", "secret_cache"]
	return false

func _group_for(k: String) -> String:
	if COMBAT_KEYS.has(k): return "Combat"
	if VISUAL_KEYS.has(k): return "Visual"
	if COST_KEYS.has(k): return "Costs"
	return "Other"

func _entry_blurb(cat: String, id: String, data: Dictionary) -> String:
	var nm := String(data.get("name", id))
	match cat:
		"mobs":
			return "%s — HT %s · dmg %s · DR %s · delay %s" % [
				nm, data.get("ht", "?"), data.get("dmg", "?"), data.get("dr", "?"), data.get("delay", "?")]
		"items":
			return "%s — %s tier %s" % [nm, data.get("type", "item"), data.get("tier", "?")]
		"facilities":
			return "%s — max Lv%s · fuel %s" % [nm, data.get("max", "?"), data.get("fuel", "?")]
		"recipes":
			return "%s — crafts %s (min facility Lv%s)" % [nm, data.get("out", "?"), data.get("min_level", 1)]
		"biomes":
			var fl: Array = data.get("floors", [])
			return "%s — floors %s-%s · boss %s" % [
				nm, fl[0] if fl.size() > 0 else "?", fl[1] if fl.size() > 1 else "?", data.get("boss", "?")]
		"milestones":
			return "%s — %s ≥ %s" % [nm, data.get("stat", "?"), data.get("goal", "?")]
		_:
			return nm

func _mob_preview(data: Dictionary) -> String:
	var wd: Dictionary = _files.items.get("worn_shortsword", {})
	var hero_dmg := Weapons.dmg(wd, 0)
	var hero_delay := float(wd.get("delay", 1.0))
	var ht := int(data.get("ht", 1))
	var mdr := int(data.get("dr", 0))
	var mdmg := int(data.get("dmg", 1))
	var mdelay := float(data.get("delay", 1.0))
	var per_hit := maxi(1, hero_dmg - mdr)
	var hits := int(ceil(float(ht) / float(per_hit)))
	var turns := hits * hero_delay
	var hero_ht := 25
	var mob_per := maxi(1, mdmg)  # warrior DR ~1 at start; keep simple
	var mob_hits := int(ceil(float(hero_ht) / float(maxi(1, mob_per - 1))))
	return "vs Warrior +0 (worn shortsword dmg %d): ~%d hits / ~%.1f turns to kill · mob needs ~%d hits on 25 HP" % [
		hero_dmg, hits, turns, mob_hits]

func _add_field(form: VBoxContainer, cat: String, id: String, key: String, v: Variant, balance: bool) -> void:
	if not balance:
		if typeof(v) == TYPE_STRING:
			_add_text_field(form, cat, id, key, String(v))
		elif key == "pages" and v is Array:
			_add_tip_pages(form, cat, id, v)
		return
	if key == "encounter_sets" and v is Array:
		_add_encounter_sets(form, cat, id, v)
		return
	if typeof(v) in [TYPE_FLOAT, TYPE_INT]:
		_add_num_field(form, cat, id, key, float(v))
	elif typeof(v) == TYPE_ARRAY and (v as Array).size() > 0 and typeof((v as Array)[0]) in [TYPE_INT, TYPE_FLOAT]:
		_add_array_num_field(form, cat, id, key, v)
	elif typeof(v) == TYPE_DICTIONARY:
		_add_cost_fields(form, cat, id, key, v)

func _add_encounter_sets(form: VBoxContainer, cat: String, id: String, sets: Array) -> void:
	form.add_child(UIKit.label("encounter_sets (min_floor per pack)", 0.75, Color("bdb3a0")))
	for i in sets.size():
		var s: Variant = sets[i]
		if not (s is Dictionary): continue
		var row := HBoxContainer.new()
		form.add_child(row)
		var mobs: Array = s.get("mobs", [])
		var bits: PackedStringArray = PackedStringArray()
		for m in mobs:
			bits.append(String(m))
		var l := UIKit.label("#%d %s" % [i, ", ".join(bits)], 0.7, Color("bdb3a0"))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = "Encounter pack. Edit min_floor: first floor this pack can appear."
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = 1; sp.max_value = 30; sp.step = 1; sp.value = float(s.get("min_floor", 1))
		sp.tooltip_text = "Minimum floor for this encounter pack."
		var ii := i
		sp.value_changed.connect(func(v):
			if _filling: return
			_push_undo()
			var data := _entry_data(cat, id)
			if data.get("encounter_sets") is Array and ii < data.encounter_sets.size():
				data.encounter_sets[ii].min_floor = int(v)
			_mark_edit())
		row.add_child(sp)

func _field_tip(key: String) -> String:
	return String(FIELD_TIPS.get(key, "Data field \"%s\" from the JSON entry." % key))

func _tip(ctrl: Control, key: String) -> void:
	ctrl.tooltip_text = _field_tip(key)
	if ctrl is Label:
		ctrl.mouse_filter = Control.MOUSE_FILTER_STOP

func _push_undo() -> void:
	_undo.append(_deep(_files))
	while _undo.size() > UNDO_CAP:
		_undo.pop_front()

func _mark_edit() -> void:
	_dirty = true
	_mark_dirty_status()

func _mark_dirty_status() -> void:
	_set_status("Unsaved changes" if _dirty else "Ready")

func _after_field_edit(cat: String, id: String, form: VBoxContainer = null) -> void:
	_mark_edit()
	if cat == "mobs" and form != null and form.has_meta("mob_preview"):
		var prev: Label = form.get_meta("mob_preview")
		prev.text = _mob_preview(_entry_data(cat, id))

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
	te.focus_exited.connect(func():
		if te.text == String(_entry_data(cat, id).get(key, "")): return
		_push_undo()
		_set_entry_field(cat, id, key, te.text)
		_mark_edit())
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
		title_e.focus_exited.connect(func():
			_push_undo()
			_files.tutorial.tips[id].pages[ii].title = title_e.text
			_mark_edit())
		form.add_child(title_e)
		form.add_child(UIKit.label("page %d text" % i, 0.75, Color("bdb3a0")))
		var body_e := TextEdit.new()
		body_e.text = String(p.get("text", ""))
		body_e.custom_minimum_size = Vector2(0, 80)
		body_e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		body_e.focus_exited.connect(func():
			_push_undo()
			_files.tutorial.tips[id].pages[ii].text = body_e.text
			_mark_edit())
		form.add_child(body_e)

func _add_num_field(form: VBoxContainer, cat: String, id: String, key: String, val: float) -> void:
	var row := HBoxContainer.new()
	_tip(row, key)
	form.add_child(row)
	var l := UIKit.label(key, 0.8, Color("bdb3a0"))
	l.custom_minimum_size.x = 140
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
		if _filling: return
		_push_undo()
		var out: Variant = int(v) if s.step >= 1.0 else v
		_set_entry_field(cat, id, key, out)
		_after_field_edit(cat, id, form))
	row.add_child(s)

func _add_array_num_field(form: VBoxContainer, cat: String, id: String, key: String, arr: Array) -> void:
	var hdr := UIKit.label(key, 0.75, Color("bdb3a0"))
	_tip(hdr, key)
	form.add_child(hdr)
	var row := HBoxContainer.new()
	form.add_child(row)
	for i in arr.size():
		var s := SpinBox.new()
		s.min_value = -99999; s.max_value = 99999; s.allow_greater = true; s.allow_lesser = true
		s.step = 1.0
		s.value = float(arr[i])
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.tooltip_text = _field_tip(key)
		var ii := i
		s.value_changed.connect(func(v):
			if _filling: return
			_push_undo()
			var data := _entry_data(cat, id)
			if data.has(key) and data[key] is Array:
				data[key][ii] = int(v) if absf(v - roundf(v)) < 0.001 else v
			_after_field_edit(cat, id, form))
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
		l.custom_minimum_size.x = 140
		var tip := "%s\nAmount of %s." % [_field_tip(key), mat]
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(l)
		var s := SpinBox.new()
		s.min_value = -99999; s.max_value = 999999; s.step = 0.05 if typeof(cost[mk]) == TYPE_FLOAT else 1.0
		s.allow_greater = true; s.allow_lesser = true
		s.value = float(cost[mk])
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.tooltip_text = tip
		s.value_changed.connect(func(v):
			if _filling: return
			_push_undo()
			var data := _entry_data(cat, id)
			if data.has(key) and data[key] is Dictionary:
				data[key][mat] = int(v) if s.step >= 1.0 else v
			_mark_edit())
		row.add_child(s)

func _copy_from(body: VBoxContainer, i: int) -> void:
	if i <= 0: return
	var copy_btn: OptionButton = body.get_meta("copy")
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	if entry_btn.item_count == 0: return
	var cat := cat_btn.get_item_text(cat_btn.selected)
	var dest_id := entry_btn.get_item_text(entry_btn.selected)
	var src_id := copy_btn.get_item_text(i)
	if src_id == dest_id: return
	var src := _entry_data(cat, src_id)
	var dest := _entry_data(cat, dest_id)
	if src.is_empty() or dest.is_empty(): return
	_push_undo()
	for k in src.keys():
		if KEEP_ON_COPY.has(String(k)): continue
		dest[k] = _deep_val(src[k])
	copy_btn.select(0)
	_mark_edit()
	_fill_form(body)
	_set_status("Copied fields from %s → %s" % [src_id, dest_id])

func _entry_data(cat: String, id: String) -> Dictionary:
	match cat:
		"mobs": return _files.mobs.get(id, {})
		"items": return _files.items.get(id, {})
		"materials": return _files.items.get("_materials", {}).get(id, {})
		"facilities": return _files.facilities.get(id, {})
		"biomes": return _files.biomes.get(id, {})
		"recipes":
			var parts := id.split("/", false, 1)
			if parts.size() != 2: return {}
			var arr: Variant = _files.recipes.get(parts[0], [])
			if arr is Array:
				for r in arr:
					if r is Dictionary and String(r.get("id", "")) == parts[1]:
						return r
			return {}
		"tips": return _files.tutorial.get("tips", {}).get(id, {})
		"milestones":
			for m in _files.milestones.get("milestones", []):
				if m is Dictionary and String(m.get("id", "")) == id:
					return m
	return {}

func _set_entry_field(cat: String, id: String, key: String, val: Variant) -> void:
	var data := _entry_data(cat, id)
	if data.is_empty(): return
	data[key] = val

func _active_body() -> VBoxContainer:
	if _tabs == null: return _balance_body
	return _balance_body if _tabs.current_tab == 2 else _text_body if _tabs.current_tab == 1 else _balance_body

func _active_cat_id() -> Array:
	var body := _balance_body if _active_balance or (_tabs != null and _tabs.current_tab == 2) else _text_body
	if _tabs != null and _tabs.current_tab == 1:
		body = _text_body
	elif _tabs != null and _tabs.current_tab == 2:
		body = _balance_body
	if body == null or not body.has_meta("cat"): return ["", ""]
	var cat_btn: OptionButton = body.get_meta("cat")
	var entry_btn: OptionButton = body.get_meta("entry")
	if cat_btn.item_count == 0 or entry_btn.item_count == 0: return ["", ""]
	return [cat_btn.get_item_text(cat_btn.selected), entry_btn.get_item_text(entry_btn.selected)]

# --- Load / save / validate ---------------------------------------------------

func _load_files() -> void:
	_files = {
		"mobs": _read(FILE_PATHS.mobs),
		"items": _read(FILE_PATHS.items),
		"facilities": _read(FILE_PATHS.facilities),
		"recipes": _read(FILE_PATHS.recipes),
		"tutorial": _read(FILE_PATHS.tutorial),
		"milestones": _read(FILE_PATHS.milestones),
		"biomes": _read(FILE_PATHS.biomes),
	}
	_baseline = _deep(_files)
	_undo.clear()
	_dirty = false

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

func _deep(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))

func _deep_val(v: Variant) -> Variant:
	return _deep(v)

func _reload_all() -> void:
	_load_files()
	LiveLayout.reload()
	DB.reload()
	GameState.touch()
	_build_content_tab(_text_body, false)
	_build_content_tab(_balance_body, true)
	_rebuild_ui_list()
	_set_status("Reloaded from disk.")

func _undo_last() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo.")
		return
	_files = _undo.pop_back()
	_dirty = not _files_equal(_files, _baseline)
	_build_content_tab(_text_body, false)
	_build_content_tab(_balance_body, true)
	_mark_dirty_status()
	_set_status("Undid last edit." + (" (still unsaved)" if _dirty else ""))

func _apply_live() -> void:
	_push_to_db()
	GameState.touch()
	_set_status("Applied in memory (not saved to disk yet)." if _dirty else "Applied.")

func _request_save_all() -> void:
	var verr := _validate_all()
	if verr != "":
		_set_status(verr)
		GameState.toast.emit(verr)
		return
	var lines := _diff_lines()
	if lines.is_empty() and not _layout_dirty():
		_set_status("No changes to save.")
		return
	_show_diff_confirm(lines, func(): _do_save_all())

func _layout_dirty() -> bool:
	# Compare current layout dumps to disk reload — approximate: any ui offset or camp != baseline file
	return true  # always allow layout save via full save; diff lists content JSON primarily

func _do_save_all() -> void:
	for k in FILE_PATHS:
		var err := LiveLayout.write_json(FILE_PATHS[k], _files[k])
		if err != "":
			_set_status(err)
			GameState.toast.emit(err)
			return
	var lerr := LiveLayout.save_layouts()
	if lerr != "":
		_set_status(lerr)
		GameState.toast.emit(lerr)
		return
	_baseline = _deep(_files)
	_undo.clear()
	_push_to_db()
	GameState.touch()
	_dirty = false
	_set_status("Saved data/*.json.")
	GameState.toast.emit("Live Editor saved")

func _save_this_entry() -> void:
	var pair := _active_cat_id()
	var cat: String = pair[0]
	var id: String = pair[1]
	if cat == "" or id == "":
		_set_status("Select a Text or Balance entry first.")
		return
	var verr := _validate_entry(cat, id)
	if verr != "":
		_set_status(verr)
		GameState.toast.emit(verr)
		return
	var err := _write_entry(cat, id)
	if err != "":
		_set_status(err)
		GameState.toast.emit(err)
		return
	_push_to_db()
	GameState.touch()
	_set_status("Saved %s / %s." % [cat, id])
	GameState.toast.emit("Saved %s" % id)

func _write_entry(cat: String, id: String) -> String:
	match cat:
		"mobs", "facilities", "biomes":
			var path: String = FILE_PATHS[cat]
			var disk := _read(path)
			disk[id] = _deep(_files[cat][id])
			_files[cat][id] = disk[id]
			_baseline[cat][id] = _deep(disk[id])
			return LiveLayout.write_json(path, disk)
		"items":
			var disk2 := _read(FILE_PATHS.items)
			disk2[id] = _deep(_files.items[id])
			_files.items[id] = disk2[id]
			_baseline.items[id] = _deep(disk2[id])
			return LiveLayout.write_json(FILE_PATHS.items, disk2)
		"materials":
			var disk3 := _read(FILE_PATHS.items)
			if not disk3.has("_materials"): disk3._materials = {}
			disk3._materials[id] = _deep(_files.items._materials[id])
			_files.items._materials[id] = disk3._materials[id]
			_baseline.items._materials[id] = _deep(disk3._materials[id])
			return LiveLayout.write_json(FILE_PATHS.items, disk3)
		"recipes":
			var parts := id.split("/", false, 1)
			if parts.size() != 2: return "Bad recipe id"
			var disk4 := _read(FILE_PATHS.recipes)
			var arr: Array = disk4.get(parts[0], [])
			var data := _entry_data("recipes", id)
			for i in arr.size():
				if arr[i] is Dictionary and String(arr[i].get("id", "")) == parts[1]:
					arr[i] = _deep(data)
					break
			disk4[parts[0]] = arr
			_files.recipes = disk4
			_baseline.recipes[parts[0]] = _deep(arr)
			return LiveLayout.write_json(FILE_PATHS.recipes, disk4)
		"tips":
			var disk5 := _read(FILE_PATHS.tutorial)
			disk5.tips[id] = _deep(_files.tutorial.tips[id])
			_files.tutorial.tips[id] = disk5.tips[id]
			_baseline.tutorial.tips[id] = _deep(disk5.tips[id])
			return LiveLayout.write_json(FILE_PATHS.tutorial, disk5)
		"milestones":
			var disk6 := _read(FILE_PATHS.milestones)
			var list: Array = disk6.get("milestones", [])
			var data2 := _entry_data("milestones", id)
			for i in list.size():
				if list[i] is Dictionary and String(list[i].get("id", "")) == id:
					list[i] = _deep(data2)
					break
			disk6.milestones = list
			_files.milestones = disk6
			return LiveLayout.write_json(FILE_PATHS.milestones, disk6)
	return "Cannot save category %s as a single entry." % cat

func _validate_all() -> String:
	for id in _files.mobs:
		if String(id).begins_with("_"): continue
		var e := _validate_entry("mobs", String(id))
		if e != "": return e
	for id in _files.items:
		if String(id).begins_with("_"): continue
		var e2 := _validate_entry("items", String(id))
		if e2 != "": return e2
	for id in _files.facilities:
		if String(id).begins_with("_"): continue
		var e3 := _validate_entry("facilities", String(id))
		if e3 != "": return e3
	for fac in _files.recipes:
		if String(fac).begins_with("_"): continue
		var arr: Variant = _files.recipes[fac]
		if arr is Array:
			for r in arr:
				if r is Dictionary and r.has("id"):
					var e4 := _validate_entry("recipes", "%s/%s" % [fac, r.id])
					if e4 != "": return e4
	return ""

func _validate_entry(cat: String, id: String) -> String:
	var d := _entry_data(cat, id)
	if d.is_empty(): return "Missing %s/%s" % [cat, id]
	for k in ["ht", "dmg", "exp", "loot", "dr"]:
		if d.has(k) and float(d[k]) < 0.0:
			return "%s.%s: %s must be ≥ 0" % [cat, id, k]
	if d.has("delay") and float(d.delay) <= 0.0:
		return "%s.%s: delay must be > 0" % [cat, id]
	if d.has("fw") and int(d.fw) < 1:
		return "%s.%s: fw must be ≥ 1" % [cat, id]
	if d.has("fh") and int(d.fh) < 1:
		return "%s.%s: fh must be ≥ 1" % [cat, id]
	if cat == "facilities" and d.has("max") and int(d.max) < 1:
		return "%s.%s: max must be ≥ 1" % [cat, id]
	for ck in ["cost", "upgrade_cost", "reward"]:
		if d.get(ck) is Dictionary:
			for mk in d[ck]:
				if float(d[ck][mk]) < 0.0:
					return "%s.%s: %s.%s must be ≥ 0" % [cat, id, ck, mk]
	return ""

func _diff_lines() -> Array:
	var lines: Array = []
	_diff_dict("", _baseline, _files, lines)
	return lines

func _diff_dict(prefix: String, a: Variant, b: Variant, lines: Array) -> void:
	if lines.size() > DIFF_CAP + 5: return
	if typeof(a) != typeof(b):
		lines.append("%s: type changed" % prefix)
		return
	if a is Dictionary and b is Dictionary:
		var keys := {}
		for k in a: keys[k] = true
		for k in b: keys[k] = true
		for k in keys:
			if String(k).begins_with("_note"): continue
			var p := "%s.%s" % [prefix, k] if prefix != "" else String(k)
			if not a.has(k):
				lines.append("%s: (added)" % p)
			elif not b.has(k):
				lines.append("%s: (removed)" % p)
			else:
				_diff_dict(p, a[k], b[k], lines)
	elif a is Array and b is Array:
		if JSON.stringify(a) != JSON.stringify(b):
			lines.append("%s: array changed" % prefix)
	else:
		if a != b:
			lines.append("%s: %s → %s" % [prefix, str(a), str(b)])

func _show_diff_confirm(lines: Array, on_yes: Callable) -> void:
	for c in _confirm_host.get_children():
		c.queue_free()
	_confirm_host.visible = true
	_confirm_host.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_host.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(520, 360)
	card.offset_left = -260; card.offset_right = 260
	card.offset_top = -180; card.offset_bottom = 180
	_confirm_host.add_child(card)
	var v := UIKit.vbox(card)
	v.add_child(UIKit.header("Save changes?"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 220
	v.add_child(sc)
	var lv := VBoxContainer.new()
	sc.add_child(lv)
	var shown := mini(lines.size(), DIFF_CAP)
	for i in shown:
		lv.add_child(UIKit.label(String(lines[i]), 0.75, Color("e8e0d4")))
	if lines.size() > DIFF_CAP:
		lv.add_child(UIKit.label("…and %d more" % (lines.size() - DIFF_CAP), 0.75, Color("9a8f7c")))
	if lines.is_empty():
		lv.add_child(UIKit.label("(content JSON unchanged — will still save layouts)", 0.75, Color("9a8f7c")))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UIKit.button("Save", func():
		_hide_confirm()
		on_yes.call()))
	row.add_child(UIKit.secondary(UIKit.button("Cancel", _hide_confirm)))

func _hide_confirm() -> void:
	_confirm_host.visible = false
	_confirm_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in _confirm_host.get_children():
		c.queue_free()

func _files_equal(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func _push_to_db() -> void:
	DB.mobs = _strip_keys(_files.mobs)
	var it: Dictionary = _files.items
	DB.materials = it.get("_materials", {})
	DB.items = _strip_keys(it)
	DB.facilities = _strip_keys(_files.facilities)
	DB.recipes = _strip_keys(_files.recipes)
	DB.biomes = _strip_keys(_files.biomes)
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
