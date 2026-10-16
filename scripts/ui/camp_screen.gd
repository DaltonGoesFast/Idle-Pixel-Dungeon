## CampScreen: the persistent Surface Camp hub (DECISIONS #82, #124).
## Layout: a one-line resource strip, then a drawn camp scene (CampScene) where you tap the NPCs to open the facilities.
## The scene takes the free space; a dock under it (beside it when wide) holds hero portraits, the destination, then Delve.
## On the wide dock the patrol list scrolls in whatever room is left under Delve, so the start button stays with the biome it uses.
## Facilities, Stash, Heroes, Journal and Settings open as SPD windows over the hub. Item lists are
## SPD-style item-slot grids; tapping a slot opens an info window with its actions.
## Content is rebuilt from GameState on every change.
extends Control

const CampScene := preload("res://scripts/ui/camp_scene.gd")
var main: Control
var root_box: BoxContainer
var summary: HBoxContainer
var scene: Control
var side: VBoxContainer
var pages := {}
var loadout := {"ration": 2, "torch": 2, "potion_healing": 1, "scroll_passage": 0, "elixir_starter": 0}
var chosen_hero := "warrior"
var chosen_biome := "sewers"
var portrait := true
var open_name := ""          # page shown in the window ("" = hub)
var win_layer: Control       # page window
var info_layer: Control      # item info popup (on top of the window)
var _update_btn: Button      # Camp header Update control (Android / Windows)
const PAGE_ORDER := ["Delve", "Heroes", "Stash", "Forge", "Alchemy", "Enchanter", "Guild", "Journal", "Settings"]
const TAB_ORDER := PAGE_ORDER   # kept for older tests/tools
const PAGE_ICONS := {"Delve": "enter", "Heroes": "rankings", "Stash": "backpack_lrg", "Forge": "challenge", "Alchemy": "alchemy",
	"Enchanter": "scroll", "Guild": "badges", "Journal": "journal", "Settings": "prefs"}
const FAC_PAGE := {"Forge": "blacksmith", "Alchemy": "alchemy", "Enchanter": "enchanter", "Guild": "guild"}
const NPC := {"blacksmith": ["blacksmith", 13, 16], "enchanter": ["wandmaker", 12, 14], "guild": ["shopkeeper", 14, 14]}
const HERO_FRAME := Vector2i(12, 15)

func _ready() -> void:
	_build_shell()
	GameState.changed.connect(rebuild)
	Updater.changed.connect(_on_updater)
	if Updater.supports_platform() and Updater.state == Updater.State.IDLE:
		Updater.check_now()
	rebuild()

func _on_updater() -> void:
	if not is_inside_tree() or root_box == null:
		return
	# Full rebuild when the header Update button appears/disappears; otherwise just retitle it.
	var want := Updater.supports_platform() and Updater.has_update()
	if want == (_update_btn != null and is_instance_valid(_update_btn)):
		if _update_btn != null and is_instance_valid(_update_btn):
			_update_btn.text = _camp_update_label()
			_update_btn.disabled = Updater.state == Updater.State.DOWNLOADING or Updater.state == Updater.State.CHECKING
		return
	rebuild()

func _camp_update_label() -> String:
	if Updater.state == Updater.State.DOWNLOADING:
		return "Updating %d%%" % int(Updater.progress * 100.0)
	if Updater.remote_version != "":
		return "Update v%s" % Updater.remote_version
	return "Update"

func apply_layout(p: bool, _size: Vector2) -> void:
	if p == portrait and root_box != null: rebuild(); return
	portrait = p
	_build_shell(); rebuild()

func _build_shell() -> void:
	for c in get_children(): c.queue_free()
	var outer := UIKit.vbox(self); outer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# top bar: title, version, Update (when available), Journal + Settings
	var top := UIKit.hbox(outer)
	var title := UIKit.header("Surface Camp"); title.size_flags_horizontal = SIZE_EXPAND_FILL; top.add_child(title)
	var ver := UIKit.label(UIKit.version(), 0.75, Color("9a9488")); ver.size_flags_vertical = SIZE_SHRINK_CENTER
	ver.autowrap_mode = TextServer.AUTOWRAP_OFF; top.add_child(ver)
	_update_btn = null
	if Updater.supports_platform() and Updater.has_update():
		_update_btn = UIKit.button(_camp_update_label(), func(): Updater.start_update())
		_update_btn.disabled = Updater.state == Updater.State.DOWNLOADING or Updater.state == Updater.State.CHECKING
		_update_btn.size_flags_horizontal = SIZE_SHRINK_END; _update_btn.size_flags_vertical = SIZE_SHRINK_CENTER
		_update_btn.custom_minimum_size.x = UIKit.font_size * 6
		top.add_child(_update_btn)
	for p in ["Journal", "Settings"]:
		var b := UIKit.as_toolbar(UIKit.button("", func(): open_page(p)), PAGE_ICONS[p])
		b.tooltip_text = p; b.custom_minimum_size = Vector2.ONE * UIKit.btn_height()
		b.size_flags_horizontal = SIZE_SHRINK_END; b.size_flags_vertical = SIZE_SHRINK_CENTER; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top.add_child(b)
	# resource strip in an SPD toast frame: one row that scrolls sideways, so it never pushes the scene down
	var rp := PanelContainer.new(); rp.add_theme_stylebox_override("panel", UIKit.chrome("toast", Color.WHITE, UIKit.font_size * 0.35)); outer.add_child(rp)
	var rs := ScrollContainer.new(); rs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; rp.add_child(rs)
	summary = HBoxContainer.new(); rs.add_child(summary)
	summary.add_theme_constant_override("separation", int(UIKit.font_size * 0.9))
	# body: scene + controls (stacked on the cover, side-by-side on the inner screen)
	root_box = VBoxContainer.new() if portrait else HBoxContainer.new()
	root_box.size_flags_vertical = SIZE_EXPAND_FILL; outer.add_child(root_box)
	root_box.add_theme_constant_override("separation", int(UIKit.font_size * 0.4))
	var frame := PanelContainer.new(); frame.add_theme_stylebox_override("panel", UIKit.chrome("window", Color.WHITE, UIKit.font_size * 0.25))
	frame.size_flags_vertical = SIZE_EXPAND_FILL; frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0 if portrait else 1.35
	root_box.add_child(frame)
	scene = CampScene.new(); scene.custom_minimum_size = Vector2(0, UIKit.font_size * 10)
	scene.picked.connect(open_page); frame.add_child(scene)
	side = UIKit.vbox(); side.size_flags_horizontal = SIZE_EXPAND_FILL
	side.size_flags_vertical = SIZE_SHRINK_END if portrait else SIZE_EXPAND_FILL
	root_box.add_child(side)
	win_layer = null; info_layer = null

func rebuild() -> void:
	if not is_inside_tree() or summary == null: return
	UIKit.clear(summary)
	for k in ["gold", "iron_ore", "dark_gold", "seeds", "arcane_resin", "dew", "scroll_upgrade", "torch", "ration", "potion_healing"]:
		if GameState.mat(k) > 0 or k in ["gold", "iron_ore", "seeds"]:
			var chip := UIKit.res_chip(k, str(GameState.mat(k)), 0.9); chip.tooltip_text = DB.mat_name(k); summary.add_child(chip)
	if not GameState.heroes[chosen_hero].unlocked: chosen_hero = "warrior"
	if not (chosen_biome in start_biomes(chosen_hero)): chosen_biome = "sewers"
	scene.hero = chosen_hero
	_build_side()
	if open_name != "": _fill_window()

# ------------------------------------------------------------ hub controls
func _build_side() -> void:
	UIKit.clear(side)
	# hero selector: SPD portrait slots with level badges; the selected one is framed in red, a second tap opens Heroes
	var hr := HFlowContainer.new(); hr.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.4)); side.add_child(hr)
	for c in GameState.heroes:
		hr.add_child(_hero_slot(c))
	var h: Dictionary = GameState.heroes[chosen_hero]
	side.add_child(UIKit.label(hero_line(chosen_hero), 0.85, Color("ffd27a")))
	if not h.patrol.is_empty() and portrait:
		side.add_child(UIKit.label("On patrol - recall at the Guild.", 0.8, Color("c9a96e")))
	# biome picker (start at any biome after the one this hero has cleared)
	side.add_child(UIKit.label("Destination", 0.8, Color("bdb3a0")))
	var bf := HFlowContainer.new(); side.add_child(bf)
	var ok := start_biomes(chosen_hero)
	for b in DB.biomes:
		var d: Dictionary = DB.biomes[b]
		var bb := UIKit.button(d.name, func(): chosen_biome = b; rebuild(), b in ok,
			"Floors %d-%d" % [d.floors[0], d.floors[1]] if b in ok else "Clear the previous biome with this hero first")
		if b != chosen_biome: UIKit.secondary(bb)
		bb.size_flags_horizontal = 0; bb.custom_minimum_size.x = UIKit.font_size * 4.5
		bf.add_child(bb)
		if not (b in ok): break   # show only the next locked one
	# Delve sits with the destination it uses. A disabled reason (hero out on patrol) stays on screen
	# instead of falling off the bottom of a short dock.
	var go := UIKit.action("Delve: %s" % DB.biomes[chosen_biome].name, func(): open_page("Delve"), GameState.can_start_run(chosen_hero))
	go.name = "DelveGo"
	var delve_btn := go.get_child(0) as Button
	if delve_btn: delve_btn.custom_minimum_size.y = UIKit.btn_height() * 1.35
	side.add_child(go)
	if not portrait:
		# wide dock: patrols fill the rest and scroll. The cover stays lean; Guild still has the full page.
		side.add_child(UIKit.label("Patrols (max %dh)" % int(GameState.patrol_max_hours()), 0.8, Color("bdb3a0")))
		var sc := ScrollContainer.new(); sc.name = "PatrolScroll"; sc.size_flags_vertical = SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.follow_focus = false
		side.add_child(sc)
		var pv := UIKit.vbox(sc); pv.size_flags_horizontal = SIZE_EXPAND_FILL
		pv.size_flags_vertical = SIZE_SHRINK_BEGIN
		_patrol_list(pv)

