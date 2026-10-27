## CombatScreen: hosts GridView + controls (D-pad / Attack on mobile; Wait/skills/Bag/Auto) + scrollable log.
## Mobile: portrait = grid on top / panel below; wide = grid left / panel right (Fold).
## Desktop (DECISIONS #232): StatusPane on top, log | grid mid row (log ~1/3), bottom toolbar + Menu.
extends Control

const GridView := preload("res://scripts/ui/grid_view.gd")
const Keybinds := preload("res://scripts/ui/keybinds.gd")

var main: Control
var combat: Combat
var on_done: Callable
var event: Dictionary
var reward: Dictionary = {}
var split: BoxContainer
var desk: VBoxContainer
var desk_mid: HBoxContainer
var grid
var side: VBoxContainer
var header_label: Label
var status: Label
## Desktop only: hosts the one-line status under the pane. Mobile folds tips into the log.
var status_host: ScrollContainer
var pane: StatusPane
var buttons: Container
var toolbar_scroll: ScrollContainer
var log_scroll: ScrollContainer
var log_label: RichTextLabel
var result_layer: Control
var mode := ""
var potions := 0
var potions_used := 0
var heal := 10
var auto := false
var _auto_t := 0.0
var _low_hp_stopped := false
var finished := false
var _applied := false
var _summary := {}
var _pause_after := false
## Guided first fight (v0.11.0, DECISIONS #63): 0 = off, 1 move, 2 attack, 3 finish, 4 done
var bag_open := false
var bag_layer: Control
var bag_host: VBoxContainer
## Mid-fight Scroll of Passage confirm (DECISIONS #202). Open = Auto Battle waits; Cancel spends no turn.
var passage_confirm := false
var passage_layer: Control
## Desktop/Mobile Settings overlay (pauses Auto while open).
var menu_open := false
var menu_layer: Control
var guide := 0
var guide_label: Label
## Class skill / mode buttons for combat_skill_1 / _2 keybinds (Shove, Slam, Cloak, Bolt in build order).
var _skill_cbs: Array = []
var _skill_enabled: Array = []

## `saved` (optional) = Combat.to_dict() from GameState.run.active_fight when resuming after the app was killed.
func setup(ev: Dictionary, done: Callable, saved := {}) -> void:
	event = ev; on_done = done
	_applied = false; _summary = {}; _pause_after = false
	var run: Dictionary = GameState.run
	reward = ev.get("reward", run.get("active_fight", {}).get("reward", {}))
	var hs: Dictionary = GameState.hero_stats(run.hero)
	if saved.is_empty():
		combat = Delve.new_combat(GameState, ev)
	else:
		combat = Combat.new(); combat.from_dict(saved)
		combat._log("(fight resumed)")
	potions = int(run.supplies.get("potion_healing", 0))
	heal = GameState.potion_heal(run.hero)
	if combat.over:
		finished = true; auto = false
		if combat.won: _ensure_victory_summary()
		return
	# Auto Battle plays the fight itself: the combat Auto toggle starts on (unless already close to dying).
	if bool(GameState.settings.get("full_auto", false)):
		if combat.close_to_dying(): _stop_auto_low_hp()
		else: auto = true

func _ready() -> void:
	grid = GridView.new(); grid.tapped.connect(_on_cell)
	if not GameState.run.is_empty():
		grid.tileset = DB.biomes[GameState.run.biome].tile
		grid.water_name = DB.biomes[GameState.run.biome].get("water", "water0")
		grid.lighting = bool(GameState.settings.get("lighting", true))
	grid.set_combat(combat)
	header_label = UIKit.header("BOSS: " + DB.mobs[event.mobs[0]].name if event.get("boss", false) else "Combat")
	if not event.get("boss", false) and bool(GameState.settings.get("tutorial", true)) and not ("guided_fight" in GameState.tutorial_done):
		guide = 1
		guide_label = UIKit.label("", 1.0, Color("9fd3ff")); guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pane = StatusPane.new()
	var hs0 := combat.hero
	pane.set_hero(String(hs0.sprite), int(hs0.fw), int(hs0.fh), int(hs0.get("row", 0)))
	status = UIKit.label("")
	log_scroll = ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bg := UIKit.chrome("toast", Color(0.75, 0.75, 0.75))
	log_scroll.add_theme_stylebox_override("panel", bg)
	log_label = RichTextLabel.new(); log_label.fit_content = true; log_label.scroll_active = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = SIZE_EXPAND_FILL; log_scroll.add_child(log_label)
	_assemble_chrome()
	_refresh()
	if main: main.tip("boss" if event.get("boss", false) else "first_fight")

var _portrait := true
var _area := Vector2.ZERO
var desktop_ui := false

func apply_layout(portrait: bool, s: Vector2, desk_ui := false) -> void:
	if VitaBoot.runs_on_vita():
		_vita_btn_key = ""
	var changed := desk_ui != desktop_ui or (split == null and desk == null)
	_portrait = portrait; _area = s; desktop_ui = desk_ui
	if changed or (desktop_ui and desk == null) or (not desktop_ui and split == null):
		_assemble_chrome()
	if desktop_ui:
		_pin_full_rect(desk)
		grid.size_flags_vertical = SIZE_EXPAND_FILL
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		_fit_desk_pane()
	elif split:
		_pin_full_rect(split)
		split.vertical = portrait
		grid.size_flags_vertical = SIZE_SHRINK_BEGIN if portrait else SIZE_FILL
		if pane: pane.set_max_w(0.0); pane.size_flags_horizontal = SIZE_EXPAND_FILL
	_refresh()

## Desktop: keep the status strip phone-wide instead of spanning the whole monitor.
func _fit_desk_pane() -> void:
	if pane == null: return
	pane.set_max_w(UIKit.desk_bar_w(_area.x) if _area.x > 0.0 else UIKit.desk_bar_w(size.x))
	pane.size_flags_horizontal = SIZE_SHRINK_BEGIN

## Full-rect anchors after the node is in the tree (don't assign size — anchors own it).
func _pin_full_rect(n: Control) -> void:
	if n == null: return
	n.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

## Move a kept widget onto a new parent (Mobile↔Desktop reassembly).
func _reparent(n: Node, parent: Node) -> void:
	if n == null or parent == null: return
	var old := n.get_parent()
	if old == parent: return
	if old: old.remove_child(n)
	parent.add_child(n)

## Build Mobile split or Desktop column without freeing GridView / StatusPane mid-fight.
func _assemble_chrome() -> void:
	# Pull kept widgets off the old chrome before freeing it (otherwise add_child fails and only
	# a new empty toolbar shows — which is what the broken Desktop fight looked like).
	var keep := [grid, pane, status, guide_label, header_label, log_scroll, bag_layer, passage_layer, menu_layer]
	for n in keep:
		if n and is_instance_valid(n) and n.get_parent():
			n.get_parent().remove_child(n)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	split = null; desk = null; desk_mid = null; side = null; toolbar_scroll = null; buttons = null
	status_host = null
	result_layer = null
	if desktop_ui:
		desk = VBoxContainer.new(); desk.name = "DeskChrome"
		desk.add_theme_constant_override("separation", int(UIKit.font_size * 0.3))
		add_child(desk)
		_pin_full_rect(desk)
		# Top chrome (SPD status strip) — capped width on Desktop (see _fit_desk_pane)
		pane.size_flags_vertical = SIZE_SHRINK_BEGIN
		_fit_desk_pane()
		_reparent(pane, desk)
		status.size_flags_vertical = SIZE_SHRINK_BEGIN
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_reparent(status, desk)
		if guide_label:
			guide_label.size_flags_vertical = SIZE_SHRINK_BEGIN
			_reparent(guide_label, desk)
		# Mid: combat log (left ~1/3) | dungeon grid (right ~2/3)
		desk_mid = HBoxContainer.new(); desk_mid.name = "DeskMid"
		desk_mid.add_theme_constant_override("separation", int(UIKit.font_size * 0.4))
		desk_mid.size_flags_vertical = SIZE_EXPAND_FILL
		desk_mid.size_flags_horizontal = SIZE_EXPAND_FILL
		desk.add_child(desk_mid)
		log_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
		log_scroll.size_flags_stretch_ratio = 1.0
		log_scroll.custom_minimum_size = Vector2.ZERO
		_reparent(log_scroll, desk_mid)
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.size_flags_vertical = SIZE_EXPAND_FILL
		grid.size_flags_stretch_ratio = 2.0
		_reparent(grid, desk_mid)
		# Bottom toolbar — roomy SPD action bar
		toolbar_scroll = ScrollContainer.new()
		toolbar_scroll.size_flags_vertical = SIZE_SHRINK_BEGIN
		toolbar_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		toolbar_scroll.custom_minimum_size.y = _desk_toolbar_h()
		desk.add_child(toolbar_scroll)
		buttons = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", int(UIKit.font_size * 0.45))
		buttons.size_flags_vertical = SIZE_SHRINK_CENTER
		toolbar_scroll.add_child(buttons)
	else:
		split = BoxContainer.new(); split.name = "MobileSplit"
		split.add_theme_constant_override("separation", 12)
		split.clip_contents = true
		add_child(split)
		_pin_full_rect(split)
		_reparent(grid, split)
		side = UIKit.vbox(split)
		side.size_flags_horizontal = SIZE_EXPAND_FILL; side.size_flags_vertical = SIZE_EXPAND_FILL
		side.clip_contents = true
		_reparent(header_label, side)
		if guide_label: _reparent(guide_label, side)
		pane.set_max_w(0.0)
		pane.size_flags_horizontal = SIZE_EXPAND_FILL
		_reparent(pane, side)
		# Mobile: no separate status strip (its Label min-width was clipping the pane/controls).
		# Tips live at the top of the combat log instead.
		status_host = null
		status.visible = false
		log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
		log_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		log_scroll.size_flags_stretch_ratio = 1.0
		log_scroll.custom_minimum_size = Vector2(0, UIKit.font_size * 3)
		log_scroll.clip_contents = true
		_reparent(log_scroll, side)
		# Mid-fight actions+chrome, or Victory/Defeat content after clear.
		buttons = UIKit.vbox(side, int(UIKit.font_size * 0.35))
		buttons.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.size_flags_vertical = SIZE_SHRINK_BEGIN
		side.clip_contents = true

