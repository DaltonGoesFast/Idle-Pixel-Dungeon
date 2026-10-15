## DelveScreen: the Delve Bar. Ticks floor progress, shows supplies, and presents encounter cards
## (combat, Door Choice, special rooms, floor cleared, campfire). Rules live in core/delve.gd.
extends Control

const SPEED := 5.0          # % per second (20 s per floor at 1x)

var main: Control
var box: VBoxContainer
var title: Label
var bar: ProgressBar
var stats: VBoxContainer
var pane: StatusPane
var card_host: VBoxContainer
var controls: HFlowContainer
var running := true
var fast := false
var pending: Dictionary = {}   # current event card (pauses the bar)
var portrait := true
var scene: DelveScene

func _ready() -> void:
	box = UIKit.vbox(self); box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pane = StatusPane.new(); box.add_child(pane)
	title = UIKit.header(""); box.add_child(title)
	bar = ProgressBar.new(); bar.custom_minimum_size.y = UIKit.font_size * 1.6; bar.show_percentage = true; box.add_child(bar)
	scene = DelveScene.new(); scene.host = self; scene.custom_minimum_size.y = UIKit.font_size * 7; box.add_child(scene)
	stats = UIKit.vbox(box)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(sc)
	card_host = UIKit.vbox(sc); card_host.size_flags_horizontal = SIZE_EXPAND_FILL
	controls = HFlowContainer.new(); box.add_child(controls)
	GameState.settings_changed.connect(func(): if pending.get("kind", "") == "settings": _show_card())
	if Delve.floor_done(GameState.run) or GameState.run.events.is_empty(): pass
	_refresh_controls()

func apply_layout(p: bool, s: Vector2) -> void:
	portrait = p
	bar.custom_minimum_size.y = UIKit.font_size * 1.6
	# corridor height: a multiple of 5 tile rows; shorter when the inner screen is wide
	scene.custom_minimum_size.y = floorf(minf(s.y * (0.24 if p else 0.26), UIKit.font_size * (10.0 if p else 9.0)) / 5.0) * 5.0
	_refresh_controls(); _show_card()

func on_shown() -> void:
	if pending.is_empty() and GameState.run.has("pending_card"): pending = GameState.run.pending_card
	_refresh(); _show_card()
	main.tip("delve_bar")

var _save_t := 0.0

func _process(delta: float) -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	_save_t += delta
	if _save_t > 3.0:
		_save_t = 0.0; SaveSystem.save_game()
	if main and main.tip_open(): _refresh(); return
	if pending.is_empty() and not run.get("overflow", []).is_empty():
		_open_panel("backpack")   # full-pack loot needs a decision before exploring on
	elif pending.is_empty() and running and GameState.talent_points_total_free(run.hero) > 0 and not run.get("talent_prompted", false):
		run.talent_prompted = true; _open_panel("talents")   # level-up: offer the new talent once
	if GameState.settings.get("full_auto", false): _auto_tick(delta)
	if running and pending.is_empty():
		if Delve.floor_done(run):
			_floor_cleared()
		else:
			var ev := Delve.advance(GameState, delta * SPEED * speed_mult())
			if not ev.is_empty():
				pending = ev; _encounter_cue(ev); _show_card(); SaveSystem.save_game()
	_refresh()

# ---------------------------------------------------------------- Full Auto (DECISIONS #102)
var _auto_t := 0.0
const AUTO_DELAY := 0.8     # seconds a card stays visible before Full Auto acts (so you can watch)

func set_full_auto(on: bool) -> void:
	GameState.settings.full_auto = on
	GameState.log_line("Auto: Full Auto %s." % ("on" if on else "off"), "auto")
	if on: running = true
	SaveSystem.save_game(); _refresh_controls(); _show_card()

func _auto_tick(delta: float) -> void:
	var run: Dictionary = GameState.run
	if pending.is_empty():
		var why := Delve.auto_should_stop(GameState)
		if why != "": set_full_auto(false); running = false; GameState.say("Auto: stopped - %s." % why, "warning"); _refresh_controls(); return
		running = true
		return
	_auto_t += delta
	if _auto_t < AUTO_DELAY: return
	_auto_t = 0.0
	match pending.kind:
		"backpack":
			while not run.get("overflow", []).is_empty(): GameState.resolve_overflow(-1)
			GameState.log_line("Auto: dropped the least valuable item.", "auto"); _close_panel()
		"talents":
			GameState.auto_pick_talents(run.hero); GameState.log_line("Auto: picked talents.", "auto"); _close_panel()
		"settings", "confirm_abandon": pass
		_: auto_act(Delve.auto_decide(GameState, pending))

