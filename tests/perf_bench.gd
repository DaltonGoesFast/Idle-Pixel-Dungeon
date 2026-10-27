## Frame-time probe for the redraw / AI / save hot spots.
##   godot --headless --path . res://tests/perf_bench.tscn
## Prints one line per probe: name, mean microseconds, and any layer redraw counters.
extends Node

const N := 40

func _ready() -> void:
	SaveSystem.autosave = false
	SaveSystem.path = "user://perf_bench.json"
	GameState.new_game()
	get_window().size = Vector2i(484, 1188)
	await get_tree().process_frame
	await _camp()
	await _delve()
	await _grid()
	_bot()
	_save()
	get_tree().quit()

func _time_frames(node: CanvasItem, frames: int) -> Dictionary:
	for i in 4:
		node.queue_redraw()
		await get_tree().process_frame
	var acc := 0.0
	var draws := 0.0
	var calls := 0.0
	for i in frames:
		node.queue_redraw()
		await get_tree().process_frame
		acc += Performance.get_monitor(Performance.TIME_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	return {"us": acc / float(frames) * 1000000.0, "draws": draws / float(frames), "objects": calls / float(frames)}

func _camp() -> void:
	var scene = load("res://scripts/ui/camp_scene.gd").new()
	scene.custom_minimum_size = Vector2(460, 700)
	scene.size = Vector2(460, 700)
	add_child(scene)
	await get_tree().process_frame
	var m: Dictionary = await _time_frames(scene, N)
	var extra := ""
	if scene.get("_ground_draws") != null:
		extra = " ground_draws=%s" % scene._ground_draws
	print("PERF camp_frame_us %.1f draw_us %.1f n %d%s" % [m.us, _avg(scene), scene.draw_n, extra])
	scene.queue_free()

func _delve() -> void:
	GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)
	var scene = load("res://scripts/ui/delve_scene.gd").new()
	scene.custom_minimum_size = Vector2(460, 420)
	scene.size = Vector2(960, 280)
	add_child(scene)
	scene.scroll = 40.0
	scene.target = 40.0
	await get_tree().process_frame
	var idle: Dictionary = await _time_frames(scene, N)
	scene.target = 80.0
	var move: Dictionary = await _time_frames(scene, N)
	var extra := ""
	if scene.get("_static_draws") != null:
		extra = " static_draws=%s" % scene._static_draws
	print("PERF delve_idle_us %.1f delve_move_us %.1f draw_us %.1f n %d%s" % [idle.us, move.us, _avg(scene), scene.draw_n, extra])
	scene.queue_free()
	GameState.run = {}

func _grid() -> void:
	var gv = load("res://scripts/ui/grid_view.gd").new()
	gv.custom_minimum_size = Vector2(460, 460)
	gv.size = Vector2(460, 460)
	var c := Combat.new()
	c.setup(DB.rooms[0], GameState.hero_stats("warrior"), 20, ["gnoll", "crab"])
	gv.set_combat(c)
	gv.lighting = true
	add_child(gv)
	await get_tree().process_frame
	var m: Dictionary = await _time_frames(gv, N)
	var extra := ""
	if gv.get("_ground_draws") != null:
		extra = " ground=%s walls=%s fog=%s" % [gv._ground_draws, gv._wall_draws, gv._fog_draws]
	print("PERF combat_grid_us %.1f draw_us %.1f n %d%s" % [m.us, _avg(gv), gv.draw_n, extra])
	gv.queue_free()

func _bot() -> void:
	var hs: Dictionary = GameState.hero_stats("warrior")
	var samples: Array = []
	for i in 12:
		var c := Combat.new()
		c.setup(DB.rooms[i % DB.rooms.size()], hs, int(hs.ht), ["gnoll", "crab", "rat"])
		var t0 := Time.get_ticks_usec()
		CombatBot.suggest(c, 2, 10)
		samples.append(Time.get_ticks_usec() - t0)
	samples.sort()
	var sum := 0
	for s in samples: sum += s
	var casts := 0
	var paths := 0
	var hits := 0
	for i in 12:
		var c2 := Combat.new()
		c2.setup(DB.rooms[i % DB.rooms.size()], hs, int(hs.ht), ["gnoll", "crab", "rat"])
		CombatBot.suggest(c2, 2, 10)
		casts += c2.fov_casts
		paths += c2.path_calls
		hits += c2.path_hits
	print("PERF bot_suggest_us mean %.0f median %d fov_casts %d path_calls %d path_hits %d" % [float(sum) / samples.size(), samples[samples.size() / 2], casts, paths, hits])
	var room: Array = DB.biome_rooms.prison[0]
	var deep := GameState.hero_stats("warrior")
	var fight := Combat.new()
	fight.setup(room, deep, int(deep.ht), ["guard", "skeleton", "thief"])
	var t1 := Time.get_ticks_usec()
	CombatBot.play(fight, 2, 10, 80)
	print("PERF bot_play_us %d turns %s fov_casts %d path_calls %d" % [Time.get_ticks_usec() - t1, fight.time, fight.fov_casts, fight.path_calls])

func _avg(node) -> float:
	if node.draw_n <= 0: return 0.0
	return float(node.draw_us_sum) / float(node.draw_n)

func _save() -> void:
	GameState.start_run("warrior", {"ration": 2, "torch": 2, "potion_healing": 2}, "sewers", 7)
	var t0 := Time.get_ticks_usec()
	for i in 8:
		SaveSystem.save_game()
	print("PERF save_us %.0f" % (float(Time.get_ticks_usec() - t0) / 8.0))
	GameState.run = {}
