## Headless scripted combat sim: godot --headless --path . -s tests/sim.gd
extends SceneTree

func _init() -> void:
	var fails := 0
	# Chip rule unit checks
	var c := Combat.new()
	c.setup(0, {"hp":20,"ht":20,"dmg":5,"dr":1,"barrier_max":6})
	c.hit_hero(1, "test")
	if c.hero.barrier != 5 or c.hero.hp != 20: fails += 1; print("FAIL chip")
	c.hit_hero(4, "test")
	if c.hero.barrier != 2 or c.hero.hp != 20: fails += 1; print("FAIL barrier spill ", c.hero)
	# Full greedy-AI fights in every room
	for r in Combat.ROOMS.size():
		c = Combat.new()
		c.setup(r, {"hp":20,"ht":20,"dmg":5,"dr":1,"barrier_max":6})
		var turns := 0
		while not c.over and turns < 200:
			turns += 1
			var es := c.enemies()
			var tgt = es[0]
			for e in es:
				if Combat.cheb(e.pos, c.hero.pos) < Combat.cheb(tgt.pos, c.hero.pos): tgt = e
			if Combat.cheb(tgt.pos, c.hero.pos) == 1:
				c.hero_tap(tgt.pos)
			else:
				var step = c._path_step(c.hero.pos, tgt.pos)
				if step == null or not c.hero_tap(step): c.hero_wait()
		print("room %d: turns=%d won=%s hp=%d barrier=%d loot=%d t=%.1f" % [r, turns, c.won, c.hero.hp, c.hero.barrier, c.loot, c.time])
		if not c.over: fails += 1; print("FAIL room did not finish")
	# Determinism: same inputs -> same result
	var a := Combat.new(); a.setup(1, {"hp":20,"ht":20,"dmg":5,"dr":1,"barrier_max":6})
	var b := Combat.new(); b.setup(1, {"hp":20,"ht":20,"dmg":5,"dr":1,"barrier_max":6})
	for i in 6: a.hero_wait(); b.hero_wait()
	if a.log_lines != b.log_lines: fails += 1; print("FAIL determinism")
	# Chasm knockback
	c = Combat.new(); c.setup(0, {"hp":20,"ht":20,"dmg":5,"dr":1,"barrier_max":6})
	var m = c.enemies()[0]; m.pos = Vector2i(2,2); c.hero.pos = Vector2i(1,2)
	c.knockback(m, Vector2i(1,0))
	if m.hp != 0: fails += 1; print("FAIL chasm")
	print("SIM RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
