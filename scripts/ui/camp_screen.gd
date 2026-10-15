## CampScreen: the persistent Surface Camp. Tabs: Expedition, Heroes, Stash, Blacksmith, Alchemy,
## Enchanter, Guild (supplies & patrols), Settings. Content is rebuilt from GameState on every change.
extends Control

var main: Control
var root_box: VBoxContainer
var summary: HFlowContainer
var tabs: TabContainer
var pages := {}
var loadout := {"ration": 2, "torch": 2, "potion_healing": 1, "scroll_passage": 0, "elixir_starter": 0}
var chosen_hero := "warrior"
var portrait := true
const TAB_ORDER := ["Delve", "Heroes", "Stash", "Forge", "Alchemy", "Enchanter", "Guild", "Settings"]

func _ready() -> void:
	root_box = UIKit.vbox(self)
	root_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var title := UIKit.header("Surface Camp")
	root_box.add_child(title)
	summary = HFlowContainer.new(); root_box.add_child(summary)
	tabs = TabContainer.new(); tabs.size_flags_vertical = SIZE_EXPAND_FILL
	root_box.add_child(tabs)
	for t in TAB_ORDER:
		var sc := ScrollContainer.new(); sc.name = t
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var v := UIKit.vbox(sc); v.size_flags_horizontal = SIZE_EXPAND_FILL
		tabs.add_child(sc); pages[t] = v
	GameState.changed.connect(rebuild)
	rebuild()

func apply_layout(p: bool, _size: Vector2) -> void:
	portrait = p
	rebuild()

func rebuild() -> void:
	if not is_inside_tree(): return
	UIKit.clear(summary)
	for k in ["gold", "iron_ore", "dark_gold", "seeds", "arcane_resin", "dew", "scroll_upgrade"]:
		if GameState.mat(k) > 0 or k in ["gold", "iron_ore", "seeds"]:
			var r := UIKit.icon_row(k, str(GameState.mat(k)), 0.9); summary.add_child(r)
	_page_delve(); _page_heroes(); _page_stash()
	_page_facility("Forge", "blacksmith"); _page_facility("Alchemy", "alchemy"); _page_facility("Enchanter", "enchanter")
	_page_guild(); _page_settings()

func _p(name: String) -> VBoxContainer:
	var v: VBoxContainer = pages[name]
	UIKit.clear(v)
	return v

# ------------------------------------------------------------ Delve (loadout & start)
func _page_delve() -> void:
	var v := _p("Delve")
	v.add_child(UIKit.label("Choose a hero, pack supplies, and descend into the Sewers (floors 1-5, Goo waits on 5). Extract at the floor-5 campfire or with a Scroll of Passage; dying loses the pack."))
	var hb := HFlowContainer.new(); v.add_child(hb)
	for c in GameState.heroes:
		var h: Dictionary = GameState.heroes[c]
		var label: String = ("%s Lv%d" % [DB.heroes[c].name, h.level]) if h.unlocked else (DB.heroes[c].name + " (locked)")
		var b := UIKit.button(("> " if c == chosen_hero else "") + label, func(): chosen_hero = c; rebuild(), h.unlocked)
		b.custom_minimum_size.x = UIKit.font_size * 8
		hb.add_child(b)
	v.add_child(_stats_card(chosen_hero))
	v.add_child(UIKit.header("Supplies"))
	for k in ["ration", "torch", "potion_healing", "scroll_passage", "elixir_starter"]:
		var have := GameState.mat(k)
		var cap := GameState.belt_size() if k == "potion_healing" else (1 if k == "scroll_passage" else 6)
		loadout[k] = clampi(int(loadout[k]), 0, mini(have, cap))
		if k == "elixir_starter" and have == 0: continue
		var row := UIKit.hbox(v)
		var r := UIKit.icon_row(k, "%s: %d  (stash %d)" % [DB.mat_name(k), loadout[k], have], 0.9)
		r.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(r)
		var minus := UIKit.button("-", func(): loadout[k] -= 1; rebuild(), loadout[k] > 0); minus.size_flags_horizontal = 0
		var plus := UIKit.button("+", func(): loadout[k] += 1; rebuild(), loadout[k] < mini(have, cap)); plus.size_flags_horizontal = 0
		minus.custom_minimum_size.x = UIKit.btn_height(); plus.custom_minimum_size.x = UIKit.btn_height()
		row.add_child(minus); row.add_child(plus)
	if GameState.mat("elixir_starter") > 0 and GameState.heroes[chosen_hero].level < 3:
		v.add_child(UIKit.button("Drink Starter Elixir (boost to Lv3)", func(): GameState.use_elixir(chosen_hero)))
	v.add_child(UIKit.action("Descend into the Sewers", _start, GameState.can_start_run(chosen_hero)))

