## Captures screenshots of each screen at Fold cover + inner sizes into /workspace/builds/shots (needs a display: xvfb-run).
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn
extends Node

var main
var f := 0
var out := "/workspace/builds/shots"
const SIZES := {"cover": Vector2i(484, 1188), "inner": Vector2i(928, 1080)}
var plan := []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	SaveSystem.autosave = false; SaveSystem.path = "user://shots.json"
	GameState.new_game()
	GameState.settings.tutorial = false
	GameState.settings.lighting = not OS.has_environment("NOLIGHT")
	GameState.add_mat("iron_ore", 20); GameState.add_mat("gold", 200)
	main = load("res://scenes/main.tscn").instantiate(); add_child(main)
	for sz in SIZES:
		plan.append([sz, "camp", func(): main.show_camp(); main.screen.close_page()])
		plan.append([sz, "camp_expedition", func(): main.show_camp(); main.screen.open_page("Delve")])
		plan.append([sz, "camp_heroes", func(): main.show_camp(); main.screen.open_page("Heroes")])
		plan.append([sz, "camp_stash", func(): main.show_camp(); main.screen.open_page("Stash")])
		plan.append([sz, "forge", func(): main.show_camp(); main.screen.open_page("Forge")])
		plan.append([sz, "camp_forge_info", func():
			main.show_camp(); main.screen.open_page("Forge")
			var r: Dictionary = DB.recipes.blacksmith[0]
			main.screen.info(r.out, r.name, [main.screen.cost_row(r.cost), "A sample recipe."], [["Make", func(): pass, ""]])])
		plan.append([sz, "camp_alchemy", func(): main.show_camp(); main.screen.open_page("Alchemy")])
		plan.append([sz, "camp_enchanter", func():
			var u: int = GameState.add_gear("ring_wealth", false); GameState.add_gear("ring_evasion", false); GameState.enqueue_identify(u)
			main.show_camp(); main.screen.open_page("Enchanter")])
		plan.append([sz, "camp_guild", func(): main.show_camp(); main.screen.open_page("Guild")])
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
			if GameState.run.is_empty(): GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)
			main.show_delve(); main.delve.running = false
			for i in 30: Delve.advance(GameState, 1.0)
			main.delve.pending = {"kind": "door", "door": DB.doors[0]}; main.delve._show_card()])
		plan.append([sz, "backpack", func():
			if GameState.run.is_empty(): GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)
			if GameState.run.pack_gear.is_empty():
				Delve.reward(GameState, {"item": "mace"}); Delve.reward(GameState, {"item": "mail_armor"}); Delve.reward(GameState, {"item_unknown": "ring"})
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
			GameState.run.biome = "sewers"
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
			GameState.run.biome = "sewers"
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
		get_window().size = SIZES[step[0]]
		step[2].call()
	if f % 12 == 11:
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, step[0], step[1]])
		if main.screen.get("grid") != null: print("GRID ", step[1], " ", main.screen.grid.size, " cs=", main.screen.grid.cell_size(), " win=", get_viewport().get_visible_rect().size)
		if false: print("box ", main.screen.root_box.size, " title ", main.screen.root_box.get_child(0).size, " tabs ", main.screen.tabs.size, " anchors ", main.screen.root_box.anchor_right, " off ", main.screen.root_box.offset_right)
