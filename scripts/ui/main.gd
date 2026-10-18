## Main: root of the app. Owns layout (Fold cover/inner, safe areas, theme scale) and screen switching.
## Screens: CampScreen, DelveScreen, CombatScreen. Each screen implements apply_layout(portrait, size).
extends Control

const CampScreen := preload("res://scripts/ui/camp_screen.gd")
const DelveScreen := preload("res://scripts/ui/delve_screen.gd")
const CombatScreen := preload("res://scripts/ui/combat_screen.gd")
const TipOverlay := preload("res://scripts/ui/tip_overlay.gd")

var margin: MarginContainer
var host: Control
var toast_box: VBoxContainer
var screen: Control
var delve: Control           # kept alive while a combat runs on top of it
var portrait := true
var tips: Control            # TipOverlay (tutorial cards above everything)
var _id_timer := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bg := ColorRect.new(); bg.color = Color("1b1712"); bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	margin = MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(margin)
	host = Control.new(); margin.add_child(host)
	toast_box = VBoxContainer.new(); toast_box.set_anchors_preset(PRESET_CENTER_TOP)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(toast_box)
	tips = TipOverlay.new(); add_child(tips)
	add_child(TouchScroll.new())
	get_tree().node_added.connect(func(n):
		if n is ScrollContainer: TouchScroll.style(n)
		elif n is BaseButton and n.mouse_filter == Control.MOUSE_FILTER_STOP: n.mouse_filter = Control.MOUSE_FILTER_PASS)   # drags reach the scroller
	GameState.toast.connect(_toast)
	GameState.settings_changed.connect(_relayout)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	GameState.tick_identify()
	if Telemetry.needs_notice(): show_data_notice()
	if GameState.run.is_empty(): show_camp()
	else:
		show_delve()
		if GameState.run.has("active_fight"): delve.resume_fight()

func _process(delta: float) -> void:
	# toasts never cover a tutorial card (they keep their timers and reappear when it closes)
	toast_box.visible = not tip_open()
	_id_timer += delta
	if _id_timer > 1.0:
		_id_timer = 0.0
		GameState.tick_identify()

func _relayout() -> void:
	var vs := get_viewport_rect().size
	portrait = vs.x / vs.y < 0.85
	var l := 12.0; var t := 12.0; var r := 12.0; var b := 12.0
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if OS.has_feature("mobile") and win.x > 0 and safe.size.x > 0:
		var k := vs.x / float(win.x)
		l += safe.position.x * k; t += safe.position.y * k
		r += (win.x - safe.end.x) * k; b += (win.y - safe.end.y) * k
	var cap := minf(vs.x, vs.y) * 0.2
	for p in [["left", l], ["top", t], ["right", r], ["bottom", b]]:
		margin.add_theme_constant_override("margin_" + p[0], int(clampf(p[1], 8.0, cap)))
	var fs := int(clampf(minf(vs.x, vs.y) / 24.0 * float(GameState.settings.get("text_scale", 1.0)), 14, 60))
	theme = UIKit.make_theme(fs)
	get_window().theme = theme   # popups / anything parented outside Main inherit the SPD theme too
	if screen: _layout_screen()
	if tips and tips.is_open(): tips._render()

func content_size() -> Vector2:
	var vs := get_viewport_rect().size
	return vs - Vector2(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))

func _layout_screen() -> void:
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen.apply_layout(portrait, content_size())

func _set_screen(s: Control) -> void:
	if screen and screen != delve: screen.queue_free()
	if screen: host.remove_child(screen)
	screen = s
	host.add_child(s)
	_layout_screen()

func show_camp() -> void:
	if delve: delve.queue_free(); delve = null
	var s := CampScreen.new(); s.main = self
	_set_screen(s)
	match GameState.last_result:
		"death": tip("after_death")
		"extract": tip("after_extract")
	GameState.last_result = ""
	if int(GameState.stats.runs) == 0: tip("welcome"); tip("camp_delve")
	Sfx.music("theme_2" if int(GameState.stats.get("goo_kills", 0)) > 0 else "theme_1")

func show_delve() -> void:
	if delve == null:
		delve = DelveScreen.new(); delve.main = self
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
	var s := CombatScreen.new(); s.main = self
	s.setup(event, on_done, saved)
	_set_screen(s)
	if event.get("boss", false): Sfx.music(DB.biomes[GameState.run.biome].boss_music); Sfx.play("boss")

func end_combat() -> void:
	show_delve()

## One-time notice that anonymous gameplay data is collected (DECISIONS #197). Tip card look; OK + Privacy link.
const DATA_NOTICE_TITLE := "Gameplay data"
const DATA_NOTICE_TEXT := "SPD Tactics collects anonymous gameplay data (fights, floors, deaths, loot) to improve the game's balance. No names or accounts."
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