func _start() -> void:
	if GameState.start_run(chosen_hero, loadout):
		main.show_delve()

func _stats_card(c: String) -> Control:
	var card := UIKit.card()
	var v := UIKit.vbox(card)
	var h: Dictionary = GameState.heroes[c]
	var s: Dictionary = GameState.hero_stats(c)
	v.add_child(UIKit.label("%s - Lv%d (%d/%d xp), %d Str" % [s.name, h.level, h.xp, GameState.xp_to_next(h.level), h.str], 1.0, Color("ffd27a")))
	var line := "HP %d   Barrier %d   DR %d   Dmg %d" % [s.ht, s.barrier_max, s.dr, s.dmg]
	if s.delay != 1.0: line += "   (swing %.1f ticks)" % s.delay
	v.add_child(UIKit.label(line))
	if s.has("bolt"): v.add_child(UIKit.label("Staff bolt: %s, %d dmg (ignores DR), %d charges" % [s.bolt.name, s.bolt.dmg, s.bolt.charges], 0.9))
	v.add_child(UIKit.label("Weapon: %s\nArmor: %s\nRing: %s" % [GameState.gear_name(GameState.gear_by_uid(h.weapon)),
		GameState.gear_name(GameState.gear_by_uid(h.armor)), GameState.gear_name(GameState.gear_by_uid(h.ring))], 0.9))
	if not h.unlocked: v.add_child(UIKit.label("Unlock: " + DB.heroes[c].get("unlock", ""), 0.9, Color("c9a96e")))
	v.add_child(UIKit.label(DB.heroes[c].desc, 0.8, Color("bdb3a0")))
	return card

# ------------------------------------------------------------ Heroes (equipment)
func _page_heroes() -> void:
	var v := _p("Heroes")
	for c in GameState.heroes:
		v.add_child(_stats_card(c))
		if not GameState.heroes[c].unlocked: continue
		var flow := HFlowContainer.new(); v.add_child(flow)
		for g in GameState.gear:
			var t: String = DB.item(g.id).type
			if not (t in ["weapon", "armor", "ring"]): continue
			var h: Dictionary = GameState.heroes[c]
			if h.weapon == g.uid or h.armor == g.uid or h.ring == g.uid: continue
			var why: String = GameState.can_equip(c, g.uid)
			if why.begins_with("heirloom") or why.begins_with("equipped"): continue
			var b := UIKit.button("Equip " + GameState.gear_name(g), func(): GameState.equip(c, g.uid), why == "", why)
			b.custom_minimum_size.x = UIKit.font_size * 10
			b.icon = null
			flow.add_child(b)
		if c == "mage":
			for g in GameState.gear:
				if DB.item(g.id).type == "wand" and g.known:
					flow.add_child(UIKit.button("Imbue " + GameState.gear_name(g), func(): GameState.imbue_wand(g.uid)))

