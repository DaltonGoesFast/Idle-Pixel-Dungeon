## Main: root of the app. Owns layout (Fold cover/inner, safe areas, theme scale) and screen switching.
## Screens: CampScreen, DelveScreen, CombatScreen. Each screen implements apply_layout(portrait, size, desktop_ui).
extends Control

const CampScreen := preload("res://scripts/ui/camp_screen.gd")
const TipOverlay := preload("res://scripts/ui/tip_overlay.gd")
## Delve and combat stay unloaded until a run starts. Parsing both at boot cost ~45s on ux0
## and the free RAM (about 28 MiB before the main scene) that the first frame needs.
const Keybinds := preload("res://scripts/ui/keybinds.gd")

var margin: MarginContainer
var host: Control
var toast_box: VBoxContainer
var screen: Control
var delve: Control           # kept alive while a combat runs on top of it
var portrait := true
var desktop_ui := false
var tips: Control            # TipOverlay (tutorial cards above everything), the only child of tip_layer
## Tutorial tips live on their own CanvasLayer above the default canvas (DECISIONS #213). A z_index only orders
## siblings inside one canvas, so the delve's encounter window (z 20), its result/Defeat layer (z 30) or anything a
## screen raises later drew over a tip opened beneath it. A higher CanvasLayer always draws last and Godot hands it
## GUI input first, so a tip is the topmost window on every screen, including windows that open after it.
const TIP_LAYER := 100
var tip_layer: CanvasLayer
var _id_timer := 0.0
var _vita_prof := 0.0
var _vita_worst_ms := 0

## DECISIONS #224: integer content scale on web when at least 1× of the design size fits (crisp pixels).
## Godot clips instead of shrinking when integer scale would be below 1×, so desktop browsers and most
## phone windows stay fractional; CSS `image-rendering: pixelated` still keeps the canvas nearest-neighbour.
static func use_integer_content_scale(is_web: bool = OS.has_feature("web"), win: Vector2i = DisplayServer.window_get_size()) -> bool:
	if not is_web:
		return false
	var bw: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var bh: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	if bw <= 0.0 or bh <= 0.0 or win.x <= 0 or win.y <= 0:
		return false
	return float(win.x) >= bw and float(win.y) >= bh

## DECISIONS #232: Desktop UI when set to desktop, or Auto on non-mobile. Mobile OS feature covers Android/iOS.
## Vita is a 960×544 touch handheld (DECISIONS #244). It keeps the wide mobile chrome even if interface is desktop.
static func resolve_desktop_ui(settings: Dictionary = GameState.settings, is_mobile: bool = OS.has_feature("mobile"), os_name: String = OS.get_name()) -> bool:
	if os_name == "Vita":
		return false
	match String(settings.get("interface", "auto")):
		"desktop": return true
		"mobile": return false
		_: return not is_mobile

## Same portrait cut as _relayout (aspect < 0.85). The phone design is portrait; 960×544 is wide.
static func layout_is_portrait(size: Vector2) -> bool:
	if size.y <= 0.0:
		return true
	return size.x / size.y < 0.85

func _apply_content_scale() -> void:
	var root := get_tree().root
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if use_integer_content_scale() else Window.CONTENT_SCALE_STRETCH_FRACTIONAL

func _vita_log(stage: String) -> void:
	if OS.get_name() != "Vita":
		return
	printerr("[vita-boot] %s static=%d peak=%d" % [stage, OS.get_static_memory_usage(), OS.get_static_memory_peak_usage()])

func _ready() -> void:
	_vita_log("main enter")
	Keybinds.apply()
	_apply_content_scale()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bg := ColorRect.new(); bg.color = Color("1b1712"); bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	margin = MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(margin)
	host = Control.new(); margin.add_child(host)
	toast_box = VBoxContainer.new(); toast_box.set_anchors_preset(PRESET_CENTER_TOP)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(toast_box)
	tip_layer = CanvasLayer.new(); tip_layer.name = "TipLayer"; tip_layer.layer = TIP_LAYER; add_child(tip_layer)
	tips = TipOverlay.new(); tips.name = "TipOverlay"; tips.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; tip_layer.add_child(tips)
	add_child(TouchScroll.new())
	get_tree().node_added.connect(func(n):
		if n is ScrollContainer: TouchScroll.style(n)
		elif n is BaseButton and n.mouse_filter == Control.MOUSE_FILTER_STOP: n.mouse_filter = Control.MOUSE_FILTER_PASS)   # drags reach the scroller
	GameState.toast.connect(_toast)
	GameState.settings_changed.connect(_relayout)
	get_viewport().size_changed.connect(_relayout)
	PatrolBridge.open_guild.connect(_open_guild_patrols)
	_relayout()
	_vita_log("theme ready")
	# SceneTree::initialize is root->_set_tree. Building Camp inside that call sits on the
	# loader's 8 MiB main stack and is where the device died (last line: initialize begin).
	if OS.get_name() == "Vita":
		call_deferred("_open_initial_screen")
	else:
		_open_initial_screen()

