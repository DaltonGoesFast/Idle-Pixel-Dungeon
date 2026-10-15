## CombatScreen: hosts GridView + controls (Wait, Shove/Bolt modes, Potion, Hint/Auto) + scrollable log.
## Portrait (Fold cover): grid on top, panel below. Wide (Fold inner): grid left, panel right.
extends Control

const GridView := preload("res://scripts/ui/grid_view.gd")

var main: Control
var combat: Combat
var on_done: Callable
var event: Dictionary
var split: BoxContainer
var grid
var side: VBoxContainer
var status: Label
var buttons: HFlowContainer
var log_scroll: ScrollContainer
var log_label: RichTextLabel
var mode := ""
var potions := 0
var potions_used := 0
var heal := 10
var auto := false
var _auto_t := 0.0
var finished := false

## `saved` (optional) = Combat.to_dict() from GameState.run.active_fight when resuming after the app was killed.
func setup(ev: Dictionary, done: Callable, saved := {}) -> void:
	event = ev; on_done = done
	var run: Dictionary = GameState.run
	var hs: Dictionary = GameState.hero_stats(run.hero)
	if saved.is_empty():
		combat = Delve.new_combat(GameState, ev)
	else:
		combat = Combat.new(); combat.from_dict(saved)
		combat._log("(fight resumed)")
	potions = int(run.supplies.get("potion_healing", 0))
	heal = GameState.potion_heal(run.hero)

func _ready() -> void:
	split = BoxContainer.new(); add_child(split); split.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 12)
	grid = GridView.new(); grid.tapped.connect(_on_cell)
	if not GameState.run.is_empty(): grid.tileset = DB.biomes[GameState.run.biome].tile
	split.add_child(grid)
	grid.set_combat(combat)
	side = UIKit.vbox(split); side.size_flags_horizontal = SIZE_EXPAND_FILL; side.size_flags_vertical = SIZE_EXPAND_FILL
	side.add_child(UIKit.header("BOSS: " + DB.mobs[event.mobs[0]].name if event.get("boss", false) else "Combat"))
	status = UIKit.label(""); side.add_child(status)
	buttons = HFlowContainer.new(); side.add_child(buttons)
	log_scroll = ScrollContainer.new(); log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size.y = UIKit.font_size * 4
	var bg := StyleBoxFlat.new(); bg.bg_color = Color("2a241c"); bg.set_content_margin_all(8)
	log_scroll.add_theme_stylebox_override("panel", bg)
	side.add_child(log_scroll)
	log_label = RichTextLabel.new(); log_label.fit_content = true; log_label.scroll_active = false
	log_label.size_flags_horizontal = SIZE_EXPAND_FILL; log_scroll.add_child(log_label)
	_refresh()
	main.tip("boss" if event.get("boss", false) else "first_fight")

func apply_layout(portrait: bool, s: Vector2) -> void:
	split.vertical = portrait
	if portrait:
		grid.custom_minimum_size = Vector2(s.x, s.x)
		grid.size_flags_vertical = SIZE_SHRINK_BEGIN
	else:
		var g := minf(s.y, s.x * 0.6)
		grid.custom_minimum_size = Vector2(g, g)
		grid.size_flags_vertical = SIZE_FILL
	_refresh()

func _process(d: float) -> void:
	if main and main.tip_open(): return
	if auto and not finished:
		_auto_t += d
		if _auto_t > 0.35:
			_auto_t = 0.0; _do_bot()

func _btn(text: String, cb: Callable, enabled := true) -> void:
	var b := UIKit.button(text, cb, enabled)
	b.custom_minimum_size.x = UIKit.font_size * 6.5
	buttons.add_child(b)

