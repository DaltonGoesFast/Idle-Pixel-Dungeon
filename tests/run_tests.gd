## Headless test suite (run as a scene so autoloads exist):
##   godot --headless --path . res://tests/run_tests.tscn
## Exit code 0 = all pass. Covers combat rules, balance (bot wins every encounter), delve, camp economy, save/load.
extends Node

var fails := 0
var passes := 0

func check(cond: bool, name: String) -> void:
	if cond: passes += 1
	else: fails += 1; print("  FAIL: ", name)

func _ready() -> void:
	var gs = GameState
	var ss = SaveSystem
	ss.autosave = false
	ss.path = "user://test_save.json"
	gs.new_game()
	test_rules(gs)
	test_balance(gs)
	test_boss(gs)
	test_fullrun(gs)
	test_delve(gs)
	test_camp(gs)
	test_save(gs, ss)
	print("TESTS: %d passed, %d failed -> %s" % [passes, fails, "PASS" if fails == 0 else "FAIL"])
	get_tree().quit(1 if fails else 0)

func warrior(gs) -> Dictionary:
	return gs.hero_stats("warrior")

func test_rules(gs) -> void:
	print("[rules]")
	var c := Combat.new()
	var hs := warrior(gs)
	c.setup(DB.rooms[0], hs, hs.ht, ["rat"])
	var b0: int = c.hero.barrier
	c.hit_hero(int(c.hero.dr), "t")
	check(c.hero.barrier == b0 - 1 and c.hero.hp == hs.ht, "chip rule: fully blocked hit removes 1 barrier")
	c.hero.barrier = 2; c.hit_hero(int(c.hero.dr) + 5, "t")
	check(c.hero.barrier == 0 and c.hero.hp == hs.ht - 3, "barrier absorbs then spills to HP")
	var m = c.enemies()[0]; m.pos = Vector2i(5, 2)  # next to chasm at (4,2)? room0 chasm at x3-4,y2-3
	c.knockback(m, Vector2i(-1, 0))
	check(m.hp == 0 and c.fallen_loot > 0, "knockback into chasm kills & halves loot")
	# determinism
	var a := Combat.new(); a.setup(DB.rooms[1], hs, hs.ht, ["gnoll", "crab"])
	var b := Combat.new(); b.setup(DB.rooms[1], hs, hs.ht, ["gnoll", "crab"])
	CombatBot.play(a); CombatBot.play(b)
	check(a.log_lines == b.log_lines, "combat is deterministic")
	# tick economy: crab (0.5) acts twice per hero tick
	var t := Combat.new(); t.setup(DB.rooms[0], hs, hs.ht, ["crab"])
	var crab = t.enemies()[0]; crab.pos = t.hero.pos + Vector2i(1, 1)
	var hp0: int = t.hero.hp + t.hero.barrier
	t.hero_wait(); t.hero_wait()
	# crab acts at 0.5, 1.0, 1.5 (hero wins the tie at 2.0) -> 3 hits in 2 hero ticks
	check(hp0 - (t.hero.hp + t.hero.barrier) == 3 * maxi(1, int(crab.dmg) - int(t.hero.dr)), "fast crab acts every 0.5 ticks")
	# surprise from grass
	var s := Combat.new(); s.setup(DB.rooms[0], hs, hs.ht, ["gnoll"])
	s.hero.pos = Vector2i(4, 1)  # grass tile in room0
	check(s.tile(s.hero.pos) == Combat.T.GRASS, "room0 (4,1) is grass")
	var g = s.enemies()[0]; g.pos = Vector2i(5, 1)
	s.hero_tap(g.pos)
	check(g.hp == int(g.ht) - int(hs.dmg * 1.5), "surprise ignores DR, x1.5")
	check(g.pos == Vector2i(6, 1), "surprise knockback")
	# telegraph resolves and can be dodged
	var d := Combat.new(); d.setup(DB.rooms[0], hs, hs.ht, ["gnoll"])
	var gn = d.enemies()[0]; gn.pos = d.hero.pos + Vector2i(3, 0); gn.next = 0.5
	d.hero.barrier = 0
	d.hero.next = 1.0; d.run_until_hero()
	check(not d.danger.is_empty(), "gnoll telegraphs a throw")
	d.hero_tap(d.hero.pos + Vector2i(0, 1))
	check(d.hero.hp == hs.ht, "stepping off the red tile dodges")