## The selected hero's stats in one line under the portraits.
func hero_line(c: String) -> String:
	var s := GameState.hero_stats(c); var h: Dictionary = GameState.heroes[c]
	return "%s  Lv%d   HP %d  DR %d  Dmg %d  Str %d" % [s.name, h.level, s.ht, s.dr, s.dmg, h.str]

func _hero_slot(c: String) -> Control:
	var h: Dictionary = GameState.heroes[c]
	var b := Button.new(); b.focus_mode = FOCUS_NONE
	var sz := UIKit.font_size * 3.4; var ht := UIKit.font_size * 4.0
	b.custom_minimum_size = Vector2(sz, ht)
	var sel := c == chosen_hero
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, UIKit.chrome("red_button" if sel else "grey_button", Color(1, 1, 1) if st != "disabled" else Color(0.5, 0.5, 0.5), UIKit.font_size * 0.3))
	b.tooltip_text = DB.heroes[c].name + ("" if h.unlocked else " (locked): " + DB.heroes[c].get("unlock", ""))
	b.disabled = not h.unlocked
	b.pressed.connect(func():
		Sfx.play("click")
		if c == chosen_hero: open_page("Heroes")
		else: chosen_hero = c; rebuild())
	var tr := UIKit.pixel(_hero_tex(c), maxi(1, int(sz * 0.62 / 15.0)))
	tr.set_anchors_and_offsets_preset(PRESET_FULL_RECT); tr.offset_bottom = -int(UIKit.font_size * 1.55)
	if not h.unlocked: tr.modulate = Color(0, 0, 0, 0.75)
	b.add_child(tr)
	var lv := UIKit.label(("Lv%d\nStr %d" % [h.level, h.str]) if h.unlocked else "?", 0.75, Color("ffffaa"))
	lv.add_theme_constant_override("line_spacing", -int(UIKit.font_size * 0.1))
	lv.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE); lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.offset_top = -UIKit.font_size * 1.75; lv.mouse_filter = MOUSE_FILTER_IGNORE; b.add_child(lv)
	return b

func _hero_tex(c: String) -> Texture2D:
	var at := AtlasTexture.new(); at.atlas = load("res://assets/sprites/%s.png" % c)
	at.region = Rect2(Vector2(0, GameState.armor_tier(c) * HERO_FRAME.y), HERO_FRAME); return at

## Biomes a hero may start in: Sewers, plus the biome after each one they've cleared.
func start_biomes(c: String) -> Array:
	var out := ["sewers"]
	for b in DB.biomes:
		if b in GameState.heroes[c].get("cleared", []) and DB.biomes[b].has("next"): out.append(DB.biomes[b].next)
	return out

# ------------------------------------------------------------ windows
## Open a page (facility, Stash, Heroes, Journal, Settings or Delve) as an SPD window over the hub.
func open_page(p: String) -> void:
	if not (p in PAGE_ORDER): return
	if p != open_name: top_next = true
	open_name = p
	if main:
		for t in main.toast_box.get_children(): t.queue_free()   # nothing floats over a window
		main.tip("camp_" + p.to_lower())
	_fill_window()

func close_page() -> void:
	open_name = ""; _close_info()
	if win_layer: win_layer.queue_free(); win_layer = null

## A dimmed overlay with a centred SPD window: title row (icon, name, close), a scrolling body, and a footer
## under the scroller for the page's main action (hidden until a page uses it, see _foot).
func _make_window(title: String, icon_name: String, close_cb: Callable, w_frac := 0.96, h_frac := 0.92) -> Array:
	var layer := Control.new(); layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); layer.add_child(dim)
	# The click that opened the window can land on this dimmer (Forge and Alchemy sit left of the
	# centred panel on a wide screen) and would close it in the same gesture. Ignore input until
	# that button is up; the next press outside the panel dismisses.
	var block := [true]
	var unblock: Callable
	unblock = func():
		if not is_instance_valid(dim): return
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			unblock.call_deferred()
			return
		block[0] = false
	unblock.call_deferred()
	dim.gui_input.connect(func(e: InputEvent):
		var click: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or (e is InputEventScreenTouch and e.pressed)
		if not click: return
		dim.accept_event()
		if block[0]: return
		close_cb.call())
	var pc := PanelContainer.new(); layer.add_child(pc)
	var vs := get_viewport_rect().size
	var w := minf(vs.x * w_frac, UIKit.font_size * 36.0); var h := vs.y * h_frac
	pc.position = ((vs - Vector2(w, h)) / 2.0).floor(); pc.size = Vector2(w, h); pc.custom_minimum_size = Vector2(w, 0)
	var v := UIKit.vbox(pc)
	var tr := UIKit.hbox(v)
	if icon_name != "":
		var ic := UIKit.pixel(UIKit.spd_icon(icon_name), 1); ic.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(ic)
	var tl := UIKit.header(title); tl.size_flags_horizontal = SIZE_EXPAND_FILL; tr.add_child(tl)
	var x := UIKit.button("X", close_cb); UIKit.secondary(x); x.custom_minimum_size = Vector2.ONE * UIKit.btn_height()
	x.size_flags_horizontal = SIZE_SHRINK_END; tr.add_child(x)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = SIZE_EXPAND_FILL; v.add_child(sc)
	var body := UIKit.vbox(sc); body.size_flags_horizontal = SIZE_EXPAND_FILL
	var foot := UIKit.vbox(v); foot.visible = false; layer.set_meta("foot", foot)
	# message strip at the window's foot: toasts land here instead of floating over the window
	var msg := UIKit.label("", 0.8, Color("ffff88")); msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.visible = false; v.add_child(msg); layer.set_meta("msg", msg)
	if Time.get_ticks_msec() - int(last_msg[1]) < 3500:   # windows rebuild on every change; keep the latest message
		(func(): if is_instance_valid(msg): _show_msg(msg, last_msg[0], 3.5 - (Time.get_ticks_msec() - int(last_msg[1])) / 1000.0)).call_deferred()
	return [layer, body, pc, sc]

## Called by main._toast: show the message in the topmost open window. Returns false when the hub is bare.
func window_toast(text: String) -> bool:
	var layer: Control = info_layer if info_layer else win_layer
	if layer == null or not is_instance_valid(layer): return false
	last_msg = [text, Time.get_ticks_msec()]
	_show_msg(layer.get_meta("msg"), text, 3.5)
	return true

var last_msg := ["", -100000]
func _show_msg(msg: Label, text: String, hold: float) -> void:
	msg.text = text; msg.visible = true; msg.modulate.a = 1.0
	var tw := msg.create_tween(); tw.tween_interval(maxf(0.1, hold)); tw.tween_property(msg, "modulate:a", 0.0, 0.6)

func _fill_window() -> void:
	var keep_scroll := 0
	if win_layer:
		var old_sc: ScrollContainer = win_layer.get_meta("sc"); keep_scroll = 0 if top_next else old_sc.scroll_vertical
		win_layer.queue_free()
	top_next = false
	var w := _make_window(open_name if open_name != "Delve" else "Expedition", PAGE_ICONS[open_name], close_page)
	win_layer = w[0]; win_layer.set_meta("sc", w[3]); pages[open_name] = w[1]
	match open_name:
		"Delve": _page_delve()
		"Heroes": _page_heroes()
		"Stash": _page_stash()
		"Guild": _page_guild()
		"Journal": _page_journal()
		"Settings": SettingsPanel.build(_p("Settings"))
		_: _page_facility(open_name, FAC_PAGE[open_name])
	(func(): if is_instance_valid(w[3]): w[3].scroll_vertical = keep_scroll).call_deferred()
	if info_layer: move_child(info_layer, -1)

func _p(name: String) -> VBoxContainer:
	var v: VBoxContainer = pages[name]
	UIKit.clear(v)
	return v

## The open window's footer: stays under the scrolling body, so the main action is always in reach.
func _foot() -> VBoxContainer:
	var f: VBoxContainer = win_layer.get_meta("foot")
	f.visible = true
	return f

## Section buttons at the top of a window (Stash, Forge, Guild). Returns the selected key.
## opts: [[key, label], ...]; the choice is kept per page while the app runs.
var section := {}
var top_next := false   # the next window rebuild starts scrolled to the top (a section switch)
func _switcher(v: Control, page: String, opts: Array) -> String:
	var cur: String = section.get(page, opts[0][0])
	if not opts.any(func(o): return o[0] == cur): cur = opts[0][0]
	var sw := HFlowContainer.new(); v.add_child(sw)
	sw.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.3))
	for o in opts:
		var key: String = o[0]
		var b := UIKit.button(o[1], func(): section[page] = key; top_next = true; _fill_window())
		if key != cur: UIKit.secondary(b)
		b.size_flags_horizontal = SIZE_EXPAND_FILL; b.autowrap_mode = TextServer.AUTOWRAP_OFF
		sw.add_child(b)
	return cur

## Small info window for one item/recipe: icon + name, text lines, then the given action buttons.
func info(id: String, title: String, lines: Array, actions: Array = [], badge := "") -> void:
	_close_info()
	var w := _make_window(title, "", _close_info, 0.86, 0.5)
	info_layer = w[0]
	var body: VBoxContainer = w[1]
	var top := UIKit.hbox(body); var ic := UIKit.icon(id, UIKit.font_size * 3, badge); top.add_child(ic)
	var tv := UIKit.vbox(top); tv.size_flags_horizontal = SIZE_EXPAND_FILL
	for l in lines:
		if typeof(l) == TYPE_OBJECT:
			# a line may be a node the last popup freed (recipe slots used to keep the cost row)
			if not is_instance_valid(l) or (l as Node).get_parent() != null: continue
			if l is Control and (l as Control).has_meta("wide"): body.add_child(l)   # quantity pickers span the window
			elif l is Control: tv.add_child(l)
			else: tv.add_child(UIKit.label(str(l), 0.9))
		else:
			tv.add_child(UIKit.label(String(l), 0.9))
	for a in actions:   # [text, callable, reason]
		body.add_child(UIKit.action(a[0], func(): a[1].call(); _close_info(), a[2]))
	# fit the popup to its content
	(func():
		if not is_instance_valid(w[2]): return
		var pc: PanelContainer = w[2]; var vs := get_viewport_rect().size
		var hh := minf(vs.y * 0.8, body.get_combined_minimum_size().y + UIKit.font_size * 4.0)
		pc.size.y = hh; pc.position.y = floorf((vs.y - hh) / 2.0)).call_deferred()