# ------------------------------------------------------------ Stash
func _page_stash() -> void:
	var v := _p("Stash")
	v.add_child(UIKit.header("Materials & consumables"))
	var grid := GridContainer.new(); grid.columns = 2 if portrait else 3; v.add_child(grid)
	for k in DB.materials:
		if GameState.mat(k) > 0:
			var r := UIKit.icon_row(k, "%s x%d" % [DB.mat_name(k), GameState.mat(k)], 0.9)
			r.size_flags_horizontal = SIZE_EXPAND_FILL; grid.add_child(r)
	v.add_child(UIKit.header("Gear"))
	for g in GameState.gear:
		var who := GameState.equipped_by(g.uid)
		var text := GameState.gear_name(g) + ("  [%s]" % DB.heroes[who].name if who != "" else "")
		v.add_child(UIKit.icon_row(g.id if g.known else ("RING_HOLDER" if DB.item(g.id).type == "ring" else g.id), text, 0.9))

# ------------------------------------------------------------ Facilities
func _facility_header(v: VBoxContainer, id: String) -> void:
	var f: Dictionary = GameState.facilities[id]
	var d: Dictionary = DB.facilities[id]
	v.add_child(UIKit.header("%s  Lv%d / cap %d (max %d)" % [d.name, f.level, f.cap, d.max]))
	v.add_child(UIKit.label(d.desc, 0.85, Color("bdb3a0")))
	var why: String = GameState.can_upgrade_facility(id)
	v.add_child(UIKit.action("Upgrade (%s)" % GameState.cost_text(GameState.facility_upgrade_cost(id)), func(): GameState.upgrade_facility(id), why))
	if f.cap < int(d.max) and GameState.mat("scroll_upgrade") > 0:
		v.add_child(UIKit.button("Apply Scroll of Upgrade (raise cap)", func(): GameState.apply_sou(id)))

func _page_facility(page: String, id: String) -> void:
	var v := _p(page)
	_facility_header(v, id)
	v.add_child(UIKit.header("Recipes"))
	for r in DB.recipes.get(id, []):
		var out: String = r.get("out", r.get("out_mat", ""))
		var row := UIKit.vbox(v)
		row.add_child(UIKit.icon_row(out, "%s  -  %s" % [r.name, GameState.cost_text(r.cost)], 0.9))
		row.add_child(UIKit.action("Make", func(): GameState.craft(id, r.id), GameState.can_craft(id, r.id)))
	if id == "blacksmith":
		v.add_child(UIKit.header("Upgrade & repair (cap +%d)" % GameState.facility_level("blacksmith")))
		for g in GameState.gear:
			var t: String = DB.item(g.id).type
			if not (t in ["weapon", "armor"]): continue
			if g.cracked:
				v.add_child(UIKit.action("Repair %s (%s)" % [GameState.gear_name(g), GameState.cost_text(GameState.repair_cost(g.uid))],
					func(): GameState.repair(g.uid), "" if GameState.can_afford(GameState.repair_cost(g.uid)) else "need " + GameState.cost_text(GameState.repair_cost(g.uid))))
			else:
				v.add_child(UIKit.action("Upgrade %s (%s)" % [GameState.gear_name(g), GameState.cost_text(GameState.item_upgrade_cost(g.uid))],
					func(): GameState.upgrade_item(g.uid), GameState.can_upgrade_item(g.uid)))
	if id == "enchanter":
		v.add_child(UIKit.header("Identification queue (%d min each)" % int(GameState.identify_seconds() / 60)))
		for q in GameState.id_queue:
			var g := GameState.gear_by_uid(q.uid)
			var left := maxf(0.0, float(q.ready_at) - GameState.now())
			v.add_child(UIKit.label("%s - %d:%02d left" % [GameState.gear_name(g), int(left) / 60, int(left) % 60], 0.9))
		for g in GameState.gear:
			if g.known: continue
			if GameState.id_queue.any(func(q): return q.uid == g.uid): continue
			v.add_child(UIKit.button("Queue %s for identification" % GameState.gear_name(g), func(): GameState.enqueue_identify(g.uid)))
		if not GameState.id_queue.is_empty():
			var t := Timer.new(); t.wait_time = 1.0; t.autostart = true; v.add_child(t)
			t.timeout.connect(func(): if tabs.current_tab == TAB_ORDER.find("Enchanter"): _page_facility("Enchanter", "enchanter"))