## Carry out one Full Auto decision on the open card (also used by tests).
func auto_act(d: Dictionary) -> void:
	GameState.log_line("Auto: " + String(d.why), "auto")
	match d.act:
		"fight": _fight(pending, {})
		"door": _choose_door(pending.door[d.side])
		"special":
			if int(d.index) >= 0: _special_option(pending.special.options[int(d.index)])
			else: pending = {}; _show_card()
		"ignore": pending = {}; _show_card()
		"search": GameState.log_line(Delve.search_floor(GameState)); _show_card()
		"descend": Sfx.play("descend"); Delve.descend(GameState); pending = {}; main.play_floor_music(); _show_card()
		"deeper": Sfx.play("descend"); Delve.continue_deeper(GameState); pending = {}; main.play_floor_music(); _show_card()
		"extract": GameState.end_run("extract"); main.show_camp()
		"stop": set_full_auto(false); running = false; GameState.say("Auto: stopped - %s." % d.why, "warning")

## A soft cue when a card opens (the SPD alarm is never used, DECISIONS #100).
func _encounter_cue(ev: Dictionary) -> void:
	match ev.get("kind", ""):
		"door", "special": Sfx.play("door_open")
		"combat": Sfx.buzz(25)

## Delve Bar speed = Settings "Delve speed" x the in-run x3 toggle.
func speed_mult() -> float:
	return float(GameState.settings.get("delve_speed", 1.0)) * (3.0 if fast else 1.0)

var _log_box: VBoxContainer
var _log_serial := -1
const LOG_LINES := 8
## SPD-coloured log under the bar; rebuilt only when a line is added.
func _fill_log() -> void:
	if not is_instance_valid(_log_box) or _log_serial == GameState.log_serial: return
	_log_serial = GameState.log_serial
	UIKit.clear(_log_box)
	var msgs := GameState.messages; var kinds := GameState.message_kinds
	for i in range(maxi(0, msgs.size() - LOG_LINES), msgs.size()):
		var k: String = kinds[i] if i < kinds.size() else "info"
		_log_box.add_child(UIKit.label(msgs[i], 0.8, GameState.LOG_COLORS.get(k, Color("bdb3a0"))))

var _stats_cache := {}
var _stats_key := ""
var _pane_key := ""
var _row_key := ""
## Perf (DECISIONS #99): this runs every frame, so it only touches UI when something visible changed and only
## recomputes hero_stats when level/gear change.
func _refresh() -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	var h: Dictionary = GameState.heroes[run.hero]
	var sk := "%s|%d|%s|%s|%s|%s" % [run.hero, int(h.level), h.weapon, h.armor, h.ring, h.get("artifact", 0)]
	if sk != _stats_key: _stats_key = sk; _stats_cache = GameState.hero_stats(run.hero)
	var s: Dictionary = _stats_cache
	if pending.is_empty(): _fill_log()
	title.text = "%s - Floor %d / %d" % [DB.biomes[run.biome].name, run.floor, DB.biomes[run.biome].floors[1]]
	bar.value = run.progress
	if pane.hero_sprite == null or pane.hero_row != int(s.row): pane.set_hero(s.sprite, int(s.fw), int(s.fh), int(s.row))
	var bl := []
	if Delve.darkness(run): bl.append(16)                      # BLINDNESS
	elif float(run.torch) > 0: bl.append(22)                   # LIGHT
	if float(run.satiety) <= 0: bl.append(6)                   # STARVATION
	elif float(run.satiety) < 30: bl.append(5)                 # HUNGER
	var pk := "%d|%d|%d|%d|%s|%d" % [int(run.hp), int(s.ht), int(run.torch), int(run.satiety), bl, int(run.get("floor", 1))]
	if pk == _pane_key and _row_key == _supplies_key(run): return
	if pk != _pane_key:
		_pane_key = pk
		pane.set_data({"name": s.name, "level": GameState.heroes[run.hero].level, "hp": run.hp, "ht": s.ht, "buffs": bl,
			"depth": "F%d" % int(run.get("floor", 1)),
			"minis": [{"kind": "exp", "frac": float(run.torch) / 100.0, "text": "Torch %d%%" % run.torch},
				{"kind": "shield", "frac": float(run.satiety) / 100.0, "text": "Food %d%%" % run.satiety}]})
	var rk := _supplies_key(run)
	if rk == _row_key: return
	_row_key = rk
	UIKit.clear(stats)
	var line := ""
	if Delve.darkness(run): line += "DARK: no Barrier in fights!   "
	if float(run.satiety) <= 0.0: line += "STARVING"
	if line != "": stats.add_child(UIKit.label(line, 0.95, Color("ff7070")))
	var flow := HFlowContainer.new(); stats.add_child(flow)
	flow.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.9))
	flow.add_theme_constant_override("v_separation", int(UIKit.font_size * 0.25))
	for k in run.supplies:
		if int(run.supplies[k]) > 0: flow.add_child(UIKit.res_chip(k, str(run.supplies[k])))
	var pl := UIKit.label("Pack:", 0.85, Color("c9a96e")); pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(pl)
	for k in run.pack:
		if int(run.pack[k]) > 0: flow.add_child(UIKit.res_chip(k, str(run.pack[k])))
	if not run.pack_gear.is_empty():
		var il := UIKit.label("+%d items" % run.pack_gear.size(), 0.85); il.autowrap_mode = TextServer.AUTOWRAP_OFF; flow.add_child(il)