func test_balance(gs) -> void:
	print("[balance] bot plays every encounter set x every room, full HP, starting Warrior")
	var hs := warrior(gs)
	var sets: Array = DB.biomes.sewers.encounter_sets
	var wins := 0; var total := 0; var worst := 999
	for si in sets.size():
		for ri in DB.rooms.size():
			var c := Combat.new(); c.setup(DB.rooms[ri], hs, hs.ht, sets[si].mobs)
			var r := CombatBot.play(c)
			total += 1
			if r.won: wins += 1; worst = mini(worst, r.hp)
			else: print("  lost: set %s room %d" % [sets[si].mobs, ri])
	print("  warrior: %d/%d wins, lowest end HP %d/%d" % [wins, total, worst, hs.ht])
	check(wins == total, "starting Warrior beats every sewer encounter with sensible tactics")
	# door fights
	for dd in DB.doors:
		if dd.a.kind == "combat":
			var c := Combat.new(); c.setup(DB.rooms[2], hs, hs.ht, dd.a.mobs)
			check(CombatBot.play(c).won, "door fight %s winnable" % dd.id)
	var st := Combat.new(); st.setup(DB.rooms[0], hs, hs.ht, ["statue"])
	check(CombatBot.play(st).won, "statue fight winnable")
	for cls in ["mage", "rogue", "huntress"]:
		var ms: Dictionary = gs.hero_stats(cls)
		var mw := 0
		for si in sets.size():
			for ri in DB.rooms.size():
				var c := Combat.new(); c.setup(DB.rooms[ri], ms, ms.ht, sets[si].mobs)
				if CombatBot.play(c).won: mw += 1
		print("  %s: %d/%d wins" % [cls, mw, total])
		check(mw >= total * 0.9, "starting %s wins >=90%% of encounters" % cls)
	# cloak: enemies stop attacking, next hit is a surprise
	var rs: Dictionary = gs.hero_stats("rogue")
	var cc := Combat.new(); cc.setup(DB.rooms[0], rs, rs.ht, ["rat"])
	var rat = cc.enemies()[0]; rat.pos = cc.hero.pos + Vector2i(1, 0)
	var hp_before: int = cc.hero.hp + cc.hero.barrier
	check(cc.hero_cloak(), "rogue can cloak")
	check(cc.hero.hp + cc.hero.barrier == hp_before, "hidden rogue isn't attacked")
	cc.hero_tap(rat.pos)
	check(rat.hp <= 0, "cloaked dagger surprise (x2) kills a rat")
	# warrior slam knocks a crowd back
	var sl := Combat.new(); var ws := warrior(gs); sl.setup(DB.rooms[0], ws, ws.ht, ["rat", "rat"])
	var r1 = sl.enemies()[0]; var r2 = sl.enemies()[1]
	sl.hero.pos = Vector2i(3, 4); r1.pos = Vector2i(3, 3); r2.pos = Vector2i(4, 4)   # chasm at (3,2)? room0 rows 2-3 x3-4
	check(sl.hero_slam(), "warrior can slam")
	check(r1.hp <= 0, "slam knocks a rat into the chasm")
	check(not sl.hero_slam(), "slam is once per fight")
	# lightning chains through water
	gs.heroes.mage.wand = "wand_lightning"
	var ls: Dictionary = gs.hero_stats("mage")
	var lc := Combat.new(); lc.setup(DB.rooms[6], ls, ls.ht, ["rat", "rat"])
	var la = lc.enemies()[0]; var lb = lc.enemies()[1]
	la.pos = Vector2i(4, 2); lb.pos = Vector2i(5, 3); lc.hero.pos = Vector2i(2, 2)
	check(lc.tile(la.pos) == Combat.T.WATER and lc.tile(lb.pos) == Combat.T.WATER, "test rats stand in water")
	la.hp = 5; lb.hp = 3
	lc.hero_bolt(la.pos)
	check(la.hp <= 0 and lb.hp <= 0, "lightning chains through connected water")
	gs.heroes.mage.wand = "wand_magic_missile"
	# combat save/restore round trip
	var sv := Combat.new(); sv.setup(DB.rooms[1], ws, ws.ht, ["gnoll", "crab"])
	for i in 3: sv.hero_wait()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(sv.to_dict()))
	var rs2 := Combat.new(); rs2.from_dict(snap)
	CombatBot.play(sv); CombatBot.play(rs2)
	check(sv.log_lines == rs2.log_lines, "restored fight plays out identically")
	# huntress arrows are unlimited and respect DR
	var hu: Dictionary = gs.hero_stats("huntress")
	var hc := Combat.new(); hc.setup(DB.rooms[0], hu, hu.ht, ["crab"])
	var cr = hc.enemies()[0]
	for i in 3: hc.hero_bolt(cr.pos)
	check(cr.hp == int(cr.ht) - 3 * maxi(0, int(hu.bolt.dmg) - int(cr.dr)) or cr.hp <= 0 or Combat.cheb(cr.pos, hc.hero.pos) == 1, "arrows unlimited, DR applies")

