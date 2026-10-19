## CombatScreen: hosts GridView + controls (Wait, Shove/Bolt modes, Potion, Hint/Auto) + scrollable log.
## Portrait (Fold cover): grid on top, panel below. Wide (Fold inner): grid left, panel right.
extends Control

const GridView := preload("res://scripts/ui/grid_view.gd")

var main: Control
var combat: Combat
var on_done: Callable
var event: Dictionary
var reward: Dictionary = {}
var split: BoxContainer
var grid
var side: VBoxContainer
var status: Label
var pane: StatusPane
var buttons: HFlowContainer
var log_scroll: ScrollContainer
var log_label: RichTextLabel
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
var guide := 0
var guide_label: Label

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
	split = BoxContainer.new(); add_child(split); split.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 12)
	grid = GridView.new(); grid.tapped.connect(_on_cell)
	if not GameState.run.is_empty():
		grid.tileset = DB.biomes[GameState.run.biome].tile
		grid.water_name = DB.biomes[GameState.run.biome].get("water", "water0")
		grid.lighting = bool(GameState.settings.get("lighting", true))
	split.add_child(grid)
	grid.set_combat(combat)
	side = UIKit.vbox(split); side.size_flags_horizontal = SIZE_EXPAND_FILL; side.size_flags_vertical = SIZE_EXPAND_FILL
	side.add_child(UIKit.header("BOSS: " + DB.mobs[event.mobs[0]].name if event.get("boss", false) else "Combat"))
	if not event.get("boss", false) and bool(GameState.settings.get("tutorial", true)) and not ("guided_fight" in GameState.tutorial_done):
		guide = 1
		guide_label = UIKit.label("", 1.0, Color("9fd3ff")); guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(guide_label)
	pane = StatusPane.new(); side.add_child(pane)
	var hs0 := combat.hero
	pane.set_hero(String(hs0.sprite), int(hs0.fw), int(hs0.fh), int(hs0.get("row", 0)))
	status = UIKit.label(""); side.add_child(status)
	buttons = HFlowContainer.new(); side.add_child(buttons)
	log_scroll = ScrollContainer.new(); log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size.y = UIKit.font_size * 4
	var bg := UIKit.chrome("toast", Color(0.75, 0.75, 0.75))
	log_scroll.add_theme_stylebox_override("panel", bg)
	side.add_child(log_scroll)
	log_label = RichTextLabel.new(); log_label.fit_content = true; log_label.scroll_active = false
	log_label.size_flags_horizontal = SIZE_EXPAND_FILL; log_scroll.add_child(log_label)
	_refresh()
	if main: main.tip("boss" if event.get("boss", false) else "first_fight")

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
	if finished: return
	if passage_confirm: return
	if auto:
		_auto_t += d
		if _auto_t > 0.35:
			_auto_t = 0.0; _do_bot()

const BTN_ICONS := {"Wait": "wait", "Search": "search", "Search again": "search", "Bag": "backpack", "Hint": "info",
	"Auto": "busy", "Auto: ON": "busy", "Shove": "arrow", "Shove: ON": "arrow", "Scroll of Passage": "scroll"}
const BTN_PREFIX_ICONS := {"Slam": "warning", "Potion": "plus", "Cloak": "buffs", "Bolt": "target", "Scroll of Passage": "scroll"}
func _btn(text: String, cb: Callable, enabled := true) -> void:
	var b := UIKit.button(text, cb, enabled)
	b.custom_minimum_size.x = UIKit.font_size * 6.5
	var ic: String = BTN_ICONS.get(text, "")
	for pre in BTN_PREFIX_ICONS:
		if text.begins_with(pre): ic = BTN_PREFIX_ICONS[pre]
	UIKit.as_toolbar(b, ic)   # SPD toolbar slots for in-fight actions
	buttons.add_child(b)

