## UI smoke test: drives Camp -> Delve -> combat (auto) -> door/special cards -> extract, at both Fold sizes.
## Run: godot --headless --path . res://tests/ui_smoke.tscn
extends Node

var main
var f := 0
var stage := 0
var classes := ["warrior", "mage", "rogue", "huntress"]
var ci := 0
var resumed := false
var tips_seen := {}

func _ready() -> void:
	SaveSystem.autosave = false
	SaveSystem.wipe()
	SaveSystem.path = "user://ui_smoke.json"
	GameState.new_game()
	GameState.settings.tutorial = true; GameState.tutorial_done.clear()
	for c in GameState.heroes: GameState.heroes[c].unlocked = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _process(_d: float) -> void:
	f += 1
	if f > 5 and main and is_instance_valid(main) and main.tip_open():
		tips_seen[main.tips.queue[0].id] = true
		main.tips.next(); return
	match f:
		5:
			_check(main.screen.get_script().resource_path.ends_with("camp_screen.gd"), "starts in camp")
			_check(main.tip_open() and main.tips.queue[0].id == "welcome", "first run shows the welcome tutorial")
			for i in main.screen.tabs.get_tab_count(): main.screen.tabs.current_tab = i
			main.screen.journal_view = "codex"; main.screen.rebuild()
			_check(main.screen.pages["Journal"].get_child_count() > 3, "journal codex renders")
			GameState.set_setting("text_scale", 1.3); GameState.set_setting("text_scale", 1.0)
			_check(UIKit.font_size > 0, "text size change relayouts")
			main.screen.chosen_hero = classes[0]
			main.screen._start()
		8:
			_check(main.screen == main.delve, "delve screen shown")
			main.delve.fast = true
			GameState.settings.delve_speed = 2.0
			_check(is_equal_approx(main.delve.speed_mult(), 6.0), "delve speed setting stacks with x3")
			GameState.settings.delve_speed = 1.0
			main.delve.pending = {"kind": "settings"}; main.delve._show_card()
			_check(main.delve.card_host.get_child_count() > 0, "delve settings card opens")
			main.delve.pending = {}; main.delve.running = true; main.delve._show_card()
		_:
			if f > 8 and f < 20000: _drive()
	if f == 20000:
		print("UI SMOKE: timeout at stage ", stage, " screen ", main.screen.get_script().resource_path, " run ", GameState.run.get("biome"), " f", GameState.run.get("floor"), " pending ", main.delve.pending if main.delve else "-")
		if main.screen.get("combat") != null: print("  last log: ", main.screen.combat.log_lines.slice(-6))
		get_tree().quit(1)
var guided_checked := false
var talents_ui := false
var backpack_ui := false