func _supplies_key(run: Dictionary) -> String:
	return "%s|%s|%d|%s|%s" % [run.supplies, run.pack, run.pack_gear.size(), Delve.darkness(run), float(run.satiety) <= 0.0]

func _refresh_controls() -> void:
	if controls == null: return
	UIKit.clear(controls)
	var w := UIKit.font_size * 7.0
	var b1 := UIKit.button("Pause" if running else "Resume", func(): running = not running; _refresh_controls()); b1.custom_minimum_size.x = w
	var b2 := UIKit.button("Speed x3" if not fast else "Speed x1", func(): fast = not fast; _refresh_controls()); b2.custom_minimum_size.x = w
	UIKit.as_toolbar(b1, "sleep" if running else "arrow"); UIKit.as_toolbar(b2, "busy")
	var fa: bool = GameState.settings.get("full_auto", false)
	var b0 := UIKit.button("Full Auto: ON" if fa else "Full Auto", func(): set_full_auto(not GameState.settings.get("full_auto", false))); b0.custom_minimum_size.x = w
	UIKit.as_toolbar(b0, "busy"); b0.name = "FullAuto"
	controls.add_child(b1); controls.add_child(b2); controls.add_child(b0)
	if int(GameState.run.get("supplies", {}).get("scroll_passage", 0)) > 0:
		var b3 := UIKit.button("Read Scroll of Passage (extract)", func():
			GameState.run.supplies.scroll_passage -= 1; Sfx.play("read"); GameState.end_run("extract"); main.show_camp()); b3.custom_minimum_size.x = w * 2
		controls.add_child(b3)
	var nfree := GameState.talent_points_total_free(GameState.run.hero) if not GameState.run.is_empty() else 0
	var bb := UIKit.button("Backpack %d/%d" % [GameState.backpack_used(), GameState.BACKPACK_SLOTS], func(): _open_panel("backpack")); bb.custom_minimum_size.x = w
	UIKit.as_toolbar(bb, "backpack"); controls.add_child(bb)
	var bt := UIKit.button("Talents" + (" (%d!)" % nfree if nfree > 0 else ""), func(): _open_panel("talents")); bt.custom_minimum_size.x = w
	UIKit.as_toolbar(bt, "talent"); controls.add_child(bt)
	var b5 := UIKit.button("Settings", func(): _open_panel("settings")); b5.custom_minimum_size.x = w
	UIKit.as_toolbar(b5, "prefs"); controls.add_child(b5)
	var b4 := UIKit.button("Abandon run", _confirm_abandon); b4.custom_minimum_size.x = w
	UIKit.as_toolbar(b4, "exit"); controls.add_child(b4)

## Backpack / Talents cards pause the bar; closing resumes it.
## Opening over an encounter card (door, campfire...) remembers it and brings it back on close.
var _under := {}
func _open_panel(kind: String) -> void:
	if not pending.is_empty() and pending.kind == "combat": return
	if not pending.is_empty() and not (pending.kind in ["backpack", "talents", "settings"]): _under = pending
	running = false; pending = {"kind": kind}; _refresh_controls(); _show_card()
	if main:
		for t in main.toast_box.get_children(): t.queue_free()

func _close_panel() -> void:
	pending = _under; _under = {}
	running = pending.is_empty(); _refresh_controls(); _show_card()

func _confirm_abandon() -> void:
	pending = {"kind": "confirm_abandon"}; _show_card()

# ------------------------------------------------------------ cards
func _card(title_text: String, body: String) -> VBoxContainer:
	UIKit.clear(card_host)
	var c := UIKit.card(); card_host.add_child(c)
	var v := UIKit.vbox(c)
	v.add_child(UIKit.header(title_text))
	if body != "": v.add_child(UIKit.label(body))
	return v