func _close_info() -> void:
	if info_layer: info_layer.queue_free(); info_layer = null

## Quantity picker (DECISIONS #97): [-] slider [+] count, live total cost, and the action button "<verb> xN".
## max_n = affordable / cap; the button is disabled with `why0` when nothing can be done.
func qty_picker(max_n: int, cost_fn: Callable, verb: String, act: Callable, why0 := "") -> VBoxContainer:
	var box := UIKit.vbox()
	var row := UIKit.hbox(box)
	var n := [mini(1, max_n)]
	var minus := UIKit.button("-", func(): pass); minus.custom_minimum_size.x = UIKit.btn_height(); minus.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var sl := HSlider.new(); sl.min_value = mini(1, max_n); sl.max_value = maxi(1, max_n); sl.step = 1; sl.value = n[0]
	sl.size_flags_horizontal = SIZE_EXPAND_FILL; sl.size_flags_vertical = SIZE_SHRINK_CENTER; sl.editable = max_n > 1
	sl.custom_minimum_size.y = UIKit.font_size * 1.2
	var plus := UIKit.button("+", func(): pass); plus.custom_minimum_size.x = UIKit.btn_height(); plus.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var cnt := UIKit.label("x%d" % n[0], 1.0, Color("ffd27a")); cnt.autowrap_mode = TextServer.AUTOWRAP_OFF; cnt.custom_minimum_size.x = UIKit.font_size * 2.5
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for c in [minus, sl, plus, cnt]: row.add_child(c)
	var total := UIKit.hbox(box)
	var tl := UIKit.label("Total:", 0.85, Color("bdb3a0")); tl.autowrap_mode = TextServer.AUTOWRAP_OFF; tl.size_flags_vertical = SIZE_SHRINK_CENTER; total.add_child(tl)
	var cost_host := HBoxContainer.new(); total.add_child(cost_host)
	var why := why0 if max_n < 1 else ""
	var act_host := UIKit.action("%s x%d" % [verb, maxi(1, n[0])], func(): if n[0] >= 1: act.call(n[0]); _close_info(), why if why != "" else ("" if max_n >= 1 else "can't afford"))
	box.add_child(act_host)
	var act_btn: Button = act_host.get_child(0) as Button
	var upd := func(v: int):
		n[0] = clampi(v, mini(1, max_n), max_n)
		sl.set_value_no_signal(n[0]); cnt.text = "x%d" % n[0]
		for c in cost_host.get_children(): c.queue_free()
		cost_host.add_child(cost_row(cost_fn.call(maxi(1, n[0]))))
		act_btn.text = "%s x%d" % [verb, maxi(1, n[0])]
		minus.disabled = n[0] <= 1 or max_n < 1; plus.disabled = n[0] >= max_n or max_n < 1
	sl.value_changed.connect(func(v): upd.call(int(v)))
	minus.pressed.connect(func(): upd.call(n[0] - 1))
	plus.pressed.connect(func(): upd.call(n[0] + 1))
	upd.call(n[0])
	box.set_meta("wide", true)
	box.set_meta("set_n", upd); box.set_meta("n", n); box.set_meta("button", act_btn); box.set_meta("cost_host", cost_host)
	return box

## Live materials strip (Forge / Guild headers): icon + amount for each material the facility uses.
const FAC_MATS := {"blacksmith": ["iron_ore", "dark_gold", "gold", "arcane_resin", "scroll_upgrade"], "guild": ["gold", "dew", "seeds", "iron_ore"]}
func mats_header(id: String) -> HFlowContainer:
	var f := HFlowContainer.new(); f.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.8))
	f.name = "MatsHeader"
	for k in FAC_MATS.get(id, []):
		f.add_child(UIKit.res_chip(k, "%d" % GameState.mat(k), 0.9))
	return f

## Cost as resource chips; amounts you can't afford are red.
func cost_row(cost: Dictionary) -> HFlowContainer:
	var f := HFlowContainer.new(); f.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.6))
	for k in cost:
		var chip := UIKit.res_chip(k, "%d" % int(cost[k]), 0.85)
		if GameState.mat(k) < int(cost[k]): (chip.get_child(1) as Label).add_theme_color_override("font_color", Color("ff6a5a"))
		f.add_child(chip)
	return f

## cell: column width in font sizes (captioned recipe slots are wider, see item_slot).
func slot_grid(v: Control, cell := 3.2) -> GridContainer:
	var g := GridContainer.new()
	var w := minf(get_viewport_rect().size.x * 0.96, UIKit.font_size * 36.0) - UIKit.font_size * 2.0
	g.columns = maxi(3, int(w / (UIKit.font_size * cell)))
	g.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.2)); g.add_theme_constant_override("v_separation", int(UIKit.font_size * 0.2))
	v.add_child(g); return g

# ------------------------------------------------------------ Delve (loadout & start)
func _page_delve() -> void:
	var v := _p("Delve")
	if GameState.owed_sou > 0:
		v.add_child(UIKit.label("Owed: %d Scroll%s of Upgrade - beat any boss to recover." % [GameState.owed_sou, "" if GameState.owed_sou == 1 else "s"], 0.85, Color("ffff66")))
	var b: Dictionary = DB.biomes[chosen_biome]
	var hd := UIKit.hbox(v)
	var tr := UIKit.pixel(_hero_tex(chosen_hero), maxi(2, int(UIKit.font_size / 6.0))); tr.size_flags_vertical = SIZE_SHRINK_CENTER
	hd.add_child(tr)
	var hv := UIKit.vbox(hd); hv.size_flags_horizontal = SIZE_EXPAND_FILL
	hv.add_child(UIKit.label("%s  ->  %s" % [DB.heroes[chosen_hero].name, b.name], 1.0, Color("ffd27a")))
	hv.add_child(UIKit.label("Floors %d-%d, boss: %s. Recommended: Lv %d, Strength %d." % [b.floors[0], b.floors[1], DB.mobs.get(b.get("boss", ""), {}).get("name", "?"), int(b.get("rec_level", 1)), b.str_gate], 0.8, Color("bdb3a0")))
	hv.add_child(UIKit.label("Extract at a boss campfire or with a Scroll of Passage. Dying loses the pack.", 0.75, Color("9a9488")))
	var caps := supply_max()
	for k in SUPPLY_KEYS: loadout[k] = clampi(int(loadout.get(k, 0)), 0, int(caps[k]))
	var sh := UIKit.hbox(v)
	var shl := UIKit.header("Supplies"); shl.size_flags_horizontal = SIZE_EXPAND_FILL; sh.add_child(shl)
	var mall := UIKit.button("Max all", func(): max_all_supplies(); _fill_window(), not supplies_all_max())
	mall.name = "MaxAll"; mall.autowrap_mode = TextServer.AUTOWRAP_OFF; mall.custom_minimum_size.x = UIKit.font_size * 5; mall.size_flags_horizontal = 0; mall.size_flags_vertical = SIZE_SHRINK_CENTER; UIKit.secondary(mall); sh.add_child(mall)
	for k in SUPPLY_KEYS:
		var have := GameState.mat(k)
		var cap := int(caps[k])
		if k == "elixir_starter" and have == 0: continue
		var row := UIKit.hbox(v)
		var r := UIKit.icon_row(k, "%s  x%d" % [DB.mat_name(k), loadout[k]], 0.9)
		var mx := UIKit.label("max %d" % mini(have, cap), 0.75, Color("9a9488")); mx.autowrap_mode = TextServer.AUTOWRAP_OFF; mx.size_flags_vertical = SIZE_SHRINK_CENTER; r.add_child(mx)
		r.size_flags_horizontal = SIZE_EXPAND_FILL; r.tooltip_text = "In stash: %d" % have; row.add_child(r)
		var minus := UIKit.button("-", func(): loadout[k] -= 1; _fill_window(), loadout[k] > 0); minus.size_flags_horizontal = 0
		var plus := UIKit.button("+", func(): loadout[k] += 1; _fill_window(), loadout[k] < mini(have, cap)); plus.size_flags_horizontal = 0
		minus.custom_minimum_size.x = UIKit.btn_height(); plus.custom_minimum_size.x = UIKit.btn_height()
		UIKit.secondary(minus); UIKit.secondary(plus)
		for pm in [minus, plus]: pm.add_theme_font_size_override("font_size", UIKit.font_px(UIKit.font_size * 1.5))
		row.add_child(minus); row.add_child(plus)
	var gl := GameState.facility_level("guild")
	if gl < int(DB.facilities.guild.max):
		var gh := UIKit.label("Rations and torches: pack cap %d at Guild Lv%d. Upgrade Guild to raise (Lv%d: %d)." % [GameState.guild_pack_cap(), gl, gl + 1, GameState.guild_pack_cap(gl + 1)], 0.7, Color("9a9488"))
		gh.name = "GuildCapHint"; gh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(gh)
	var floors := int(b.floors[1]) - int(b.floors[0]) + 1
	if loadout.torch < mini(floors - 2, int(caps.torch)): v.add_child(UIKit.label("Tip: about one torch per floor (%d floors)." % floors, 0.75, Color("ffb060")))
	if GameState.mat("elixir_starter") > 0 and GameState.heroes[chosen_hero].level < 3:
		v.add_child(UIKit.button("Drink Starter Elixir (boost to Lv3)", func(): GameState.use_elixir(chosen_hero)))
	var go := UIKit.action("Descend into the %s" % b.name, _start, GameState.can_start_run(chosen_hero))
	go.custom_minimum_size.y = UIKit.btn_height() * 1.3; _foot().add_child(go)

const SUPPLY_KEYS := ["ration", "torch", "potion_healing", "scroll_passage", "elixir_starter"]
## Most of each supply the pack can take: the stash count, capped by GameState.supply_cap (belt size for potions,
## 1 Passage, the Guild-level cap for rations and torches).
func supply_max() -> Dictionary:
	var out := {}
	for k in SUPPLY_KEYS:
		var cap := GameState.supply_cap(k)
		out[k] = mini(GameState.mat(k), cap)
	return out