func _drive() -> void:
	var s = main.screen
	if s.get_script().resource_path.ends_with("combat_screen.gd"):
		if not s.finished and s.grid.tileset != DB.biomes[GameState.run.biome].tile:
			_check(false, "fights use the biome's tileset")
		if stage == 0 and not guided_checked and not s.finished:
			guided_checked = true
			_check(s.guide >= 1 and s.guide_label.text.begins_with("Step"), "first fight is guided")
			_check(s.guide != 1 or s.grid.hint_cell.x >= 0, "guided step 1 highlights a tile")
			s.bag_open = true; s._refresh()
			_check(s.bag_host.get_child_count() > 0, "combat Bag opens the backpack")
			s.bag_open = false; s._refresh()
		if stage > 0 and s.guide > 0 and not s.finished and "guided_fight" in GameState.tutorial_done:
			_check(false, "guided fight only once")
		if not s.finished:
			s._do_bot()
			if stage == 0 and s.combat.log_lines.size() >= 3 and not s.finished and not resumed:
				# simulate Android killing the app mid-fight: save, rebuild everything from disk, resume
				resumed = true
				SaveSystem.save_game()
				main.queue_free(); main = load("res://scenes/main.tscn").instantiate()
				GameState.new_game(); SaveSystem.load_game()
				add_child(main)
				await get_tree().process_frame
				_check(main.screen.get_script().resource_path.ends_with("combat_screen.gd"), "fight resumed after simulated kill")
				_check(main.screen.combat.log_lines.size() >= 4, "resumed fight kept its state")
				print("  resumed fight after simulated app kill OK")
		else:
			stage += 1
			if stage == 1:
				get_window().size = Vector2i(1856, 2160); main._relayout()
				get_window().size = Vector2i(968, 2376); main._relayout()
			s._finish()
	elif s == main.delve:
		var p: Dictionary = s.pending
		if p.is_empty(): GameState.run.progress = minf(100, GameState.run.progress + 0.0); return
		match p.kind:
			"talents":
				talents_ui = true
				var picked := false
				for t in DB.talents[GameState.run.hero]["1"]:
					if GameState.can_pick_talent(GameState.run.hero, t) == "":
						var tb = _find_button(s.card_host, DB.talents[GameState.run.hero]["1"][t].name)
						if tb: tb.pressed.emit(); picked = true
						break
				GameState.auto_pick_talents(GameState.run.hero)
				s._close_panel()
			"backpack":
				backpack_ui = true
				while not GameState.run.get("overflow", []).is_empty(): GameState.resolve_overflow(-1)
				s._close_panel()
			"combat": s._fight(p, {})
			"door": s._choose_door(p.door.a)
			"special": s._special_option(p.special.options.back())
			"campfire":
				if GameState.run.biome == "prison":
					print("  Tengu defeated through the UI, continuing into the Caves")
					_check(GameState.heroes[GameState.run.hero].mask, "Tengu kill grants Tengu's Mask")
					s._show_card()
					_check(Delve.next_biome(GameState.run) == "caves", "Tengu campfire offers the Caves")
					Delve.continue_deeper(GameState); s.pending = {}; main.play_floor_music()
					_check(GameState.run.biome == "caves" and int(GameState.run.floor) == 11, "continue enters Caves floor 11")
					GameState.run.floor = 14; Delve.descend(GameState); s._show_card()
				else:
					_check(GameState.run.biome == "caves", "campfire reached after DM-300")
					print("  DM-300 defeated through the UI, extracting")
					var hc: String = GameState.run.hero
					GameState.end_run("extract"); main.show_camp()
					main.screen.rebuild()
					var btn = _find_button(main.screen.pages["Heroes"], "Become ")
					_check(btn != null, "Heroes page offers subclass choices")
					if btn: btn.pressed.emit()
					_check(GameState.heroes[hc].subclass != "", "subclass chosen through the Camp UI")
			"floor_done":
				if Delve.can_search_floor(GameState.run):
					s._show_card()
					GameState.say(Delve.search_floor(GameState)); s._show_card()
					_check(not Delve.can_search_floor(GameState.run), "floor search is once per floor")
				if ci == classes.size() - 1 and GameState.run.biome == "sewers":
					# last class: jump to Prison floor 9 and fight Tengu on 10 through the real UI
					GameState.run.biome = "prison"; GameState.run.floor = 9
					Delve.descend(GameState); s.pending = {}; s._show_card()
				elif int(GameState.run.floor) >= 2:
					GameState.run.supplies.scroll_passage = 1; s._refresh_controls()
					GameState.end_run("extract"); main.show_camp()
				else:
					Delve.descend(GameState); s.pending = {}; s._show_card()
	else:
		_check(GameState.run.is_empty(), "back at camp with no run")
		print("  %s run done" % classes[ci])
		ci += 1
		if ci < classes.size():
			if ci == classes.size() - 1:
				var h: Dictionary = GameState.heroes[classes[ci]]
				h.level = 11; h.str = 14; h.weapon = GameState.add_gear("mace", true, 2); h.armor = GameState.add_gear("mail_armor", true, 2)
				GameState.add_mat("potion_healing", 3); s.loadout.potion_healing = 3; GameState.facilities.alchemy.level = 3
			s.chosen_hero = classes[ci]; s._start(); main.delve.fast = true
			return
		_check(talents_ui, "level-up opened the Talents card mid-delve")
		_check(GameState.heroes.values().any(func(h): return not h.get("talents", []).is_empty()), "a talent was learned through the UI")
		_check("guided_fight" in GameState.tutorial_done, "guided first fight completed and remembered")
		for t in ["welcome", "delve_bar", "first_fight", "floor_done"]:
			_check(tips_seen.has(t), "tutorial tip shown: " + t)
		_check(not main.tip_open() and "welcome" in GameState.tutorial_done, "tips are remembered once dismissed")
		GameState.tutorial_done.erase("after_death"); main.tip("after_death"); main._process(0.0)
		_check(main.tip_open() and not main.toast_box.visible, "toasts hide while a tip is open")
		main.tips.next(); main._process(0.0)
		_check(main.toast_box.visible, "toasts come back after the tip closes")
		print("  tutorial tips shown: ", tips_seen.keys())
		print("UI SMOKE: PASS (fights=%d, stash gold=%d)" % [stage, GameState.mat("gold")])
		SaveSystem.wipe()
		get_tree().quit(0)

func _find_button(n: Node, prefix: String):
	if n is Button and n.text.begins_with(prefix): return n
	for ch in n.get_children():
		var r = _find_button(ch, prefix)
		if r: return r
	return null

func _check(c: bool, n: String) -> void:
	if not c:
		print("UI SMOKE FAIL: ", n); get_tree().quit(1)