## The side column never gets less than SIDE_MIN_FS font sizes, nor less than what its widest row needs.
const SIDE_MIN_FS := 13.0
## Ultrawide Mobile: D-pad basis cap so controls stay finger-sized while the side column still fills leftover width (DECISIONS #236).
const PAD_BASIS_MAX_FS := 20.0
## Wide layout: the grid is a square of at most 60% of the width, and gives up width so the side column (status,
## buttons, the Victory card) fits. The side expands into leftover space (fills the monitor); only the D-pad is
## capped (#236). Re-run after every _refresh: the Victory card only exists once the fight is over.
static func wide_pad_basis(area: Vector2) -> float:
	return floorf(minf(area.x * 0.45, UIKit.font_size * PAD_BASIS_MAX_FS))

static func wide_grid_side(area: Vector2, side_min: float, sep: float) -> float:
	var need := maxf(side_min, UIKit.font_size * SIDE_MIN_FS)
	return floorf(maxf(0.0, minf(area.y, minf(area.x * 0.6, area.x - need - sep))))

func _desk_toolbar_h() -> float:
	return UIKit.btn_height() * 1.25 + 8.0

## D-pad cell size: portrait uses half the combat width; wide uses a phone-sized basis, not the full ultrawide side.
func _mobile_pad_cell() -> float:
	var basis: float
	if _portrait:
		basis = _area.x * 0.48 if _area.x > 0.0 else UIKit.font_size * 10.0
	elif _area != Vector2.ZERO:
		basis = wide_pad_basis(_area)
	else:
		basis = UIKit.font_size * 10.0
	var half := basis * 0.95
	var sep := UIKit.font_size * 0.12 * 2.0
	var cell := floorf((half - sep) / 3.0)
	cell = floorf(cell * 0.5) * 2.0
	# Hard cap: about 3.5 font sizes per cell so PC Mobile stays finger-sized, not monitor-sized.
	cell = minf(cell, floorf(UIKit.font_size * 3.5 / 2.0) * 2.0)
	return maxf(UIKit.btn_height(), cell)

func _mobile_pad_h() -> float:
	var cell := _mobile_pad_cell()
	return cell * 3.0 + UIKit.font_size * 0.12 * 2.0

## Height of the mobile D-pad / skills row + Bag/Auto/Menu chrome.
func _mobile_controls_min_h() -> float:
	var fs := float(UIKit.font_size)
	var chrome := UIKit.btn_height() + fs * 0.35
	return _mobile_pad_h() + chrome + fs * 0.35

## Portrait side column floor: header, pane, log floor, controls (so the grid can shrink to fit).
func _mobile_side_min_h() -> float:
	var fs := float(UIKit.font_size)
	var h := fs * 1.6
	if guide_label and is_instance_valid(guide_label) and guide_label.visible:
		h += fs * 2.5
	h += StatusPane.PANE_H * float(maxi(2, UIKit.px_scale))
	h += fs * 4.0
	h += _mobile_controls_min_h()
	h += fs * 1.0
	return h

## Reserved height above/below the desktop mid row (status + toolbar + seps).
func _desktop_chrome_h() -> float:
	var fs := float(UIKit.font_size)
	var top := StatusPane.PANE_H * float(maxi(2, UIKit.px_scale)) + fs * 1.4
	if guide_label and guide_label.get_parent() == desk:
		top += fs * 2.2
	return top + _desk_toolbar_h() + fs * 0.8

func _fit_split() -> void:
	if grid == null or _area == Vector2.ZERO: return
	if desktop_ui:
		_pin_full_rect(desk)
		var sep := float(desk_mid.get_theme_constant("separation")) if desk_mid else 8.0
		var mid_h := floorf(maxf(64.0, _area.y - _desktop_chrome_h()))
		var log_w := floorf(_area.x / 3.0)
		var grid_side := floorf(maxf(64.0, minf(_area.x - log_w - sep, mid_h)))
		log_scroll.custom_minimum_size = Vector2(log_w, mid_h)
		grid.custom_minimum_size = Vector2(grid_side, grid_side)
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.size_flags_vertical = SIZE_EXPAND_FILL
		if toolbar_scroll:
			toolbar_scroll.custom_minimum_size.y = _desk_toolbar_h()
		return
	if _portrait:
		# Full-width square used to eat the Fold cover; shrink so D-pad + Bag/Auto/Menu stay on screen.
		var sep := float(split.get_theme_constant("separation")) if split else 12.0
		var grid_side := floorf(minf(_area.x, maxf(96.0, _area.y - _mobile_side_min_h() - sep)))
		grid.custom_minimum_size = Vector2(grid_side, grid_side)
		if log_scroll:
			log_scroll.custom_minimum_size.y = UIKit.font_size * 3
		return
	var g := wide_grid_side(_area, side_min_width(), float(split.get_theme_constant("separation")))
	grid.custom_minimum_size = Vector2(g, g)

## The widest row the side column needs, leaving out the combat log: its fit_content RichTextLabel reports the width
## it was last laid out at, so after a wide layout a smaller window would keep that width as the column's floor and
## crush the arena (Bugbot on #113). The log wraps to whatever width the column gets.
func side_min_width() -> float:
	if side == null: return UIKit.font_size * SIDE_MIN_FS
	var w := 0.0
	for c in side.get_children():
		if c == log_scroll or not (c is Control) or not (c as Control).visible: continue
		w = maxf(w, (c as Control).get_combined_minimum_size().x)
	return w

var _vita_btn_key := ""
var _vita_log_key := ""
var _vita_auto_at := 0
var _vita_save_at := 0
var _vita_stick_at := 0

func _process(d: float) -> void:
	if VitaBoot.runs_on_vita():
		_process_vita()
		return
	if main and main.tip_open(): return
	if finished: return
	if passage_confirm or menu_open or bag_open: return
	if auto:
		_auto_t += d
		if _auto_t > 0.35:
			_auto_t = 0.0; _do_bot()

## Wall-clock gap so a slow frame cannot fire Auto on every frame. Vita waits 700 ms so a slow
## turn does not start another on the next frame. Phone auto still uses _auto_t > 0.35.
## Left stick walks in 8 directions with a short cooldown (D-pad stays edge-triggered).
func _process_vita() -> void:
	if main and main.tip_open(): return
	if finished: return
	if passage_confirm or menu_open or bag_open: return
	if not auto:
		_vita_stick_move()
		return
	if _vita_auto_at == 0:
		_vita_auto_at = Time.get_ticks_msec() + 700
	if Time.get_ticks_msec() < _vita_auto_at:
		return
	var t0 := Time.get_ticks_usec()
	_do_bot()
	VitaBoot.add_us("combat_bot", int(Time.get_ticks_usec() - t0))
	_vita_auto_at = Time.get_ticks_msec() + 700

func _vita_stick_move() -> void:
	var step := Keybinds.vita_stick_step()
	if step == Vector2i.ZERO:
		return
	if Time.get_ticks_msec() < _vita_stick_at:
		return
	_vita_stick_at = Time.get_ticks_msec() + 180
	_act(func(): combat.hero_tap(combat.hero.pos + step, mode))