## Supplies header "Max all": every row to its max (disabled once they all are).
func max_all_supplies() -> void:
	var caps := supply_max()
	for k in SUPPLY_KEYS: loadout[k] = int(caps[k])

func supplies_all_max() -> bool:
	var caps := supply_max()
	for k in SUPPLY_KEYS:
		if int(loadout.get(k, 0)) < int(caps[k]): return false
	return true

func _start() -> void:
	if GameState.start_run(chosen_hero, loadout, chosen_biome):
		close_page(); main.show_delve()

## A locked class: what unlocks it and how close you are (the same card the Journal uses).
func _unlock_card(c: String) -> Control:
	var rule: Dictionary = DB.heroes[c].get("unlock_rule", {})
	if rule.is_empty(): return _progress_card(DB.heroes[c].name + " (locked)", DB.heroes[c].get("unlock", ""), 0, 1, "", false)
	return _progress_card(DB.heroes[c].name + " (locked)", DB.heroes[c].get("unlock", ""), GameState.stat_value(rule.stat), int(rule.goal), "Unlocks the class", false)

# ------------------------------------------------------------ item slots
## SPD inventory slot: dark translucent square, item sprite, count bottom-right, "+N" top-left.
## A caption adds a name strip under the sprite and widens the slot (recipe grids, CAPTION_CELL).
const CAPTION_CELL := 4.4
func item_slot(id: String, br: String, tl: String, cb: Callable, tint := Color.WHITE, frame := "", gear := {}, badge := "", caption := "") -> Button:
	var b := Button.new(); b.focus_mode = FOCUS_NONE
	var sz := UIKit.font_size * 3.0
	var cap_h := UIKit.font_size * 0.95 if caption != "" else 0.0
	b.custom_minimum_size = Vector2(UIKit.font_size * (CAPTION_CELL - 0.2) if caption != "" else sz, sz + cap_h)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.33, 0.34, 0.30, 0.6)
	if frame != "": bg.border_color = Color(frame); bg.set_border_width_all(maxi(2, int(UIKit.font_size * 0.12)))
	var hv := bg.duplicate(); hv.bg_color = Color(0.45, 0.46, 0.40, 0.75)
	b.add_theme_stylebox_override("normal", bg); b.add_theme_stylebox_override("hover", hv); b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if badge == "" and not gear.is_empty():
		badge = UIKit.gear_badge(gear)
		if badge == "": badge = "NONE"
	var ic := UIKit.icon(id, int(sz * 0.7), badge); ic.set_anchors_and_offsets_preset(PRESET_FULL_RECT); ic.mouse_filter = MOUSE_FILTER_IGNORE
	ic.offset_bottom = -cap_h
	# cracked gear keeps its true colours (a tint hid small ring/potion sprites on device) and gets a red
	# frame + "!" badge instead (DECISIONS #98)
	var cracked: bool = gear.get("cracked", false)
	if cracked:
		bg.border_color = Color("ff5040"); bg.set_border_width_all(maxi(2, int(UIKit.font_size * 0.12)))
		var bl := UIKit.label("!", 0.9, Color("ff5040")); bl.position = Vector2(UIKit.font_size * 0.2, 0); bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		bl.mouse_filter = MOUSE_FILTER_IGNORE; b.add_child(bl)
	elif tint.a < 1.0 or tint.r < 0.99 or tint.g < 0.99: ic.modulate *= Color(1, 1, 1, maxf(0.55, tint.a))   # only dim, never recolour
	b.add_child(ic)
	if br != "":
		var l := UIKit.label(br, 0.75); l.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT); l.grow_horizontal = GROW_DIRECTION_BEGIN; l.grow_vertical = GROW_DIRECTION_BEGIN
		l.autowrap_mode = TextServer.AUTOWRAP_OFF; l.offset_right = -UIKit.font_size * 0.15; l.mouse_filter = MOUSE_FILTER_IGNORE; b.add_child(l)
		l.offset_bottom -= cap_h; l.offset_top -= cap_h
	if caption != "":
		var cl := UIKit.label(caption, 0.75, Color("e8e0c8")); cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cl.clip_text = true; cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cl.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE); cl.offset_top = -cap_h
		cl.offset_left = UIKit.font_size * 0.1; cl.offset_right = -UIKit.font_size * 0.1
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.mouse_filter = MOUSE_FILTER_IGNORE; b.add_child(cl)
	if tl != "":
		var l2 := UIKit.label(tl, 0.75, Color("66ffff")); l2.position = Vector2(UIKit.font_size * 0.15, 0); l2.autowrap_mode = TextServer.AUTOWRAP_OFF
		l2.mouse_filter = MOUSE_FILTER_IGNORE; b.add_child(l2)
	UIKit.add_str_label(b, id, int(GameState.heroes.get(chosen_hero, {}).get("str", 10)), gear)
	if gear.is_empty():
		b.pressed.connect(func(): Sfx.play("click"); cb.call())
		return b
	# long-press (0.45 s) compares with what the selected hero has equipped (DECISIONS #83)
	b.set_meta("held", false)
	var hold := Timer.new(); hold.one_shot = true; hold.wait_time = 0.45; b.add_child(hold)
	hold.timeout.connect(func(): b.set_meta("held", true); Sfx.play("click"); compare(gear))
	b.button_down.connect(func(): b.set_meta("held", false); hold.start())
	b.button_up.connect(func(): hold.stop())
	b.pressed.connect(func():
		if b.get_meta("held"): return
		Sfx.play("click"); cb.call())
	return b

const SLOT_OF := {"weapon": "weapon", "armor": "armor", "ring": "ring", "artifact": "artifact"}
## Stat lines for a comparison: [label, value] pairs.
func gear_stats(g: Dictionary) -> Dictionary:
	if g.is_empty(): return {}
	var d := DB.item(g.id); var out := {}
	if not g.known: return {"?": 0}
	var lv := int(g.lvl)
	if d.has("dmg"): out["Dmg"] = int(d.dmg) + lv
	if d.has("dr"): out["DR"] = int(d.dr) + lv
	if d.has("delay"): out["Swing"] = float(d.delay)
	if d.has("str"): out["Str"] = int(d.str)
	for k in ["ht_bonus", "dr_bonus", "dmg_bonus", "barrier_bonus", "charges_bonus", "search_add"]:
		if d.has(k): out[k.replace("_bonus", "").replace("_add", "").replace("ht", "HP").capitalize()] = int(d[k])
	if d.has("bolt_bonus"): out["Ranged dmg"] = int(d.bolt_bonus)
	if d.has("force_bonus"): out["Tier-1 dmg"] = int(d.force_bonus)
	if d.has("delay_mult"): out["Melee speed %"] = int(round((1.0 - float(d.delay_mult)) * 100))
	if d.has("move_cost"): out["Move speed %"] = int(round((1.0 - float(d.move_cost)) * 100))
	if d.has("elem_resist"): out["Magic resist %"] = int(round((1.0 - float(d.elem_resist)) * 100))
	if d.has("gold_mult"): out["Gold %"] = int(round((float(d.gold_mult) - 1.0) * 100))
	if d.has("hunger_mult"): out["Hunger %"] = int(round((float(d.hunger_mult) - 1.0) * 100))
	if d.get("type", "") == "artifact":   # artifact stats at the item's level (DECISIONS #164)
		var pl: Dictionary = d.get("per_level", {})
		for k in ["thorns", "freeze_start", "grass_root", "chain_root", "loot_mult", "ht_bonus", "search_add", "hunger_mult"]:
			if not d.has(k) and not pl.has(k): continue
			var v := float(d.get(k, 0.0)) + float(pl.get(k, 0.0)) * lv
			var lab: String = Codex.ARTIFACT_STATS[k][0]
			if k in ["loot_mult", "hunger_mult"]: out[lab + " %"] = int(round((v - 1.0) * 100))
			elif k in ["ht_bonus", "search_add", "thorns"]: out[lab] = int(floor(v))
			else: out[lab] = snappedf(v, 0.01)
	return out

## Side-by-side compare window: the item vs the selected hero's equipped item of the same kind.
func compare(g: Dictionary) -> void:
	var t: String = DB.item(g.id).type
	var h: Dictionary = GameState.heroes[chosen_hero]
	var cur := GameState.gear_by_uid(int(h.get(SLOT_OF.get(t, ""), 0))) if SLOT_OF.has(t) else {}
	var a := gear_stats(g); var c := gear_stats(cur)
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(UIKit.font_size * 1.2))
	var nl := func(t: String, sc: float, col: Color) -> Label:
		var l := UIKit.label(t, sc, col); l.autowrap_mode = TextServer.AUTOWRAP_OFF; return l
	for txt in ["", "This", "Equipped"]: grid.add_child(nl.call(txt, 0.85, Color("ffd27a")))
	var keys := a.keys()
	for k in c.keys(): if not (k in keys): keys.append(k)
	for k in keys:
		grid.add_child(nl.call(String(k), 0.85, Color("bdb3a0")))
		var av = a.get(k, null); var cv = c.get(k, null)
		var col := Color.WHITE
		if av != null and cv != null and k != "?":
			var better: bool = (av < cv) if k in ["Swing", "Str", "Hunger %"] else (av > cv)
			if av != cv: col = Color("6bff6b") if better else Color("ff6a5a")
		grid.add_child(nl.call("-" if av == null else str(av), 0.9, col))
		grid.add_child(nl.call("-" if cv == null else str(cv), 0.9, Color.WHITE))
	var lines: Array = ["vs %s's %s" % [DB.heroes[chosen_hero].name, GameState.gear_name(cur) if not cur.is_empty() else "empty slot"], grid]
	var acts := []
	if SLOT_OF.has(t) and GameState.equipped_by(g.uid) == "":
		acts.append(["Equip on " + DB.heroes[chosen_hero].name, func(): GameState.equip(chosen_hero, g.uid), GameState.can_equip(chosen_hero, g.uid)])
	var bdg := UIKit.gear_badge(g)
	if bdg == "": bdg = "NONE"
	info(gear_icon(g), "Compare: " + GameState.gear_name(g), lines, acts, bdg)

func gear_icon(g: Dictionary) -> String:
	return g.id   # rings show their gem, as in SPD (the gem is the appearance, not the identity)

