## UI smoke test: drives Camp -> Delve -> combat (auto) -> door/special cards -> extract, at both Fold sizes.
## Run: godot --headless --path . res://tests/ui_smoke.tscn
extends Node

var main
var f := 0
var stage := 0
var classes := ["warrior", "mage", "rogue", "huntress"]
var ci := 0

func _ready() -> void:
	SaveSystem.autosave = false
	SaveSystem.path = "user://ui_smoke.json"
	GameState.new_game()
	for c in GameState.heroes: GameState.heroes[c].unlocked = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _process(_d: float) -> void:
	f += 1
	match f:
		5:
			_check(main.screen.get_script().resource_path.ends_with("camp_screen.gd"), "starts in camp")
			for i in main.screen.tabs.get_tab_count(): main.screen.tabs.current_tab = i
			main.screen.chosen_hero = classes[0]
			main.screen._start()
		8:
			_check(main.screen == main.delve, "delve screen shown")
			main.delve.fast = true
		_:
			if f > 8 and f < 12000: _drive()
	if f == 12000:
		print("UI SMOKE: timeout at stage ", stage); get_tree().quit(1)

func _drive() -> void:
	var s = main.screen
	if s.get_script().resource_path.ends_with("combat_screen.gd"):
		if not s.finished: s._do_bot()
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
			"combat": s._fight(p, {})
			"door": s._choose_door(p.door.a)
			"special": s._special_option(p.special.options.back())
			"floor_done":
				if int(GameState.run.floor) >= 2:
					GameState.run.supplies.scroll_passage = 1; s._refresh_controls()
					GameState.end_run("extract"); main.show_camp()
				else:
					Delve.descend(GameState); s.pending = {}; s._show_card()
	else:
		_check(GameState.run.is_empty(), "back at camp with no run")
		print("  %s run done" % classes[ci])
		ci += 1
		if ci < classes.size():
			s.chosen_hero = classes[ci]; s._start(); main.delve.fast = true
			return
		print("UI SMOKE: PASS (fights=%d, stash gold=%d)" % [stage, GameState.mat("gold")])
		SaveSystem.wipe()
		get_tree().quit(0)

func _check(c: bool, n: String) -> void:
	if not c:
		print("UI SMOKE FAIL: ", n); get_tree().quit(1)