## Combat keyboard (DECISIONS #232) and the Vita pad (DECISIONS #244). Bag / Passage / Menu / tip own cancel first.
func _unhandled_input(event: InputEvent) -> void:
	if main and main.tip_open(): return
	if not Keybinds.accepts_combat_shortcut(event): return
	if Keybinds.just_pressed("combat_cancel", event):
		get_viewport().set_input_as_handled()
		if menu_open:
			menu_open = false; _refresh(); return
		if bag_open:
			bag_open = false; _refresh(); return
		if passage_confirm:
			_cancel_passage(); return
		if mode != "":
			mode = ""; grid.mode = ""; _refresh(); return
		return
	if finished or passage_confirm or bag_open or menu_open: return
	if auto and not Keybinds.just_pressed("combat_auto", event): return
	for action in Keybinds.MOVE_DIR.keys():
		if Keybinds.just_pressed(action, event):
			get_viewport().set_input_as_handled()
			var step: Vector2i = combat.hero.pos + Keybinds.MOVE_DIR[action]
			_act(func(): combat.hero_tap(step, mode))
			return
	if Keybinds.just_pressed("combat_wait", event):
		get_viewport().set_input_as_handled(); _act(func(): combat.hero_wait()); return
	if Keybinds.just_pressed("combat_search", event):
		get_viewport().set_input_as_handled(); _act(func(): combat.hero_search()); return
	if Keybinds.just_pressed("combat_bag", event):
		get_viewport().set_input_as_handled(); bag_open = not bag_open; set_meta("bag_scroll", 0); _refresh(); return
	if Keybinds.just_pressed("combat_hint", event):
		get_viewport().set_input_as_handled(); _hint(); return
	if Keybinds.just_pressed("combat_auto", event):
		get_viewport().set_input_as_handled(); auto = not auto; _refresh(); return
	if Keybinds.just_pressed("combat_potion", event):
		get_viewport().set_input_as_handled(); _drink(); return
	if Keybinds.just_pressed("combat_skill_1", event) and _skill_cbs.size() > 0:
		get_viewport().set_input_as_handled()
		if _skill_enabled.size() > 0 and _skill_enabled[0]:
			_skill_cbs[0].call()
		return
	if Keybinds.just_pressed("combat_skill_2", event) and _skill_cbs.size() > 1:
		get_viewport().set_input_as_handled()
		if _skill_enabled.size() > 1 and _skill_enabled[1]:
			_skill_cbs[1].call()
		return

const BTN_ICONS := {"Wait": "wait", "Search": "search", "Search again": "search", "Bag": "backpack",
	"Auto": "busy", "Auto: ON": "busy", "Shove": "arrow", "Shove: ON": "arrow", "Scroll of Passage": "scroll",
	"Passage": "scroll", "Menu": "prefs", "Attack": "challenge"}
const BTN_PREFIX_ICONS := {"Slam": "warning", "Cloak": "buffs", "Bolt": "target", "Scroll of Passage": "scroll", "Passage": "scroll"}
## Desktop toolbar: short labels, no wrap, roomy slots (vanilla SPD bottom bar).
const DESK_LABELS := {"Scroll of Passage": "Passage", "Search again": "Search"}
## Cached SPD arrow icons rotated for the mobile D-pad (key = "x,y@px_scale").
static var _dir_tex: Dictionary = {}

func _btn(text: String, cb: Callable, enabled := true, skill := false, parent: Node = null) -> Button:
	var label := String(DESK_LABELS.get(text, text)) if desktop_ui else text
	var b := UIKit.button(label, cb, enabled)
	if desktop_ui:
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.clip_text = true
		b.custom_minimum_size = Vector2(UIKit.font_size * 7.2, UIKit.btn_height() * 1.2)
		b.size_flags_horizontal = SIZE_SHRINK_BEGIN
		b.size_flags_vertical = SIZE_SHRINK_CENTER
	else:
		# No large min width: 3x (font*6.5) Bag/Auto/Menu overflowed phone widths and clipped the right edge.
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, UIKit.btn_height())
		b.size_flags_horizontal = SIZE_EXPAND_FILL
	var ic: String = BTN_ICONS.get(text, BTN_ICONS.get(label, ""))
	for pre in BTN_PREFIX_ICONS:
		if text.begins_with(pre) or label.begins_with(pre): ic = BTN_PREFIX_ICONS[pre]
	UIKit.as_toolbar(b, ic)   # SPD toolbar slots for in-fight actions
	(parent if parent else buttons).add_child(b)
	if skill:
		_skill_cbs.append(cb)
		_skill_enabled.append(enabled)
	return b

## Icon-only toolbar slot (Search / Wait / D-pad). Tooltip carries the name.
func _icon_btn(tip: String, icon: String, cb: Callable, enabled := true, parent: Node = null, tex: Texture2D = null) -> Button:
	var b := UIKit.button("", cb, enabled, tip)
	b.size_flags_horizontal = SIZE_SHRINK_BEGIN
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2.ONE * UIKit.btn_height()
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.as_toolbar(b, icon if tex == null else "")
	if tex != null:
		b.icon = tex
		b.expand_icon = false
	(parent if parent else buttons).add_child(b)
	return b

## Direction chevron at a fixed pixel size (same for cardinals and diagonals).
func _dir_icon(dir: Vector2i, px: int = -1) -> Texture2D:
	var s := px if px > 0 else int(_mobile_pad_cell())
	s = maxi(12, s - s % 2)
	var key := "chev%d,%d@%d" % [dir.x, dir.y, s]
	if _dir_tex.has(key):
		return _dir_tex[key]
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var forward := Vector2(dir).normalized()
	var c := Vector2((s - 1) * 0.5, (s - 1) * 0.5)
	var tip := c + forward * (s * 0.40)
	var back := c - forward * (s * 0.22)
	var perp := Vector2(-forward.y, forward.x)
	var left := back + perp * (s * 0.34)
	var right := back - perp * (s * 0.34)
	# Black outline then SPD-blue fill so it reads on the grey toolbar slot.
	_fill_tri(img, tip, left, right, Color("000000"))
	var inset := 1.15
	_fill_tri(img, c + (tip - c) / inset, c + (left - c) / inset, c + (right - c) / inset, Color("6ea8ff"))
	_dir_tex[key] = ImageTexture.create_from_image(img)
	return _dir_tex[key]

func _fill_tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var min_x := int(floor(minf(a.x, minf(b.x, c.x))))
	var max_x := int(ceil(maxf(a.x, maxf(b.x, c.x))))
	var min_y := int(floor(minf(a.y, minf(b.y, c.y))))
	var max_y := int(ceil(maxf(a.y, maxf(b.y, c.y))))
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, min_y), mini(h, max_y + 1)):
		for x in range(maxi(0, min_x), mini(w, max_x + 1)):
			var p := Vector2(x, y)
			var v0 := c - a
			var v1 := b - a
			var v2 := p - a
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 0.0001:
				continue
			var aa := (v2.x * v1.y - v1.x * v2.y) / den
			var bb := (v0.x * v2.y - v2.x * v0.y) / den
			if aa >= 0.0 and bb >= 0.0 and aa + bb <= 1.0:
				img.set_pixel(x, y, col)

## items.png sprite for an item/material id, nearest-scaled for toolbar buttons.
func _item_icon_tex(id: String) -> Texture2D:
	if id == "" or (not DB.items.has(id) and not DB.materials.has(id)):
		return null
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/items.png")
	at.region = UIKit.item_rect(DB.icon_index(id))
	var img: Image = at.get_image()
	var k := maxi(2, UIKit.px_scale)
	img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	var w := img.get_width() + img.get_width() % 2
	var h := img.get_height() + img.get_height() % 2
	if w != img.get_width() or h != img.get_height():
		var pad := Image.create(w, h, false, img.get_format())
		pad.fill(Color(0, 0, 0, 0))
		pad.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img = pad
	return ImageTexture.create_from_image(img)

## Equipped weapon sprite for the Attack button (falls back to challenge icon).
func _attack_weapon_tex() -> Texture2D:
	if GameState.run.is_empty():
		return null
	var uid := int(GameState.heroes[GameState.run.hero].get("weapon", 0))
	var g: Dictionary = GameState.gear_by_uid(uid)
	if g.is_empty():
		return null
	return _item_icon_tex(String(g.get("id", "")))

## Melee Attack target: last_target if still in reach, else nearest foe in reach.
func _attack_target() -> Dictionary:
	var reach: Array = combat.in_reach()
	if reach.is_empty():
		return {}
	for e in reach:
		if int(e.uid) == combat.last_target:
			return e
	var best: Dictionary = reach[0]
	var bd := Combat.cheb(best.pos, combat.hero.pos)
	for e in reach:
		var d := Combat.cheb(e.pos, combat.hero.pos)
		if d < bd:
			bd = d
			best = e
	return best

func _attack_press() -> void:
	var t := _attack_target()
	if t.is_empty():
		return
	_act(func(): combat.hero_tap(t.pos, mode))

func _move_dir(dir: Vector2i) -> void:
	_act(func(): combat.hero_tap(combat.hero.pos + dir, mode))

func _register_skill(cb: Callable, enabled: bool) -> void:
	_skill_cbs.append(cb)
	_skill_enabled.append(enabled)

