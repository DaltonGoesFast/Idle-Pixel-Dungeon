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
	if _summary_on: _build_summary()

func on_shown() -> void:
	if pending.is_empty() and GameState.run.has("pending_card"): pending = GameState.run.pending_card
	_refresh(); _show_card()
	main.tip("delve_bar")

var _save_t := 0.0

func _process(delta: float) -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	_expire_card_toasts()
	_save_t += delta
	if _save_t > 3.0:
		_save_t = 0.0; SaveSystem.save_game()
	if main and main.tip_open(): _refresh(); return
	if _summary_on:
		_refresh(); return
	var held := _is_encounter(_under)
	if pending.is_empty() and not held and not run.get("overflow", []).is_empty():
		_open_panel("backpack")   # full-pack loot needs a decision before exploring on
	elif pending.is_empty() and not held and running and GameState.talent_points_total_free(run.hero) > 0 and not run.get("talent_prompted", false):
		run.talent_prompted = true; _open_panel("talents")   # level-up: offer the new talent once
	if GameState.settings.get("full_auto", false): _auto_tick(delta)
	# A closed encounter is still unresolved: the bar must not walk past it.
	if running and pending.is_empty() and not _is_encounter(_under):
		if Delve.floor_done(run):
			_floor_cleared()
		else:
			var ev := Delve.advance(GameState, delta * SPEED * speed_mult())
			if not ev.is_empty():
				pending = ev; _encounter_cue(ev); _show_card(); SaveSystem.save_game()
	_refresh()

# ---------------------------------------------------------------- Auto Battle (DECISIONS #105)
var _auto_t := 0.0
const AUTO_DELAY := 0.8     # seconds an ambush stays visible before Auto Battle starts the fight

func set_full_auto(on: bool) -> void:
	GameState.settings.full_auto = on
	GameState.log_line("Auto battle %s." % ("on" if on else "off"), "auto")
	if on: running = true
	SaveSystem.save_game(); _refresh_controls(); _show_card()

func _stop_auto_low_hp() -> void:
	GameState.settings.full_auto = false
	running = false
	_auto_t = 0.0
	var msg := "Low HP! Auto battle off - take control or use Scroll of Passage." if Delve.scroll_passage_count(GameState) > 0 else "Low HP! Auto battle off - take manual control."
	GameState.log_line(msg, "warning")
	SaveSystem.save_game(); _refresh_controls(); _show_card()

## Plays ambushes only. Doors, rooms, floor ends, campfires, backpack, and talents wait for the player.
## Stops and pauses when close to dying so the player can take control or use a Scroll of Passage.
func _auto_tick(delta: float) -> void:
	if Delve.close_to_dying(GameState):
		_stop_auto_low_hp()
		return
	if pending.get("kind", "") != "combat":
		_auto_t = 0.0
		return
	if not running: return
	_auto_t += delta
	if _auto_t < AUTO_DELAY: return
	_auto_t = 0.0
	GameState.log_line("Auto: fight %s." % _mob_names(pending.get("mobs", [])), "auto")
	_fight(pending, {})

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
var _log_limit := LOG_LINES
var _haul_label: Label
var _haul_text := ""
const LOG_LINES := 8
const CARD_LOG_LINES := 4
## SPD-coloured log under the bar; rebuilt only when a line is added.
## The haul line stays pinned above it and updates in place as gold and materials come in.
func _mount_log(limit: int = LOG_LINES, show_haul := true) -> void:
	if show_haul:
		_haul_label = UIKit.label("", 0.8, GameState.LOG_COLORS.positive)
		_haul_text = "\t"
		card_host.add_child(_haul_label)
	else:
		_haul_label = null
	_log_limit = limit
	_log_box = UIKit.vbox(card_host)
	_log_box.name = "DelveLog"
	_log_serial = -1
	_fill_log()

func _fill_log() -> void:
	_sync_haul()
	if not is_instance_valid(_log_box) or _log_serial == GameState.log_serial: return
	_log_serial = GameState.log_serial
	UIKit.clear(_log_box)
	var msgs := GameState.messages; var kinds := GameState.message_kinds
	for i in range(maxi(0, msgs.size() - _log_limit), msgs.size()):
		var k: String = kinds[i] if i < kinds.size() else "info"
		_log_box.add_child(UIKit.label(msgs[i], 0.8, GameState.LOG_COLORS.get(k, Color("bdb3a0"))))