func _open_initial_screen() -> void:
	_vita_log("open screen")
	GameState.tick_identify()
	if Telemetry.needs_notice(): show_data_notice()
	if GameState.run.is_empty(): show_camp()
	else:
		show_delve()
		if GameState.run.has("active_fight"): delve.resume_fight()
	if PatrolBridge.take_open():
		_open_guild_patrols()
	_vita_log("screen open")

static func ui_font_size(shortest: float, text_scale: float = 1.0, vita := false) -> int:
	if vita:
		return int(clampf(shortest / 16.0 * text_scale, 28, 40))
	return int(clampf(shortest / 24.0 * text_scale, 14, 60))

func _process(delta: float) -> void:
	if VitaBoot.runs_on_vita():
		_vita_frame(delta)
	# toasts never cover a tutorial card (they keep their timers and reappear when it closes)
	toast_box.visible = not tip_open()
	_id_timer += delta
	if _id_timer > 1.0:
		_id_timer = 0.0
		GameState.tick_identify()

func _vita_frame(delta: float) -> void:
	var ms := int(delta * 1000.0)
	if ms > _vita_worst_ms:
		_vita_worst_ms = ms
	_vita_prof += delta
	if _vita_prof < 2.0:
		return
	var draw_us := -1
	var camp: Variant = screen.get("scene") if screen != null else null
	if camp != null:
		draw_us = int(camp.get("_last_draw_us"))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	VitaBoot.mark("tick worst_ms=%d camp_draw_us=%d nodes=%d" % [_vita_worst_ms, draw_us, nodes])
	_vita_prof = 0.0
	_vita_worst_ms = 0

## Live Editor layout mode: drag named Camp chrome (DECISIONS #233). Camp NPCs use CampScene._gui_input.
func _input(e: InputEvent) -> void:
	if not LiveLayout.editing:
		return
	if LiveLayout.ui_input(self, e):
		get_viewport().set_input_as_handled()

## Desktop: 0 opens the Live Editor (DECISIONS #233).
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode != KEY_0 and e.physical_keycode != KEY_0:
		return
	if not LiveLayout.desktop_allowed():
		return
	preload("res://scripts/ui/live_editor.gd").open()
	get_viewport().set_input_as_handled()

func _relayout() -> void:
	_apply_content_scale()
	var vs := get_viewport_rect().size
	portrait = layout_is_portrait(vs)
	desktop_ui = resolve_desktop_ui()
	var l := 12.0; var t := 12.0; var r := 12.0; var b := 12.0
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if OS.has_feature("mobile") and win.x > 0 and safe.size.x > 0:
		var k := vs.x / float(win.x)
		l += safe.position.x * k; t += safe.position.y * k
		r += (win.x - safe.end.x) * k; b += (win.y - safe.end.y) * k
	# Desktop chrome uses less padding so the dungeon fills like vanilla SPD.
	if desktop_ui:
		l = minf(l, 8.0); t = minf(t, 8.0); r = minf(r, 8.0); b = minf(b, 8.0)
	var cap := minf(vs.x, vs.y) * 0.2
	for p in [["left", l], ["top", t], ["right", r], ["bottom", b]]:
		margin.add_theme_constant_override("margin_" + p[0], int(clampf(p[1], 4.0 if desktop_ui else 8.0, cap)))
	var fs := int(clampf(minf(vs.x, vs.y) / 24.0 * float(GameState.settings.get("text_scale", 1.0)), 14, 60))
	if VitaBoot.runs_on_vita():
		fs = ui_font_size(minf(vs.x, vs.y), float(GameState.settings.get("text_scale", 1.0)), true)
	theme = UIKit.make_theme(fs)
	get_window().theme = theme   # popups / anything parented outside Main inherit the SPD theme too
	if tips: tips.theme = theme   # a CanvasLayer breaks Control theme inheritance, so the tip layer gets it directly
	if screen: _layout_screen()
	if tips and tips.is_open(): tips._render()

func content_size() -> Vector2:
	var vs := get_viewport_rect().size
	return vs - Vector2(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))

