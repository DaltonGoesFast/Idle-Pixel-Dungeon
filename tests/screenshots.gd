## Captures screenshots of each screen at Fold cover + inner sizes into /workspace/builds/shots (needs a display: xvfb-run).
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn
extends Node

var main
var f := 0
var out := "/workspace/builds/shots"
const SIZES := {"cover": Vector2i(484, 1188), "inner": Vector2i(928, 1080)}
## The window at SIZES is a 0.5x stretch of the 968x2376 viewport, which drops 1-px pixel-font columns
## ("i", ":", ".") that are fine on device. Render at 2x and downsample (SHOT_NATIVE=1 keeps the 2x image) (DECISIONS #112).
const RENDER_SCALE := 2
var plan := []

func _ready() -> void:
	if OS.has_environment("SHOT_DIR"): out = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	SaveSystem.autosave = false; SaveSystem.path = "user://shots.json"
	GameState.new_game()
	GameState.settings.tutorial = false
	GameState.settings.lighting = not OS.has_environment("NOLIGHT")
	GameState.add_mat("iron_ore", 20); GameState.add_mat("gold", 200)
	main = load("res://scenes/main.tscn").instantiate(); add_child(main)
	for sz in SIZES:
		plan.append([sz, "camp", func(): main.show_camp(); main.screen.close_page()])
		plan.append([sz, "icon_audit", func():
			# every icon context with centre guides: item slots, paperdoll slots, res chips, icon buttons, hero portraits
			main.show_camp(); main.screen.close_page()
			var layer := PanelContainer.new(); layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main.screen.add_child(layer)
			var sc := ScrollContainer.new(); layer.add_child(sc); var v := UIKit.vbox(sc); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(UIKit.header("Icon audit"))
			var g: GridContainer = main.screen.slot_grid(v)
			for id in ["GOLD", "DEWDROP", "TORCH", "IRON_KEY", "RATION", "ORE", "potion_healing", "ring_wealth", "chalice_blood", "shortsword", "mace", "WEAPON_HOLDER", "ARMOR_HOLDER", "RING_HOLDER", "ARTIFACT_HOLDER", "CHEST"]:
				var b: Button = main.screen.item_slot(id, "", "", func(): pass)
				var guide := ColorRect.new(); guide.color = Color(1, 0, 1, 0.5); guide.set_anchors_preset(Control.PRESET_CENTER); guide.size = Vector2(1, 1000); guide.position = Vector2(UIKit.font_size * 1.5, -400); guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(guide); var gh := ColorRect.new(); gh.color = guide.color; gh.size = Vector2(1000, 1); gh.position = Vector2(-400, UIKit.font_size * 1.5); gh.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(gh)
				b.clip_contents = true; g.add_child(b)
			var chips := HFlowContainer.new(); v.add_child(chips)
			for k in ["gold", "iron_ore", "seeds", "torch", "ration", "potion_healing"]: chips.add_child(UIKit.res_chip(k, "88", 0.9))
			var bf := HFlowContainer.new(); v.add_child(bf)
			for n in ["enter", "backpack_lrg", "prefs", "journal", "talent", "alchemy"]:
				var tb := UIKit.as_toolbar(UIKit.button("", func(): pass), n); tb.custom_minimum_size = Vector2.ONE * UIKit.btn_height(); tb.size_flags_horizontal = 0; tb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; bf.add_child(tb)
			for n in ["Stash", "Forge", "Journal"]:
				var lb := UIKit.button(n, func(): pass); UIKit.with_icon(lb, main.screen.PAGE_ICONS[n]); lb.size_flags_horizontal = 0; lb.custom_minimum_size.x = UIKit.font_size * 7; bf.add_child(lb)
			var hr := HFlowContainer.new(); v.add_child(hr)
			for c in GameState.heroes: hr.add_child(main.screen._hero_slot(c))
			Paperdoll.build(v, "warrior", not main.screen.portrait, "camp", func(): pass)])
		plan.append([sz, "camp_expedition", func(): main.show_camp(); main.screen.open_page("Delve")])
		plan.append([sz, "camp_heroes", func(): main.show_camp(); main.screen.open_page("Heroes")])
		plan.append([sz, "camp_paperdoll", func():
			GameState.add_gear("shortsword"); GameState.add_gear("mace"); GameState.add_gear("ring_wealth"); GameState.add_gear("chalice_blood")
			Paperdoll.sel_slot = "weapon"; main.show_camp(); main.screen.open_page("Heroes")])
		plan.append([sz, "camp_talents", func():
			Paperdoll.sel_slot = ""; GameState.heroes.warrior.level = 5; HeroPanels.sel_talent = "iron_will"
			main.show_camp(); main.screen.show_talents = true; main.screen.open_page("Heroes")
			(func(): main.screen.win_layer.get_meta("sc").scroll_vertical = 100000).call_deferred()])
		plan.append([sz, "camp_compare", func():
			HeroPanels.sel_talent = ""; GameState.heroes.warrior.level = 1
			main.show_camp(); main.screen.open_page("Stash")
			main.screen.compare(GameState.gear.filter(func(g): return g.id == "mace")[0])])
		plan.append([sz, "camp_toast", func():
			main.show_camp(); main.screen.open_page("Guild"); GameState.say("Bought a Ration.")])
		plan.append([sz, "camp_stash", func():
			# every ring kind, known + unknown + cracked, a potion and a scroll: the icons must all show
			for rid in ["ring_might", "ring_tenacity", "ring_evasion", "ring_wealth", "ring_energy"]:
				GameState.add_gear(rid, true); GameState.add_gear(rid, false)
			var cr: int = GameState.add_gear("ring_might", true); GameState.gear_by_uid(cr).cracked = true
			GameState.add_mat("potion_toxic", 1); GameState.add_mat("scroll_upgrade", 1)
			main.show_camp(); main.screen.section["Stash"] = "gear"; main.screen.open_page("Stash")])
		plan.append([sz, "forge", func():
			GameState.add_mat("iron_ore", 40); GameState.add_mat("dark_gold", 5); GameState.add_mat("gold", 100)
			GameState.facilities.blacksmith.level = 3
			var a: int = GameState.add_gear("shortsword", true, 0); var b: int = GameState.add_gear("cloth_armor", true, 1)
			GameState.gear_by_uid(a).cracked = true; GameState.gear_by_uid(b).cracked = true
			var rg: int = GameState.add_gear("ring_wealth", true); GameState.gear_by_uid(rg).cracked = true
			main.show_camp(); main.screen.section["Forge"] = "upgrade"; main.screen.open_page("Forge")])
		plan.append([sz, "forge_craft", func():
			main.show_camp(); main.screen.section["Forge"] = "craft"; main.screen.open_page("Forge")])
		plan.append([sz, "camp_forge_info", func():
			main.show_camp(); main.screen.open_page("Forge")
			var uid: int = GameState.add_gear("mace", true, 0)
			main.screen._gear_forge_info(GameState.gear_by_uid(uid), ["+0  ->  +N"], "")])
		plan.append([sz, "camp_forge_buy", func():
			main.show_camp(); main.screen.open_page("Forge")
			var r: Dictionary = DB.recipes.blacksmith[0]
			main.screen._recipe_info("blacksmith", r, r.out, [main.screen.cost_row(r.cost)], "")])
		plan.append([sz, "camp_alchemy", func():
			GameState.add_mat("potion_toxic", 1); GameState.add_mat("seeds", 3)
			main.show_camp(); main.screen.alch_sel = "transmute_toxic"; main.screen.open_page("Alchemy")])
		plan.append([sz, "camp_enchanter", func():
			var u: int = GameState.add_gear("ring_wealth", false); GameState.add_gear("ring_evasion", false); GameState.enqueue_identify(u)
			main.show_camp(); main.screen.section["Enchanter"] = "identify"; main.screen.open_page("Enchanter")])
		plan.append([sz, "camp_guild", func():
			GameState.add_mat("gold", 200); GameState.facilities.guild.level = 2
			main.show_camp(); main.screen.open_page("Guild")])
		plan.append([sz, "camp_guild_buy", func():
			main.show_camp(); main.screen.open_page("Guild")
			var r: Dictionary = GameState.recipe("guild", "buy_ration")
			main.screen._recipe_info("guild", r, r.out_mat, [main.screen.cost_row(r.cost)], "")])
		plan.append([sz, "journal", func():
			GameState.stats.extractions = 1; GameState.stats.kills = 37; GameState.touch()
			main.show_camp(); main.screen.open_page("Journal")])
		plan.append([sz, "codex", func():
			for m in ["rat", "snake", "gnoll", "crab", "goo"]: GameState.discover("mob:" + m)
			GameState.discover("trap:worn_dart")
			main.show_camp(); main.screen.journal_view = "codex"; main.screen.open_page("Journal")
			main.screen.rebuild()])
		plan.append([sz, "tip", func():
			main.show_camp(); main.tips.push("welcome")])
		plan.append([sz, "tip_closed", func(): main.tips.skip_all(); GameState.settings.tutorial = false])
		plan.append([sz, "settings", func(): main.show_camp(); main.screen.open_page("Settings")])
		plan.append([sz, "delve", func():
			_fresh_warrior_run()
			main.show_delve(); main.delve.running = false
			for i in 30: Delve.advance(GameState, 1.0)
			main.delve.pending = {"kind": "door", "door": DB.doors[0]}; main.delve._show_card()])
		plan.append([sz, "delve_walk", func():
			_fresh_warrior_run(); main.show_delve()
			GameState.heroes.warrior.armor = GameState.add_gear("scale_armor")   # armor tier row must show
			main.delve.pending = {}; main.delve.running = true; main.delve._show_card()
			main.delve.scene.scroll = main.delve.scene.target - 0.6; main.delve.scene.pops.append({"idx": DB.icon_index("gold"), "age": 0.2, "n": 3}); main.delve.scene.glow = 0.8])
		for b in [["prison", 7], ["caves", 12], ["city", 17], ["halls", 22]]:   # biome corridor art (DECISIONS #181)
			plan.append([sz, "delve_" + b[0], _biome_walk.bind(b[0], b[1])])
		plan.append([sz, "delve_enemy", func():
			_clear_pops()
			main.delve.running = false
			main.delve.pending = Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["gnoll", "rat"]); main.delve._show_card()])
		plan.append([sz, "delve_special", func():
			_clear_pops()
			main.delve.running = false
			main.delve.pending = {"kind": "special", "special": DB.specials[0]}; main.delve._show_card()])
		plan.append([sz, "delve_auto", func():
			_clear_pops()
			main.delve.pending = {}; GameState.settings.full_auto = true
			GameState.log_line("Auto: fight Marsupial Rat", "auto"); GameState.log_line("Victory: 2 kills, took 3 damage, +5 gold, +2 xp.", "positive")
			GameState.log_line("Warning: your torch is burning low.", "warning"); GameState.log_line("You descend to floor 2.", "highlight")
			main.delve._refresh_controls(); main.delve._show_card(); GameState.settings.full_auto = false])
		plan.append([sz, "delve_menu", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.run.supplies["scroll_passage"] = 1
			main.delve.pending = {}; main.delve._open_panel("menu")])
		plan.append([sz, "delve_low_hp", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			main.delve.pending = {}; main.delve.running = false
			GameState.run.hp = 4; main.delve._refresh_controls(); main.delve._show_card()])
		plan.append([sz, "delve_campfire", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.run.hp = 20; GameState.run.boss_dead = true; GameState.run.floor = 5
			GameState.run.pack["iron_ore"] = 3; Delve.reward(GameState, {"item": "mace"})
			main.delve.pending = {"kind": "campfire"}; main.delve._show_card()])
		plan.append([sz, "backpack", func():
			_fresh_warrior_run()
			if GameState.run.pack_gear.is_empty():
				Delve.reward(GameState, {"item": "mace"}); Delve.reward(GameState, {"item": "mail_armor"}); Delve.reward(GameState, {"item_unknown": "ring"})
				GameState.run.pack["potion_toxic"] = 1; GameState.run.pack["scroll_upgrade"] = 1
			main.show_delve(); main.delve._open_panel("backpack")])
		plan.append([sz, "talents", func():
			GameState.heroes.warrior.level = 9; GameState.heroes.warrior.talents = ["hearty_meal"]
			main.show_delve(); main.delve._open_panel("talents")])
		plan.append([sz, "guided", func():
			main.delve._close_panel(); GameState.heroes.warrior.level = 1; GameState.heroes.warrior.talents = []
			GameState.settings.tutorial = true; GameState.tutorial_done = ["first_fight", "welcome", "delve_bar"]
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 3), ["rat"]), func(_r): pass)
			GameState.settings.tutorial = false])
		plan.append([sz, "combat", func():
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 3), ["gnoll", "crab"]), func(_r): pass)
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "huntress", func():
			GameState.end_run("abandon")
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			GameState.start_run("huntress", {}, "sewers", 9); main.show_delve(); main.delve.running = false
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["crab", "rat"]), func(_r): pass)
			for i in 2: main.screen._do_bot()])
		plan.append([sz, "combat_bag", func():
			for id in ["mace", "leather_armor", "ring_wealth"]: GameState.run.pack_gear.append({"uid": 9100 + GameState.run.pack_gear.size(), "id": id, "lvl": 0, "cracked": false, "known": false, "owned": false})
			main.screen.bag_open = true; main.screen._refresh()])
		plan.append([sz, "prison", func():
			GameState.run.biome = "prison"; GameState.run.floor = 7
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.prison[0], "mobs": ["guard", "dm100", "skeleton"]}, func(_r): pass)
			main.screen._act(func(): main.screen.combat.hero_search())
			for i in 2: main.screen._do_bot()])
		plan.append([sz, "tengu", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[1], "mobs": ["tengu"]}, func(_r): pass)
			for i in 4: main.screen._do_bot()])
		plan.append([sz, "caves", func():
			GameState.run.biome = "caves"; GameState.run.floor = 12
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.caves[0], "mobs": ["brute", "shaman", "bat"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "dm300", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[2], "mobs": ["dm300"]}, func(_r): pass)
			for i in 4: main.screen._do_bot()])
		plan.append([sz, "city", func():
			GameState.run.biome = "city"; GameState.run.floor = 17
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.city[1], "mobs": ["ghoul", "warlock", "monk"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "dking", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[3], "mobs": ["dking"]}, func(_r): pass)
			for i in 5: main.screen._do_bot()])
		plan.append([sz, "halls", func():
			GameState.run.biome = "halls"; GameState.run.floor = 22
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.halls[1], "mobs": ["succubus", "eye", "ripper"]}, func(_r): pass)
			main.screen.combat.hero.ht = 120; main.screen.combat.hero.hp = 120
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "yog", func():
			GameState.run.biome = "halls"; GameState.run.floor = 25
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[DB.biomes.halls.boss_room], "mobs": ["yog"]}, func(_r): pass)
			main.screen.combat.hero.ht = 120; main.screen.combat.hero.hp = 120
			for i in 6: main.screen._do_bot()])
		plan.append([sz, "terrain", func():
			# hero standing in a doorway, a rat in tall grass (with grass above it) and a trampled cell
			GameState.run.biome = "sewers"; GameState.run.floor = 1
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.prison[0], "mobs": ["rat", "crab"]}, func(_r): pass)
			var cb = main.screen.combat; var T = cb.T
			for y in range(1, cb.SIZE - 1):
				for x in range(1, cb.SIZE - 1): cb.terrain[y][x] = T.FLOOR
			for x in cb.SIZE: cb.terrain[3][x] = T.WALL
			cb.terrain[3][2] = T.DOOR; cb.terrain[3][5] = T.DOOR
			for y in range(5, 8):
				for x in range(3, 7): cb.terrain[y][x] = T.GRASS
			cb.terrain[6][3] = T.FLOOR; cb.trampled[Vector2i(3, 6)] = true
			cb.hero.pos = Vector2i(2, 3)
			var es: Array = cb.enemies(); es[0].pos = Vector2i(5, 6); es[1].pos = Vector2i(4, 2)
			cb.terrain[2][4] = T.FLOOR
			main.screen.grid.queue_redraw()])
		plan.append([sz, "boss", func():
			GameState.run.biome = "sewers"; GameState.run.floor = 1
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[0], "mobs": ["goo"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])

func _process(_d: float) -> void:
	if f == 0 and OS.has_environment("SHOTS"):  # SHOTS=caves,dm300 -> only those steps
		var only: PackedStringArray = OS.get_environment("SHOTS").split(",")
		plan = plan.filter(func(st): return st[1] in only)
	f += 1
	var i := f / 12
	if i >= plan.size():
		SaveSystem.wipe(); get_tree().quit(); return
	var step = plan[i]
	if f % 12 == 1:
		get_window().size = SIZES[step[0]] * RENDER_SCALE
		step[2].call()
	if f % 12 == 11:
		var img := get_viewport().get_texture().get_image()
		if not OS.has_environment("SHOT_NATIVE"): img.resize(SIZES[step[0]].x, SIZES[step[0]].y, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s_%s.png" % [out, step[0], step[1]])
		if main.screen.get("grid") != null: print("GRID ", step[1], " ", main.screen.grid.size, " cs=", main.screen.grid.cell_size(), " win=", get_viewport().get_visible_rect().size)
		if false: print("box ", main.screen.root_box.size, " title ", main.screen.root_box.get_child(0).size, " tabs ", main.screen.tabs.size, " anchors ", main.screen.root_box.anchor_right, " off ", main.screen.root_box.offset_right)


## The staged "+3 gold" pop of delve_walk lives 1.1 s, longer than the next shots take, so clear it (DECISIONS #113).
func _clear_pops() -> void:
	if main.delve != null and main.delve.scene != null: main.delve.scene.pops.clear(); main.delve.scene.glow = 0.0


## A delve corridor walk in another biome (tile sheet, wall deco, region props).
func _biome_walk(biome: String, fl: int) -> void:
	_fresh_warrior_run(); main.show_delve(); _clear_pops()
	GameState.run.biome = biome; GameState.run.floor = fl
	main.delve.pending = {}; main.delve.running = true; main.delve._show_card()
	main.delve.scene.scroll = main.delve.scene.target - 0.6


## Delve shots always start from a clean Warrior run on Sewers 1 (no state leaking from boss/biome shots).
func _fresh_warrior_run() -> void:
	if not GameState.run.is_empty() and (GameState.run.hero != "warrior" or GameState.run.biome != "sewers" or int(GameState.run.floor) > 5):
		GameState.run = {}
	if GameState.run.is_empty():
		for k in ["ration", "torch", "potion_healing"]: GameState.add_mat(k, 1)
		GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)