func _sync_haul() -> void:
	if not is_instance_valid(_haul_label): return
	var t := GameState.haul_line()
	if t == _haul_text: return
	_haul_text = t
	_haul_label.text = t
	_haul_label.visible = t != ""

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
	_fill_log()
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
	var b1 := UIKit.button("Pause" if running else "Resume", func():
		if not running and pending.is_empty() and _is_encounter(_under):
			running = true; _restore_encounter(); return   # Resume reopens the waiting encounter, it does not skip it
		running = not running; _refresh_controls()); b1.custom_minimum_size.x = w
	var b2 := UIKit.button("Speed x3" if not fast else "Speed x1", func(): fast = not fast; _refresh_controls()); b2.custom_minimum_size.x = w
	UIKit.as_toolbar(b1, "sleep" if running else "arrow"); UIKit.as_toolbar(b2, "busy")
	var fa: bool = GameState.settings.get("full_auto", false)
	var b0 := UIKit.button("Auto Battle: ON" if fa else "Auto Battle", func(): set_full_auto(not GameState.settings.get("full_auto", false)), true, "Plays fights for you. Doors, rooms, and campfires still wait.")
	b0.custom_minimum_size.x = w * 1.6
	UIKit.as_toolbar(b0, "busy"); b0.name = "FullAuto"
	controls.add_child(b1); controls.add_child(b2); controls.add_child(b0)
	if Delve.scroll_passage_count(GameState) > 0:
		var b3 := UIKit.button("Read Scroll of Passage (extract)", func():
			if Delve.use_scroll_passage(GameState) and main: main.show_camp()); b3.custom_minimum_size.x = w * 2
		UIKit.as_toolbar(b3, "scroll")
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

## Backpack / Talents / Settings pause the bar; closing brings back whatever encounter was open.
## Closing an encounter card only sets it aside (`_under`) so the bag and settings stay reachable.
var _under := {}

func _is_encounter(p: Dictionary) -> bool:
	return p.get("kind", "") in ["combat", "door", "special", "floor_done", "campfire"]

func _open_panel(kind: String) -> void:
	if _is_encounter(pending): _under = pending
	running = false; pending = {"kind": kind}; _refresh_controls(); _show_card()

func _close_panel() -> void:
	pending = _under; _under = {}
	running = pending.is_empty(); _refresh_controls(); _show_card()

## Hide the encounter card without resolving it. The bar stays put until it is dealt with.
func _dismiss_encounter() -> void:
	if not _is_encounter(pending): return
	_under = pending; pending = {}
	_refresh_controls(); _show_card()

func _restore_encounter() -> void:
	if not _is_encounter(_under): return
	pending = _under; _under = {}
	_refresh_controls(); _show_card()

func _encounter_name(p: Dictionary) -> String:
	match p.get("kind", ""):
		"combat":
			if p.get("boss", false) and not p.get("mobs", []).is_empty(): return DB.mobs[p.mobs[0]].name
			return "Ambush"
		"door": return "The doors"
		"special": return String(p.get("special", {}).get("title", "The room"))
		"floor_done": return "The stairs"
		"campfire": return "The campfire"
		_: return "The encounter"

func _add_close(v: VBoxContainer) -> void:
	v.add_child(UIKit.secondary(UIKit.button("Close", _dismiss_encounter)))

func _confirm_abandon() -> void:
	if _is_encounter(pending): _under = pending
	running = false; pending = {"kind": "confirm_abandon"}; _show_card()

func _cancel_abandon() -> void:
	pending = _under; _under = {}
	running = pending.is_empty(); _refresh_controls(); _show_card()

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
	_log_box = null
	_haul_label = null
	# remember the open card in the save (an app kill must not skip an encounter, even one set aside)
	if not GameState.run.is_empty():
		var remembered := pending if _is_encounter(pending) else (_under if _is_encounter(_under) else {})
		if remembered.is_empty(): GameState.run.erase("pending_card")
		else: GameState.run.pending_card = remembered
	if pending.is_empty():
		_card_toasts.clear()
		_clear_floating_toasts()
		if _is_encounter(_under):
			card_host.add_child(UIKit.label("%s is waiting." % _encounter_name(_under), 0.95, Color("ffd27a")))
			card_host.add_child(UIKit.button("Return to encounter", _restore_encounter))
		var hint := "The bar holds until you deal with the encounter." if _is_encounter(_under) else ("Exploring... encounters every ~20-25%." if running else "Paused.")
		card_host.add_child(UIKit.label(hint, 0.9, Color("9a8f7c")))
		_mount_log(LOG_LINES, true)
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
			v.add_child(UIKit.button("Keep delving", _cancel_abandon))
	_take_floating_toast()
	_mount_card_toast()
	if _is_encounter(pending):
		_mount_log(CARD_LOG_LINES, false)