func _refresh() -> void:
	if status == null: return
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
	pane.set_data({"name": h.name, "level": lvl, "hp": h.hp, "ht": h.ht, "shield": h.barrier, "buffs": bl,
		"depth": ("F%d" % int(run.get("floor", 1))) if not run.is_empty() else "",
		"danger": combat.enemies().filter(func(e): return e.hp > 0).size(), "minis": minis})
	var line := "DR %d  Dmg %d%s   t=%.1f" % [h.dr, h.dmg, ("  Reach %d" % int(h.reach)) if int(h.get("reach", 1)) > 1 else "", combat.time]
	if not h.bolt.is_empty():
		if h.bolt.get("infinite", false): line += "\nTap any tile in range to shoot %s (%d dmg; it passes tall grass)" % [h.bolt.name, h.bolt.dmg]
		else: line += "\nStaff charges %d/%d (%s, %d dmg, ignores DR)" % [h.charges, h.bolt.charges, h.bolt.name, h.bolt.dmg]
	if combat.hidden(): line += "\nHIDDEN in shadows - enemies can't find you"
	if int(h.get("poison", 0)) > 0: line += "\nPOISONED: -1 HP per turn for %d turns" % int(h.poison)
	if combat.surprise_now(): line += "\nThey lost sight of you: next attack is a SURPRISE (x%.1f, no DR, knockback)" % float(h.surprise_mult)
	if combat.enemies().any(func(e): return e.get("evade_unless_surprise", false)):
		line += "\nSnake: melee needs a Surprise; magic always hits, bows after the first shot"
	status.text = line
	status.visible = not finished
	_guide_update()
	if main and not finished:
		# Don't pop the Surprise modal over the guided first fight (steps 1-3): an unseen foe in tall grass makes
		# surprise_ready() true from turn 0, which hid the step banner and froze _process until Next (DECISIONS #139).
		if combat.surprise_ready() and (guide == 0 or guide >= 4): main.tip("surprise")
		if not combat.danger.is_empty(): main.tip("telegraph")
		if combat.traps.values().any(func(t): return not t.hidden): main.tip("trap")
	UIKit.clear(buttons)
	if finished:
		_result_buttons(); _refresh_log(); _refresh_bag(); _refresh_passage(); return
	_btn("Wait", func(): _act(func(): combat.hero_wait()))
	if "shove" in h.abilities:
		_btn("Shove: ON" if mode == "shove" else "Shove", func(): mode = "" if mode == "shove" else "shove"; grid.mode = mode; _refresh())
	if "slam" in h.abilities:
		_btn("Slam (%d)" % h.slams, func(): _act(func(): combat.hero_slam()), int(h.slams) > 0 and combat.enemies().any(func(e): return Combat.cheb(e.pos, h.pos) == 1))
	if not h.cloak.is_empty():
		_btn("Cloak (%d/%d)" % [int(h.cloak_charges), _cloak_cap(h)], func(): _act(func(): combat.hero_cloak()), int(h.cloak_charges) > 0 and not combat.hidden())
	if not h.bolt.is_empty() and not h.bolt.get("infinite", false):
		_btn("Bolt (%d)" % h.charges, func(): mode = "" if mode == "bolt" else "bolt"; grid.mode = mode; _refresh(), h.charges > 0)
	_btn("Search" if not h.get("searched", false) else "Search again", func(): _act(func(): combat.hero_search()))
	_btn("Potion (%d)" % (potions - potions_used), _drink, potions - potions_used > 0 and h.hp < h.ht)
	if Delve.scroll_passage_count(GameState) > 0:
		_btn("Scroll of Passage", _ask_passage)
	_btn("Bag", func(): bag_open = not bag_open; set_meta("bag_scroll", 0); _refresh())
	_btn("Hint", _hint)
	_btn("Auto: ON" if auto else "Auto", func(): auto = not auto; _refresh())
	_refresh_log()
	_refresh_bag()
	_refresh_passage()