## Mobile left half: 8-way D-pad with Wait in the middle.
func _build_mobile_pad(parent: Node) -> void:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	wrap.size_flags_vertical = SIZE_SHRINK_CENTER
	wrap.size_flags_stretch_ratio = 1.0
	parent.add_child(wrap)
	var pad := GridContainer.new()
	pad.columns = 3
	var gap := int(UIKit.font_size * 0.12)
	pad.add_theme_constant_override("h_separation", gap)
	pad.add_theme_constant_override("v_separation", gap)
	wrap.add_child(pad)
	var cell := _mobile_pad_cell()
	var dirs: Array = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	var tips := {
		Vector2i(0, -1): "Move north", Vector2i(0, 1): "Move south",
		Vector2i(-1, 0): "Move west", Vector2i(1, 0): "Move east",
		Vector2i(-1, -1): "Move NW", Vector2i(1, -1): "Move NE",
		Vector2i(-1, 1): "Move SW", Vector2i(1, 1): "Move SE",
	}
	for d in dirs:
		if d == Vector2i.ZERO:
			var wait_b := _icon_btn("Wait", "wait", func(): _act(func(): combat.hero_wait()), true, pad)
			wait_b.custom_minimum_size = Vector2.ONE * cell
			wait_b.expand_icon = true
		else:
			var dir: Vector2i = d
			var b := _icon_btn(tips[dir], "", func(): _move_dir(dir), true, pad, _dir_icon(dir, int(cell)))
			b.custom_minimum_size = Vector2.ONE * cell
			b.expand_icon = true

## Mobile right half: Attack, class skills (Shove / Slam / Cloak / Bolt), Heal.
func _build_mobile_skills(parent: Node) -> void:
	var col := UIKit.vbox(parent, int(UIKit.font_size * 0.2))
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	var h := combat.hero
	var n := 2  # Attack + Heal
	if "shove" in h.abilities: n += 1
	if "slam" in h.abilities: n += 1
	if not h.cloak.is_empty(): n += 1
	if not h.bolt.is_empty() and not h.bolt.get("infinite", false): n += 1
	var gap := UIKit.font_size * 0.2
	var row_h := maxf(UIKit.btn_height(), floorf((_mobile_pad_h() - gap * float(n - 1)) / float(n)))
	var tgt := _attack_target()
	var atk := _btn("Attack", _attack_press, not tgt.is_empty(), false, col)
	atk.custom_minimum_size.y = row_h
	atk.size_flags_vertical = SIZE_EXPAND_FILL
	atk.tooltip_text = "Attack"
	# Equipped weapon art instead of the challenge trophy.
	var wtex := _attack_weapon_tex()
	if wtex != null:
		atk.icon = wtex
		atk.expand_icon = false
	if "shove" in h.abilities:
		var shove_on := mode == "shove"
		var shove_cb := func():
			mode = "" if mode == "shove" else "shove"
			grid.mode = mode
			_refresh()
		var shove := _btn("Shove", shove_cb, true, true, col)
		shove.custom_minimum_size.y = row_h
		shove.size_flags_vertical = SIZE_EXPAND_FILL
		shove.tooltip_text = "Shove: ON" if shove_on else "Shove"
		if shove_on:
			shove.modulate = Color(1.15, 1.15, 0.85)
	if "slam" in h.abilities:
		var can_slam := int(h.slams) > 0 and combat.enemies().any(func(e): return Combat.cheb(e.pos, h.pos) == 1)
		var slam := _btn("Slam %d" % h.slams, func(): _act(func(): combat.hero_slam()), can_slam, true, col)
		slam.custom_minimum_size.y = row_h
		slam.size_flags_vertical = SIZE_EXPAND_FILL
		slam.tooltip_text = "Slam (%d)" % h.slams
	if not h.cloak.is_empty():
		var can_cloak := int(h.cloak_charges) > 0 and not combat.hidden()
		var cloak := _btn("Cloak", func(): _act(func(): combat.hero_cloak()), can_cloak, true, col)
		cloak.custom_minimum_size.y = row_h
		cloak.size_flags_vertical = SIZE_EXPAND_FILL
		cloak.tooltip_text = "Cloak (%d/%d)" % [int(h.cloak_charges), _cloak_cap(h)]
	if not h.bolt.is_empty() and not h.bolt.get("infinite", false):
		var bolt_on := mode == "bolt"
		var bolt_tip := "Bolt: ON (%d)" % h.charges if bolt_on else "Bolt (%d)" % h.charges
		var bolt := _btn("Bolt %d" % h.charges, _bolt_press, h.charges > 0, true, col)
		bolt.custom_minimum_size.y = row_h
		bolt.size_flags_vertical = SIZE_EXPAND_FILL
		bolt.tooltip_text = bolt_tip
		if bolt_on:
			bolt.modulate = Color(1.15, 1.15, 0.85)
	var pot_n := potions - potions_used
	var pot := _btn("Heal %d" % pot_n, _drink, pot_n > 0 and h.hp < h.ht, false, col)
	pot.custom_minimum_size.y = row_h
	pot.size_flags_vertical = SIZE_EXPAND_FILL
	pot.tooltip_text = "Potion of Healing (%d)" % pot_n
	var ptex := _item_icon_tex("potion_healing")
	if ptex != null:
		pot.icon = ptex
		pot.expand_icon = false

## Shared class-skill strip for the desktop toolbar (Shove / Slam / Cloak / Bolt).
func _add_skill_buttons(parent: Node) -> void:
	var h := combat.hero
	if "shove" in h.abilities:
		_btn("Shove: ON" if mode == "shove" else "Shove", func():
			mode = "" if mode == "shove" else "shove"
			grid.mode = mode
			_refresh()
		, true, true, parent)
	if "slam" in h.abilities:
		_btn("Slam (%d)" % h.slams, func(): _act(func(): combat.hero_slam()), int(h.slams) > 0 and combat.enemies().any(func(e): return Combat.cheb(e.pos, h.pos) == 1), true, parent)
	if not h.cloak.is_empty():
		_btn("Cloak (%d/%d)" % [int(h.cloak_charges), _cloak_cap(h)], func(): _act(func(): combat.hero_cloak()), int(h.cloak_charges) > 0 and not combat.hidden(), true, parent)
	if not h.bolt.is_empty() and not h.bolt.get("infinite", false):
		_btn("Bolt: ON (%d)" % h.charges if mode == "bolt" else "Bolt (%d)" % h.charges, _bolt_press, h.charges > 0, true, parent)

func _build_mobile_controls() -> void:
	# Middle row: half movement, half actions (no side icon column).
	var actions := UIKit.hbox(buttons)
	actions.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.size_flags_vertical = SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override("separation", int(UIKit.font_size * 0.35))
	_build_mobile_pad(actions)
	_build_mobile_skills(actions)
	# Bottom chrome: Search, optional Passage, Bag, Auto, Menu.
	var chrome := UIKit.hbox(buttons)
	chrome.size_flags_horizontal = SIZE_EXPAND_FILL
	chrome.add_theme_constant_override("separation", int(UIKit.font_size * 0.25))
	var search_tip := "Search again" if combat.hero.get("searched", false) else "Search"
	var search_b := _icon_btn(search_tip, "search", func(): _act(func(): combat.hero_search()), true, chrome)
	search_b.size_flags_horizontal = SIZE_EXPAND_FILL
	if Delve.scroll_passage_count(GameState) > 0:
		var pass_b := _icon_btn("Scroll of Passage", "scroll", _ask_passage, true, chrome)
		pass_b.size_flags_horizontal = SIZE_EXPAND_FILL
	var bag := _icon_btn("Bag", "backpack", func(): bag_open = not bag_open; menu_open = false; set_meta("bag_scroll", 0); _refresh(), true, chrome)
	bag.size_flags_horizontal = SIZE_EXPAND_FILL
	var auto_b := _icon_btn("Auto battle: ON" if auto else "Auto battle", "busy", func(): auto = not auto; _refresh(), true, chrome)
	auto_b.size_flags_horizontal = SIZE_EXPAND_FILL
	if auto:
		auto_b.modulate = Color(1.15, 1.15, 0.85)
	var menu_b := _icon_btn("Menu", "prefs", func(): menu_open = not menu_open; bag_open = false; _refresh(), true, chrome)
	menu_b.size_flags_horizontal = SIZE_EXPAND_FILL