func test_boss(gs) -> void:
	print("[boss]")
	for lvl in [3, 4]:
		gs.heroes.warrior.level = lvl
		var hs := warrior(gs)
		var c := Combat.new(); c.setup(DB.boss_rooms[0], hs, hs.ht, ["goo"])
		var r := CombatBot.play(c, 2)
		print("  Goo vs Warrior Lv%d: won=%s turns=%d hp=%d potions=%d" % [lvl, r.won, r.turns, r.hp, r.potions_used])
		check(r.won and c.boss_killed, "Lv%d Warrior with 2 potions beats Goo" % lvl)
	gs.heroes.warrior.level = 1
	var c2 := Combat.new(); var hs2 := warrior(gs); c2.setup(DB.boss_rooms[0], hs2, hs2.ht, ["goo"])
	var seen := false
	for i in 12:
		c2.hero_wait()
		if not c2.danger.is_empty(): seen = true; break
	check(seen, "Goo telegraphs its pump-up slam")

func test_fullrun(gs) -> void:
	print("[fullrun] CombatBot plays whole Sewers expeditions (2 rations, 2 torches, 2 potions), 10 seeds per class")
	for cls in ["warrior", "mage", "rogue", "huntress"]:
		var wins := 0; var deaths := []; var lv := 0
		for seed in 10:
			gs.new_game()
			for c in gs.heroes: gs.heroes[c].unlocked = true
			gs.add_mat("potion_healing", 1)
			var r := RunSim.play(gs, cls, {"ration": 2, "torch": 2, "potion_healing": 2}, 1000 + seed)
			if r.result == "extract": wins += 1; lv += r.level
			else: deaths.append("f%d %s" % [r.floor, r.boss_entry])
		print("  %s: cleared %d/10 (avg Lv at clear %.1f) deaths at %s" % [cls, wins, float(lv) / maxf(1, wins), deaths])
		check(wins >= 5, "%s clears the Sewers in at least half the seeded runs" % cls)

func test_delve(gs) -> void:
	print("[delve]")
	gs.new_game()
	check(gs.start_run("warrior", {"ration": 2, "torch": 2}, "sewers", 1234), "start run")
	check(gs.mat("ration") == 0, "supplies leave the stash")
	var kinds := []
	var events := 0
	var guard := 0
	while not Delve.floor_done(gs.run) and guard < 1000:
		guard += 1
		var ev := Delve.advance(gs, 1.0)
		if not ev.is_empty(): events += 1; kinds.append(ev.kind)
	check(events == 4, "4 encounters per floor (got %d)" % events)
	check(int(gs.run.pack.get("gold", 0)) == 25, "passive gold: 1 per 4%")
	# reproducible schedule
	var e1: Array = gs.run.events.duplicate(true)
	Delve.plan_floor(gs.run)
	check(e1 == gs.run.events, "event schedule is seeded")
	# go to floor 5: last event is the boss
	for f in 4: Delve.descend(gs)
	check(int(gs.run.floor) == 5 and gs.run.events.back().kind == "boss", "floor 5 ends with the boss")
	check(gs.heroes.warrior.str == 10, "no strength potion when floors are skipped")
	gs.run.floor = 2; Delve.plan_floor(gs.run)
	for i in 60: Delve.advance(gs, 1.0)
	check(gs.heroes.warrior.str == 11, "strength potion milestone at floor 2, 50%")
	gs.run.floor = 5; Delve.plan_floor(gs.run)
	# cost / reward
	gs.run.pack["iron_key"] = 0
	check(Delve.pay(gs, {"iron_key": 1}), "pay key from stash")
	check(not Delve.pay(gs, {"iron_key": 1}), "can't pay without key")
	Delve.reward(gs, {"item_unknown": "ring", "seeds": 2})
	check(gs.run.pack_gear.size() == 1 and int(gs.run.pack.seeds) == 2, "reward to pack")
	# death rules
	var wuid: int = gs.heroes.warrior.weapon
	gs.heroes.warrior.level = 3
	gs.end_run("death")
	check(gs.gear_by_uid(wuid).cracked and gs.heroes.warrior.level == 1 and gs.heroes.warrior.str == 10, "death cracks gear & resets hero")
	check(gs.mat("seeds") == 2, "death loses pack (stash seeds unchanged)")
	check(gs.repair(wuid) == false, "repair needs ore")
	gs.add_mat("iron_ore", 10); check(gs.repair(wuid), "repair with ore")
	# extraction banks pack
	gs.start_run("warrior", {}, "sewers", 7)
	gs.pack_add("iron_ore", 5); Delve.reward(gs, {"item": "dagger"})
	var ore0: int = gs.mat("iron_ore")
	gs.end_run("extract")
	check(gs.mat("iron_ore") == ore0 + 5 and gs.gear.any(func(g): return g.id == "dagger"), "extraction banks 100%")