## In-combat Bag: swap weapon/armor/ring/wand from the backpack; costs the hero's turn (1 tick).
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
	HeroPanels.backpack(body, _refresh, true, _equip_in_combat)
	var keep := int(get_meta("bag_scroll", 0))
	(func(): if is_instance_valid(sc): sc.scroll_vertical = keep).call_deferred()

func _equip_in_combat() -> void:
	bag_open = false
	var hs := GameState.hero_stats(GameState.run.hero)
	_act(func(): combat.apply_stats(hs); combat._log("%s swaps gear." % combat.hero.name); combat.hero_wait())
	heal = GameState.potion_heal(GameState.run.hero)

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
			guide_label.text = "Step 1/3 - Move: tap the glowing tile to step toward the enemy. Each action costs time; enemies act on the same clock."
			if not foes.is_empty():
				var st = combat.path_step(h.pos, foes[0].pos, true, true, true)
				if st != null: grid.hint_cell = st
		2:
			guide_label.text = "Step 2/3 - Attack: tap the glowing enemy next to you."
			grid.hint_cell = adj[0].pos if not adj.is_empty() else Vector2i(-1, -1)
		3:
			guide_label.text = "Step 3/3 - Finish it! Blue bar = Barrier (soaks hits first, refills each fight). Red tiles = an attack is coming: step off. Stuck? Tap Hint."
	grid.queue_redraw()

func _refresh_log() -> void:
	log_label.clear()
	for l in combat.log_lines: log_label.append_text(l + "\n")
	await get_tree().process_frame
	if is_instance_valid(log_scroll): log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

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
		if combat.loot > 0: got.append("+%d Gold" % combat.loot)
		if combat.fallen_loot > 0: got.append("+%d Gold on the next floor" % combat.fallen_loot)
		if combat.xp > 0: got.append("+%d XP" % combat.xp)
		if potions_used > 0: lost.append("-%d %s" % [potions_used, DB.display_name("potion_healing")])
		_summary = {"got": got, "lost": lost}

func _result_buttons() -> void:
	if combat.won:
		_ensure_victory_summary()
		var card := UIKit.card()
		card.name = "VictoryResults"
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.add_child(card)
		var box := UIKit.vbox(card, int(UIKit.font_size * 0.25))
		box.size_flags_horizontal = SIZE_EXPAND_FILL
		box.add_child(UIKit.header("Victory"))
		_result_section(box, "Got", _summary.got, GameState.LOG_COLORS.positive)
		if not _summary.lost.is_empty():
			_result_section(box, "Lost", _summary.lost, GameState.LOG_COLORS.negative)
		var row := UIKit.hbox(box)
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", int(UIKit.font_size * 0.3))
		var cont := UIKit.button("Continue", _finish)
		var pause := UIKit.button("Continue and pause", _finish_paused, true,
			"Turns off x3 speed and Auto Battle, then pauses the delve.")
		var bh := UIKit.btn_height() + UIKit.font_px(UIKit.font_size)
		for b in [cont, pause]:
			b.custom_minimum_size = Vector2(UIKit.font_size * 6.5, bh)
			UIKit.as_toolbar(b)
			row.add_child(b)
	else:
		buttons.add_child(UIKit.label("Defeat... the pack is lost and your gear cracks.", 1.0, Color("ff7070")))
		_btn("Wake at Camp", _finish)

func _result_section(parent: Node, heading: String, lines: PackedStringArray, color: Color) -> void:
	parent.add_child(UIKit.label(heading, 1.0, color))
	if lines.is_empty():
		parent.add_child(UIKit.label("Nothing", 0.9, Color("9a8f7c")))
		return
	for s in lines:
		parent.add_child(UIKit.label(s, 0.9, color))

func result() -> Dictionary:
	var r := {"won": combat.won, "hp": combat.hero.hp, "loot": combat.loot, "fallen_loot": combat.fallen_loot, "xp": combat.xp,
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