func _refresh() -> void:
	var vita := VitaBoot.runs_on_vita()
	var t0 := Time.get_ticks_usec() if vita else 0
	if vita and _vita_refresh_skip():
		VitaBoot.add_us("combat_refresh", int(Time.get_ticks_usec() - t0))
		return
	if vita and _vita_auto_light():
		VitaBoot.add_us("combat_refresh", int(Time.get_ticks_usec() - t0))
		return
	if status == null:
		return
	var h := combat.hero
	var bl := []
	if int(h.get("poison", 0)) > 0: bl.append(3)              # POISON
	if combat.hidden(): bl.append(12)                          # INVISIBLE
	if int(h.barrier) > 0: bl.append(20)                       # ARMOR
	var run: Dictionary = GameState.run
	var lvl := 1
	if not run.is_empty(): lvl = int(GameState.heroes[run.hero].level)
	var minis := []
	if not run.is_empty():
		minis = [{"kind": "exp", "icon": "torch", "frac": float(run.torch) / 100.0, "text": "Torch %d%%" % run.torch},
			{"kind": "shield", "icon": "ration", "frac": float(run.satiety) / 100.0, "text": "Food %d%%" % run.satiety}]
	pane.set_data({"name": h.name, "level": lvl, "hp": h.hp, "ht": h.ht, "shield": h.barrier, "shield_hits": combat.barrier_hits(), "buffs": bl,
		"floor": int(run.get("floor", 1)) if not run.is_empty() else 0,
		"feeling": String(run.get("feeling", "")) if not run.is_empty() else "",
		"danger": combat.enemies().filter(func(e): return e.hp > 0).size(), "minis": minis})
	# Desktop: one status line under the pane. Mobile: tips ride in the combat log (see _refresh_log).
	if desktop_ui:
		var tips := _combat_tip_lines()
		var line := "\n".join(tips)
		status.text = tips[0] if not tips.is_empty() else ""
		status.tooltip_text = line
		status.visible = not finished
		if status_host and is_instance_valid(status_host):
			status_host.visible = not finished
	else:
		status.visible = false
	_guide_update()
	if main and not finished:
		# Don't pop the Surprise modal over the guided first fight (steps 1-3): an unseen foe in tall grass makes
		# surprise_ready() true from turn 0, which hid the step banner and froze _process until Next (DECISIONS #139).
		if combat.surprise_ready() and (guide == 0 or guide >= 4): main.tip("surprise")
		if not combat.danger.is_empty(): main.tip("telegraph")
		if combat.traps.values().any(func(t): return not t.hidden): main.tip("trap")
	if buttons: UIKit.clear(buttons)
	_skill_cbs.clear(); _skill_enabled.clear()
	_clear_result_layer()
	if finished:
		_result_buttons(); _refresh_log(); _refresh_bag(); _refresh_passage(); _fit_split()
		if vita:
			VitaBoot.add_us("combat_refresh", int(Time.get_ticks_usec() - t0))
		return
	if desktop_ui:
		_btn("Wait", func(): _act(func(): combat.hero_wait()))
		_add_skill_buttons(buttons)
		_btn("Search" if not h.get("searched", false) else "Search again", func(): _act(func(): combat.hero_search()))
		var desk_pot := _btn("Heal (%d)" % (potions - potions_used), _drink, potions - potions_used > 0 and h.hp < h.ht)
		desk_pot.tooltip_text = "Potion of Healing (%d)" % (potions - potions_used)
		var desk_ptex := _item_icon_tex("potion_healing")
		if desk_ptex != null:
			desk_pot.icon = desk_ptex
			desk_pot.expand_icon = false
		if Delve.scroll_passage_count(GameState) > 0:
			_btn("Scroll of Passage", _ask_passage)
		_btn("Bag", func(): bag_open = not bag_open; menu_open = false; set_meta("bag_scroll", 0); _refresh())
		_btn("Auto: ON" if auto else "Auto", func(): auto = not auto; _refresh())
		_btn("Menu", func(): menu_open = not menu_open; bag_open = false; _refresh())
	else:
		_build_mobile_controls()
	_refresh_log()
	_refresh_bag()
	_refresh_menu()
	_refresh_passage()
	_fit_split()
	if vita:
		VitaBoot.add_us("combat_refresh", int(Time.get_ticks_usec() - t0))

## Vita: the status pane still redraws, but the button tree stays until the buttons themselves change.
func _vita_refresh_skip() -> bool:
	if status == null or buttons == null or combat == null:
		return false
	var h := combat.hero
	var bl := []
	if int(h.get("poison", 0)) > 0: bl.append(3)
	if combat.hidden(): bl.append(12)
	if int(h.barrier) > 0: bl.append(20)
	var run: Dictionary = GameState.run
	var lvl := 1
	if not run.is_empty(): lvl = int(GameState.heroes[run.hero].level)
	var minis := []
	if not run.is_empty():
		minis = [{"kind": "exp", "icon": "torch", "frac": float(run.torch) / 100.0, "text": "Torch %d%%" % run.torch},
			{"kind": "shield", "icon": "ration", "frac": float(run.satiety) / 100.0, "text": "Food %d%%" % run.satiety}]
	pane.set_data({"name": h.name, "level": lvl, "hp": h.hp, "ht": h.ht, "shield": h.barrier, "shield_hits": combat.barrier_hits(), "buffs": bl,
		"floor": int(run.get("floor", 1)) if not run.is_empty() else 0,
		"feeling": String(run.get("feeling", "")) if not run.is_empty() else "",
		"danger": combat.enemies().filter(func(e): return e.hp > 0).size(), "minis": minis})
	_guide_update()
	var slam_adj := false
	if "slam" in h.abilities:
		slam_adj = combat.enemies().any(func(e): return Combat.cheb(e.pos, h.pos) == 1)
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		finished, auto, mode, bag_open, menu_open, passage_confirm, desktop_ui,
		potions - potions_used, h.get("searched", false), Delve.scroll_passage_count(GameState),
		int(h.get("charges", 0)), int(h.get("slams", 0)), int(h.get("cloak_charges", 0)),
		combat.hidden(), int(h.hp) < int(h.ht), slam_adj]
	var log_key := str(combat.log_lines.size())
	if not combat.log_lines.is_empty():
		log_key += str(combat.log_lines[-1])
	log_key += "|%s|%s" % [combat.surprise_ready(), combat.danger.is_empty()]
	if key != _vita_btn_key or buttons.get_child_count() == 0:
		_vita_btn_key = key
		_vita_log_key = log_key
		return false
	if log_key != _vita_log_key:
		_vita_log_key = log_key
		_refresh_log()
	_vita_combat_tips()
	return true

## While Auto is running and the buttons already exist, skip the button rebuild. Status and the log still move.
## Fight end sets auto off before _refresh, so the result buttons still build.
func _vita_auto_light() -> bool:
	if not auto or finished or status == null or combat == null or buttons == null or buttons.get_child_count() == 0:
		return false
	_vita_status_only()
	_guide_update()
	var log_key := str(combat.log_lines.size())
	if not combat.log_lines.is_empty():
		log_key += str(combat.log_lines[-1])
	log_key += "|%s|%s" % [combat.surprise_ready(), combat.danger.is_empty()]
	if log_key != _vita_log_key:
		_vita_log_key = log_key
		_refresh_log()
	_vita_combat_tips()
	return true

func _vita_status_only() -> void:
	var h := combat.hero
	var bl := []
	if int(h.get("poison", 0)) > 0: bl.append(3)
	if combat.hidden(): bl.append(12)
	if int(h.barrier) > 0: bl.append(20)
	var run: Dictionary = GameState.run
	var lvl := 1
	if not run.is_empty(): lvl = int(GameState.heroes[run.hero].level)
	var minis := []
	if not run.is_empty():
		minis = [{"kind": "exp", "icon": "torch", "frac": float(run.torch) / 100.0, "text": "Torch %d%%" % run.torch},
			{"kind": "shield", "icon": "ration", "frac": float(run.satiety) / 100.0, "text": "Food %d%%" % run.satiety}]
	pane.set_data({"name": h.name, "level": lvl, "hp": h.hp, "ht": h.ht, "shield": h.barrier, "shield_hits": combat.barrier_hits(), "buffs": bl,
		"floor": int(run.get("floor", 1)) if not run.is_empty() else 0,
		"feeling": String(run.get("feeling", "")) if not run.is_empty() else "",
		"danger": combat.enemies().filter(func(e): return e.hp > 0).size(), "minis": minis})

func _vita_combat_tips() -> void:
	if main == null or finished:
		return
	if combat.surprise_ready() and (guide == 0 or guide >= 4): main.tip("surprise")
	if not combat.danger.is_empty(): main.tip("telegraph")
	if combat.traps.values().any(func(t): return not t.hidden): main.tip("trap")

## In-combat Bag: swap weapon/armor/ring/wand from the backpack; a swap costs the hero's turn (1 tick).
## A carried Scroll of Passage is listed here too. Read opens the confirm; accepting extracts with no tick.
## Opens as a modal window clamped to the viewport (DECISIONS #143): it used to be appended under the
## buttons in the side column, which ran off the bottom on the Fold cover and off the right on the inner screen.
const BAG_MARGIN := 0.02
## The bag panel's rect for a viewport of size vs: centred, at most 36 font sizes wide, inside a 2% margin.
static func bag_rect(vs: Vector2) -> Rect2:
	var m := (vs * BAG_MARGIN).floor()
	var w := minf(vs.x - 2.0 * m.x, UIKit.font_size * 36.0); var h := vs.y - 2.0 * m.y
	return Rect2(((vs - Vector2(w, h)) / 2.0).floor(), Vector2(w, h).floor())

