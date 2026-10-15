## DelveScreen: the Delve Bar. Ticks floor progress, shows supplies, and presents encounter cards
## (combat, Door Choice, special rooms, floor cleared, campfire). Rules live in core/delve.gd.
extends Control

const SPEED := 5.0          # % per second (20 s per floor at 1x)

var main: Control
var box: VBoxContainer
var title: Label
var bar: ProgressBar
var stats: VBoxContainer
var card_host: VBoxContainer
var controls: HFlowContainer
var running := true
var fast := false
var pending: Dictionary = {}   # current event card (pauses the bar)
var portrait := true

func _ready() -> void:
	box = UIKit.vbox(self); box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	title = UIKit.header(""); box.add_child(title)
	bar = ProgressBar.new(); bar.custom_minimum_size.y = UIKit.font_size * 1.6; bar.show_percentage = true; box.add_child(bar)
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
	_refresh_controls(); _show_card()

func on_shown() -> void:
	if pending.is_empty() and GameState.run.has("pending_card"): pending = GameState.run.pending_card
	_refresh(); _show_card()

var _save_t := 0.0

func _process(delta: float) -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	_save_t += delta
	if _save_t > 3.0:
		_save_t = 0.0; SaveSystem.save_game()
	if running and pending.is_empty():
		if Delve.floor_done(run):
			_floor_cleared()
		else:
			var ev := Delve.advance(GameState, delta * SPEED * (3.0 if fast else 1.0))
			if not ev.is_empty():
				pending = ev; Sfx.play("alert"); _show_card(); SaveSystem.save_game()
	_refresh()

func _refresh() -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	var s: Dictionary = GameState.hero_stats(run.hero)
	title.text = "%s - Floor %d / %d" % [DB.biomes[run.biome].name, run.floor, DB.biomes[run.biome].floors[1]]
	bar.value = run.progress
	UIKit.clear(stats)
	var line := "%s Lv%d   HP %d/%d   Torch %d%%   Satiety %d%%" % [s.name, GameState.heroes[run.hero].level, run.hp, s.ht, run.torch, run.satiety]
	if Delve.darkness(run): line += "   DARK: no Barrier in fights!"
	if float(run.satiety) <= 0.0: line += "   STARVING"
	stats.add_child(UIKit.label(line, 0.95))
	var flow := HFlowContainer.new(); stats.add_child(flow)
	for k in run.supplies:
		if int(run.supplies[k]) > 0: flow.add_child(UIKit.icon_row(k, str(run.supplies[k]), 0.85))
	var pl := UIKit.label("|  Pack:", 0.85, Color("c9a96e")); pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	flow.add_child(pl)
	for k in run.pack:
		if int(run.pack[k]) > 0: flow.add_child(UIKit.icon_row(k, str(run.pack[k]), 0.85))
	if not run.pack_gear.is_empty():
		var il := UIKit.label("+%d items" % run.pack_gear.size(), 0.85); il.autowrap_mode = TextServer.AUTOWRAP_OFF; flow.add_child(il)

func _refresh_controls() -> void:
	if controls == null: return
	UIKit.clear(controls)
	var w := UIKit.font_size * 7.0
	var b1 := UIKit.button("Pause" if running else "Resume", func(): running = not running; _refresh_controls()); b1.custom_minimum_size.x = w
	var b2 := UIKit.button("Speed x3" if not fast else "Speed x1", func(): fast = not fast; _refresh_controls()); b2.custom_minimum_size.x = w
	controls.add_child(b1); controls.add_child(b2)
	if int(GameState.run.get("supplies", {}).get("scroll_passage", 0)) > 0:
		var b3 := UIKit.button("Read Scroll of Passage (extract)", func():
			GameState.run.supplies.scroll_passage -= 1; Sfx.play("read"); GameState.end_run("extract"); main.show_camp()); b3.custom_minimum_size.x = w * 2
		controls.add_child(b3)
	var b5 := UIKit.button("Settings", func(): running = false; pending = {"kind": "settings"}; _refresh_controls(); _show_card()); b5.custom_minimum_size.x = w
	controls.add_child(b5)
	var b4 := UIKit.button("Abandon run", _confirm_abandon); b4.custom_minimum_size.x = w
	controls.add_child(b4)

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
		if pending.is_empty() or pending.kind in ["confirm_abandon", "settings"]: GameState.run.erase("pending_card")
		else: GameState.run.pending_card = pending
	if pending.is_empty():
		var hint := "Exploring... encounters every ~20-25%." if running else "Paused."
		card_host.add_child(UIKit.label(hint, 0.9, Color("9a8f7c")))
		var log := UIKit.vbox(card_host)
		var msgs := GameState.messages
		for i in range(maxi(0, msgs.size() - 6), msgs.size()): log.add_child(UIKit.label(msgs[i], 0.8, Color("bdb3a0")))
		return
	match pending.kind:
		"combat": _card_combat()
		"door": _card_door()
		"special": _card_special()
		"floor_done": _card_floor()
		"campfire": _card_campfire()
		"settings":
			var v := _card("Settings", "")
			SettingsPanel.build(v, false)
			v.add_child(UIKit.button("Close", func(): pending = {}; running = true; _refresh_controls(); _show_card()))
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
	if GameState.heroes[GameState.run.hero].level > lvl: Sfx.play("levelup")
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
	v.add_child(UIKit.button("Ignore both", func(): pending = {}; _show_card()))

func _choose_door(o: Dictionary) -> void:
	Sfx.play("door_open")
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
	var v := _card(sp.title, sp.text)
	for o in sp.options:
		var cost: Dictionary = o.get("cost", {})
		var ok := cost.is_empty() or Delve.pay_possible(GameState, cost)
		var why := "" if ok else "can't afford"
		if o.has("requires_class") and o.requires_class != GameState.run.hero: why = "%s only" % DB.heroes[o.requires_class].name
		v.add_child(UIKit.action(o.text, func(): _special_option(o), why))

func _special_option(o: Dictionary) -> void:
	if o.has("fight"):
		var ev := Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 55), o.fight)
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
