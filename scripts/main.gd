## Vertical slice: Camp -> Delve Bar -> encounters / Door Choice -> 8x8 combat -> loot / extract.
## Responsive: portrait (Fold cover) = grid top, controls below; wide/square (Fold inner) = grid left, panels right.
extends Control

const GridView := preload("res://scripts/grid_view.gd")
const HERO_BASE := {"ht":20, "dmg":5, "dr":1, "barrier_max":6}  # SPD Warrior HT 20; Worn Shortsword 1-10 -> 5; Cloth Armor 0-2 -> 1

enum S { CAMP, DELVE, CHOICE, COMBAT, RESULT }
var state := S.CAMP
var stash := {"gold":0, "dew":0, "iron_ore":0, "iron_key":1}
var pack := {}
var hero_hp := 20
var floor_n := 1
var progress := 0.0
var torch := 100.0
var satiety := 100.0
var next_enc := 0
var encounters := [22, 45, 68, 90]
var room_counter := 0
var combat: Combat
var shove_mode := false
var gather_step := 0
var starve_step := 0

var margin: MarginContainer
var split: BoxContainer
var grid: Control
var side: VBoxContainer
var title: Label
var info: Label
var bar: ProgressBar
var buttons: VBoxContainer
var log_box: RichTextLabel
var log_scroll: ScrollContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bg := ColorRect.new(); bg.color = Color("1b1712"); bg.set_anchors_preset(PRESET_FULL_RECT); add_child(bg)
	margin = MarginContainer.new(); margin.set_anchors_preset(PRESET_FULL_RECT); add_child(margin)
	split = BoxContainer.new(); margin.add_child(split)
	split.add_theme_constant_override("separation", 12)
	grid = GridView.new(); grid.size_flags_horizontal = SIZE_EXPAND_FILL; grid.size_flags_vertical = SIZE_EXPAND_FILL
	grid.tapped.connect(_on_cell)
	split.add_child(grid)
	side = VBoxContainer.new(); side.size_flags_horizontal = SIZE_EXPAND_FILL; side.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(side)
	title = Label.new(); side.add_child(title)
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; side.add_child(info)
	bar = ProgressBar.new(); bar.custom_minimum_size.y = 40; side.add_child(bar)
	buttons = VBoxContainer.new(); side.add_child(buttons)
	# Scrollable log: ScrollContainer gives touch-drag scrolling; label grows with content.
	log_scroll = ScrollContainer.new(); log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size.y = 120; side.add_child(log_scroll)
	var log_bg := StyleBoxFlat.new(); log_bg.bg_color = Color("2a241c"); log_bg.set_content_margin_all(8)
	log_scroll.add_theme_stylebox_override("panel", log_bg)
	log_box = RichTextLabel.new(); log_box.fit_content = true; log_box.scroll_active = false
	log_box.size_flags_horizontal = SIZE_EXPAND_FILL; log_scroll.add_child(log_box)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_show_camp()