func _refresh_bag() -> void:
	if bag_layer and is_instance_valid(bag_layer):
		var sc0: ScrollContainer = bag_layer.get_meta("sc")
		set_meta("bag_scroll", sc0.scroll_vertical)
		bag_layer.queue_free()
	bag_layer = null
	if not bag_open or finished or GameState.run.is_empty(): return
	var close := func(): bag_open = false; _refresh()
	bag_layer = Control.new(); bag_layer.name = "BagLayer"; bag_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(bag_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); bag_layer.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			dim.accept_event(); close.call())
	var pc := PanelContainer.new(); pc.name = "BagPanel"; pc.clip_contents = true; bag_layer.add_child(pc)
	var r := bag_rect(size if size.x > 0 and size.y > 0 else get_viewport_rect().size)
	pc.position = r.position; pc.size = r.size; pc.custom_minimum_size = r.size
	var v := UIKit.vbox(pc)
	var tr := UIKit.hbox(v)
	var ic := UIKit.pixel(UIKit.spd_icon("backpack"), 1); ic.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(ic)
	var tl := UIKit.header("Bag"); tl.size_flags_horizontal = SIZE_EXPAND_FILL; tr.add_child(tl)
	var x := UIKit.button("X", close); x.name = "BagClose"; UIKit.secondary(x); x.custom_minimum_size = Vector2.ONE * UIKit.btn_height()
	x.size_flags_horizontal = SIZE_SHRINK_END; tr.add_child(x)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = SIZE_EXPAND_FILL; v.add_child(sc); bag_layer.set_meta("sc", sc)
	var body := UIKit.vbox(sc); body.size_flags_horizontal = SIZE_EXPAND_FILL
	HeroPanels.backpack(body, _refresh, true, _equip_in_combat, _ask_passage)
	var keep := int(get_meta("bag_scroll", 0))
	(func(): if is_instance_valid(sc): sc.scroll_vertical = keep).call_deferred()

func _equip_in_combat() -> void:
	bag_open = false
	var hs := GameState.hero_stats(GameState.run.hero)
	_act(func(): combat.apply_stats(hs); combat._log("%s swaps gear." % combat.hero.name); combat.hero_wait())
	heal = GameState.potion_heal(GameState.run.hero)

## In-fight Settings (same panel as Camp / Delve). Auto Battle waits while open.
func _refresh_menu() -> void:
	if menu_layer and is_instance_valid(menu_layer):
		set_meta("menu_scroll", menu_layer.get_meta("sc").scroll_vertical if menu_layer.has_meta("sc") else 0)
		menu_layer.queue_free()
	menu_layer = null
	if not menu_open or finished: return
	var close := func(): menu_open = false; _refresh()
	menu_layer = Control.new(); menu_layer.name = "MenuLayer"
	menu_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(menu_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); menu_layer.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			dim.accept_event(); close.call())
	var pc := PanelContainer.new(); pc.name = "MenuPanel"; pc.clip_contents = true; menu_layer.add_child(pc)
	pc.add_theme_stylebox_override("panel", UIKit.chrome("window", Color.WHITE, UIKit.font_size * 0.6))
	var r := bag_rect(size if size.x > 0 and size.y > 0 else get_viewport_rect().size)
	pc.position = r.position; pc.size = r.size; pc.custom_minimum_size = r.size
	var v := UIKit.vbox(pc)
	var tr := UIKit.hbox(v)
	var ic := UIKit.pixel(UIKit.spd_icon("prefs"), 1); ic.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(ic)
	var tl := UIKit.header("Settings"); tl.size_flags_horizontal = SIZE_EXPAND_FILL; tr.add_child(tl)
	var x := UIKit.button("X", close); UIKit.secondary(x); x.custom_minimum_size = Vector2.ONE * UIKit.btn_height()
	x.size_flags_horizontal = SIZE_SHRINK_END; tr.add_child(x)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = SIZE_EXPAND_FILL; v.add_child(sc); menu_layer.set_meta("sc", sc)
	var body := UIKit.vbox(sc); body.size_flags_horizontal = SIZE_EXPAND_FILL
	# on_rebuild refreshes this menu so category folds, wipe cancel, and rebind keep working.
	SettingsPanel.build(body, false, func(): if main: main.show_camp(), func(): _refresh_menu())
	var keep := int(get_meta("menu_scroll", 0))
	(func(): if is_instance_valid(sc): sc.scroll_vertical = keep).call_deferred()

## Guided first fight: a step banner + a glowing tile showing exactly what to tap. Never blocks input.
func _guide_update() -> void:
	if guide == 0 or guide_label == null: return
	var h := combat.hero
	var foes := combat.enemies()
	var adj := foes.filter(func(e): return Combat.cheb(e.pos, h.pos) == 1)
	if finished:
		if guide < 4:
			guide = 4
			if not ("guided_fight" in GameState.tutorial_done): GameState.tutorial_done.append("guided_fight")
		guide_label.text = "Tutorial complete! Positioning wins fights: close a door behind you or circle tall grass for a Surprise attack, step off red tiles, and use your class ability." if combat.won else "You fell - that's part of learning. Gear cracks, but the Camp keeps everything you banked."
		return
	if guide <= 2 and (combat.kills > 0 or foes.any(func(e): return e.hp < e.ht)): guide = 3
	if guide == 1 and not adj.is_empty(): guide = 2
	match guide:
		1:
			if desktop_ui:
				guide_label.text = "Step 1/3 - Move: tap the glowing tile to step toward the enemy. Each action costs time; enemies act on the same clock."
			else:
				guide_label.text = "Step 1/3 - Move: use the D-pad or tap the glowing tile to step toward the enemy. Each action costs time; enemies act on the same clock."
			if not foes.is_empty():
				var st = combat.path_step(h.pos, foes[0].pos, true, true, true)
				if st != null: grid.hint_cell = st
		2:
			if desktop_ui:
				guide_label.text = "Step 2/3 - Attack: tap the glowing enemy next to you."
			else:
				guide_label.text = "Step 2/3 - Attack: tap Attack or the glowing enemy next to you."
			grid.hint_cell = adj[0].pos if not adj.is_empty() else Vector2i(-1, -1)
		3:
			guide_label.text = "Step 3/3 - Finish it! Blue bar = Barrier (soaks hits first, refills each fight; each segment = one hit it stops). Red tiles = an attack is coming: step off."
	grid.queue_redraw()

## Situational combat tips (staff, Surprise, snake, …). Mobile shows these in the log; desktop uses the status line.
func _combat_tip_lines() -> PackedStringArray:
	var h := combat.hero
	var tips: PackedStringArray = []
	tips.append("DR %d  Dmg %d%s   t=%.1f" % [h.dr, h.dmg, ("  Reach %d" % int(h.reach)) if int(h.get("reach", 1)) > 1 else "", combat.time])
	if not h.bolt.is_empty():
		if h.bolt.get("infinite", false):
			tips.append("Tap any tile in range to shoot %s (%d dmg; it passes tall grass)" % [h.bolt.name, h.bolt.dmg])
		else:
			tips.append("Staff charges %d/%d (%s, %d dmg, ignores DR)" % [h.charges, h.bolt.charges, h.bolt.name, h.bolt.dmg])
			if mode == "bolt":
				tips.append("Bolt again: nearest foe, or last attacker")
	if combat.hidden():
		tips.append("HIDDEN in shadows - enemies can't find you")
	if int(h.get("poison", 0)) > 0:
		tips.append("POISONED: -1 HP per turn for %d turns" % int(h.poison))
	if combat.surprise_now():
		var pierce := ""
		if int(h.get("sur_bonus", 0)) > 0 or String(h.get("sub", "")) == "assassin": pierce = ", 50% DR pierce"
		elif String(h.get("sub", "")) == "warden" and combat.has_ranged() and not h.bolt.get("magic", true): pierce = ", 50% DR pierce"
		elif h.bolt.get("pierce", false): pierce = ", ignores DR"
		tips.append("Surprise ready (%.1fx dmg, can't miss%s)" % [float(h.surprise_mult), pierce])
	if combat.enemies().any(func(e): return e.get("evade_unless_surprise", false)):
		tips.append("Snake: melee needs a Surprise; magic always hits, bows after the first shot")
	return tips

func _refresh_log() -> void:
	log_label.clear()
	# Never set custom_minimum_size.x from log_scroll.size — that feedback-looped and walked the
	# whole combat UI rightward on each click. H-scroll is disabled, so the label is sized to the panel
	# and autowrap handles long tip lines.
	log_label.custom_minimum_size.x = 0
	if not desktop_ui and not finished:
		log_label.push_color(Color("c9a96e"))
		for tip in _combat_tip_lines():
			log_label.add_text(tip + "\n")
		log_label.pop()
		if not combat.log_lines.is_empty():
			log_label.add_text("\n")
	for l in combat.log_lines:
		log_label.add_text(l + "\n")
	await get_tree().process_frame
	if is_instance_valid(log_scroll): log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