func _mob_names(ids: Array) -> String:
	return ", ".join(ids.map(func(m): return DB.mobs[m].name))

func _card_combat() -> void:
	var boss: bool = pending.get("boss", false)
	var v := _card("BOSS: " + DB.mobs[pending.mobs[0]].name if boss else "Ambush!", "You face: " + _mob_names(pending.mobs))
	_add_close(v)
	v.add_child(UIKit.button("Fight", func(): _fight(pending, {})))
	if Delve.scroll_passage_count(GameState) > 0:
		v.add_child(UIKit.button("Read Scroll of Passage (extract)", func():
			if Delve.use_scroll_passage(GameState) and main: main.show_camp()))

func _fight(ev: Dictionary, reward: Dictionary, saved := {}) -> void:
	_under = {}
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
	var before := Delve.ledger(GameState)
	var lvl: int = GameState.heroes[GameState.run.hero].level
	if not Delve.apply_fight_result(GameState, ev, res, reward):
		Sfx.play("death")
		if main: main.end_combat()
		var loss: Dictionary = Delve.defeat_changes(GameState, before, res)
		_open_summary("Defeat", loss.got, loss.lost, _defeat_ok, true, loss.note)
		return
	if GameState.heroes[GameState.run.hero].level > lvl:
		Sfx.play("levelup"); GameState.run.talent_prompted = false
	var gain := Delve.fight_changes(before, Delve.ledger(GameState), res)
	if Delve.close_to_dying(GameState) and GameState.settings.get("full_auto", false):
		_stop_auto_low_hp()
	if main: main.end_combat()
	_open_summary("Victory", gain.got, gain.lost)

func _defeat_ok() -> void:
	GameState.end_run("death")
	if main: main.show_camp()

func _card_door() -> void:
	var d: Dictionary = pending.door
	var v := _card("Two doors...", "Choose your path.")
	_add_close(v)
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
			var before := Delve.ledger(GameState)
			if Delve.pay(GameState, o.get("cost", {})):
				var mid := Delve.ledger(GameState)
				Sfx.play("unlock")
				GameState.say("Chest: " + Delve.reward(GameState, o.reward))
				var after := Delve.ledger(GameState)
				pending = {}; _show_card(); GameState.touch()
				_show_trade(String(o.get("text", "Chest")), before, mid, after)
			else:
				pending = {}; _show_card(); GameState.touch()
		"special":
			pending = Delve.build_event(GameState.run, {"kind": "special", "salt": 99}); _show_card()

func _card_special() -> void:
	var sp: Dictionary = pending.special
	var v := _card(sp.title, "")
	_add_close(v)
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
	var before := Delve.ledger(GameState)
	if o.has("cost") and not Delve.pay(GameState, o.cost): return
	var mid := Delve.ledger(GameState)
	if o.get("secret", false): GameState.add_stat("hidden_doors", 1)
	if o.has("reward"):
		Sfx.play("secret" if o.get("secret", false) else "item"); GameState.say(Delve.reward(GameState, o.reward))
	var after := Delve.ledger(GameState)
	pending = {}; _show_card(); GameState.touch()
	_show_trade(String(o.get("text", "The room")), before, mid, after)

func _floor_cleared() -> void:
	var run: Dictionary = GameState.run
	if Delve.is_campfire(run): pending = {"kind": "campfire"}
	else: pending = {"kind": "floor_done"}
	_show_card()