func gear_lines(g: Dictionary) -> Array:
	var d := DB.item(g.id); var out := []
	var who := GameState.equipped_by(g.uid)
	if g.known:
		var bits := []
		if d.has("dmg"): bits.append("Dmg %d" % (int(d.dmg) + int(g.lvl)))
		if d.has("dr"): bits.append("DR %d" % (int(d.dr) + int(g.lvl)))
		if d.has("str"): bits.append("Str %d" % int(d.str))
		if not bits.is_empty(): out.append("  ".join(bits))
		if d.has("desc"): out.append(d.desc)
		elif bits.is_empty(): out.append(Codex.item_line(g.id))
		out.append_array(Codex.artifact_lines(g, GameState.enchant_cap(), GameState.ARTIFACT_XP_PER_LVL))   # DECISIONS #164
	else: out.append("Unidentified. The Enchanter can identify it.")
	if g.get("cracked", false): out.append("Cracked - repair at the Forge.")
	if who != "": out.append("Equipped by " + DB.heroes[who].name)
	return out

# ------------------------------------------------------------ Heroes (equipment)
var show_talents := false
func _page_heroes() -> void:
	var v := _p("Heroes")
	var hr := HFlowContainer.new(); hr.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.4)); v.add_child(hr)
	for c in GameState.heroes: hr.add_child(_hero_slot(c))
	var c := chosen_hero
	if not GameState.heroes[c].unlocked:
		v.add_child(_unlock_card(c)); return
	# Diablo-style paperdoll (DECISIONS #84)
	Paperdoll.build(v, c, not portrait, "camp", _fill_window, func(): show_talents = not show_talents; _fill_window())
	if GameState.can_choose_subclass(c):
		var subs: Dictionary = DB.heroes[c].subclasses
		for sid in subs:
			v.add_child(UIKit.button("Become %s: %s" % [subs[sid].name, subs[sid].desc], func(): GameState.choose_subclass(c, sid)))
	if c == "mage":
		for g in GameState.gear:
			if DB.item(g.id).type == "wand" and g.known:
				v.add_child(UIKit.button("Imbue " + GameState.gear_name(g), func(): GameState.imbue_wand(g.uid)))
	if show_talents or GameState.talent_points_total_free(c) > 0: HeroPanels.talents(v, c, _fill_window)

# ------------------------------------------------------------ Stash
const GEAR_CATS := [["weapon", "Weapons"], ["armor", "Armor"], ["ring", "Rings"], ["artifact", "Artifacts"], ["wand", "Wands"]]

func _is_potion_or_scroll(k: String) -> bool:
	var kind: String = DB.materials.get(k, {}).get("kind", "")
	return kind in ["potion", "scroll"] or k.begins_with("potion_") or k.begins_with("scroll_") or k.begins_with("elixir_")

func _add_mat_grid(v: VBoxContainer, keys: Array) -> void:
	var grid := slot_grid(v)
	for k in keys:
		var md: Dictionary = DB.materials[k]
		grid.add_child(item_slot(k, str(GameState.mat(k)), "", func(): info(k, DB.mat_name(k), [md.get("desc", "") if GameState.is_mat_known(k) else "Unidentified - use it during a delve to learn what it is.", "In stash: %d" % GameState.mat(k)])))

func _stash_gear_less(a: Dictionary, b: Dictionary) -> bool:
	var da := DB.item(a.id); var db := DB.item(b.id)
	var ta := int(da.get("tier", 0)); var tb := int(db.get("tier", 0))
	if ta != tb: return ta < tb
	if a.known != b.known: return bool(a.known)
	if a.id != b.id: return String(a.id) < String(b.id)
	if int(a.lvl) != int(b.lvl): return int(a.lvl) > int(b.lvl)
	var wa := GameState.equipped_by(a.uid) != ""; var wb := GameState.equipped_by(b.uid) != ""
	if wa != wb: return wa
	return int(a.uid) < int(b.uid)

func _page_stash() -> void:
	var v := _p("Stash")
	if GameState.owed_sou > 0:
		var row := UIKit.hbox(v); row.add_child(UIKit.icon("scroll_upgrade"))
		var ol := UIKit.label("%d lost Scroll%s of Upgrade will return on your next boss kill." % [GameState.owed_sou, "" if GameState.owed_sou == 1 else "s"], 0.85, Color("ffff66"))
		ol.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(ol)
	var mats := []; var potions := []; var scrolls := []
	for k in DB.materials:
		if GameState.mat(k) <= 0: continue
		if not _is_potion_or_scroll(k): mats.append(k)
		elif String(k).begins_with("scroll_") or DB.materials[k].get("kind", "") == "scroll": scrolls.append(k)
		else: potions.append(k)
	var sec := _switcher(v, "Stash", [["mats", "Materials"], ["potions", "Potions & scrolls (%d)" % (potions.size() + scrolls.size())],
		["gear", "Gear (%d)" % GameState.gear.size()]])
	if sec == "mats":
		if mats.is_empty(): v.add_child(UIKit.label("No materials yet.", 0.8, Color("9a9488")))
		else: _add_mat_grid(v, mats)
		return
	if sec == "potions":
		if potions.is_empty() and scrolls.is_empty(): v.add_child(UIKit.label("No potions or scrolls. Find them in a delve or brew them at Alchemy.", 0.8, Color("9a9488")))
		else: _add_mat_grid(v, potions + scrolls)
		return
	if GameState.gear.is_empty(): v.add_child(UIKit.label("No gear yet. Craft some at the Forge.", 0.8, Color("9a9488")))
	v.add_child(UIKit.label("Tap for info, hold to compare with %s's gear." % DB.heroes[chosen_hero].name, 0.75, Color("9a9488")))
	for cat in GEAR_CATS:
		var list := GameState.gear.filter(func(g): return DB.item(g.id).type == cat[0])
		if list.is_empty(): continue
		list.sort_custom(_stash_gear_less)
		v.add_child(UIKit.label("%s (%d)" % [cat[1], list.size()], 0.95, Color("ffd27a")))
		var gg := slot_grid(v)
		for g in list:
			var who := GameState.equipped_by(g.uid)
			var bdg := UIKit.gear_badge(g)
			if bdg == "": bdg = "NONE"
			gg.add_child(item_slot(gear_icon(g), DB.heroes[who].name.substr(0, 1) if who != "" else "", "+%d" % g.lvl if g.lvl > 0 and g.known else "",
				func(): info(gear_icon(g), GameState.gear_name(g), gear_lines(g), [], bdg), Color(1, 0.55, 0.5) if g.get("cracked", false) else Color.WHITE, "c9a96e" if who != "" else "", g))

# ------------------------------------------------------------ Facilities
const NEXT_TEXT := {"blacksmith": "Gear upgrade cap +%d", "alchemy": "Potion belt %d slots", "enchanter": "Faster identification, ring/wand cap +%d", "guild": "Patrols up to %dh"}

func _preview(id: String, lvl: int) -> String:
	match id:
		"blacksmith": return NEXT_TEXT[id] % lvl
		"alchemy": return (NEXT_TEXT[id] % (lvl + 1)) + (", Starter Elixirs" if lvl == 2 else "")
		"guild": return NEXT_TEXT[id] % [2, 4, 8][clampi(lvl - 1, 0, 2)]
		"enchanter": return NEXT_TEXT[id] % maxi(0, lvl - 1)
		_: return NEXT_TEXT[id] % lvl

func _facility_header(v: VBoxContainer, id: String) -> void:
	var f: Dictionary = GameState.facilities[id]
	var d: Dictionary = DB.facilities[id]
	if FAC_MATS.has(id):
		var mc := UIKit.card(); v.add_child(mc); mc.add_child(mats_header(id))
	var card := UIKit.card(); v.add_child(card)
	var col := UIKit.vbox(card)
	var row := UIKit.hbox(col)
	var kk := maxf(2.0, floorf(UIKit.font_size / 6.0))
	if NPC.has(id):
		var at := AtlasTexture.new(); at.atlas = load("res://assets/sprites/%s.png" % NPC[id][0]); at.region = Rect2(0, 0, NPC[id][1], NPC[id][2])
		var tr := UIKit.pixel(at, int(kk)); tr.size_flags_vertical = SIZE_SHRINK_CENTER; row.add_child(tr)
	else:
		var at2 := AtlasTexture.new(); at2.atlas = load("res://assets/tiles/tiles_sewers.png"); at2.region = Rect2(0, 64, 16, 16)
		var tp := UIKit.pixel(at2, int(kk)); tp.size_flags_vertical = SIZE_SHRINK_CENTER; row.add_child(tp)
	var cv := UIKit.vbox(row); cv.size_flags_horizontal = SIZE_EXPAND_FILL
	var cap: int = GameState.facility_cap(id)
	var lvl := int(f.level); var mx := int(d.max)
	cv.add_child(UIKit.label("%s   Lv %d / %d" % [d.name, lvl, mx], 1.0, Color("ffd27a")))
	# Small slot row: filled = level, open = ready to upgrade, locked = needs a Scroll of Upgrade.
	col.add_child(_facility_slots(lvl, cap, mx))
	_facility_unlock(col, id)
	if lvl < mx:
		col.add_child(UIKit.label("Next: " + _preview(id, lvl + 1), 0.85, Color("9fd3ff")))
		var why: String = GameState.can_upgrade_facility(id)
		var fr := UIKit.hbox(col)
		var cost := cost_row(GameState.facility_upgrade_cost(id)); cost.size_flags_horizontal = SIZE_EXPAND_FILL; cost.size_flags_vertical = SIZE_SHRINK_CENTER; fr.add_child(cost)
		var fill := UIKit.button("Upgrade", func(): GameState.upgrade_facility(id), why == "")
		fill.name = "FillSlot"; fill.autowrap_mode = TextServer.AUTOWRAP_OFF; fill.size_flags_horizontal = SIZE_SHRINK_END
		fill.tooltip_text = "Spend materials. Raises the level by one, up to an open slot."
		fr.add_child(fill)
		if why != "":
			var shown := "Unlock a slot first." if why.begins_with("unlock a slot") else why
			col.add_child(UIKit.label(shown, 0.75, Color("c9a96e")))
	col.add_child(UIKit.label(d.desc, 0.8, Color("bdb3a0")))

