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
	GameState.add_mat("iron_ore", 20); GameState.add_mat("gold", 200)
	main = load("res://scenes/main.tscn").instantiate(); add_child(main)
	for sz in SIZES:
		plan.append([sz, "camp", func(): main.show_camp()])
		plan.append([sz, "forge", func(): main.show_camp(); main.screen.tabs.current_tab = 3])
		plan.append([sz, "journal", func():
			GameState.stats.extractions = 1; GameState.stats.kills = 37; GameState.touch()
			main.show_camp(); main.screen.tabs.current_tab = main.screen.TAB_ORDER.find("Journal")])
		plan.append([sz, "codex", func():
			for m in ["rat", "snake", "gnoll", "crab", "goo"]: GameState.discover("mob:" + m)
			GameState.discover("trap:worn_dart")
			main.show_camp(); main.screen.journal_view = "codex"; main.screen.tabs.current_tab = main.screen.TAB_ORDER.find("Journal")
			main.screen.rebuild()])
		plan.append([sz, "tip", func():
			main.show_camp(); main.tips.push("welcome")])
		plan.append([sz, "tip_closed", func(): main.tips.skip_all(); GameState.settings.tutorial = false])
		plan.append([sz, "settings", func(): main.show_camp(); main.screen.tabs.current_tab = main.screen.TAB_ORDER.find("Settings")])
		plan.append([sz, "delve", func():
			if GameState.run.is_empty(): GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)
			main.show_delve(); main.delve.running = false
			for i in 30: Delve.advance(GameState, 1.0)
			main.delve.pending = {"kind": "door", "door": DB.doors[0]}; main.delve._show_card()])
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
		plan.append([sz, "boss", func():
			GameState.run.biome = "sewers"
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[0], "mobs": ["goo"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])

func _process(_d: float) -> void:
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
		if false: print("box ", main.screen.root_box.size, " title ", main.screen.root_box.get_child(0).size, " tabs ", main.screen.tabs.size, " anchors ", main.screen.root_box.anchor_right, " off ", main.screen.root_box.offset_right)