func _card_floor() -> void:
	var run: Dictionary = GameState.run
	var v := _card("Floor %d cleared" % run.floor, "Descending heals %d%% of max HP. Extraction is only possible at a boss campfire or with a Scroll of Passage." % int(Delve.FLOOR_REST_HEAL * 100))
	_add_close(v)
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
	_add_close(v)
	v.add_child(UIKit.button("Extract to Camp", func(): Sfx.play("mastery"); GameState.end_run("extract"); main.show_camp()))
	if nb != "":
		v.add_child(UIKit.button("Descend into the %s" % DB.biomes[nb].name, func():
			Sfx.play("descend"); Delve.continue_deeper(GameState); pending = {}; main.play_floor_music(); _show_card()))

## Result window: what the encounter gave and took. The bar waits until OK.
var _summary_on := false
var _summary_fatal := false
var _summary_t := 0.0
var _summary_title := ""
var _summary_note := ""
var _summary_got: PackedStringArray = []
var _summary_lost: PackedStringArray = []
var _summary_ok: Callable = Callable()
var _summary_layer: Control

func _summary_open() -> bool:
	return _summary_on

func _show_trade(title: String, before: Dictionary, mid: Dictionary, after: Dictionary) -> void:
	var paid := Delve.ledger_delta(before, mid)
	var gained := Delve.ledger_delta(mid, after)
	var got: PackedStringArray = []
	var lost: PackedStringArray = []
	for s in gained.got: got.append(s)
	for s in paid.got: got.append(s)
	for s in paid.lost: lost.append(s)
	for s in gained.lost: lost.append(s)
	_open_summary(title if title != "" else "Encounter", got, lost)

func _open_summary(title: String, got: PackedStringArray, lost: PackedStringArray, on_ok: Callable = Callable(), fatal := false, note := "") -> void:
	if is_instance_valid(_summary_layer):
		_summary_layer.free()
		_summary_layer = null
	_summary_on = true
	_summary_fatal = fatal
	_summary_t = 0.0
	_summary_title = title if title != "" else "Encounter"
	_summary_note = note
	_summary_got = got
	_summary_lost = lost
	_summary_ok = on_ok
	_build_summary()

func _build_summary() -> void:
	if not _summary_on: return
	if is_instance_valid(_summary_layer): _summary_layer.free()
	var layer := Control.new()
	layer.name = "EncounterSummary"
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_STOP
	layer.z_index = 30
	add_child(layer)
	_summary_layer = layer
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	layer.add_child(dim)
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var m := int(floorf(maxf(UIKit.font_size * 0.75, vs.x * 0.04)))
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mc.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]: mc.add_theme_constant_override("margin_" + side, m)
	layer.add_child(mc)
	var cc := CenterContainer.new()
	cc.mouse_filter = MOUSE_FILTER_IGNORE
	mc.add_child(cc)
	var pad := UIKit.font_size * 0.95
	var card := UIKit.card()
	card.add_theme_stylebox_override("panel", UIKit.chrome("window", Color.WHITE, pad))
	var w := floorf(minf(vs.x - 2.0 * m, UIKit.font_size * 22.0))
	card.custom_minimum_size.x = w
	cc.add_child(card)
	var gap := int(round(UIKit.font_size * 0.65))
	var box := UIKit.vbox(card, gap)
	var h := UIKit.header(_summary_title)
	h.custom_minimum_size.x = 1
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(h)
	if _summary_note != "":
		var note := UIKit.label(_summary_note, 0.85, Color("c9a96e"))
		note.custom_minimum_size.x = 1
		box.add_child(note)
	var sc := ScrollContainer.new()
	sc.name = "SummaryList"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = SIZE_EXPAND_FILL
	# Each line has its own slot, plus the gap between them. The old budget (font*1.2 per
	# counted line) ignored those gaps and the "Nothing" row, so a short victory clipped
	# and grew a scrollbar.
	var line_h := UIKit.font_size * 1.55
	var rows := _summary_row_count()
	var want := float(rows) * line_h + float(maxi(rows - 1, 0)) * float(gap) + UIKit.font_size * 0.45
	var reserved := UIKit.btn_height() + pad * 2.0 + float(gap) * 2.0 + UIKit.font_size * (3.2 if _summary_note != "" else 1.8)
	var room := maxf(line_h * 4.0, vs.y - 2.0 * float(m) - reserved)
	sc.custom_minimum_size = Vector2(0, minf(want, room))
	box.add_child(sc)
	var inner := UIKit.vbox(sc, gap)
	inner.size_flags_horizontal = SIZE_EXPAND_FILL
	_summary_section(inner, "Got", _summary_got, GameState.LOG_COLORS.positive, line_h)
	_summary_section(inner, "Lost", _summary_lost, GameState.LOG_COLORS.negative, line_h)
	var measured := inner.get_combined_minimum_size().y
	if measured > sc.custom_minimum_size.y and measured < want * 2.2:
		sc.custom_minimum_size.y = minf(measured + UIKit.font_size * 0.25, room)
	var ok := UIKit.button("OK", _accept_summary)
	ok.name = "SummaryOK"
	ok.custom_minimum_size.x = 1
	box.add_child(ok)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.15)