func _refresh() -> void:
	if status == null: return
	var h := combat.hero
	var line := "%s  HP %d/%d  Barrier %d/%d  DR %d  Dmg %d   t=%.1f" % [h.name, h.hp, h.ht, h.barrier, h.barrier_max, h.dr, h.dmg, combat.time]
	if not h.bolt.is_empty():
		if h.bolt.get("infinite", false): line += "\nTap any enemy in sight to shoot %s (%d dmg)" % [h.bolt.name, h.bolt.dmg]
		else: line += "\nStaff charges %d/%d (%s, %d dmg, ignores DR)" % [h.charges, h.bolt.charges, h.bolt.name, h.bolt.dmg]
	if combat.hidden(): line += "\nHIDDEN in shadows - enemies can't find you"
	if int(h.get("poison", 0)) > 0: line += "\nPOISONED: -1 HP per turn for %d turns" % int(h.poison)
	if combat.surprise_ready(): line += "\nIn cover: your next attack is a SURPRISE (x%.1f, no DR, knockback)" % float(h.surprise_mult)
	status.text = line
	if main and not finished:
		if combat.surprise_ready(): main.tip("surprise")
		if not combat.danger.is_empty(): main.tip("telegraph")
		if combat.traps.values().any(func(t): return not t.hidden): main.tip("trap")
	UIKit.clear(buttons)
	if finished:
		_result_buttons(); _refresh_log(); return
	_btn("Wait", func(): _act(func(): combat.hero_wait()))
	if "shove" in h.abilities:
		_btn("Shove: ON" if mode == "shove" else "Shove", func(): mode = "" if mode == "shove" else "shove"; grid.mode = mode; _refresh())
	if "slam" in h.abilities:
		_btn("Slam (%d)" % h.slams, func(): _act(func(): combat.hero_slam()), int(h.slams) > 0 and combat.enemies().any(func(e): return Combat.cheb(e.pos, h.pos) == 1))
	if not h.cloak.is_empty():
		_btn("Cloak (%d)" % h.cloak_charges, func(): _act(func(): combat.hero_cloak()), int(h.cloak_charges) > 0 and not combat.hidden())
	if not h.bolt.is_empty() and not h.bolt.get("infinite", false):
		_btn("Bolt (%d)" % h.charges, func(): mode = "" if mode == "bolt" else "bolt"; grid.mode = mode; _refresh(), h.charges > 0)
	_btn("Search" if not h.get("searched", false) else "Search again", func(): _act(func(): combat.hero_search()))
	_btn("Potion (%d)" % (potions - potions_used), _drink, potions - potions_used > 0 and h.hp < h.ht)
	_btn("Hint", _hint)
	_btn("Auto: ON" if auto else "Auto", func(): auto = not auto; _refresh())
	_refresh_log()

func _refresh_log() -> void:
	log_label.clear()
	for l in combat.log_lines: log_label.append_text(l + "\n")
	await get_tree().process_frame
	if is_instance_valid(log_scroll): log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

func _on_cell(c: Vector2i) -> void:
	if finished: return
	var u = combat.unit_at(c)
	if u != null and u != combat.hero and Combat.cheb(c, combat.hero.pos) > 1 and not combat.can_bolt(c):
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
func _persist() -> void:
	if GameState.run.has("active_fight"):
		GameState.run.active_fight.combat = combat.to_dict()
		SaveSystem.save_game()

func _inspect(u: Dictionary) -> void:
	var spd := "fast (%.1f ticks)" % u.delay if float(u.delay) < 1.0 else "normal"
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
		Sfx.play("levelup" if combat.won else "death")
	_refresh()

## Potions are consumed from the run supplies immediately (so a lost fight doesn't refund them).
func _drink() -> void:
	if potions - potions_used <= 0: return
	potions_used += 1
	GameState.run.supplies.potion_healing = maxi(0, int(GameState.run.supplies.get("potion_healing", 0)) - 1)
	_act(func(): combat.hero_heal(heal))

func _hint() -> void:
	var s := CombatBot.suggest(combat, potions - potions_used, heal)
	GameState.say("Hint: " + s.why)
	grid.hint_cell = s.get("pos", Vector2i(-1, -1))

func _do_bot() -> void:
	var s := CombatBot.suggest(combat, potions - potions_used, heal)
	match s.act:
		"heal": _drink()
		"wait": _act(func(): combat.hero_wait())
		"cloak": _act(func(): if not combat.hero_cloak(): combat.hero_wait())
		"slam": _act(func(): if not combat.hero_slam(): combat.hero_wait())
		"search": _act(func(): combat.hero_search())
		"tap": _act(func(): if not combat.hero_tap(s.pos, s.mode): combat.hero_wait())

func _result_buttons() -> void:
	if combat.won:
		var txt := "Victory! +%d gold, +%d xp" % [combat.loot, combat.xp]
		if combat.fallen_loot > 0: txt += " (%d fell to the next floor)" % combat.fallen_loot
		buttons.add_child(UIKit.label(txt, 1.0, Color("ffd27a")))
		_btn("Continue", _finish)
	else:
		buttons.add_child(UIKit.label("Defeat... the pack is lost and your gear cracks.", 1.0, Color("ff7070")))
		_btn("Wake at Camp", _finish)

func result() -> Dictionary:
	return {"won": combat.won, "hp": combat.hero.hp, "loot": combat.loot, "fallen_loot": combat.fallen_loot, "xp": combat.xp,
		"boss_killed": combat.boss_killed, "potions_used": potions_used, "kills": combat.kills, "traps_found": combat.traps_found,
		"trap_ids": combat.trap_ids_seen}

func _finish() -> void:
	GameState.run.erase("active_fight")
	on_done.call(result())