func _layout_screen() -> void:
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen.apply_layout(portrait, content_size(), desktop_ui)

func _set_screen(s: Control) -> void:
	if screen and screen != delve: screen.queue_free()
	if screen: host.remove_child(screen)
	screen = s
	host.add_child(s)
	_layout_screen()

## Home-screen widget and the return notification open the Guild patrol list when no delve is in progress.
func _open_guild_patrols() -> void:
	if not GameState.run.is_empty():
		return
	if screen == null or screen.get_script() != CampScreen:
		show_camp()
	if screen and screen.has_method("open_guild_patrols"):
		screen.open_guild_patrols()

func show_camp() -> void:
	if delve: delve.queue_free(); delve = null
	var s := CampScreen.new(); s.main = self
	_set_screen(s)
	match GameState.last_result:
		"death": tip("after_death")
		"extract": tip("after_extract")
	GameState.last_result = ""
	if int(GameState.stats.runs) == 0: tip("welcome"); tip("camp_delve")
	if OS.get_name() == "Vita":
		call_deferred("_vita_camp_music")
	else:
		Sfx.music("theme_2" if int(GameState.stats.get("goo_kills", 0)) > 0 else "theme_1")

func _vita_camp_music() -> void:
	_vita_log("before music")
	Sfx.music("theme_2" if int(GameState.stats.get("goo_kills", 0)) > 0 else "theme_1")
	_vita_log("after music")

func show_delve() -> void:
	if delve == null:
		delve = load("res://scripts/ui/delve_screen.gd").new(); delve.main = self
	_set_screen(delve)
	delve.on_shown()
	play_floor_music()

## Biome music, rotating per floor.
func play_floor_music() -> void:
	if GameState.run.is_empty(): return
	Sfx.music(Sfx.biome_track(DB.biomes[GameState.run.biome], int(GameState.run.floor)))

## Called by DelveScreen. on_done(result: Dictionary) gets {won, hp, loot, fallen_loot, xp, boss_killed, potions_used}.
func start_combat(event: Dictionary, on_done: Callable, saved := {}) -> void:
	for t in toast_box.get_children(): t.queue_free()   # nothing floats over the fight
	var s = load("res://scripts/ui/combat_screen.gd").new(); s.main = self
	s.setup(event, on_done, saved)
	_set_screen(s)
	if event.get("boss", false): Sfx.music(DB.biomes[GameState.run.biome].boss_music); Sfx.play("boss")

func end_combat() -> void:
	show_delve()

## One-time notice that anonymous gameplay data is collected (DECISIONS #197). Tip card look; OK + Privacy link.
const DATA_NOTICE_TITLE := "Gameplay data"
const DATA_NOTICE_TEXT := "Idle PD collects anonymous gameplay data (fights, floors, deaths, loot) to improve the game's balance. No names or accounts."
func show_data_notice() -> void:
	tips.push_notice("data_notice", DATA_NOTICE_TITLE, DATA_NOTICE_TEXT, Telemetry.mark_notice_seen, "Privacy", Telemetry.privacy_url)

## Show a tutorial tip once (if tips are enabled). Screens pause while one is open.
func tip(id: String) -> void:
	if tips and GameState.wants_tip(id): tips.push(id)

func tip_open() -> bool:
	return tips != null and tips.is_open()

func _toast(text: String) -> void:
	# in a fight, toasts go to the combat log instead of floating over the arena/log (DECISIONS #75)
	if screen != null and screen.get("combat") != null and screen.has_method("_refresh"):
		screen.combat._log(text)
		if not screen.combat.over: screen._refresh()
		return
	# a screen with a window/log open handles the message itself instead of floating (DECISIONS #83, #106)
	if screen != null and screen.has_method("window_toast") and screen.window_toast(text): return
	var l := UIKit.label(text, 0.85)
	var p := UIKit.card(); p.add_child(l); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = minf(get_viewport_rect().size.x * 0.8, 900)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_box.add_child(p)
	toast_box.position = Vector2((get_viewport_rect().size.x - l.custom_minimum_size.x) / 2.0, get_viewport_rect().size.y * 0.76)   # below the combat arena / delve card (DECISIONS #73)
	while toast_box.get_child_count() > 3:
		var old := toast_box.get_child(0); toast_box.remove_child(old); old.queue_free()
	var tw := create_tween()
	tw.tween_interval(2.2); tw.tween_property(p, "modulate:a", 0.0, 0.6); tw.tween_callback(p.queue_free)