func _summary_row_count() -> int:
	return 2 + maxi(_summary_got.size(), 1) + maxi(_summary_lost.size(), 1)

func _summary_line(text: String, scale: float, color: Color, line_h: float) -> Label:
	var l := UIKit.label(text, scale, color)
	l.custom_minimum_size = Vector2(1, line_h)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _summary_section(parent: Node, heading: String, lines: PackedStringArray, color: Color, line_h: float) -> void:
	parent.add_child(_summary_line(heading, 1.0, color, line_h))
	if lines.is_empty():
		parent.add_child(_summary_line("Nothing", 0.9, Color("9a8f7c"), line_h))
		return
	for s in lines:
		parent.add_child(_summary_line(s, 0.9, color, line_h))

func _accept_summary() -> void:
	var cb := _summary_ok
	_summary_on = false
	_summary_fatal = false
	_summary_t = 0.0
	_summary_ok = Callable()
	if is_instance_valid(_summary_layer):
		var layer := _summary_layer
		_summary_layer = null
		if layer.get_parent() == self: remove_child(layer)
		layer.queue_free()
	if cb.is_valid(): cb.call()

## Messages shown inside the open card so a floating toast never covers its buttons (DECISIONS #106).
var _card_toasts: Array = []

## main._toast: when a delve card (floor menu, doors, backpack, …) hides the log, show the message in-flow
## above the card's buttons; when no card is open, the delve log is already on screen so a floating toast is redundant.
func window_toast(text: String) -> bool:
	if card_host == null: return false
	if pending.is_empty():
		_clear_floating_toasts()
		_fill_log()
		return true
	_take_floating_toast()
	_push_card_toast(text)
	_mount_card_toast()
	_fill_log()
	return true

func _clear_floating_toasts() -> void:
	if main == null or not is_instance_valid(main): return
	var box: Node = main.get("toast_box")
	if box == null: return
	for t in box.get_children():
		box.remove_child(t); t.queue_free()

func _push_card_toast(text: String) -> void:
	_card_toasts.append({"text": text, "at": Time.get_ticks_msec()})
	while _card_toasts.size() > 3: _card_toasts.pop_front()

## A reward toast is often emitted before the menu opens (fight Continue). Pull it into the card.
func _take_floating_toast() -> void:
	if main == null or not is_instance_valid(main) or pending.is_empty(): return
	var box: Node = main.get("toast_box")
	if box == null: return
	for t in box.get_children():
		var found := _first_label(t)
		if found != "": _push_card_toast(found)
		box.remove_child(t); t.queue_free()

func _first_label(n: Node) -> String:
	if n is Label and n.text != "": return n.text
	for c in n.get_children():
		var s := _first_label(c)
		if s != "": return s
	return ""

func _mount_card_toast() -> void:
	if card_host == null: return
	var old := card_host.get_node_or_null("CardToast")
	if old: card_host.remove_child(old); old.free()
	if _card_toasts.is_empty() or pending.is_empty(): return
	var box := VBoxContainer.new(); box.name = "CardToast"; box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in _card_toasts:
		var l := UIKit.label(t.text, 0.85, Color("ffff88"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	card_host.add_child(box); card_host.move_child(box, 0)

func _expire_card_toasts() -> void:
	if _card_toasts.is_empty(): return
	var now := Time.get_ticks_msec()
	var live: Array = _card_toasts.filter(func(t): return now - int(t.at) < 3500)
	if live.size() == _card_toasts.size(): return
	_card_toasts = live
	if not pending.is_empty(): _mount_card_toast()