func _relayout() -> void:
	var vs := get_viewport_rect().size
	var portrait := vs.x / vs.y < 0.85
	split.vertical = portrait
	# Grid gets a square-ish share; controls get the rest.
	# Portrait (cover): grid is a square as wide as the screen; panel + log fill everything below.
	# Wide/square (inner): grid square on the left at full height; panels on the right.
	if portrait:
		var w := vs.x - float(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"))
		grid.size_flags_vertical = SIZE_SHRINK_BEGIN; grid.size_flags_horizontal = SIZE_FILL
		grid.custom_minimum_size = Vector2(w, w) if grid.visible else Vector2.ZERO
	else:
		var h := vs.y - 16.0
		grid.size_flags_horizontal = SIZE_SHRINK_BEGIN; grid.size_flags_vertical = SIZE_FILL
		grid.custom_minimum_size = Vector2(minf(h, vs.x * 0.6), 0) if grid.visible else Vector2.ZERO
	side.size_flags_vertical = SIZE_EXPAND_FILL; side.size_flags_horizontal = SIZE_EXPAND_FILL
	# Safe area (cutouts / bars), in viewport coordinates
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var l := 8.0; var t := 8.0; var r := 8.0; var b := 8.0
	if OS.has_feature("mobile") and win.x > 0 and safe.size.x > 0:
		var k := vs.x / float(win.x)
		l += safe.position.x * k; t += safe.position.y * k
		r += (win.x - safe.end.x) * k; b += (win.y - safe.end.y) * k
	for p in [["left",l],["top",t],["right",r],["bottom",b]]:
		margin.add_theme_constant_override("margin_" + p[0], int(clampf(p[1], 8.0, minf(vs.x, vs.y) * 0.2)))
	var fs := int(clampf(minf(vs.x, vs.y) / 22.0, 16, 44))
	var th := Theme.new(); th.default_font_size = fs
	theme = th
	title.add_theme_font_size_override("font_size", int(fs * 1.3))
	for c in buttons.get_children(): c.custom_minimum_size.y = fs * 2.6

func _btn(text: String, cb: Callable, enabled := true) -> void:
	var b := Button.new(); b.text = text; b.disabled = not enabled
	b.custom_minimum_size.y = theme.default_font_size * 2.6 if theme else 64
	b.pressed.connect(cb); buttons.add_child(b)

func _clear_buttons() -> void:
	for c in buttons.get_children(): c.queue_free()

func _log(s: String) -> void:
	log_box.append_text(s + "\n")
	_scroll_log()

func _scroll_log() -> void:
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

# ---------- CAMP ----------
func _show_camp() -> void:
	state = S.CAMP; grid.visible = false; bar.visible = false
	title.text = "Surface Camp"
	info.text = "Stash: %d gold, %d dew, %d iron ore, %d iron keys\nHero: Warrior (Lv1, 10 Str) HP %d  DR %d  Barrier %d  Dmg %d\n[Crafting, Loadout, Enchanter's Desk, Offline Patrols: coming soon]" % [
		stash.gold, stash.dew, stash.iron_ore, stash.iron_key, HERO_BASE.ht, HERO_BASE.dr, HERO_BASE.barrier_max, HERO_BASE.dmg]
	_clear_buttons()
	_btn("Delve the Sewers (Warrior)", _start_run)
	_relayout()

func _start_run() -> void:
	pack = {"gold":0, "dew":0, "iron_ore":0}
	hero_hp = HERO_BASE.ht; floor_n = 1; torch = 100; satiety = 100
	_start_floor()

func _start_floor() -> void:
	progress = 0; next_enc = 0; gather_step = 0; starve_step = 0
	_log("[b]Floor %d[/b]" % floor_n)
	_show_delve()

# ---------- DELVE ----------
func _show_delve() -> void:
	state = S.DELVE; grid.visible = false; bar.visible = true
	title.text = "Sewers - Floor %d" % floor_n
	_clear_buttons()
	_btn("Retreat (lose pack)", _die.bind("You fled. The pack is lost."))
	_relayout()

func _process(delta: float) -> void:
	if state == S.DELVE:
		progress += delta * 6.0
		torch = maxf(0, torch - delta * 0.8); satiety = maxf(0, satiety - delta * 0.5)
		# Passive gathering: +1 gold every 4%, +1 dew every 10% (deterministic)
		var step := int(progress / 4.0)
		if step > gather_step:
			gather_step = step; pack.gold += 1
			if step % 3 == 0: pack.dew += 1
		# Stub penalty (GDD open question): starving or dark costs 1 HP per 10%
		if (torch <= 0 or satiety <= 0) and int(progress / 10.0) > starve_step:
			starve_step = int(progress / 10.0); hero_hp = maxi(1, hero_hp - 1)
		if next_enc < encounters.size() and progress >= encounters[next_enc]:
			next_enc += 1
			if next_enc == 2: _door_choice()
			else: _start_combat(room_counter)
		elif progress >= 100:
			_floor_done()
	if state in [S.DELVE, S.CHOICE]:
		bar.value = progress
		info.text = "HP %d/%d   Torch %d%%   Satiety %d%%\nPack: %d gold, %d dew, %d ore" % [hero_hp, HERO_BASE.ht, torch, satiety, pack.gold, pack.dew, pack.iron_ore]

func _door_choice() -> void:
	state = S.CHOICE
	title.text = "Two doors..."
	_clear_buttons()
	_btn("Door A: Smells of ozone (fight - wand reward)", _start_combat.bind(1, true))
	_btn("Door B: Locked (1 Iron Key - crystal chest)", _chest, stash.iron_key > 0)
	_btn("Ignore both", _show_delve)
	_relayout()

func _chest() -> void:
	stash.iron_key -= 1; pack.iron_ore += 3; pack.gold += 15
	_log("Crystal chest: +15 gold, +3 iron ore.")
	_show_delve()

func _floor_done() -> void:
	state = S.RESULT
	title.text = "Floor %d cleared" % floor_n
	info.text = "Campfire (slice: every floor). Pack: %d gold, %d dew, %d ore" % [pack.gold, pack.dew, pack.iron_ore]
	_clear_buttons()
	_btn("Extract to Camp (keep 100%)", _extract)
	_btn("Descend to Floor %d" % (floor_n + 1), func(): floor_n += 1; _start_floor())

func _extract() -> void:
	for k in pack: stash[k] = stash.get(k, 0) + pack[k]
	_log("Extracted with the pack!")
	_show_camp()

func _die(msg: String) -> void:
	_log(msg + " Unbanked loot lost.")
	_show_camp()

# ---------- COMBAT ----------
var wand_room := false
func _start_combat(idx: int, wand := false) -> void:
	wand_room = wand
	room_counter += 1
	combat = Combat.new()
	var hs := HERO_BASE.duplicate(); hs.hp = hero_hp
	combat.setup(idx, hs)
	grid.combat = combat; grid.visible = true; bar.visible = false; _relayout()
	state = S.COMBAT; shove_mode = false
	title.text = "Combat"
	_combat_ui()

func _combat_ui() -> void:
	_clear_buttons()
	_btn("Wait (1.0 tick)", func(): combat.hero_wait(); _after_action())
	_btn("Shove: %s" % ("ON" if shove_mode else "off"), func(): shove_mode = not shove_mode; _combat_ui())
	_relayout(); _refresh_combat()

func _on_cell(c: Vector2i) -> void:
	if state != S.COMBAT: return
	if combat.hero_tap(c, shove_mode):
		if shove_mode: shove_mode = false; _combat_ui()
		_after_action()

func _refresh_combat() -> void:
	var h := combat.hero
	info.text = "Warrior HP %d/%d  Barrier %d  DR %d  t=%.1f\nTap adjacent: move/attack. Attack from door/grass = Surprise (+50%%, no DR, knockback)." % [h.hp, h.ht, h.barrier, h.dr, combat.time]
	log_box.clear()
	for l in combat.log_lines: log_box.append_text(l + "\n")
	_scroll_log()

func _after_action() -> void:
	_refresh_combat()
	if not combat.over: return
	hero_hp = combat.hero.hp
	if combat.won:
		pack.gold += combat.loot
		if wand_room: _log("Found an unidentified wand (stub).")
		state = S.RESULT
		_clear_buttons()
		_btn("Continue delving (+%d gold)" % combat.loot, func(): grid.visible = false; _show_delve())
		_relayout()
	else:
		_clear_buttons()
		state = S.RESULT
		_btn("Wake at Camp (pack lost)", _die.bind("The Warrior died."))
		_relayout()