## Staff Bolt button (DECISIONS #231): first tap enters aim mode; second tap fires at last attacker or nearest clear shot.
func _bolt_press() -> void:
	if finished or combat.hero.bolt.is_empty() or int(combat.hero.charges) <= 0: return
	if mode == "bolt":
		var at := combat.auto_bolt_pos()
		if at.x >= 0:
			_act(func():
				if combat.hero_bolt(at):
					mode = ""; grid.mode = ""
			)
			return
		mode = ""; grid.mode = ""; _refresh(); return
	mode = "bolt"; grid.mode = mode; _refresh()

func _on_cell(c: Vector2i) -> void:
	if finished: return
	var u = combat.unit_at(c)
	if u != null and u != combat.hero and Combat.cheb(c, combat.hero.pos) > 1 and not combat.can_bolt(c) and not combat.can_melee(u):
		_inspect(u); return
	if u == null and combat.visible_trap(c) and Combat.cheb(c, combat.hero.pos) > 1:
		var tr: Dictionary = DB.traps[combat.traps[c].id]
		GameState.say("%s: %s Enemies avoid traps, but you can shove or slam them in." % [tr.name, tr.desc]); return
	var m := mode
	_act(func():
		if combat.hero_tap(c, m):
			if m != "": mode = ""; grid.mode = ""
		)

## Keep the fight in the save so Android killing the app doesn't lose it.
## Vita writes at most once every 2 seconds. A slow ux0 save was inside every auto action.
func _persist() -> void:
	if VitaBoot.runs_on_vita():
		var now := Time.get_ticks_msec()
		if now < _vita_save_at:
			return
		_vita_save_at = now + 2000
	if GameState.run.has("active_fight"):
		GameState.run.active_fight.combat = combat.to_dict()
		SaveSystem.save_game()

func _inspect(u: Dictionary) -> void:
	var spd := "fast (%s ticks)" % Weapons.num(float(u.delay), 1) if float(u.delay) < 1.0 else "normal"
	var extra := ""
	match u.get("ability", ""):
		"throw": extra = " Throws a spear at range %d-%d (red tile, %d dmg)." % [u.throw_range[0], u.throw_range[1], int(u.dmg) + int(u.throw_bonus)]
		"pump": extra = " Every %d actions slams all adjacent tiles for x%d." % [u.pump_every, u.pump_mult]
		_: extra = " " + Codex.ability_text(u)
	GameState.say("%s: HP %d/%d, dmg %d, DR %d, %s.%s" % [u.name, u.hp, u.ht, u.dmg, u.dr, spd, extra])

func _act(f: Callable) -> void:
	grid.hint_cell = Vector2i(-1, -1)
	f.call()
	grid.play_events(combat.drain_events())
	_persist()
	if combat.over and not finished:
		finished = true; auto = false
		if combat.won: _ensure_victory_summary()
		Sfx.play("levelup" if combat.won else "death")
	else:
		_check_low_hp_stop()
	_refresh()

## Turn off Auto Battle when close to dying so the player can manually control the fight or use a Scroll of Passage.
func _check_low_hp_stop() -> bool:
	if not combat.close_to_dying():
		_low_hp_stopped = false
		return false
	if not auto or _low_hp_stopped:
		return false
	_stop_auto_low_hp()
	return true

func _stop_auto_low_hp() -> void:
	_low_hp_stopped = true
	auto = false
	if GameState.settings.get("full_auto", false):
		GameState.settings.full_auto = false
		SaveSystem.save_game()
	if main and main.get("delve") != null:
		main.delve.running = false
	var msg := "Low HP! Auto battle off - take control or use Scroll of Passage." if Delve.scroll_passage_count(GameState) > 0 else "Low HP! Auto battle off - take manual control."
	combat._log(msg)
	GameState.log_line(msg, "warning")

func _ask_passage() -> void:
	if Delve.scroll_passage_count(GameState) <= 0: return
	passage_confirm = true
	auto = false
	bag_open = false
	menu_open = false
	_refresh()

func _cancel_passage() -> void:
	passage_confirm = false
	_refresh()

func _use_passage() -> void:
	passage_confirm = false
	if not Delve.use_scroll_passage(GameState):
		_refresh()
		return
	finished = true; auto = false
	if main: main.show_camp()
	else: _refresh()

## Mid-fight Passage confirm: same SPD window look as the delve card (title, body, Read / Cancel).
func _refresh_passage() -> void:
	if passage_layer and is_instance_valid(passage_layer):
		passage_layer.queue_free()
	passage_layer = null
	if not passage_confirm or finished or GameState.run.is_empty(): return
	if Delve.scroll_passage_count(GameState) <= 0:
		passage_confirm = false
		return
	var close := _cancel_passage
	passage_layer = Control.new(); passage_layer.name = "PassageLayer"
	passage_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(passage_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); passage_layer.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			dim.accept_event(); close.call())
	var pc := PanelContainer.new(); pc.name = "PassagePanel"; passage_layer.add_child(pc)
	pc.add_theme_stylebox_override("panel", UIKit.chrome("window", Color.WHITE, UIKit.font_size * 0.6))
	var vs := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	var w := minf(vs.x * 0.9, UIKit.font_size * 28.0)
	var h := UIKit.font_size * 12.0
	pc.position = ((vs - Vector2(w, h)) / 2.0).floor(); pc.size = Vector2(w, h); pc.custom_minimum_size = Vector2(w, 0)
	var v := UIKit.vbox(pc)
	var tr := UIKit.hbox(v)
	var ic := UIKit.pixel(UIKit.spd_icon("scroll"), 1); ic.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(ic)
	var tl := UIKit.header("Scroll of Passage"); tl.size_flags_horizontal = SIZE_EXPAND_FILL; tr.add_child(tl)
	v.add_child(UIKit.label(Delve.passage_text()))
	v.add_child(UIKit.button("Read", _use_passage))
	v.add_child(UIKit.button("Cancel", close))

## Potions are consumed from the run supplies immediately (so a lost fight doesn't refund them).
func _drink() -> void:
	if potions - potions_used <= 0: return
	potions_used += 1
	combat.potions_drunk += 1   # saved with the fight, so a resume still knows (DECISIONS #195)
	GameState.run.supplies.potion_healing = maxi(0, int(GameState.run.supplies.get("potion_healing", 0)) - 1)
	_act(func(): combat.hero_heal(heal))

func _hint() -> void:
	var s := CombatBot.suggest(combat, potions - potions_used, heal)
	GameState.say("Hint: " + s.why)
	grid.hint_cell = s.get("pos", Vector2i(-1, -1))

func _do_bot() -> void:
	if _check_low_hp_stop():
		_refresh()
		return
	var s := CombatBot.suggest(combat, potions - potions_used, heal)
	combat.auto_used = true   # this fight no longer counts for "By Hand" (DECISIONS #195)
	match s.act:
		"heal": _drink()
		"wait": _act(func(): combat.hero_wait())
		"cloak": _act(func(): if not combat.hero_cloak(): combat.hero_wait())
		"slam": _act(func(): if not combat.hero_slam(): combat.hero_wait())
		"search": _act(func(): combat.hero_search())
		"tap": _act(func(): if not combat.hero_tap(s.pos, s.mode): combat.hero_wait())

## A fight saved before DECISIONS #206 has no cloak_cap on the hero: use the class's cap.
func _cloak_cap(h: Dictionary) -> int:
	if h.has("cloak_cap"): return int(h.cloak_cap)
	return GameState.cloak_cap(String(GameState.run.get("hero", ""))) if not GameState.run.is_empty() else int(h.cloak_charges)

func _ensure_victory_summary() -> void:
	if not _summary.is_empty(): return
	var res := result()
	if not GameState.run.is_empty():
		var before := Delve.ledger(GameState)
		var lvl: int = GameState.heroes[GameState.run.hero].level
		Delve.apply_fight_result(GameState, event, res, reward)
		_applied = true
		if int(GameState.heroes[GameState.run.hero].level) > lvl:
			GameState.run.talent_prompted = false
		_summary = Delve.fight_changes(before, Delve.ledger(GameState), res)
		if Delve.close_to_dying(GameState) and GameState.settings.get("full_auto", false):
			_stop_auto_low_hp()
		GameState.run.erase("active_fight")
		SaveSystem.save_game()
	else:
		var got := PackedStringArray()
		var lost := PackedStringArray()
		var icons := {}
		if combat.loot > 0: got.append("+%d Gold" % combat.loot); icons[got[-1]] = {"id": "gold", "known": true, "drop": false}
		if combat.fallen_loot > 0: got.append("+%d Gold on the next floor" % combat.fallen_loot); icons[got[-1]] = {"id": "gold", "known": true, "drop": false}
		if combat.xp > 0: got.append("+%d XP" % combat.xp)
		if combat.gold_debt > 0: lost.append("-%d Gold (thief escaped)" % combat.gold_debt); icons[lost[-1]] = {"id": "gold", "known": true, "drop": false}
		if potions_used > 0: lost.append("-%d %s" % [potions_used, DB.display_name("potion_healing")]); icons[lost[-1]] = {"id": "potion_healing", "known": true, "drop": true}
		_summary = {"got": got, "lost": lost, "icons": icons}