func test_camp(gs) -> void:
	print("[camp]")
	gs.new_game()
	gs.add_mat("iron_ore", 50); gs.add_mat("gold", 500); gs.add_mat("seeds", 10); gs.add_mat("arcane_resin", 5)
	check(gs.craft("blacksmith", "forge_shortsword"), "forge shortsword")
	var ss = gs.gear.filter(func(g): return g.id == "shortsword")[0]
	check(gs.can_equip("warrior", ss.uid) == "", "can equip shortsword")
	gs.equip("warrior", ss.uid)
	check(gs.hero_stats("warrior").dmg == 8 - 4, "str 10 < 12 req: -2 dmg per point")
	check(gs.can_craft("blacksmith", "forge_mace") != "", "mace needs blacksmith lv2")
	check(gs.upgrade_item(ss.uid), "upgrade +1 (cap = blacksmith level 1)")
	check(not gs.upgrade_item(ss.uid), "can't exceed blacksmith cap")
	check(not gs.upgrade_facility("blacksmith"), "facility capped without SoU")
	gs.add_mat("scroll_upgrade", 1)
	check(gs.apply_sou("blacksmith") and gs.upgrade_facility("blacksmith"), "SoU breaks cap")
	check(gs.craft("alchemy", "brew_healing") and gs.mat("potion_healing") == 2, "brew potion")
	check(gs.craft("enchanter", "scribe_passage"), "scribe passage")
	# identify queue
	var ring: int = gs.add_gear("ring_might", false)
	check(gs.can_equip("warrior", ring) != "", "un-ID'd ring can't be equipped")
	gs.enqueue_identify(ring)
	gs.tick_identify(); check(not gs.gear_by_uid(ring).known, "not identified instantly")
	gs.time_offset += gs.identify_seconds() + 1
	gs.tick_identify(); check(gs.gear_by_uid(ring).known, "identified after the timer")
	var dmg0: int = gs.hero_stats("warrior").dmg
	gs.equip("warrior", ring); check(gs.hero_stats("warrior").dmg == dmg0 + 1, "ring of might +1")
	# patrols
	check(gs.can_patrol("warrior", "sewers") != "", "patrol needs cleared biome")
	gs.heroes.warrior.cleared.append("sewers")
	check(gs.start_patrol("warrior", "sewers"), "start patrol")
	check(gs.can_start_run("warrior") != "", "patrolling hero can't delve")
	gs.time_offset += 3 * 3600
	var y: Dictionary = gs.patrol_preview("warrior")
	check(is_equal_approx(y._hours, 2.0), "patrol capped at guild max (2h)")
	var ore: int = gs.mat("iron_ore")
	gs.collect_patrol("warrior")
	check(gs.mat("iron_ore") > ore, "patrol yields ore")
	# unlock
	gs.start_run("warrior", {}); gs.record_boss_kill("warrior", "sewers")
	check(gs.heroes.mage.unlocked and int(gs.run.pack.scroll_upgrade) == 1, "Goo kill unlocks Mage, drops SoU")
	check(not gs.heroes.huntress.unlocked, "huntress locked before 5 brews")
	gs.add_mat("seeds", 20)
	for i in 4: gs.craft("alchemy", "brew_healing")
	check(gs.heroes.huntress.unlocked, "5 potions brewed unlocks Huntress")
	gs.note_floor(4); check(gs.heroes.rogue.unlocked, "reaching floor 4 unlocks Rogue")
	gs.end_run("extract")

func test_save(gs, ss) -> void:
	print("[save]")
	gs.new_game(); gs.add_mat("gold", 77); gs.heroes.warrior.level = 4
	gs.start_run("warrior", {"ration": 1}, "sewers", 99)
	var before := JSON.stringify(gs.to_dict())
	check(ss.save_game(), "save")
	gs.new_game()
	check(ss.load_game(), "load")
	check(gs.mat("gold") == 107 and gs.heroes.warrior.level == 4 and not gs.run.is_empty(), "state restored")
	check(typeof(gs.heroes.warrior.weapon) == TYPE_INT, "ints restored as ints")
	ss.wipe()