func _page_guild() -> void:
	var v := _p("Guild")
	_facility_header(v, "guild")
	v.add_child(UIKit.header("Supplies"))
	for r in DB.recipes.guild:
		v.add_child(UIKit.action("%s (%s)" % [r.name, GameState.cost_text(r.cost)], func(): GameState.craft("guild", r.id), GameState.can_craft("guild", r.id)))
	v.add_child(UIKit.header("Offline Patrols (max %dh)" % int(GameState.patrol_max_hours())))
	v.add_child(UIKit.label("Idle heroes patrol a cleared biome in real time and bring back upgrade fuel. Yield scales with power vs the biome's Strength gate.", 0.85, Color("bdb3a0")))
	for c in GameState.heroes:
		var h: Dictionary = GameState.heroes[c]
		if not h.unlocked: continue
		var card := UIKit.card(); var cv := UIKit.vbox(card); v.add_child(card)
		if h.patrol.is_empty():
			cv.add_child(UIKit.label("%s - idle" % DB.heroes[c].name))
			cv.add_child(UIKit.action("Patrol the Sewers (efficiency %d%%)" % int(GameState.patrol_efficiency(c, "sewers") * 100),
				func(): GameState.start_patrol(c, "sewers"), GameState.can_patrol(c, "sewers")))
		else:
			var y: Dictionary = GameState.patrol_preview(c)
			var parts := []
			for k in y:
				if not String(k).begins_with("_") and int(y[k]) > 0: parts.append("%d %s" % [y[k], DB.mat_name(k)])
			cv.add_child(UIKit.label("%s - patrolling %.1fh: %s%s" % [DB.heroes[c].name, y._hours, ", ".join(parts) if parts else "nothing yet",
				", %d curios" % y._curios if y._curios > 0 else ""]))
			cv.add_child(UIKit.button("Recall & collect", func(): GameState.collect_patrol(c)))

func _page_settings() -> void:
	var v := _p("Settings")
	for k in ["sfx", "music"]:
		v.add_child(UIKit.label("%s volume" % k.to_upper()))
		var s := HSlider.new(); s.min_value = 0; s.max_value = 1; s.step = 0.05; s.value = GameState.settings[k]
		s.custom_minimum_size.y = UIKit.btn_height()
		s.value_changed.connect(func(x): GameState.settings[k] = x; Sfx.refresh_volume())
		s.drag_ended.connect(func(_c): SaveSystem.save_game())
		v.add_child(s)
	v.add_child(UIKit.header("Developer"))
	v.add_child(UIKit.button("Unlock all heroes", func():
		for c in GameState.heroes: GameState.heroes[c].unlocked = true
		GameState.touch()))
	v.add_child(UIKit.button("+100 of every material", func():
		for k in ["gold", "iron_ore", "dark_gold", "seeds", "arcane_resin", "iron_key", "ration", "torch", "potion_healing", "scroll_passage", "scroll_upgrade"]: GameState.add_mat(k, 100 if k == "gold" else 10)
		GameState.touch()))
	v.add_child(UIKit.button("Fast-forward 1 hour (timers)", func(): GameState.time_offset += 3600; GameState.tick_identify(); GameState.touch()))
	v.add_child(UIKit.button("Wipe save (new game)", func(): SaveSystem.wipe()))
	v.add_child(UIKit.label("Art, sounds and music: Shattered Pixel Dungeon by Evan Debenham (GPL-3.0). This game is GPL-3.0. See CREDITS.md.", 0.75, Color("9a8f7c")))