## One box per facility level. Filled boxes are the current level, open boxes can be filled with materials,
## locked boxes still need a Scroll of Upgrade.
func _facility_slots(level: int, cap: int, mx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "FacilitySlots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(UIKit.font_size * 0.45))
	for i in range(1, mx + 1):
		var state := "filled" if i <= level else ("open" if i <= cap else "locked")
		row.add_child(_fac_slot(state, i))
	return row

func _fac_slot(state: String, n: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "FacSlot"
	box.set_meta("state", state)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var sz := UIKit.font_size * 1.8
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(sz, sz)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.08, 0.9)
	bg.set_border_width_all(maxi(2, int(UIKit.font_size * 0.1)))
	bg.border_color = Color("ffd27a") if state == "filled" else (Color("6bff6b") if state == "open" else Color("5c564c"))
	slot.add_theme_stylebox_override("panel", bg)
	slot.tooltip_text = "Filled. This counts toward the level." if state == "filled" else ("Open. Fill this with materials." if state == "open" else "Locked. A Scroll of Upgrade unlocks it.")
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(sz, sz)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if state == "locked":
		var ic := UIKit.icon("scroll_upgrade", int(sz * 0.85))
		ic.modulate = Color(1, 1, 1, 0.45)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(ic)
	else:
		var glyph := "+" if state == "open" else str(n)
		var lab := UIKit.label(glyph, 1.15, Color("6bff6b") if state == "open" else Color("ffd27a"))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(lab)
	slot.add_child(cc)
	box.add_child(slot)
	var word_col := Color("ffd27a") if state == "filled" else (Color("6bff6b") if state == "open" else Color("9a9488"))
	var word := UIKit.chip_label(state.capitalize(), 0.75, word_col)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(word)
	return box

## One row under the slots. Hidden once every slot is unlocked. Shown with no scrolls in the stash, so the cost is visible.
func _facility_unlock(col: VBoxContainer, id: String) -> void:
	var need: int = GameState.sou_cap_cost(id)
	if need <= 0: return
	var ur := HFlowContainer.new()
	ur.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.45))
	ur.add_theme_constant_override("v_separation", int(UIKit.font_size * 0.2))
	col.add_child(ur)
	var cr := cost_row({"scroll_upgrade": need})
	cr.size_flags_vertical = SIZE_SHRINK_CENTER
	ur.add_child(cr)
	ur.add_child(UIKit.chip_label("have %d" % GameState.mat("scroll_upgrade"), 0.85, Color("bdb3a0")))
	var can := GameState.mat("scroll_upgrade") >= need
	var ub := UIKit.button("Unlock", func(): GameState.apply_sou(id), can)
	ub.name = "UnlockSlot"
	ub.autowrap_mode = TextServer.AUTOWRAP_OFF
	ub.size_flags_horizontal = SIZE_SHRINK_END
	ub.tooltip_text = "Scrolls of Upgrade only open a locked slot. They do not raise the level."
	if GameState.can_upgrade_facility(id) == "": UIKit.secondary(ub)
	ur.add_child(ub)

func _recipe_slots(v: VBoxContainer, id: String, title: String) -> void:
	var rs: Array = DB.recipes.get(id, [])
	if rs.is_empty(): return
	v.add_child(UIKit.header(title))
	var g := slot_grid(v, CAPTION_CELL)
	for r in rs: g.add_child(recipe_slot(id, r))

## Slot caption for a recipe: its name without the verb ("Forge Mace" -> "Mace", "Buy Ration Crate" -> "Ration Crate").
static func short_name(full: String) -> String:
	var s := full.substr(full.find(" ") + 1) if full.contains(" ") else full
	for p in ["the ", "Potion of ", "Scroll of "]:
		if s.begins_with(p): s = s.substr(p.length())
	return s.trim_suffix(" Armor")

## Pack size of a recipe that makes several of one material ("x3" for the Guild ration crate), else "".
static func recipe_qty(r: Dictionary) -> String:
	var n := int(r.get("out_n", 1))
	return "x%d" % n if n > 1 and not r.has("out") else ""

## One recipe/supply slot: stash count bottom-right, pack size top-left (like the Alchemy "=> x2" slot), so the
## Guild ration crate is not a second, identical Ration slot (DECISIONS #115).
func recipe_slot(id: String, r: Dictionary) -> Button:
	var out: String = r.get("out", r.get("out_mat", ""))
	var why: String = GameState.can_craft(id, r.id)
	var have := "" if r.has("out") else str(GameState.mat(out))
	# build the cost row on click: the popup frees it when you click away, so a stored node is dead next time
	return item_slot(out, have, recipe_qty(r), func(): _recipe_info(id, r, out, _recipe_lines(r), GameState.can_craft(id, r.id)),
		Color.WHITE if why == "" else Color(1, 1, 1, 0.45), "6bff6b" if why == "" else "", {}, "", short_name(r.name))

## Fresh cost row + stat lines. Never keep the Control: closing the popup frees it.
func _recipe_lines(r: Dictionary) -> Array:
	var out: String = r.get("out", r.get("out_mat", ""))
	var lines: Array = [cost_row(r.cost)]
	if recipe_qty(r) != "": lines.append("Gives %d %s." % [int(r.out_n), DB.mat_name(out) + ("s" if not DB.mat_name(out).ends_with("s") else "")])
	var od: Dictionary = DB.item(out) if r.has("out") else DB.materials.get(out, {})
	if od.has("desc"): lines.append(od.desc)
	if r.has("out") and od.has("dmg"): lines.append("Dmg %d  Str %d" % [od.dmg, od.get("str", 10)])
	if r.has("out") and od.has("dr"): lines.append("DR %d  Str %d" % [od.dr, od.get("str", 10)])
	return lines

## Recipe / supply info with a quantity picker (Forge "Make", Guild "Buy").
func _recipe_info(id: String, r: Dictionary, out: String, lines: Array, why: String) -> void:
	var verb := "Buy" if id == "guild" else "Make"
	var cost: Dictionary = r.cost
	var rid: String = r.id
	info(out, r.name, lines + [qty_picker(GameState.craft_max(id, rid), func(n): return GameState.cost_mul(cost, n), verb,
		func(n): GameState.craft_n(id, rid, n), why)])

## Fresh lines each open. The cost row is a Control the popup frees on close.
func _open_gear_forge(uid: int) -> void:
	var g := GameState.gear_by_uid(uid)
	if g.is_empty(): return
	var cracked: bool = g.get("cracked", false)
	var cost: Dictionary = GameState.repair_cost(uid) if cracked else GameState.item_upgrade_cost(uid)
	var why: String = GameState.can_repair(uid) if cracked else GameState.can_upgrade_item(uid)
	var lines := gear_lines(g)
	if not cracked and g.known: lines.push_front("+%d  ->  +%d" % [g.lvl, g.lvl + 1])
	lines.push_front(cost_row(cost))
	_gear_forge_info(g, lines, why)

## Forge gear info: repair (single) or upgrade N levels with a quantity picker.
func _gear_forge_info(g: Dictionary, lines: Array, why: String) -> void:
	var uid: int = g.uid
	var bdg := UIKit.gear_badge(g)
	if bdg == "": bdg = "NONE"
	if g.get("cracked", false):
		info(gear_icon(g), GameState.gear_name(g), lines, [["Repair", func(): GameState.repair(uid), why]], bdg); return
	info(gear_icon(g), GameState.gear_name(g), lines + [qty_picker(GameState.upgrade_max(uid), func(n): return GameState.upgrade_cost_n(uid, n), "Upgrade",
		func(n): GameState.upgrade_item_n(uid, n), why)], [], bdg)

## Every copy of one ring: melt one, melt the spares, or repair a cracked copy.
func _open_ring_stack(id: String) -> void:
	var list: Array = GameState.rings_of(id)
	if list.is_empty(): return
	var known_n := 0
	var cracked_n := 0
	var equipped: PackedStringArray = []
	var sample: Dictionary = list[0]
	var cracked_uid := 0
	for g in list:
		if g.known:
			known_n += 1; sample = g
		if g.get("cracked", false):
			cracked_n += 1
			if cracked_uid == 0: cracked_uid = int(g.uid)
		var who := GameState.equipped_by(int(g.uid))
		if who != "": equipped.append(DB.heroes[who].name)
	var all_known := known_n == list.size()
	var d: Dictionary = DB.item(id)
	var title: String = d.name if all_known else d.get("unknown_name", "Ring")
	var lines: Array = []
	if known_n > 0:
		for l in gear_lines(sample):
			var s := String(l)
			if s.begins_with("Equipped") or s.begins_with("Cracked"): continue
			lines.append(l)
	if known_n == 0:
		lines.append("Unidentified. The Enchanter can identify it.")
	elif not all_known:
		lines.append("%d of %d identified." % [known_n, list.size()])
	lines.append("Owned: %d" % list.size())
	if not equipped.is_empty(): lines.append("Equipped: " + ", ".join(equipped))
	if cracked_n > 0: lines.append("Cracked: %d" % cracked_n)
	lines.append("Each breaks down into %s." % GameState.cost_text(GameState.ring_break_yield()))
	var acts: Array = []
	if cracked_uid != 0:
		var rc: Dictionary = GameState.repair_cost(cracked_uid)
		var why_r: String = GameState.can_repair(cracked_uid)
		var fix: int = cracked_uid
		acts.append(["Repair", func(): GameState.repair(fix), why_r])
	var one: int = GameState.breakable_ring(id)
	if one != 0:
		var melt: int = one
		acts.append(["Break down", func():
			if GameState.break_ring(melt): Sfx.play("shatter"), ""])
	else:
		acts.append(["Break down", func(): pass, "all equipped"])
	var rid := id
	var extra_n: int = GameState.ring_extras_of(rid).size()
	if extra_n > 0:
		acts.append(["Break down extras (%d)" % extra_n, func():
			if GameState.break_rings(GameState.ring_extras_of(rid)): Sfx.play("shatter"), ""])
	info(id, title, lines, acts, UIKit.gear_badge(sample) if known_n > 0 else "NONE")