func _clear_result_layer() -> void:
	if result_layer and is_instance_valid(result_layer):
		result_layer.queue_free()
	result_layer = null

## Desktop: floating chrome card over the grid. Mobile: same content in the side toolbar column.
func _result_host() -> Control:
	if not desktop_ui:
		return buttons
	_clear_result_layer()
	result_layer = Control.new(); result_layer.name = "ResultLayer"
	result_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(result_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); dim.mouse_filter = MOUSE_FILTER_STOP
	result_layer.add_child(dim)
	var pc := PanelContainer.new(); pc.name = "ResultPanel"; result_layer.add_child(pc)
	pc.add_theme_stylebox_override("panel", UIKit.chrome("window", Color.WHITE, UIKit.font_size * 0.6))
	var vs := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	var w := minf(vs.x * 0.7, UIKit.font_size * 32.0)
	var h := minf(vs.y * 0.7, UIKit.font_size * 28.0)
	pc.position = ((vs - Vector2(w, h)) / 2.0).floor(); pc.size = Vector2(w, h); pc.custom_minimum_size = Vector2(w, 0)
	var host := UIKit.vbox(pc)
	host.size_flags_horizontal = SIZE_EXPAND_FILL
	host.size_flags_vertical = SIZE_EXPAND_FILL
	return host

func _result_buttons() -> void:
	var host := _result_host()
	if combat.won:
		_ensure_victory_summary()
		var card := UIKit.card() if not desktop_ui else host
		if not desktop_ui:
			card.name = "VictoryResults"
			card.size_flags_horizontal = SIZE_EXPAND_FILL
			host.add_child(card)
		var box := card if desktop_ui else UIKit.vbox(card, int(UIKit.font_size * 0.25))
		if desktop_ui:
			box.add_theme_constant_override("separation", int(UIKit.font_size * 0.25))
		else:
			box.size_flags_horizontal = SIZE_EXPAND_FILL
		box.add_child(UIKit.header("Victory"))
		var icons: Dictionary = _summary.get("icons", {})
		var lines := VBoxContainer.new(); lines.name = "VictoryLines"
		lines.add_theme_constant_override("separation", int(UIKit.font_size * 0.15))
		lines.size_flags_horizontal = SIZE_EXPAND_FILL
		_result_section(lines, "Got", _summary.got, GameState.LOG_COLORS.positive, icons)
		if not _summary.lost.is_empty():
			_result_section(lines, "Lost", _summary.lost, GameState.LOG_COLORS.negative, icons)
		# At most VICTORY_ROWS rows show; a longer list (a boss, a full pack) scrolls inside the card instead of
		# pushing the buttons and the log off the panel.
		var sc := ScrollContainer.new(); sc.name = "VictoryList"
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = SIZE_EXPAND_FILL
		sc.size_flags_vertical = SIZE_EXPAND_FILL if desktop_ui else SIZE_SHRINK_BEGIN
		sc.add_child(lines)
		box.add_child(sc)
		sc.custom_minimum_size.y = victory_list_h(lines)
		var row := UIKit.hbox(box)
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", int(UIKit.font_size * 0.3))
		var cont := UIKit.button("Continue", _finish)
		var pause := UIKit.button("Continue and pause", _finish_paused, true,
			"Turns off x3 speed and Auto Battle, then pauses the delve.")
		var bh := UIKit.btn_height() + UIKit.font_px(UIKit.font_size)
		for b in [cont, pause]:
			# the label wraps ("Continue and / pause"), so a narrow side column squeezes the buttons, not the screen
			b.custom_minimum_size = Vector2(UIKit.font_size * 4.0, bh)
			UIKit.as_toolbar(b)
			row.add_child(b)
	else:
		# Column, not a bare label in the HFlow: a wrapping Label with no width collapses to one
		# letter per line and used to stretch Wake at Camp to half the screen (DECISIONS #228).
		var col := host if desktop_ui else UIKit.vbox()
		if not desktop_ui:
			col.name = "DefeatResults"
			col.size_flags_horizontal = SIZE_EXPAND_FILL
			host.add_child(col)
		var msg := UIKit.label("Defeat... the pack is lost and your gear cracks.", 1.0, Color("ff7070"))
		msg.size_flags_horizontal = SIZE_EXPAND_FILL
		msg.custom_minimum_size.x = UIKit.font_size * SIDE_MIN_FS
		col.add_child(msg)
		var wake := UIKit.button("Wake at Camp", _finish)
		wake.custom_minimum_size.x = UIKit.font_size * 6.5
		UIKit.as_toolbar(wake)
		col.add_child(wake)

## Rows the Victory list shows before it scrolls (a heading counts as a row).
const VICTORY_ROWS := 6

## Height of the first VICTORY_ROWS rows (all of them if fewer), plus half a row peeking out when there are more.
## Measured from the rows themselves (single-line labels, so their height doesn't depend on the column width).
static func victory_list_h(lines: Container) -> float:
	var kids := lines.get_children()
	var sep := float(lines.get_theme_constant("separation"))
	var h := 0.0
	for i in mini(kids.size(), VICTORY_ROWS):
		h += (kids[i] as Control).get_combined_minimum_size().y + (sep if i > 0 else 0.0)
	if kids.size() > VICTORY_ROWS:
		h += sep + (kids[VICTORY_ROWS] as Control).get_combined_minimum_size().y * 0.5
	return ceilf(h)

## Item sprites on the Victory card: an integer multiple of SPD's 16-px cell, about a line of text tall.
static func victory_icon_px() -> int:
	return maxi(32, int(UIKit.font_size * 1.2 / 16.0) * 16)

## A heading, then one row per line. A line in `icons` gets its SPD sprite (gold coin, potion, scroll, ring, weapon,
## material); a found item is also drawn in SPD's highlight yellow so drops stand out from gold and XP (DECISIONS #217).
## Lines without a sprite (HP, XP, Level) keep an empty slot of the same width so the text lines up.
func _result_section(parent: Node, heading: String, lines: PackedStringArray, color: Color, icons := {}) -> void:
	var px := victory_icon_px()
	parent.add_child(_victory_text(heading, 1.0, color, px))
	if lines.is_empty():
		parent.add_child(_victory_text("Nothing", 0.9, Color("9a8f7c"), px))
		return
	for s in lines:
		var ic: Dictionary = icons.get(s, {})
		var row := HBoxContainer.new(); row.name = "VictoryRow"
		row.add_theme_constant_override("separation", int(UIKit.font_size * 0.3))
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		var slot: Control
		if String(ic.get("id", "")) != "" and (DB.items.has(ic.id) or DB.materials.has(ic.id) or DB.icons.has(ic.id)):
			var badge := ""
			if DB.items.has(ic.id): badge = String(DB.item(ic.id).get("badge", "")) if bool(ic.get("known", true)) else "NONE"
			slot = UIKit.icon(String(ic.id), px, badge)
			slot.name = "VictoryIcon"
			slot.set_meta("item_id", String(ic.id))
		else:
			slot = Control.new(); slot.custom_minimum_size = Vector2(px, px)
		slot.size_flags_vertical = SIZE_SHRINK_CENTER
		slot.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(slot)
		var drop := bool(ic.get("drop", false)) and color == GameState.LOG_COLORS.positive
		var l := _victory_text(s, 0.9, GameState.LOG_COLORS.highlight if drop else color, px)
		l.name = "VictoryText"
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(l)
		parent.add_child(row)

## One line of the Victory list: never wraps (a long gear name ends in "..." instead), so each row is one line
## high whatever the column width, and the list height can be measured before layout.
static func _victory_text(text: String, scale: float, color: Color, px: int) -> Label:
	var l := UIKit.label(text, scale, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(1, px)
	return l

func result() -> Dictionary:
	var r := {"won": combat.won, "hp": combat.hero.hp, "loot": combat.loot, "fallen_loot": combat.fallen_loot, "gold_debt": combat.gold_debt, "xp": combat.xp,
		"boss_killed": combat.boss_killed, "potions_used": potions_used, "kills": combat.kills, "traps_found": combat.traps_found,
		"trap_ids": combat.trap_ids_seen, "applied": _applied, "pause_after": _pause_after}
	r.merge(combat.milestone_result())
	return r

func _finish() -> void:
	GameState.run.erase("active_fight")
	on_done.call(result())

## Same as Continue, then the delve drops x3 speed and Auto Battle and holds the bar.
func _finish_paused() -> void:
	_pause_after = true
	_finish()