func _show_card() -> void:
	if card_host == null: return
	UIKit.clear(card_host)
	# remember the open card in the save (an app kill must not skip an encounter)
	if not GameState.run.is_empty():
		if pending.is_empty() or pending.kind in ["confirm_abandon", "settings", "backpack", "talents"]: GameState.run.erase("pending_card")
		else: GameState.run.pending_card = pending
	if pending.is_empty():
		var hint := "Exploring... encounters every ~20-25%." if running else "Paused."
		card_host.add_child(UIKit.label(hint, 0.9, Color("9a8f7c")))
		_log_box = UIKit.vbox(card_host); _log_serial = -1; _fill_log()
		return
	if main and pending.kind in ["door", "special", "floor_done", "campfire"]: main.tip(pending.kind)
	match pending.kind:
		"combat": _card_combat()
		"door": _card_door()
		"special": _card_special()
		"floor_done": _card_floor()
		"campfire": _card_campfire()
		"backpack":
			HeroPanels.backpack(card_host, func(): _refresh(); _refresh_controls(); _show_card())
			if GameState.run.get("overflow", []).is_empty(): card_host.add_child(UIKit.button("Close", _close_panel))
		"talents":
			HeroPanels.talents(card_host, GameState.run.hero, func(): _refresh(); _refresh_controls(); _show_card())
			card_host.add_child(UIKit.button("Close", _close_panel))
		"settings":
			var v := _card("Settings", "")
			SettingsPanel.build(v, false)
			v.add_child(UIKit.button("Close", _close_panel))
		"confirm_abandon":
			var v := _card("Abandon the expedition?", "Everything in your pack is lost. Unused supplies return to the stash.")
			v.add_child(UIKit.button("Abandon", func(): GameState.end_run("abandon"); main.show_camp()))
			v.add_child(UIKit.button("Keep delving", func(): pending = {}; _show_card()))

func _mob_names(ids: Array) -> String:
	return ", ".join(ids.map(func(m): return DB.mobs[m].name))

func _card_combat() -> void:
	var boss: bool = pending.get("boss", false)
	var v := _card("BOSS: " + DB.mobs[pending.mobs[0]].name if boss else "Ambush!", "You face: " + _mob_names(pending.mobs))
	v.add_child(UIKit.button("Fight", func(): _fight(pending, {})))

func _fight(ev: Dictionary, reward: Dictionary, saved := {}) -> void:
	GameState.run.erase("pending_card")
	GameState.run.active_fight = {"event": ev, "reward": reward, "combat": saved}
	main.start_combat(ev, func(res: Dictionary): _after_fight(ev, res, reward), saved)
	SaveSystem.save_game()

## Called on launch when the save holds an unfinished fight.
func resume_fight() -> void:
	var af: Dictionary = GameState.run.active_fight
	_fight(af.event, af.get("reward", {}), af.get("combat", {}))

func _after_fight(ev: Dictionary, res: Dictionary, reward: Dictionary) -> void:
	pending = {}
	var lvl: int = GameState.heroes[GameState.run.hero].level
	if not Delve.apply_fight_result(GameState, ev, res, reward):
		Sfx.play("death")
		GameState.end_run("death"); main.show_camp(); return
	if GameState.heroes[GameState.run.hero].level > lvl:
		Sfx.play("levelup"); GameState.run.talent_prompted = false
	main.end_combat()

func _card_door() -> void:
	var d: Dictionary = pending.door
	var v := _card("Two doors...", "Choose your path.")
	for side in ["a", "b"]:
		var o: Dictionary = d[side]
		var cost: Dictionary = o.get("cost", {})
		var label: String = o.text
		if o.kind == "combat": label += "  [fight: %s]" % _mob_names(o.mobs)
		if not cost.is_empty(): label += "  [costs %s]" % GameState.cost_text(cost)
		var ok := cost.is_empty() or Delve.pay_possible(GameState, cost)
		v.add_child(UIKit.action(label, func(): _choose_door(o), "" if ok else "can't afford"))
	v.add_child(UIKit.secondary(UIKit.button("Ignore both", func(): pending = {}; _show_card())))

func _choose_door(o: Dictionary) -> void:
	Sfx.play("door_open"); GameState.log_line("Chose: " + String(o.text), "info")
	match o.kind:
		"combat":
			var ev := Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 77), o.mobs)
			_fight(ev, o.get("reward", {}))
		"chest":
			if Delve.pay(GameState, o.get("cost", {})):
				Sfx.play("unlock")
				GameState.say("Chest: " + Delve.reward(GameState, o.reward))
			pending = {}; _show_card(); GameState.touch()
		"special":
			pending = Delve.build_event(GameState.run, {"kind": "special", "salt": 99}); _show_card()