func _ring_forge_section(v: VBoxContainer) -> void:
	v.add_child(UIKit.header("Break down rings"))
	v.add_child(UIKit.label("A spare ring melts into %s. Extras keeps every worn ring and one spare of each." % GameState.cost_text(GameState.ring_break_yield()), 0.8, Color("bdb3a0")))
	var extras: Array = GameState.ring_extras()
	if not extras.is_empty():
		var rw := UIKit.hbox(v)
		var rl := UIKit.label("Extras: %d" % extras.size(), 0.85, Color("ffd27a"))
		rl.size_flags_vertical = SIZE_SHRINK_CENTER; rl.autowrap_mode = TextServer.AUTOWRAP_OFF; rw.add_child(rl)
		var yl := UIKit.label(GameState.cost_text(GameState.cost_mul(GameState.ring_break_yield(), extras.size())), 0.85, Color("6bff6b"))
		yl.size_flags_horizontal = SIZE_EXPAND_FILL; rw.add_child(yl)
		var ba := UIKit.action("Break down extras", func():
			if GameState.break_ring_extras(): Sfx.play("shatter"), "")
		ba.name = "BreakExtras"; v.add_child(ba)
	var ids: Array = []
	for g in GameState.gear:
		if DB.item(g.id).type == "ring" and not (g.id in ids): ids.append(g.id)
	if ids.is_empty():
		v.add_child(UIKit.label("No rings to break down.", 0.8, Color("9a9488")))
		return
	ids.sort()
	var g2 := slot_grid(v)
	for id in ids:
		var rid := String(id)
		var list: Array = GameState.rings_of(rid)
		var one: Dictionary = list[0] if list.size() == 1 else {}
		var frame := "6bff6b" if GameState.ring_extras_of(rid).size() > 0 else ""
		var bdg := "NONE"
		for g in list:
			if g.known: bdg = UIKit.gear_badge(g); break
		g2.add_child(item_slot(rid, str(list.size()) if list.size() > 1 else "", "", func(): _open_ring_stack(rid), Color.WHITE, frame, one, bdg))

var alch_sel := ""
## Recipe names would give away an unidentified ingredient, so those read "Brew the <appearance>" until it is known.
func recipe_name(r: Dictionary) -> String:
	for k in r.cost:
		if DB.materials.get(k, {}).get("unknown", false) and not GameState.is_mat_known(k): return "Brew the " + DB.mat_name(k)
	return r.name
## SPD WndAlchemy-style pot: ingredient slots -> arrow -> result slot, with Brew underneath; recipes to pick below.
func _alchemy_pot(v: VBoxContainer) -> void:
	var rs: Array = DB.recipes.get("alchemy", [])
	if rs.is_empty(): return
	if not rs.any(func(r): return r.id == alch_sel): alch_sel = rs[0].id
	var r: Dictionary = rs.filter(func(x): return x.id == alch_sel)[0]
	var out: String = r.get("out", r.get("out_mat", ""))
	var why: String = GameState.can_craft("alchemy", r.id)
	var pot := UIKit.card(); v.add_child(pot)
	var pv := UIKit.vbox(pot)
	pv.add_child(UIKit.label(recipe_name(r), 1.0, Color("ffd27a")))
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; pv.add_child(row)
	row.add_theme_constant_override("separation", int(UIKit.font_size * 0.3))
	for k in r.cost:
		var need := int(r.cost[k]); var have := GameState.mat(k)
		var sl := item_slot(k, "%d/%d" % [mini(have, need), need], "", func(): info(k, DB.mat_name(k), ["Need %d, have %d." % [need, have], DB.materials.get(k, {}).get("desc", "")]),
			Color.WHITE if have >= need else Color(1, 1, 1, 0.4), "6bff6b" if have >= need else "ff6a5a")
		row.add_child(sl)
	var arrow := UIKit.label("=>", 1.5, Color("ffd27a")); arrow.autowrap_mode = TextServer.AUTOWRAP_OFF; arrow.size_flags_vertical = SIZE_SHRINK_CENTER; row.add_child(arrow)
	var od: Dictionary = DB.item(out) if r.has("out") else DB.materials.get(out, {})
	var on := int(r.get("out_n", 1))
	row.add_child(item_slot(out, "x%d" % on if on > 1 else "", "", func(): info(out, DB.mat_name(out), [od.get("desc", ""), "In stash: %d" % GameState.mat(out)]), Color.WHITE, "ffd27a"))
	if od.has("desc"): pv.add_child(UIKit.label(od.desc, 0.8, Color("bdb3a0")))
	var brew := UIKit.action("Brew", func():
		if GameState.craft("alchemy", r.id): Sfx.play("drink"), why)
	brew.custom_minimum_size.y = UIKit.btn_height() * 1.2; pv.add_child(brew)
	v.add_child(UIKit.header("Recipes"))
	# list (not a captioned grid): full names, no ellipsis
	for x in rs:
		var o2: String = x.get("out", x.get("out_mat", ""))
		var ok := GameState.can_craft("alchemy", x.id) == ""
		var ukey := ""
		for k in x.cost:
			if DB.materials.get(k, {}).get("unknown", false): ukey = k
		var rid: String = x.id
		var rr := UIKit.hbox(v)
		var ic := UIKit.icon(ukey if ukey != "" else o2); ic.size_flags_vertical = SIZE_SHRINK_CENTER; rr.add_child(ic)
		var b := UIKit.button(recipe_name(x), func(): alch_sel = rid; _fill_window())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.size_flags_horizontal = SIZE_EXPAND_FILL
		if rid != alch_sel: UIKit.secondary(b)
		if not ok: b.modulate = Color(1, 1, 1, 0.55)
		rr.add_child(b)

func _page_facility(page: String, id: String) -> void:
	var v := _p(page)
	_facility_header(v, id)
	if id == "alchemy": _alchemy_pot(v); return
	if id == "blacksmith":
		var nc0 := GameState.cracked_gear().size()
		var sec := _switcher(v, page, [["craft", "Craft"], ["upgrade", "Upgrade & repair" + (" (%d cracked)" % nc0 if nc0 else "")], ["rings", "Rings"]])
		if sec == "craft": _recipe_slots(v, id, "Recipes (tap for details)")
		elif sec == "rings": _ring_forge_section(v)
		else: _forge_upgrade_section(v)
		return
	_recipe_slots(v, id, "Recipes (tap for details)")
	if id == "enchanter": _identify_section(v); _attune_section(v)

func _forge_upgrade_section(v: VBoxContainer) -> void:
	v.add_child(UIKit.header("Upgrade & repair (cap +%d)" % GameState.forge_cap()))
	var rw := UIKit.hbox(v)
	var nc := GameState.cracked_gear().size()
	var rl := UIKit.label("Cracked: %d" % nc, 0.85, Color("ff8a7a") if nc else Color("9a9488")); rl.size_flags_vertical = SIZE_SHRINK_CENTER; rl.autowrap_mode = TextServer.AUTOWRAP_OFF; rw.add_child(rl)
	if nc: rw.add_child(cost_row(GameState.repair_all_cost()))
	var ra := UIKit.action("Repair all", func(): GameState.repair_all(), GameState.can_repair_all()); ra.size_flags_horizontal = SIZE_EXPAND_FILL; ra.name = "RepairAll"
	v.add_child(ra)
	if GameState.can_patch_up() == "":
		var pu := UIKit.button("Patch up (free) - can't afford any repair", func(): GameState.patch_up()); pu.name = "PatchUp"; v.add_child(pu)
	var g2 := slot_grid(v)
	for g in GameState.gear:
		var t: String = DB.item(g.id).type
		var cracked: bool = g.get("cracked", false)
		# weapons/armor upgrade here; cracked artifacts come here to be repaired.
		# Rings have their own section (DECISIONS #98, #107).
		if not (t in ["weapon", "armor"]) and not (cracked and t == "artifact"): continue
		var cost: Dictionary = GameState.repair_cost(g.uid) if cracked else GameState.item_upgrade_cost(g.uid)
		var why: String = GameState.can_repair(g.uid) if cracked else GameState.can_upgrade_item(g.uid)
		var uid: int = int(g.uid)
		g2.add_child(item_slot(gear_icon(g), "", "+%d" % g.lvl if g.lvl > 0 and g.known else "", func(): _open_gear_forge(uid),
			Color(1, 0.55, 0.5) if cracked else Color.WHITE, "6bff6b" if why == "" else "", g))
	if g2.get_child_count() == 0: v.add_child(UIKit.label("No weapons or armor yet. Craft some first.", 0.8, Color("9a9488")))

## Rings, wands and artifacts level and repair here (DECISIONS #158).
func _attune_section(v: VBoxContainer) -> void:
	var cap := GameState.enchant_cap()
	v.add_child(UIKit.header("Attune rings, wands & artifacts (cap +%d)" % cap))
	if cap <= 0: v.add_child(UIKit.label("Upgrade the Desk to Lv2 to level and repair rings and wands (Lv3: repair artifacts).", 0.8, Color("9a9488")))
	var h: Dictionary = GameState.heroes.mage
	if String(h.get("wand", "")) != "":
		var cr: bool = h.get("wand_cracked", false)
		var cost: Dictionary = GameState.staff_wand_repair_cost() if cr else GameState.staff_wand_cost()
		var why: String = GameState.can_repair_staff_wand() if cr else GameState.can_upgrade_staff_wand()
		var row := UIKit.hbox(v)
		row.add_child(UIKit.icon(String(h.wand), -1, "NONE"))
		var nm := "%s +%d%s" % [DB.item(h.wand).name, int(h.get("wand_lvl", 0)), " (cracked)" if cr else ""]
		var lv := UIKit.label(nm, 0.85); lv.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(lv)
		row.add_child(cost_row(cost))
		var b := UIKit.action("Repair" if cr else "Upgrade", func(): (GameState.repair_staff_wand() if cr else GameState.upgrade_staff_wand()), why); b.name = "StaffWand"; v.add_child(b)
	var g2 := slot_grid(v)
	for g in GameState.gear:
		if not GameState.is_trinket(g) or not g.known: continue
		var cracked: bool = g.get("cracked", false)
		if DB.item(g.id).type == "artifact" and not cracked: continue
		var why2: String = GameState.can_repair(g.uid) if cracked else GameState.can_upgrade_item(g.uid)
		var uid: int = int(g.uid)
		g2.add_child(item_slot(gear_icon(g), "", "+%d" % g.lvl if g.lvl > 0 else "", func(): _open_gear_forge(uid),
			Color(1, 0.55, 0.5) if cracked else Color.WHITE, "6bff6b" if why2 == "" else "", g))

func _identify_section(v: VBoxContainer) -> void:
	v.add_child(UIKit.header("Identifying (%d min each)" % int(GameState.identify_seconds() / 60)))
	if GameState.id_queue.is_empty(): v.add_child(UIKit.label("Nothing queued. Tap an unknown item below.", 0.8, Color("9a9488")))
	for q in GameState.id_queue:
		var g := GameState.gear_by_uid(q.uid)
		var left := maxf(0.0, float(q.ready_at) - GameState.now())
		var row := UIKit.hbox(v)
		row.add_child(UIKit.icon(gear_icon(g), -1, "NONE"))
		var cv := UIKit.vbox(row); cv.size_flags_horizontal = SIZE_EXPAND_FILL
		cv.add_child(UIKit.label("%s   %d:%02d" % [GameState.gear_name(g), int(left) / 60, int(left) % 60], 0.85))
		var pb := ProgressBar.new(); pb.name = "IdentifyBar"; pb.max_value = 1.0; pb.step = 0.0; pb.show_percentage = false
		pb.value = GameState.identify_progress(q); pb.custom_minimum_size.y = UIKit.font_size * 0.5
		cv.add_child(pb)
	var unk := GameState.identify_candidates()
	var uh := UIKit.hbox(v)
	var uhl := UIKit.header("Unknown items"); uhl.size_flags_horizontal = SIZE_EXPAND_FILL; uh.add_child(uhl)
	var qa := UIKit.button("Queue all", func(): GameState.enqueue_identify_all(); _fill_window(), not unk.is_empty())
	qa.name = "QueueAll"; qa.autowrap_mode = TextServer.AUTOWRAP_OFF; qa.custom_minimum_size.x = UIKit.font_size * 5.5; qa.size_flags_horizontal = 0; qa.size_flags_vertical = SIZE_SHRINK_CENTER; UIKit.secondary(qa); uh.add_child(qa)
	if unk.is_empty(): v.add_child(UIKit.label("No unknown items to queue.", 0.8, Color("9a9488")))
	else:
		var ug := slot_grid(v)
		for g in unk:
			ug.add_child(item_slot(gear_icon(g), "", "?", func(): info(gear_icon(g), GameState.gear_name(g), gear_lines(g), [["Queue for identification", func(): GameState.enqueue_identify(g.uid), ""]], "NONE"), Color.WHITE, "", g))
	if not GameState.id_queue.is_empty():
		var t := Timer.new(); t.wait_time = 1.0; t.autostart = true; v.add_child(t)
		t.timeout.connect(func(): if open_name == "Enchanter" and info_layer == null: _fill_window())

func _page_guild() -> void:
	var v := _p("Guild")
	_facility_header(v, "guild")
	var out := GameState.heroes.values().filter(func(h): return not h.patrol.is_empty()).size()
	if _switcher(v, "Guild", [["supplies", "Supplies"], ["patrols", "Patrols" + (" (%d out)" % out if out else "")]]) == "supplies":
		_recipe_slots(v, "guild", "Supplies (tap to buy)")
		return
	v.add_child(UIKit.header("Offline Patrols (max %dh)" % int(GameState.patrol_max_hours())))
	v.add_child(UIKit.label("Idle heroes patrol a cleared biome in real time and bring back upgrade fuel.", 0.8, Color("bdb3a0")))
	_patrol_list(v)

## One card per unlocked hero: idle biome buttons, or progress + Recall. Used by Guild and the wide camp dock.
func _patrol_list(v: Control) -> void:
	for c in GameState.heroes:
		var h: Dictionary = GameState.heroes[c]
		if not h.unlocked: continue
		var card := UIKit.card(); var row := UIKit.hbox(card); v.add_child(card)
		var tr := UIKit.pixel(_hero_tex(c), maxi(2, int(UIKit.font_size / 8.0))); tr.size_flags_vertical = SIZE_SHRINK_CENTER; row.add_child(tr)
		var cv := UIKit.vbox(row); cv.size_flags_horizontal = SIZE_EXPAND_FILL
		if h.patrol.is_empty():
			cv.add_child(UIKit.label("%s - idle" % DB.heroes[c].name, 0.9))
			if int(h.level) < GameState.train_cap(c):
				cv.add_child(UIKit.button("Retrain to Lv %d (%s)" % [int(h.level) + 1, GameState.cost_text(GameState.train_cost(c))], func(): GameState.train(c), GameState.can_train(c) == "", GameState.can_train(c)))
			var bf := HFlowContainer.new(); cv.add_child(bf)
			for b in DB.biomes:
				if GameState.can_patrol(c, b) != "" and not GameState.can_patrol(c, b).begins_with("need"): continue
				var pb := UIKit.button("%s %d%%  (%dg)" % [DB.biomes[b].name, int(GameState.patrol_efficiency(c, b) * 100), int(GameState.patrol_fee(b).gold)], func(): GameState.start_patrol(c, b), GameState.can_patrol(c, b) == "", GameState.can_patrol(c, b))
				bf.add_child(pb)
			if bf.get_child_count() == 0: cv.add_child(UIKit.label("Clear a biome first.", 0.8, Color("9a9488")))
		else:
			var y: Dictionary = GameState.patrol_preview(c)
			var head := UIKit.hbox(cv)
			var title := UIKit.label("%s   %.1fh / %dh" % [DB.heroes[c].name, y._hours, int(GameState.patrol_max_hours())], 0.9, Color("ffd27a") if c == chosen_hero else Color.WHITE)
			title.size_flags_horizontal = SIZE_EXPAND_FILL; title.size_flags_vertical = SIZE_SHRINK_CENTER
			head.add_child(title)
			var recall := UIKit.button("Recall", func(): GameState.collect_patrol(c))
			recall.tooltip_text = "Recall and collect"; recall.autowrap_mode = TextServer.AUTOWRAP_OFF
			recall.custom_minimum_size.x = UIKit.font_size * 4.6
			recall.size_flags_horizontal = SIZE_SHRINK_END; recall.size_flags_vertical = SIZE_SHRINK_CENTER
			UIKit.secondary(recall); head.add_child(recall)
			var pr := ProgressBar.new(); pr.max_value = GameState.patrol_max_hours(); pr.step = 0.0; pr.value = float(y._hours); pr.show_percentage = false
			pr.custom_minimum_size.y = UIKit.font_size * 0.5; cv.add_child(pr)
			var yf := HFlowContainer.new(); cv.add_child(yf)
			for k in y:
				if not String(k).begins_with("_") and int(y[k]) > 0: yf.add_child(UIKit.res_chip(k, str(y[k]), 0.8))
			if y._curios > 0: yf.add_child(UIKit.chip_label("+%d curio%s" % [y._curios, "" if int(y._curios) == 1 else "s"], 0.8))

# ------------------------------------------------------------ Journal (meta-progression + codex)
var journal_view := "progress"

func _page_journal() -> void:
	var v := _p("Journal")
	var sw := HFlowContainer.new(); v.add_child(sw)
	for t in [["progress", "Progress"], ["codex", "Codex"]]:
		var b := UIKit.button(t[1], func(): journal_view = t[0]; _fill_window())
		if journal_view != t[0]: UIKit.secondary(b)
		b.custom_minimum_size.x = UIKit.font_size * 7; sw.add_child(b)
	if journal_view == "codex": CodexView.build(v, portrait); return
	var done := GameState.milestones_claimed.size()
	v.add_child(UIKit.header("Milestones  %d / %d" % [done, DB.milestones.size()]))
	# open milestones as cards; finished ones collapse to one line of names
	var finished: PackedStringArray = []
	for m in DB.milestones:
		if m.id in GameState.milestones_claimed: finished.append(m.name); continue
		v.add_child(_progress_card(m.name, m.desc, GameState.stat_value(m.stat), int(m.goal), "Reward: " + GameState.cost_text(m.reward), false))
	if not finished.is_empty():
		v.add_child(UIKit.label("Completed (%d): %s" % [finished.size(), ", ".join(finished)], 0.8, Color("6bff6b")))
	v.add_child(UIKit.header("Heroes"))
	for c in GameState.heroes:
		var h: Dictionary = GameState.heroes[c]
		var rule: Dictionary = DB.heroes[c].get("unlock_rule", {})
		var cleared: String = ", ".join(h.cleared.map(func(b): return DB.biomes[b].name)) if not h.cleared.is_empty() else "nothing yet"
		if rule.is_empty() or h.unlocked:
			v.add_child(_progress_card("%s - Lv%d" % [DB.heroes[c].name, h.level], "Cleared: %s" % cleared, 1, 1, "", true))
		else:
			v.add_child(_unlock_card(c))
	v.add_child(UIKit.header("Lifetime"))
	var st: Dictionary = GameState.stats
	var lines := ["Expeditions: %d (%d extracted, %d deaths)" % [st.runs, st.extractions, st.deaths], "Deepest floor: %d" % st.deepest_floor,
		"Monsters defeated: %d   Goo: %d   Tengu: %d" % [st.kills, st.goo_kills, st.tengu_kills],
		"Hidden traps found: %d   Hidden doors: %d   Potions brewed: %d" % [st.traps_found, st.hidden_doors, st.potions_brewed]]
	for l in lines: v.add_child(UIKit.label(l, 0.85))

func _progress_card(title: String, desc: String, have: int, goal: int, reward: String, done: bool) -> Control:
	var card := UIKit.card(); var cv := UIKit.vbox(card)
	cv.add_child(UIKit.label(("[done] " if done else "") + title, 1.0, Color("6bff6b") if done else Color("ffd27a")))
	cv.add_child(UIKit.label(desc, 0.8, Color("bdb3a0")))
	if not done:
		var bar := ProgressBar.new(); bar.max_value = goal; bar.value = mini(have, goal); bar.show_percentage = false
		bar.custom_minimum_size.y = UIKit.font_size * 0.6; cv.add_child(bar)
		cv.add_child(UIKit.label("%d / %d   %s" % [mini(have, goal), goal, reward], 0.8))
	return card