func _card_special() -> void:
	var sp: Dictionary = pending.special
	var v := _card(sp.title, "")
	var top := UIKit.hbox(v)   # special-room art + text (DECISIONS #86)
	if sp.has("icon"): top.add_child(UIKit.icon(sp.icon, int(UIKit.font_size * 3)))
	var tl := UIKit.label(sp.text); tl.size_flags_horizontal = SIZE_EXPAND_FILL; top.add_child(tl)
	for o in sp.options:
		var cost: Dictionary = o.get("cost", {})
		var ok := cost.is_empty() or Delve.pay_possible(GameState, cost)
		var why := "" if ok else "can't afford"
		if o.has("requires_class") and o.requires_class != GameState.run.hero: why = "%s only" % DB.heroes[o.requires_class].name
		v.add_child(UIKit.action(o.text, func(): _special_option(o), why))

func _special_option(o: Dictionary) -> void:
	GameState.log_line("Chose: " + String(o.text), "info")
	if o.has("fight"):
		# "biome": a regular encounter of this biome/floor (garden grass, sacrificial fire - DECISIONS #91)
		var ev := Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 55), [] if typeof(o.fight) == TYPE_STRING else o.fight)
		_fight(ev, o.get("reward", {})); return
	if o.has("cost") and not Delve.pay(GameState, o.cost): return
	if o.get("secret", false): GameState.add_stat("hidden_doors", 1)
	if o.has("reward"):
		Sfx.play("secret" if o.get("secret", false) else "item"); GameState.say(Delve.reward(GameState, o.reward))
	pending = {}; _show_card(); GameState.touch()

func _floor_cleared() -> void:
	var run: Dictionary = GameState.run
	if Delve.is_campfire(run): pending = {"kind": "campfire"}
	else: pending = {"kind": "floor_done"}
	_show_card()

func _card_floor() -> void:
	var run: Dictionary = GameState.run
	var v := _card("Floor %d cleared" % run.floor, "Descending heals %d%% of max HP. Extraction is only possible at a boss campfire or with a Scroll of Passage." % int(Delve.FLOOR_REST_HEAL * 100))
	if int(run.get("searched_floor", 0)) != int(run.floor):
		var hint := " (Rogue: always finds it)" if run.hero == "rogue" else " (%d%% chance)" % Delve.SEARCH_CHANCE
		v.add_child(UIKit.action("Search for hidden doors (-%d torch)%s" % [int(Delve.SEARCH_TORCH), hint], func():
			var msg := Delve.search_floor(GameState)
			Sfx.play("secret" if msg.begins_with("A hidden") else "scan"); GameState.say(msg); _show_card(); GameState.touch(),
			"" if Delve.can_search_floor(run) else "not enough torch"))
	v.add_child(UIKit.button("Descend to floor %d" % (int(run.floor) + 1), func():
		Sfx.play("descend"); Delve.descend(GameState); pending = {}; main.play_floor_music(); _show_card()))

func _card_campfire() -> void:
	var run: Dictionary = GameState.run
	var boss: String = DB.mobs[DB.biomes[run.biome].boss].name
	var nb := Delve.next_biome(run)
	var txt := "%s is defeated. Rest here and extract with 100%% of your pack" % boss
	if nb != "": txt += ", or press on into the %s (floors %d-%d, %d Str recommended) - nothing is banked until you extract." % [DB.biomes[nb].name, DB.biomes[nb].floors[0], DB.biomes[nb].floors[1], DB.biomes[nb].str_gate]
	else: txt += ". This is the deepest biome in this build."
	var v := _card("Campfire", txt)
	v.add_child(UIKit.button("Extract to Camp", func(): Sfx.play("mastery"); GameState.end_run("extract"); main.show_camp()))
	if nb != "":
		v.add_child(UIKit.button("Descend into the %s" % DB.biomes[nb].name, func():
			Sfx.play("descend"); Delve.continue_deeper(GameState); pending = {}; main.play_floor_music(); _show_card()))

## main._toast: while a Backpack/Talents/Settings panel is open the message goes into the panel, not over it (DECISIONS #85).
func window_toast(text: String) -> bool:
	if pending.is_empty() or not (pending.kind in ["backpack", "talents", "settings"]) or card_host == null: return false
	var l := UIKit.label(text, 0.85, Color("ffff88")); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_host.add_child(l); card_host.move_child(l, 0)
	var tw := l.create_tween(); tw.tween_interval(3.5); tw.tween_property(l, "modulate:a", 0.0, 0.6); tw.tween_callback(l.queue_free)
	return true
