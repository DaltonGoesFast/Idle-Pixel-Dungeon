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
	test_traps(gs)
	test_prison(gs)
	test_caves(gs)
	test_fullrun(gs)
	test_cavesrun(gs)
	test_city(gs)
	test_halls(gs)
	test_render(gs)
	test_identify(gs)
	test_doors_grass(gs)
	test_paperdoll(gs)
	test_specials(gs)
	test_icon_centering(gs)
	test_armor_tiers(gs)
	test_floor_label(gs)
	test_total_wipe(gs)
	test_goo_spiral(gs)
	test_food_sources(gs)
	test_facility_cap(gs)
	test_owed_sou(gs)
	await test_icon_sizes(gs)
	test_full_auto(gs)
	test_encounter_dismiss(gs)
	await test_encounter_summary(gs)
	await test_menu_toast(gs)
	test_log_and_sounds(gs)
	test_ring_contexts(gs)
	test_item_badges(gs)
	test_forge_bulk(gs)
	test_break_rings(gs)
	test_all_icons(gs)
	test_delve(gs)
	test_camp(gs)
	test_camp_npc_hits()
	test_save(gs, ss)
	test_meta(gs, ss)
	test_subclass(gs, ss)
	test_talents(gs)
	test_backpack(gs)
	await test_touch_scroll()
	await test_tip_fit()
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
		if dd.a.kind == "combat" and "sewers" in dd.get("biomes", ["sewers"]):
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
	print("[deeprun] Lv1 hero with forged tier-2 gear, Sewers + Prison in one expedition (6 rations, 8 torches, 4 potions), 10 seeds")
	for cls in ["warrior", "mage", "rogue", "huntress"]:
		var wins := 0; var deaths := []
		for seed in 10:
			gs.new_game()
			for c in gs.heroes: gs.heroes[c].unlocked = true
			gs.add_mat("potion_healing", 2); gs.add_mat("ration", 4); gs.add_mat("torch", 6); gs.facilities.alchemy.level = 3
			_kit_tier2(gs, cls)
			var r := RunSim.play(gs, cls, {"ration": 6, "torch": 8, "potion_healing": 4}, 2000 + seed, true, "prison")
			if r.result == "extract" and r.biome == "prison": wins += 1
			else: deaths.append("f%d" % r.floor)
		print("  %s: cleared Prison %d/10, ended at %s" % [cls, wins, deaths])
		check(wins >= 2, "%s can clear the Prison in a single deep run sometimes" % cls)

func test_traps(gs) -> void:
	print("[traps]")
	gs.new_game()
	var hs := warrior(gs)
	var room := ["########", "#H^....#", "#.?....#", "#......#", "#......#", "#.....1#", "#......#", "########"]
	var c := Combat.new(); c.setup(room, hs, hs.ht, ["rat"], false, ["worn_dart"])
	check(c.traps.size() == 2 and c.visible_trap(Vector2i(2, 1)) and not c.visible_trap(Vector2i(2, 2)), "room parses visible + hidden traps")
	var hp0: int = c.hero.hp; var b0: int = c.hero.barrier
	c.hero_tap(Vector2i(2, 1))
	check(not c.traps.has(Vector2i(2, 1)) and (c.hero.hp < hp0 or c.hero.barrier < b0), "stepping on a trap fires it once")
	check(c.hero_search() and c.visible_trap(Vector2i(2, 2)), "search reveals adjacent hidden traps")
	# mobs path around traps; knockback pushes them in
	var c2 := Combat.new(); c2.setup(room, hs, hs.ht, ["rat"], false, ["gripping"])
	var m = c2.enemies()[0]; m.pos = Vector2i(3, 1); c2.hero.pos = Vector2i(1, 1)
	c2.traps.erase(Vector2i(2, 2))
	c2.knockback(m, Vector2i(-1, 0))
	check(m.pos == Vector2i(2, 1) and not c2.traps.has(Vector2i(2, 1)) and m.hp < m.ht, "knockback onto a trap triggers it")
	var c3 := Combat.new(); c3.setup(room, hs, hs.ht, ["rat"], false, ["teleport"])
	c3.hero_tap(Vector2i(2, 1))
	check(Combat.cheb(c3.hero.pos, Vector2i(6, 5)) >= 4 or c3.hero.pos != Vector2i(2, 1), "teleport trap moves the hero away")
	var c4 := Combat.new(); c4.setup(room, hs, hs.ht, ["rat"], false, ["poison_dart"])
	c4.hero.barrier = 0; c4.hero_tap(Vector2i(2, 1))
	var hp1: int = c4.hero.hp
	c4.hero_wait(); c4.hero_wait()
	check(c4.hero.hp <= hp1 - 2, "poison ticks 1/turn through DR")
	var rs := Combat.new(); rs.from_dict(c.to_dict())
	check(rs.traps.size() == c.traps.size(), "traps survive save/restore")
	gs.heroes.rogue.unlocked = true
	var rh: Dictionary = gs.hero_stats("rogue")
	var c5 := Combat.new(); c5.setup(room, rh, rh.ht, ["rat"], false, ["worn_dart"])
	c5.hero_tap(Vector2i(1, 2))
	check(c5.visible_trap(Vector2i(2, 2)), "Rogue's keen eyes spot adjacent hidden traps while moving")

func test_prison(gs) -> void:
	print("[prison] Lv5 Warrior, Str 12, Shortsword+1 / Leather+1 (GDD: Prison = 12-13 Str, tier 2-3) vs every Prison fight")
	gs.new_game()
	var w: Dictionary = gs.heroes.warrior
	w.level = 5; w.str = 12; w.weapon = gs.add_gear("shortsword", true, 1); w.armor = gs.add_gear("leather_armor", true, 1)
	var hs := warrior(gs)
	var b: Dictionary = DB.biomes.prison
	var wins := 0; var total := 0; var worst := 999
	for set in b.encounter_sets:
		for room in DB.rooms + DB.biome_rooms.prison:
			var c := Combat.new(); c.setup(room, hs, hs.ht, set.mobs, false, b.traps)
			var r := CombatBot.play(c)
			total += 1
			if r.won: wins += 1; worst = mini(worst, r.hp)
	print("  warrior Lv5: %d/%d wins, lowest end HP %d/%d" % [wins, total, worst, hs.ht])
	check(wins >= total * 0.95, "Lv5 Warrior wins >= 95% of Prison fights")
	var tw := 0
	for room_i in 3:
		var c := Combat.new(); c.setup(DB.boss_rooms[1], hs, hs.ht, ["tengu"], false, b.traps)
		var r := CombatBot.play(c, 2, 10)
		if r.won: tw += 1
		if room_i == 0: print("  Tengu vs Lv5 Warrior + 2 potions: won=%s hp=%d turns=%d" % [r.won, r.hp, r.turns])
	check(tw >= 1, "Tengu is beatable by a Lv5 Warrior with 2 potions")
	var t := Combat.new(); t.setup(DB.boss_rooms[1], hs, hs.ht, ["tengu"], false, b.traps)
	var tg = t.enemies()[0]
	var p0: Vector2i = tg.pos
	t.hit_mob(tg, 16, false, true)
	check(tg.pos != p0, "Tengu blinks away after losing 15 HP")
	tg.hp = 40; t.hero.pos = Vector2i(1, 1); tg.pos = Vector2i(5, 5); tg.bombs = 2
	t.hero_wait(); t.hero_wait()  # hero wins the tie at t=1, Tengu acts before t=2
	check(t.danger.size() >= 3, "enraged Tengu telegraphs a 3x3 bomb")
	var sk := Combat.new(); sk.setup(DB.rooms[0], hs, hs.ht, ["skeleton", "rat"])
	var s0 = sk.enemies()[0]
	sk.hit_mob(s0, 99, false, true)
	check(sk.danger.size() >= 6, "Skeleton death telegraphs a bone burst")

func test_caves(gs) -> void:
	print("[caves] Lv10 Warrior, Str 14, Mace+1 / Mail+1 (GDD Caves: 14-15 Str, tier 3) vs every Caves fight")
	gs.new_game()
	var w: Dictionary = gs.heroes.warrior
	w.level = 10; w.str = 14; w.weapon = gs.add_gear("mace", true, 1); w.armor = gs.add_gear("mail_armor", true, 1)
	var hs := warrior(gs)
	var b: Dictionary = DB.biomes.caves
	var wins := 0; var total := 0; var worst := 999
	for set in b.encounter_sets:
		for room in DB.rooms + DB.biome_rooms.caves:
			var c := Combat.new(); c.setup(room, hs, hs.ht, set.mobs, false, b.traps)
			var r := CombatBot.play(c)
			total += 1
			if r.won: wins += 1; worst = mini(worst, r.hp)
	print("  warrior Lv10: %d/%d wins, lowest end HP %d/%d" % [wins, total, worst, hs.ht])
	check(wins >= total * 0.95, "Lv10 tier-3 Warrior wins >= 95% of Caves fights")
	var c := Combat.new(); c.setup(DB.boss_rooms[2], hs, hs.ht, ["dm300"], false, b.traps)
	var r := CombatBot.play(c, 3, 10)
	print("  DM-300 vs Lv10 Warrior + 3 potions: won=%s hp=%d turns=%d" % [r.won, r.hp, r.turns])
	check(r.won, "DM-300 is beatable by a Lv10 tier-3 Warrior with 3 potions")
	var d := Combat.new(); d.setup(DB.boss_rooms[2], hs, hs.ht, ["dm300"])
	var dm = d.enemies()[0]
	for i in 6: d.hero_wait()
	check(d.danger.size() > 0 or d.log_lines.size() > 4, "DM-300 telegraphs abilities")
	dm.hp = 60; d.hero_wait(); d.hero_wait()
	check(dm.get("supercharged", false) and int(dm.dr) == 6, "DM-300 supercharges below half HP")
	var bt := Combat.new(); bt.setup(DB.rooms[0], hs, hs.ht, ["bat"])
	var bat = bt.enemies()[0]; bat.hp = 10; bat.pos = bt.hero.pos + Vector2i(1, 0)
	bt.hero.barrier = 0; bt.hero.dr = 0; bt.hero_wait()
	check(bat.hp > 10, "Vampire Bat heals when it bites")
	var sp := Combat.new(); sp.setup(DB.rooms[0], hs, hs.ht, ["spinner"])
	var spn = sp.enemies()[0]; spn.pos = sp.hero.pos + Vector2i(1, 0)
	sp.hero.barrier = 0; sp.hero.dr = 0; sp.hero_wait(); sp.hero_wait()
	check(int(sp.hero.poison) > 0, "Cave Spinner bite poisons")

func test_city(gs) -> void:
	print("[city] Lv14 Warrior, Str 16, Longsword+1 / Scale+1 (GDD City: 16-17 Str, tier 4) vs every City fight")
	gs.new_game()
	var w: Dictionary = gs.heroes.warrior
	w.level = 14; w.str = 16; w.weapon = gs.add_gear("longsword", true, 1); w.armor = gs.add_gear("scale_armor", true, 1)
	var hs := warrior(gs)
	var b: Dictionary = DB.biomes.city
	var wins := 0; var total := 0; var worst := 999
	for set in b.encounter_sets:
		for room in DB.rooms + DB.biome_rooms.city:
			var c := Combat.new(); c.setup(room, hs, hs.ht, set.mobs, false, b.traps)
			var r := CombatBot.play(c)
			total += 1
			if r.won: wins += 1; worst = mini(worst, r.hp)
	print("  warrior Lv14: %d/%d wins, lowest end HP %d/%d" % [wins, total, worst, hs.ht])
	check(wins >= total * 0.9, "Lv14 tier-4 Warrior wins >= 90% of City fights")
	var kw := 0
	for sd in 6:
		seed(1300 + sd)
		var kc := Combat.new(); kc.setup(DB.boss_rooms[b.boss_room], hs, hs.ht, ["dking"], false, b.traps)
		var kr := CombatBot.play(kc, 3, gs.potion_heal("warrior"))
		if kr.won: kw += 1
		if sd == 0 and OS.has_environment("SIM_DEBUG"): print("    ", "\n    ".join(kc.log_lines.slice(-70)))
		if sd == 0: print("  King of Dwarves vs Lv14 Warrior + 3 potions: won=%s hp=%d turns=%d king=%d" % [kr.won, kr.hp, kr.turns, kc.units.filter(func(u): return u.get("boss", false))[0].hp])
	print("  King wins %d/6" % kw)
	check(kw >= 3, "the King of Dwarves is beatable by a Lv14 tier-4 Warrior with 3 potions (>= 3/6)")
	var d := Combat.new(); d.setup(DB.boss_rooms[b.boss_room], hs, 999, ["dking"])
	var k = d.enemies()[0]
	var spawned := false; var blasted := false
	for i in 14:
		d.hero_wait()
		if d.danger.any(func(z): return z.has("spawn")): spawned = true
		if d.danger.any(func(z): return z.get("src", "") == "Shadow blast"): blasted = true
	check(spawned and blasted, "the King telegraphs both raise-dead and shadow blast")
	check(d.enemies().any(func(e): return e.get("summoned", false)), "Risen Dwarves appear after the telegraph")
	var before := int(k.hp)
	d.hit_mob(k, 30, false, true)
	check(before - int(k.hp) == 20, "lifelink: the King takes 2/3 damage while his dwarves live")
	k.hp = int(k.ht) / 5; k.abil = 0; k.abil_n = 0
	for e in d.enemies():
		if e.get("summoned", false): e.hp = 0
	d.units = d.units.filter(func(u): return u.hp > 0 or u.has("hero"))
	for i in 9: d.hero_wait()
	check(k.get("phase3", false) and not d.danger.any(func(z): return z.has("spawn")), "phase 3: the throne cracks and the King stops summoning")
	k.hp = 1; d.hit_mob(k, 999, false, true)
	check(d.over and d.won, "minions crumble when the King dies")
	for cls in ["warrior", "huntress"]:
		var cw := 0; var ends := []
		for seed in 6:
			gs.new_game()
			for cc in gs.heroes: gs.heroes[cc].unlocked = true
			gs.add_mat("potion_healing", 3); gs.add_mat("ration", 8); gs.add_mat("torch", 9); gs.facilities.alchemy.level = 4
			var hh: Dictionary = gs.heroes[cls]
			hh.level = 12; hh.str = 16; hh.mask = true; hh.subclass = DB.heroes[cls].subclasses.keys()[0]
			hh.armor = gs.add_gear("scale_armor", true, 1); hh.weapon = gs.add_gear("longsword", true, 1)
			var rr := RunSim.play(gs, cls, {"ration": 8, "torch": 9, "potion_healing": 5}, 5000 + seed, true, "city")
			if rr.result == "extract" and rr.biome == "city": cw += 1
			else: ends.append("f%d L%d" % [rr.floor, rr.level])
		print("  [cityrun] %s Lv12 tier-4 + subclass, floors 1-20 in one run: cleared City %d/6, ended at %s" % [cls, cw, ends])
	var g := Combat.new(); g.setup(DB.rooms[0], hs, 999, ["ghoul", "golem"])
	var gh = g.enemies()[0]
	g.hit_mob(gh, 999, false, true)
	check(g.danger.any(func(z): return z.get("spawn", "") == "ghoul"), "a Ghoul marks its corpse to rise again")
	for i in 3: g.hero_wait()
	check(g.enemies().any(func(e): return e.id == "ghoul" and e.get("revived", false)), "the Ghoul rises with half HP")

## The kit a player can forge after a couple of Sewers clears (see docs/BALANCE.md "Prison readiness").
func _kit_tier2(gs, cls: String) -> void:
	var h: Dictionary = gs.heroes[cls]
	h.armor = gs.add_gear("leather_armor", true, 1)
	match cls:
		"warrior", "huntress": h.weapon = gs.add_gear("shortsword", true, 1)
		"rogue": h.weapon = gs.add_gear("dagger", true, 2)

func test_meta(gs, ss) -> void:
	print("[meta]")
	gs.new_game()
	var gold0: int = gs.mat("gold")
	gs.stats.extractions = 1; gs.touch()
	check("first_steps" in gs.milestones_claimed and gs.mat("gold") == gold0 + 30, "milestone grants its reward once reached")
	gs.touch()
	check(gs.mat("gold") == gold0 + 30, "milestone rewards are only granted once")
	check(gs.stat_value("cleared:sewers") == 0, "cleared:<biome> counts heroes")
	gs.heroes.warrior.cleared.append("sewers"); gs.heroes.mage.cleared.append("sewers")
	check(gs.stat_value("cleared:sewers") == 2, "cleared:<biome> counts every hero that cleared it")
	check(not gs.heroes.mage.unlocked, "mage starts locked")
	gs.record_boss_kill("warrior", "sewers")
	check(gs.heroes.mage.unlocked and gs.stats.goo_kills == 1, "Goo kill unlocks the Mage via data rule")
	# fight results feed lifetime stats + codex
	gs.start_run("warrior", {}, "sewers", 3)
	var ev := Delve.combat_event(gs.run, Delve.rng_for(gs.run, 1), ["rat"])
	var c := Delve.new_combat(gs, ev)
	check(gs.seen.has("mob:rat"), "codex: meeting a mob discovers it")
	CombatBot.play(c)
	var k0: int = gs.stats.kills
	Delve.apply_fight_result(gs, ev, {"won": c.won, "hp": c.hero.hp, "loot": c.loot, "fallen_loot": 0, "xp": c.xp, "boss_killed": false, "kills": c.kills, "traps_found": 2, "trap_ids": ["gripping"]}, {})
	check(gs.stats.kills == k0 + 1 and gs.stats.traps_found == 2 and gs.seen.has("trap:gripping"), "fight results update kills / traps / codex")
	gs.end_run("abandon")
	# save v1 -> v2 migration back-fills Goo kills
	var old := {"version": 1, "state": {"stats": {"runs": 3, "deaths": 1}, "boss_kills": {"warrior": ["sewers"], "huntress": ["sewers"]}}}
	var mig: Dictionary = ss.migrate(old)
	check(int(mig.version) == 2 and int(mig.state.stats.goo_kills) == 2, "save v1 -> v2 migration back-fills goo_kills")
	# settings survive a round trip
	gs.settings.text_scale = 1.3; gs.settings.haptics = false
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game(); gs.from_dict(d)
	check(is_equal_approx(float(gs.settings.text_scale), 1.3) and gs.settings.haptics == false and "first_steps" in gs.milestones_claimed, "settings + milestones persist")
	gs.settings.text_scale = 1.0; gs.settings.haptics = true
	gs.settings.delve_speed = 2.0
	var d2: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict())); gs.from_dict(d2)
	check(is_equal_approx(float(gs.settings.delve_speed), 2.0), "delve speed setting persists")
	gs.settings.delve_speed = 1.0
	# tutorial bookkeeping
	gs.settings.tutorial = true; gs.tutorial_done = []
	check(gs.wants_tip("welcome") and not gs.wants_tip("no_such_tip"), "tips: known tip wanted once")
	gs.tutorial_done.append("welcome")
	check(not gs.wants_tip("welcome"), "tips: dismissed tip is not shown again")
	gs.settings.tutorial = false
	check(not gs.wants_tip("first_fight"), "tips: the setting turns every tip off")
	gs.settings.tutorial = true
	var tips_ok := true
	for id in DB.tips:
		for p in DB.tips[id].get("pages", [DB.tips[id]]): tips_ok = tips_ok and p.has("title") and p.has("text")
	check(tips_ok and DB.tips.size() >= 15, "every tutorial page has a title and text")

func test_cavesrun(gs) -> void:
	print("[cavesrun] returning Lv8 / Str 14 hero (levels persist between runs) with tier-3 gear, all 15 floors in one expedition, 10 seeds")
	var runs := []
	for cls in ["warrior", "huntress", "mage", "rogue"]:
		runs.append([cls, ""])
		for sid in DB.heroes[cls].subclasses: runs.append([cls, sid])
	var res := {}
	for cs in runs:
		var cls: String = cs[0]
		var wins := 0; var ends := []
		for seed in 10:
			gs.new_game()
			for c in gs.heroes: gs.heroes[c].unlocked = true
			gs.add_mat("potion_healing", 3); gs.add_mat("ration", 8); gs.add_mat("torch", 9); gs.facilities.alchemy.level = 4
			var h: Dictionary = gs.heroes[cls]
			h.level = 8; h.str = 14; h.subclass = cs[1]; h.mask = cs[1] != ""
			h.armor = gs.add_gear("mail_armor", true, 1)
			if cls in ["warrior", "huntress"]: h.weapon = gs.add_gear("mace", true, 1)
			elif cls == "rogue": h.weapon = gs.add_gear("dagger", true, 3)
			var r := RunSim.play(gs, cls, {"ration": 8, "torch": 9, "potion_healing": 5}, 3000 + seed, true, "caves")
			if r.result == "extract" and r.biome == "caves": wins += 1
			else: ends.append("f%d L%d" % [r.floor, r.level])
		print("  %s %s: cleared Caves %d/10, ended at %s" % [cls, cs[1], wins, ends])
		res[cls + ":" + cs[1]] = wins
		if cls == "warrior" and cs[1] == "": check(wins >= 2, "a geared Warrior can clear all 15 floors in one run sometimes")
	var best_rogue := maxi(res["rogue:assassin"], res["rogue:freerunner"])
	check(best_rogue >= 4, "a Rogue subclass makes the Caves winnable (best %d/10)" % best_rogue)

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

## Tapping the sprite or the name plate under it opens that facility. The plate used to hang outside
## the sprite's hit box, so Stash / Alchemy / Guild / Enchanter ignored clicks on their names.
func test_camp_npc_hits() -> void:
	print("[camp npc hits]")
	var scene = load("res://scripts/ui/camp_scene.gd").new()
	add_child(scene)
	var cases := [[40, Vector2(924, 1605)], [60, Vector2(1114, 2008)], [60, Vector2(2368, 2008)]]
	for c in cases:
		scene.theme = UIKit.make_theme(c[0])
		scene.size = c[1]
		for s in scene.SPOTS:
			var page: String = s[0]
			check(scene.spot_at(scene.spot_rect(s).get_center()) == page, "%s sprite @ %s" % [page, c[1]])
			var lr: Rect2 = scene.label_rect(s)
			check(scene.spot_at(lr.get_center()) == page, "%s name centre @ %s" % [page, c[1]])
			# glyphs sit on the baseline, near the bottom of the plate; the sides of a long name too
			check(scene.spot_at(Vector2(lr.get_center().x, lr.end.y - 2)) == page, "%s name bottom @ %s" % [page, c[1]])
			check(scene.spot_at(lr.position + Vector2(3, lr.size.y * 0.6)) == page, "%s name left @ %s" % [page, c[1]])
		check(scene.spot_at(Vector2(8, 8)) == "", "sky is not an NPC @ %s" % c[1])
	scene.queue_free()

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

func test_subclass(gs, ss) -> void:
	print("[subclass]")
	gs.new_game()
	check(not gs.can_choose_subclass("rogue"), "no subclass without Tengu's Mask")
	check(not gs.choose_subclass("rogue", "assassin"), "choose refused without mask")
	gs.record_boss_kill("rogue", "prison")
	check(gs.heroes.rogue.mask and gs.can_choose_subclass("rogue"), "Tengu kill grants the mask")
	var base: Dictionary = gs.hero_stats("rogue")
	check(gs.choose_subclass("rogue", "assassin"), "choose assassin")
	check(not gs.choose_subclass("rogue", "freerunner"), "subclass is permanent")
	var a: Dictionary = gs.hero_stats("rogue")
	check(a.surprise_mult == base.surprise_mult + 1.0 and a.cloak.charges == base.cloak.charges + 1, "assassin: +1x surprise, +1 cloak")
	var d: Dictionary = gs.to_dict(); gs.new_game(); gs.from_dict(d)
	check(gs.heroes.rogue.subclass == "assassin", "subclass survives save/load")
	gs.heroes.huntress.mask = true; gs.choose_subclass("huntress", "sniper")
	check(gs.hero_stats("huntress").bolt.get("pierce", false), "sniper bow ignores DR")
	gs.heroes.warrior.mask = true; gs.choose_subclass("warrior", "gladiator")
	var c := Combat.new()
	c.setup(["########","#......#","#.H1...#","#......#","#......#","#......#","#......#","########"], gs.hero_stats("warrior"), 999, ["rat"])
	var hits := []
	c.hero.combo = 2
	check(c._melee_dmg() == int(c.hero.dmg) + 2, "gladiator combo adds damage")
	gs.heroes.mage.mask = true; gs.choose_subclass("mage", "battlemage")
	c.setup(["########","#......#","#.H1...#","#......#","#......#","#......#","#......#","########"], gs.hero_stats("mage"), 999, ["rat"])
	c.hero.charges = 0; c.hero.combo = 4; c._melee_perks()
	check(c.hero.charges == 1, "battlemage: every 5th melee hit restores a charge")

func test_talents(gs) -> void:
	print("[talents]")
	gs.new_game()
	var h: Dictionary = gs.heroes.warrior
	check(gs.talent_points_total_free("warrior") == 0, "no talent points at Lv1")
	check(gs.can_pick_talent("warrior", "hearty_meal").begins_with("reach"), "tier 1 locked below its level")
	h.level = 5
	check(gs.talent_points_free("warrior", "1") == 2 and gs.talent_points_free("warrior", "2") == 0, "Lv5: 2 tier-1 points")
	var ht0: int = gs.hero_stats("warrior").ht
	check(gs.pick_talent("warrior", "hearty_meal") and gs.hero_stats("warrior").ht == ht0 + 3, "Hearty Meal +3 HP")
	check(not gs.pick_talent("warrior", "hearty_meal"), "no double pick")
	check(gs.pick_talent("warrior", "iron_will") and not gs.pick_talent("warrior", "veterans_intuition"), "points run out")
	check(not gs.pick_talent("warrior", "iron_stomach"), "tier 2 locked")
	h.level = 12
	check(gs.talent_points_free("warrior", "2") == 2, "Lv12: 2 tier-2 points")
	var dr0: int = gs.hero_stats("warrior").dr
	check(gs.pick_talent("warrior", "iron_stomach") and gs.hero_stats("warrior").dr == dr0 + 1, "Iron Stomach +1 DR")
	var p0: int = gs.potion_heal("warrior")
	gs.pick_talent("warrior", "liquid_willpower")
	check(gs.potion_heal("warrior") > p0, "Liquid Willpower boosts potions")
	# mid-delve pick raises run HP with max HP
	gs.heroes.mage.unlocked = true; gs.heroes.mage.level = 3
	gs.start_run("mage", {}, "sewers", 5)
	var hp0: int = gs.run.hp
	check(gs.pick_talent("mage", "tested_hypothesis") and gs.run.hp == hp0 + 3, "mid-delve talent adds the HP")
	gs.end_run("death")
	check(gs.heroes.mage.talents.is_empty(), "death resets talents with the level")

func test_backpack(gs) -> void:
	print("[backpack]")
	gs.new_game()
	gs.start_run("warrior", {"potion_healing": 1}, "sewers", 9)
	var old_w: int = gs.heroes.warrior.weapon
	Delve.reward(gs, {"item": "mace"})
	check(gs.backpack_used() == 1, "found gear goes in the backpack")
	var g: Dictionary = gs.run.pack_gear[0]
	var cmp: Dictionary = gs.compare_equip(int(g.uid))
	check(cmp.dmg[1] != cmp.dmg[0] or cmp.dr[1] == cmp.dr[0], "compare shows a damage change")
	check(gs.delve_equip(int(g.uid)), "equip mid-delve")
	check(gs.heroes.warrior.weapon == int(g.uid) and gs.run.pack_gear[0].uid == old_w and gs.run.pack_gear[0].owned, "old weapon goes to the backpack, owned")
	check(not gs.delve_drop(old_w), "owned items can't be dropped")
	check(gs.delve_unequip("armor") and gs.backpack_used() == 2, "unequip armor into the pack")
	for i in gs.BACKPACK_SLOTS - 2: Delve.reward(gs, {"item": "dagger"})
	check(gs.backpack_full(), "backpack fills up")
	Delve.reward(gs, {"item": "mail_armor"})
	check(gs.run.overflow.size() == 1 and gs.backpack_used() == gs.BACKPACK_SLOTS, "full pack: loot waits in overflow")
	var drop: int = int(gs.run.pack_gear.back().uid)
	check(gs.resolve_overflow(drop) and gs.pack_item(drop).is_empty() and gs.run.overflow.is_empty(), "drop one to take the new item")
	gs.run.hp = 5
	check(gs.delve_use("potion_healing") and gs.run.hp > 5, "drink a potion outside combat")
	# combat swap costs a turn and updates stats
	var c := Combat.new()
	c.setup(["########","#......#","#.H..1.#","#......#","#......#","#......#","#......#","########"], gs.hero_stats("warrior"), 20, ["rat"])
	var t0: float = c.hero.next
	var ar: Dictionary = gs.run.pack_gear.filter(func(x): return x.id == "cloth_armor")[0]
	gs.delve_equip(int(ar.uid))
	c.apply_stats(gs.hero_stats("warrior")); c.hero_wait()
	check(c.hero.next == t0 + 1.0 and c.hero.dr == gs.hero_stats("warrior").dr, "in-combat swap: new stats, 1 tick")
	gs.end_run("death")
	check(gs.gear_by_uid(old_w).get("cracked", false), "owned gear in the pack comes home (cracked) on death")
	var saved := {}

func test_render(gs) -> void:
	print("[render]")
	var gv = load("res://scripts/ui/grid_view.gd").new()
	var c := Combat.new(); c.setup(DB.rooms[0], warrior(gs), 20, ["rat"])
	for y in Combat.SIZE:
		for x in Combat.SIZE: c.terrain[y][x] = Combat.T.FLOOR
	c.terrain[3][3] = Combat.T.WALL; c.terrain[4][3] = Combat.T.WALL; c.terrain[5][5] = Combat.T.WATER
	gv.combat = c; gv.set_combat(c)
	check(gv.terrain_visual(Vector2i(3, 4)) >= 80 and gv.terrain_visual(Vector2i(3, 4)) < 112, "wall above floor gets a raised SPD wall face")
	check(gv.terrain_visual(Vector2i(3, 3)) == -1 and gv.wall_visual(Vector2i(3, 3)) >= 144, "wall above wall is an internal wall top")
	check(gv.wall_visual(Vector2i(3, 2)) >= 192 and gv.wall_visual(Vector2i(3, 2)) < 224, "floor above a wall gets the overhang")
	check(gv.terrain_visual(Vector2i(5, 5)) == 32 + 15, "isolated water stitches all 4 edges")
	check(gv.terrain_visual(Vector2i(0, -1)) >= 80, "arena border is a raised SPD wall")
	check(gv.anims.has("rat") and gv.anims.rat.has("die"), "SPD sprite animations loaded")
	check(gv._frame("rat", "attack", 0.0) == 2, "rat attack anim starts on SPD frame 2")
	gv.free()

func test_halls(gs) -> void:
	print("[halls] Lv18 Warrior, Str 18, Greatsword+2 / Plate+2 (tier 5) vs every Halls fight")
	gs.new_game()
	var w: Dictionary = gs.heroes.warrior
	w.level = 18; w.str = 18; w.weapon = gs.add_gear("greatsword", true, 2); w.armor = gs.add_gear("plate_armor", true, 2)
	var hs := warrior(gs)
	var b: Dictionary = DB.biomes.halls
	check(DB.biomes.city.next == "halls" and b.boss == "yog", "Demon Halls follow the City, Yog-Dzewa is the boss")
	var wins := 0; var total := 0; var worst := 999
	for set in b.encounter_sets:
		for room in DB.rooms + DB.biome_rooms.halls:
			var c := Combat.new(); c.setup(room, hs, hs.ht, set.mobs, false, b.traps)
			var r := CombatBot.play(c)
			total += 1
			if r.won: wins += 1; worst = mini(worst, r.hp)
	print("  warrior Lv18: %d/%d wins, lowest end HP %d/%d" % [wins, total, worst, hs.ht])
	check(wins >= total * 0.85, "Lv18 tier-5 Warrior wins >= 85% of Halls fights")
	var yw := 0
	for seed in 4:
		var yc := Combat.new(); seed(900 + seed); yc.setup(DB.boss_rooms[b.boss_room], hs, hs.ht, ["yog"], false, b.traps)
		var yr := CombatBot.play(yc, 3, gs.potion_heal("warrior"))
		if yr.won: yw += 1
		if seed == 0: print("  Yog-Dzewa vs Lv18 Warrior + 3 potions: won=%s hp=%d turns=%d yog=%d" % [yr.won, yr.hp, yr.turns, yc.units.filter(func(u): return u.get("boss", false))[0].hp])
	print("  Yog wins %d/4" % yw)
	check(yw >= 2, "Yog-Dzewa is beatable by a Lv18 tier-5 Warrior with 3 potions (>= 2/4)")
	var d := Combat.new(); d.setup(DB.boss_rooms[b.boss_room], hs, 999, ["yog"])
	var y = d.enemies()[0]; var start: Vector2i = y.pos
	var hatched := false; var gazed := false
	d.hit_mob(y, 50, false, true)
	check(y.hp == y.ht and d.enemies().any(func(e): return e.id == "fist_burning"), "phase 1: a Burning Fist shields Yog (no damage)")
	for e in d.enemies():
		if e.get("fist", false): d.hit_mob(e, 999, false, true)
	d.hit_mob(y, 999, false, true)
	check(y.hp == int(ceil(y.ht * 2 / 3.0)) and d.enemies().any(func(e): return e.id == "fist_rotting"), "phase 2 at 2/3 HP: Rotting Fist rises, damage stops at the threshold")
	for e in d.enemies():
		if e.get("fist", false): d.hit_mob(e, 999, false, true)
	for i in 14:
		d.hero_wait()
		if d.danger.any(func(z): return z.get("src", "") == "Larva hatching"): hatched = true
		if d.danger.any(func(z): return z.get("src", "") == "Yog's gaze"): gazed = true
	check(hatched and gazed, "Yog telegraphs larva and its gaze beam")
	check(y.pos == start, "Yog-Dzewa never moves")
	for e in d.enemies():
		if e.get("fist", false): d.hit_mob(e, 999, false, true)
	y.phase = 3; y.hp = 1; d.hit_mob(y, 999, false, true)
	check(d.over and d.won, "larva and fists die with Yog")
	var hw := 0; var ends := []
	for seed in 4:
		gs.new_game()
		for cc in gs.heroes: gs.heroes[cc].unlocked = true
		gs.facilities.alchemy.level = 4
		gs.add_mat("potion_healing", 8); gs.add_mat("ration", 16); gs.add_mat("torch", 16)
		var hh: Dictionary = gs.heroes.warrior
		hh.level = 16; hh.str = 18; hh.mask = true; hh.subclass = DB.heroes.warrior.subclasses.keys()[0]
		hh.armor = gs.add_gear("plate_armor", true, 1); hh.weapon = gs.add_gear("greatsword", true, 1)
		var rr := RunSim.play(gs, "warrior", {"ration": 16, "torch": 16, "potion_healing": 8}, 7000 + seed, true, "halls")
		if rr.result == "extract" and rr.biome == "halls": hw += 1
		else: ends.append("f%d L%d" % [rr.floor, rr.level])
	print("  [hallsrun] warrior Lv16 tier-5 + subclass, floors 1-25 in one run: cleared Halls %d/4, ended at %s" % [hw, ends])
	check(hw >= 2, "a tier-5 Warrior can clear floors 1-25 in one run (>= 2/4)")


func test_identify(gs) -> void:
	print("[identify]")
	gs.new_game()
	var um: Array = gs.unknown_mats()
	check(um.size() == 6, "six unknown potions/scrolls")
	check(not gs.is_mat_known("potion_shielding"), "shielding starts unknown")
	check(gs.mat_label("potion_shielding").ends_with("Potion"), "unknown label shows appearance")
	var u: int = gs.add_gear("chalice_blood")
	var base := int(gs.hero_stats("warrior").ht)
	check(gs.equip("warrior", u), "artifact equips")
	check(int(gs.hero_stats("warrior").ht) == base + 15, "chalice +15 HT")
	var r: int = gs.add_gear("ring_energy")
	gs.equip("warrior", r)
	check(int(gs.hero_stats("warrior").ht) == base + 19, "ring of energy stacks with artifact")
	check(gs.start_run("warrior", {}), "run starts")
	gs.run.pack["potion_shielding"] = 1; gs.run.pack["scroll_teleport"] = 1
	check(gs.delve_use_pack("potion_shielding") and int(gs.run.shield_next) == 10, "shielding queues barrier")
	check(gs.is_mat_known("potion_shielding"), "use identifies")
	check(gs.delve_use_pack("scroll_teleport") and gs.run.skip_card, "teleport flags skip")
	check(not gs.delve_use_pack("scroll_teleport"), "can't use what you don't have")
	var d: Dictionary = gs.to_dict(); gs.ided = {}; gs.from_dict(d)
	check(gs.is_mat_known("potion_shielding"), "identification persists")
	gs.end_run("extract")
	gs.add_mat("potion_toxic", 1); gs.add_mat("seeds", 1)
	var hp0: int = gs.mat("potion_healing")
	check(not gs.is_mat_known("potion_toxic") and gs.craft("alchemy", "transmute_toxic"), "brew with an unknown potion")
	check(gs.mat("potion_healing") == hp0 + 2 and gs.is_mat_known("potion_toxic"), "alchemy yields x2 and identifies the ingredient")


func test_doors_grass(gs) -> void:
	print("[doors/grass]")
	var gv = load("res://scripts/ui/grid_view.gd").new()
	var c := Combat.new(); c.setup(DB.rooms[0], warrior(gs), 20, ["rat"])
	for y in Combat.SIZE:
		for x in Combat.SIZE: c.terrain[y][x] = Combat.T.FLOOR
	for x in Combat.SIZE: c.terrain[3][x] = Combat.T.WALL
	c.terrain[3][4] = Combat.T.DOOR
	c.hero.pos = Vector2i(1, 6); c.enemies()[0].pos = Vector2i(7, 7)
	gv.combat = c; gv.set_combat(c)
	var door := Vector2i(4, 3); var above := Vector2i(4, 2)
	check(gv.terrain_visual(door) == 112 and gv.wall_visual(above) == 224, "empty door: closed door + closed overhang")
	c.hero.pos = door
	check(gv.terrain_visual(door) == 113 and gv.wall_visual(above) == 225, "occupied door: SPD open door + open overhang")
	c.hero.pos = Vector2i(4, 4)
	check(gv.terrain_visual(door) == 112, "door closes again when vacated")
	# sideways door (wall above and below)
	for y in Combat.SIZE: c.terrain[y][6] = Combat.T.WALL
	c.terrain[6][6] = Combat.T.DOOR
	var sd := Vector2i(6, 6)
	check(gv.terrain_visual(sd) == 116 and gv.wall_visual(sd) >= 212 and gv.wall_visual(sd) < 216, "sideways door: closed frame on the walls layer")
	c.hero.pos = sd
	check(gv.wall_visual(sd) >= 208 and gv.wall_visual(sd) < 212 and gv.wall_visual(Vector2i(6, 5)) == -1, "sideways door opens over the occupant")
	# grass
	c.terrain[6][2] = Combat.T.GRASS
	check(gv.grass_overhang(Vector2i(2, 5)) >= 234 and gv.wall_visual(Vector2i(2, 5)) == -1, "grass overhang is in the ground pass, not over units")
	c.hero.pos = Vector2i(2, 5)
	c._place(c.hero, Vector2i(2, 6))
	check(c.tile(Vector2i(2, 6)) == Combat.T.FLOOR and c.trampled.has(Vector2i(2, 6)), "walking into tall grass tramples it")
	check(gv.terrain_visual(Vector2i(2, 6)) in [2, 8], "trampled grass draws as SPD short grass")
	var c2 := Combat.new(); c2.setup(DB.rooms[0], warrior(gs), 20, ["rat"]); c2.from_dict(c.to_dict())
	check(c2.trampled.has(Vector2i(2, 6)), "trampled grass survives save/load")
	gv.free()

func test_paperdoll(gs) -> void:
	print("[paperdoll]")
	gs.new_game()
	var w: Dictionary = gs.heroes.warrior
	w.str = 12
	var host := VBoxContainer.new()
	Paperdoll.sel_slot = "weapon"
	gs.add_gear("shortsword")
	Paperdoll.build(host, "warrior", true, "camp", func(): pass)
	check(host.get_child_count() == 1, "paperdoll builds")
	check(not Paperdoll.slot_item("warrior", "weapon").is_empty() and not Paperdoll.slot_item("warrior", "class").is_empty(), "weapon + class item slots filled")
	check(Paperdoll.slot_item("warrior", "artifact").is_empty(), "empty artifact slot")
	var s0: Dictionary = gs.hero_stats("warrior")
	var sw: int = gs.gear.filter(func(g): return g.id == "shortsword")[0].uid
	var s1: Dictionary = Paperdoll._stats_with("warrior", "weapon", sw)
	check(int(s1.dmg) > int(s0.dmg) and int(gs.hero_stats("warrior").dmg) == int(s0.dmg), "swap preview changes dmg without equipping")
	check(Paperdoll._delta_text(s0, s1)[1] > 0, "delta marks the upgrade as better")
	Paperdoll.sel_slot = ""
	host.free()


func test_specials(gs) -> void:
	print("[special rooms]")
	gs.new_game(); gs.start_run("warrior", {}, "sewers", 3)
	var ids: Array = DB.specials.map(func(x): return x.id)
	for want in ["vault", "library", "well_health", "well_awareness", "laboratory", "treasury", "shrine", "larder"]:
		check(want in ids, "special room exists: " + want)
	gs.run.hp = 5
	Delve.reward(gs, {"heal_pct": 100})
	check(int(gs.run.hp) == int(gs.hero_stats("warrior").ht), "Well of Health heals fully")
	gs.run.pack_gear.append({"uid": 999, "id": "ring_wealth", "lvl": 0, "cracked": false, "known": false})
	gs.run.pack["potion_toxic"] = 1
	Delve.reward(gs, {"identify_pack": 1})
	check(gs.run.pack_gear[-1].known and gs.is_mat_known("potion_toxic"), "Well of Awareness identifies the pack")
	var n0: int = gs.run.pack_gear.size()
	var got := Delve.reward(gs, {"artifact": 1})
	check(gs.run.pack_gear.size() == n0 + 1 and DB.item(gs.run.pack_gear[-1].id).type == "artifact", "Shrine gives an artifact (%s)" % got)
	gs.run.satiety = 10.0; Delve.reward(gs, {"satiety": 100})
	check(float(gs.run.satiety) == 100.0, "Larder refills satiety")
	var garden: Dictionary = DB.specials.filter(func(x): return x.id == "garden")[0]
	var fire: Dictionary = DB.specials.filter(func(x): return x.id == "sacrificial_fire")[0]
	check(garden.options.size() >= 4 and fire.options.size() >= 3, "garden and sacrificial fire have SPD-style choices")
	var rest: Dictionary = garden.options[1]
	gs.run.hp = 5; Delve.pay(gs, rest.cost); Delve.reward(gs, rest.reward)
	check(float(gs.run.satiety) == 85.0 and int(gs.run.hp) > 5, "resting in the sungrass heals for food (sat %s hp %s)" % [gs.run.satiety, gs.run.hp])
	var fe := Delve.combat_event(gs.run, Delve.rng_for(gs.run, 55), [])
	check(fe.kind == "combat" and not fe.mobs.is_empty() and fire.options[1].fight == "biome", "sacrificial fire lures a biome encounter")
	gs.end_run("abandon")


func test_icon_centering(_gs) -> void:
	print("[icon centring]")
	var bad := []
	for id in ["GOLD", "DEWDROP", "TORCH", "IRON_KEY", "RATION", "SEED_SUNGRASS" if DB.icons.has("SEED_SUNGRASS") else "ORE", "RING_HOLDER", "WEAPON_HOLDER", "ARMOR_HOLDER", "ARTIFACT_HOLDER"]:
		var ic: PixelIcon = UIKit.icon(id, 48)
		var tex_sz: Vector2 = ic.texture.get_size()
		var r := PixelIcon.layout(Vector2(72, 72), tex_sz, ic.draw_k())
		var off := (r.get_center() - Vector2(36, 36)).abs()
		if r.position != r.position.floor() or off.x > 0.5 * ic.scale_k() + 0.01 or off.y > 0.5 * ic.scale_k() + 0.01 or ic.scale_k() != 3: bad.append(id)
	check(bad.is_empty(), "item icons are integer-scaled and centred on their visible pixels %s" % [bad])
	check(UIKit.item_rect(DB.icon_index("IRON_KEY")).size == Vector2(8, 14), "SPD item rects loaded (iron key 8x14)")
	# DECISIONS #111: rings/potions/scrolls had no rect, so a full 16x16 cell was centred and the 8x10 ring sat top-left
	var no_rect := []
	for k in DB.icons:
		if typeof(DB.icons[k]) in [TYPE_INT, TYPE_FLOAT] and not UIKit._rects.has(str(int(DB.icons[k]))): no_rect.append(k)
	check(no_rect.is_empty(), "every icon id has an SPD item rect %s" % [no_rect])
	check(UIKit.item_rect(DB.icon_index("ring_wealth")).size == Vector2(8, 10), "ring rect is SPD's 8x10")
	var ring: PixelIcon = UIKit.icon("ring_wealth", 48); var sword: PixelIcon = UIKit.icon("shortsword", 48)
	check(ring.draw_k() == sword.draw_k() + 1, "tiny ring sprites draw one scale step larger (%d vs %d)" % [ring.draw_k(), sword.draw_k()])
	check(int(UIKit.btn_height()) % 2 == 0 and UIKit.btn_height() == floorf(UIKit.btn_height()), "button height is an even whole number")
	for n in ["enter", "backpack_lrg", "prefs", "journal", "talent"]:
		var t := UIKit.toolbar_icon(n)
		if int(t.get_width()) % 2 != 0 or int(t.get_height()) % 2 != 0: bad.append(n)
	check(bad.is_empty(), "toolbar/UI icons padded to even sizes %s" % [bad])

## Equipping each armor tier moves the hero sprite to that SPD HeroSprite row everywhere it is drawn.
func test_armor_tiers(gs) -> void:
	print("[armor tiers]")
	var old: int = gs.heroes.warrior.armor
	var regions := []; var imgs := []
	for id in ["cloth_armor", "leather_armor", "mail_armor", "scale_armor", "plate_armor"]:
		var uid: int = gs.add_gear(id)
		gs.heroes.warrior.armor = uid
		var hs: Dictionary = gs.hero_stats("warrior")
		var at: AtlasTexture = Paperdoll.hero_tex("warrior")
		check(int(hs.row) == int(DB.item(id).tier) and at.region.position.y == hs.row * 15, "%s -> sprite row %d" % [id, hs.row])
		regions.append(at.region.position.y); imgs.append(at.get_image().get_data())
	var distinct := {}
	for d in imgs: distinct[d] = true
	check(distinct.size() == 5 and regions == [15.0, 30.0, 45.0, 60.0, 75.0], "5 tiers give 5 different sprite frames (cloth is row 1, not naked)")
	var whs: Dictionary = gs.hero_stats("warrior"); var c := Combat.new(); c.setup(DB.rooms[1], whs, int(whs.ht), ["gnoll"])
	check(int(c.hero.get("row", -1)) == 5, "combat hero carries the armor row")
	gs.heroes.warrior.armor = old

## The Delve title "<Biome> - Floor f / last" always has f inside the biome's floor range, through every biome
## transition, and a corrupted save is clamped on load.
func test_floor_label(gs) -> void:
	print("[floor label]")
	var saved_run: Dictionary = gs.run.duplicate(true)
	gs.run = {}
	for k in ["ration", "torch"]: gs.add_mat(k, 1)
	gs.start_run("warrior", {}, "sewers", 7)
	var bad := []; var seen := {}
	for step in 40:
		var b: Dictionary = DB.biomes[gs.run.biome]; seen[gs.run.biome] = true
		if int(gs.run.floor) < int(b.floors[0]) or int(gs.run.floor) > int(b.floors[1]): bad.append("%s %d" % [gs.run.biome, gs.run.floor])
		if int(gs.run.floor) >= int(b.boss_floor):
			if Delve.next_biome(gs.run) == "": break
			gs.run.boss_dead = true; Delve.continue_deeper(gs)
		else: Delve.descend(gs)
	check(bad.is_empty() and seen.size() == DB.biomes.size(), "floor stays inside its biome across all %d biomes %s" % [seen.size(), bad])
	gs.run.biome = "sewers"; gs.run.floor = 25
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(int(gs.run.floor) == 5, "a save with Floor 25 in the Sewers loads clamped to the Sewers")
	gs.run = saved_run


## A touch drag that starts on a Button scrolls its ScrollContainer, carries on with momentum, and does not
## fire the Button; a plain tap still does.
func test_touch_scroll() -> void:
	print("[touch scroll]")
	var root := Control.new(); root.size = Vector2(400, 400); add_child(root)
	var ts := TouchScroll.new(); root.add_child(ts)
	var sc := ScrollContainer.new(); sc.position = Vector2.ZERO; sc.size = Vector2(400, 400); root.add_child(sc)
	TouchScroll.style(sc)
	var v := VBoxContainer.new(); sc.add_child(v)
	var fired := [0]
	for i in 30:
		var b := Button.new(); b.text = "Slot %d" % i; b.custom_minimum_size = Vector2(380, 60); v.add_child(b)
		b.pressed.connect(func(): fired[0] += 1)
	for i in 3: await get_tree().process_frame
	var vp := get_viewport(); get_window().notification(NOTIFICATION_WM_MOUSE_ENTER); vp.notification(NOTIFICATION_VP_MOUSE_ENTER)
	var send := func(ev: InputEvent): ts._input(ev)   # headless has no GUI dispatch: feed the scroller directly
	var mb := func(p: Vector2, down: bool) -> InputEventMouseButton:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; return e
	var mm := func(p: Vector2, rel: Vector2) -> InputEventMouseMotion:
		var e := InputEventMouseMotion.new(); e.position = p; e.global_position = p; e.relative = rel; e.button_mask = MOUSE_BUTTON_MASK_LEFT; return e
	# drag up 200 px starting on "Slot 2"
	var p := Vector2(200, 150)
	send.call(mm.call(p, Vector2.ZERO)); await get_tree().process_frame
	send.call(mb.call(p, true))
	for i in 10:
		var q := p - Vector2(0, 20); send.call(mm.call(q, q - p)); p = q
		await get_tree().process_frame
	var after_drag := sc.scroll_vertical
	var masked: BaseButton = ts._masked
	check(masked != null and masked.button_mask == 0, "the button under the drag has its press cancelled")
	send.call(mb.call(p, false))
	for i in 10: await get_tree().process_frame
	check(after_drag >= 150, "drag starting on a button scrolls the container (%d px)" % after_drag)
	check(fired[0] == 0 and masked.button_mask == MOUSE_BUTTON_MASK_LEFT, "the button does not fire and is re-armed after release")
	check(sc.scroll_vertical > after_drag, "kinetic scroll carries on after release (%d -> %d)" % [after_drag, sc.scroll_vertical])
	check(sc.get_v_scroll_bar().custom_minimum_size.x >= 10 and sc.scroll_deadzone > 0, "wide scrollbar and deadzone")
	# a tap still presses
	ts.momentum = null
	for i in 3: await get_tree().process_frame
	var t := Vector2(200, 200)
	for bb in v.get_children():   # the centre of a visible button (not the gap between two)
		var gr: Rect2 = bb.get_global_rect()
		if gr.position.y > 40 and gr.end.y < 360: t = gr.get_center(); break
	send.call(mm.call(t, Vector2.ZERO)); await get_tree().process_frame
	send.call(mb.call(t, true)); await get_tree().process_frame
	var tapped: Control = ts._hov
	send.call(mb.call(t, false)); await get_tree().process_frame
	check(not ts.dragging and ts._masked == null and tapped is Button and tapped.button_mask == MOUSE_BUTTON_MASK_LEFT, "a tap without movement is left to the button (%s %s %s)" % [ts.dragging, ts._masked, tapped])
	root.queue_free()

## Every item and material id (known and unidentified) resolves to an items.png cell with visible pixels; rings,
## potions and scrolls get their SPD appearance sprites (gems, colours, runes) and are not the fallback icon.
func test_all_icons(gs) -> void:
	print("[all icons]")
	var img: Image = (load("res://assets/sprites/items.png") as Texture2D).get_image()
	var bad := []
	var ids: Array = DB.items.keys().filter(func(k): return not k.begins_with("_")) + DB.materials.keys().filter(func(k): return not k.begins_with("_"))
	for id in ids:
		var idx := DB.icon_index(id)
		var r := UIKit.item_rect(idx)
		var vis := 0
		var sub := img.get_region(Rect2i(r))
		for y in sub.get_height():
			for x in sub.get_width():
				if sub.get_pixel(x, y).a > 0.1: vis += 1
		var t: String = DB.items.get(id, DB.materials.get(id, {})).get("type", "")
		var appearance: bool = t in ["ring", "potion", "scroll"] or id.begins_with("potion_") or id.begins_with("scroll_") or id.begins_with("ring_")
		if vis < 6 or (appearance and idx == int(DB.icons.get("SOMETHING", -1))) or idx <= 0: bad.append("%s=%d" % [id, idx])
	gs.new_game()
	var holders := [int(DB.icons.POTION_HOLDER), int(DB.icons.SCROLL_HOLDER)]
	for k in gs.unknown_mats():
		var before := DB.icon_index(k)
		gs.ided[k] = true
		var after := DB.icon_index(k)
		if after != before or after in holders or after <= 0: bad.append("ided %s %d->%d" % [k, before, after])
	check(bad.is_empty(), "%d item ids resolve to visible SPD icons %s" % [ids.size(), bad])


## Every tutorial tip page fits inside its card, and the card inside the screen with margins, at the Fold cover
## and inner sizes (real device px with the font sizes Main picks for them).
func test_tip_fit() -> void:
	print("[tip fit]")
	var fs0 := UIKit.font_size
	var bad := []
	for sz in [[Vector2(968, 2376), 30], [Vector2(1856, 2160), 34], [Vector2(484, 1188), 16]]:
		UIKit.make_theme(int(sz[1]))
		var ov: Control = load("res://scripts/ui/tip_overlay.gd").new()
		var holder := Control.new(); holder.theme = UIKit.make_theme(int(sz[1])); holder.size = sz[0]; add_child(holder)
		holder.add_child(ov); ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ov.size = sz[0]
		for id in DB.tips:
			var pages: Array = DB.tips[id].get("pages", [DB.tips[id]])
			for pi in pages.size():
				ov.queue = [{"id": id, "pages": pages}]; ov.page = pi; ov._render()
				for f in 3: await get_tree().process_frame
				var cr: Rect2 = ov.card.get_global_rect(); var hr := Rect2(holder.global_position, sz[0])
				var m: float = ov.margin(sz[0]) - 1.0
				var inside := cr.position.x >= hr.position.x + m and cr.end.x <= hr.end.x - m and cr.position.y >= hr.position.y and cr.end.y <= hr.end.y
				var text_ok := true
				for c in ov.box.get_children():
					if c is Label and (c.get_global_rect().end.x > cr.end.x + 0.5 or c.get_line_count() > c.get_visible_line_count() and c.max_lines_visible > 0): text_ok = false
					if c is Label and c.get_global_rect().size.y < c.get_line_count() * c.get_line_height() - 1: text_ok = false
				if not (inside and text_ok): bad.append("%s/%d@%s" % [id, pi, sz[0]])
		ov.queue = []; holder.queue_free()
	UIKit.make_theme(fs0)
	check(bad.is_empty(), "every tip page fits its card and the screen at cover and inner sizes %s" % [bad.slice(0, 6)])

## Forge/Guild quantity: craft_n pays N× cost; upgrade_cost_n rises per level; repair_all pays the sum of each repair.
func test_forge_bulk(gs) -> void:
	print("[forge bulk]")
	gs.new_game(); gs.facilities.blacksmith.level = 3; gs.facilities.guild.level = 2
	gs.add_mat("iron_ore", 40); gs.add_mat("gold", 200)
	var r: Dictionary = gs.recipe("guild", "buy_ration") if not gs.recipe("guild", "buy_ration").is_empty() else {}
	if r.is_empty():
		for x in DB.recipes.guild:
			if x.get("out_mat", "") == "ration" or x.get("out", "") == "ration": r = x; break
	check(not r.is_empty(), "guild has a ration recipe")
	var cost0: Dictionary = r.cost.duplicate(); var mx: int = gs.craft_max("guild", r.id)
	check(mx >= 2, "ration is affordable at least twice (max %d)" % mx)
	var before: int = gs.mat("ration"); var gold0: int = gs.mat("gold")
	check(gs.craft_n("guild", r.id, 2) and gs.mat("ration") == before + 2 * int(r.get("out_n", 1)), "Buy x2 adds 2 rations")
	check(gs.mat("gold") == gold0 - 2 * int(cost0.get("gold", 0)), "Buy x2 pays 2x gold")
	var uid: int = gs.add_gear("shortsword", true, 0)
	check(gs.upgrade_max(uid) >= 2 and gs.upgrade_cost_n(uid, 2) == {"iron_ore": 4 + 8}, "upgrade 0->1->2 costs 4+8 ore")
	var ore0: int = gs.mat("iron_ore"); check(gs.upgrade_item_n(uid, 2) and int(gs.gear_by_uid(uid).lvl) == 2, "Upgrade x2 raises level to +2")
	check(gs.mat("iron_ore") == ore0 - 12, "Upgrade x2 spends 12 ore")
	var a: int = gs.add_gear("cloth_armor", true, 1); var b: int = gs.add_gear("mace", true, 0)
	gs.gear_by_uid(a).cracked = true; gs.gear_by_uid(b).cracked = true
	var rc: Dictionary = gs.repair_all_cost()
	check(int(rc.iron_ore) == int(gs.repair_cost(a).iron_ore) + int(gs.repair_cost(b).iron_ore), "repair_all_cost is the sum")
	gs.add_mat("iron_ore", int(rc.iron_ore)); check(gs.can_repair_all() == "" and gs.repair_all(), "Repair all clears every cracked item")
	check(gs.cracked_gear().is_empty(), "no cracked gear left")
	check(gs.can_repair_all() == "nothing to repair", "Repair all is disabled when nothing is cracked")

## Spare rings melt into a little gold and resin. Extras keeps every worn ring and one spare of each.
func test_break_rings(gs) -> void:
	print("[break rings]")
	gs.new_game()
	var gold0: int = gs.mat("gold"); var resin0: int = gs.mat("arcane_resin")
	var only: int = gs.add_gear("ring_might", true)
	check(gs.ring_extras().is_empty() and gs.breakable_ring("ring_might") == only, "a single ring is a spare, not an extra")
	check(gs.break_ring(only) and gs.gear_by_uid(only).is_empty(), "breaking down removes the ring")
	check(gs.mat("gold") == gold0 + 5 and gs.mat("arcane_resin") == resin0 + 1, "one ring yields 5 gold and 1 resin")
	check(gs.can_break_ring(gs.add_gear("shortsword")) == "not a ring" and not gs.break_ring(gs.gear.filter(func(g): return g.id == "shortsword")[0].uid), "weapons don't break down")
	# worn rings stay; the worst unequipped copy melts first; one spare of each type is kept
	var worn: int = gs.add_gear("ring_might", true)
	gs.equip("warrior", worn)
	var cracked: int = gs.add_gear("ring_might", true); gs.gear_by_uid(cracked).cracked = true
	var unknown: int = gs.add_gear("ring_might", false)
	var other: int = gs.add_gear("ring_tenacity", true)
	var other2: int = gs.add_gear("ring_tenacity", true)
	check(gs.can_break_ring(worn) == "equipped by Warrior" and not gs.break_ring(worn), "a worn ring can't be broken down")
	check(gs.breakable_ring("ring_might") == cracked, "the cracked copy is melted before the intact one")
	var extras: Array = gs.ring_extras()
	check(extras.size() == 2, "two piles leave two extras (one spare each)")
	var ids := {}
	for g in extras: ids[g.uid] = g.id
	check(ids.get(cracked, "") == "ring_might" and (ids.get(other, "") == "ring_tenacity" or ids.get(other2, "") == "ring_tenacity"), "extras are the cracked might and one tenacity")
	check(not ids.has(worn) and not ids.has(unknown), "the worn ring and the best spare are kept")
	gs.enqueue_identify(unknown)
	var before_g: int = gs.mat("gold"); var before_r: int = gs.mat("arcane_resin")
	check(gs.break_ring_extras() and gs.gear_by_uid(cracked).is_empty(), "Break down extras melts the spare copies")
	check(gs.gear_by_uid(worn).uid == worn and gs.heroes.warrior.ring == worn, "the equipped ring stays equipped")
	check(not gs.gear_by_uid(unknown).is_empty() and gs.id_queue.size() == 1 and int(gs.id_queue[0].uid) == unknown, "the kept spare stays, including its identification")
	var left_tenacity := 0
	for g in gs.gear:
		if g.id == "ring_tenacity": left_tenacity += 1
	check(left_tenacity == 1, "one Ring of Tenacity is kept")
	check(gs.mat("gold") == before_g + 10 and gs.mat("arcane_resin") == before_r + 2, "two rings yield 10 gold and 2 resin")
	check(gs.ring_extras().is_empty() and not gs.break_ring_extras(), "nothing left to call extras")
	# melting a queued ring drops it from the desk
	var queued: int = gs.add_gear("ring_energy", false)
	gs.enqueue_identify(queued)
	check(gs.break_ring(queued) and gs.id_queue.all(func(q): return int(q.uid) != queued), "a broken ring leaves the identification queue")

func _slot_badge(root: Node) -> Texture2D:
	for c in root.find_children("*", "PixelIcon", true, false):
		if (c as PixelIcon).badge != null: return (c as PixelIcon).badge
	return null

func _ring_icons_in(root: Node, ring_idx: int) -> int:
	var n := 0
	var want := UIKit.item_rect(ring_idx)
	for c in root.find_children("*", "PixelIcon", true, false):
		var t: Texture2D = c.texture
		if t is AtlasTexture and (t as AtlasTexture).region == want and c.scale_k() >= 1 and c.modulate.a > 0.5 and c.modulate.g > 0.9 and c.modulate.b > 0.9 and c.custom_minimum_size.x >= 16:
			n += 1
	return n

## Rings show their SPD gem sprite in every UI context (stash slot, Forge, paperdoll, delve backpack, compare
## rows), including cracked and unknown ones and old-save ids; a cracked ring is repairable at the Forge and by
## Repair all.
func test_ring_contexts(gs) -> void:
	print("[ring contexts]")
	gs.new_game()
	var cs = load("res://scripts/ui/camp_screen.gd").new()
	var bad := []
	for rid in ["ring_might", "ring_tenacity", "ring_evasion", "ring_wealth", "ring_energy"]:
		var idx := DB.icon_index(rid)
		for known in [true, false]:
			var uid: int = gs.add_gear(rid, known)
			var g: Dictionary = gs.gear_by_uid(uid)
			for cracked in [false, true]:
				g.cracked = cracked
				var slot: Button = cs.item_slot(cs.gear_icon(g), "", "", func(): pass, Color(1, 0.55, 0.5) if cracked else Color.WHITE, "", g)
				if _ring_icons_in(slot, idx) != 1: bad.append("stash %s k%s c%s" % [rid, known, cracked])
				var glyph: Texture2D = _slot_badge(slot)
				var want := UIKit.badge_rect(String(DB.item(rid).badge))
				if known and (glyph == null or not (glyph is AtlasTexture) or (glyph as AtlasTexture).region != want): bad.append("badge %s" % rid)
				if not known and glyph != null: bad.append("spoiled %s" % rid)
				slot.free()
		# paperdoll ring slot
		gs.heroes.warrior.ring = gs.add_gear(rid, true)
		var ps: Button = Paperdoll._slot("warrior", "ring", "camp", func(): pass)
		if _ring_icons_in(ps, idx) != 1: bad.append("paperdoll " + rid)
		if _slot_badge(ps) == null: bad.append("paperdoll badge " + rid)
		ps.free()
	# delve backpack (carried rings) + legacy save id
	gs.add_mat("ration", 1); gs.add_mat("torch", 1)
	gs.heroes.warrior.ring = 0
	gs.start_run("warrior", {}, "sewers", 3)
	gs.run.pack_gear.append({"uid": 9001, "id": "ring_garnet", "lvl": 0})   # pre-v0.19 save shape
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(gs.run.pack_gear[-1].id == "ring_might" and gs.run.pack_gear[-1].known == true and gs.run.pack_gear[-1].cracked == false, "old-save ring ids/fields are migrated")
	var bp := VBoxContainer.new()
	HeroPanels.backpack(bp, func(): pass)
	if _ring_icons_in(bp, DB.icon_index("ring_might")) < 1: bad.append("backpack")
	bp.free()
	gs.end_run("abandon")
	check(bad.is_empty(), "ring icons render in stash/Forge/paperdoll/backpack slots %s" % [bad.slice(0, 6)])
	# repair a cracked ring
	gs.new_game(); gs.add_mat("iron_ore", 50)
	var ru: int = gs.add_gear("ring_wealth", true); gs.gear_by_uid(ru).cracked = true
	check(gs.cracked_gear().size() == 1 and int(gs.repair_all_cost().get("iron_ore", 0)) > 0, "a cracked ring counts for Repair all")
	check(gs.repair(ru) and not gs.gear_by_uid(ru).cracked, "a cracked ring can be repaired at the Forge")
	gs.gear_by_uid(ru).cracked = true
	check(gs.repair_all() and gs.cracked_gear().is_empty(), "Repair all repairs a cracked ring")
	cs.free()

## SPD's second icon (item_icons.png): a known ring/potion/scroll keeps its appearance sprite and gains the
## type glyph in the top-right. Ring of Tenacity and Potion of Shielding are the blue shield; Ring of Force's
## own glyph is the red mark at film index 5 (we have no Ring of Force).
func test_item_badges(gs) -> void:
	print("[item badges]")
	gs.new_game()
	var sheet: Image = (load("res://assets/sprites/item_icons.png") as Texture2D).get_image()
	check(sheet.get_width() == 128 and sheet.get_height() == 64, "item_icons.png is the SPD 128x64 sheet")
	check(UIKit.badge_rect("RING_FORCE") == Rect2(40, 0, 5, 6), "ring of force glyph is film index 5, 5x6")
	var force := _glyph_rgb(sheet, "RING_FORCE")
	var shield := _glyph_rgb(sheet, "RING_TENACITY")
	var pot := _glyph_rgb(sheet, "POTION_SHIELDING")
	check(force.x > force.z and shield.z > shield.x and pot.z > pot.x, "force glyph is the red mark; tenacity and shielding are the blue shield")
	var lay := PixelIcon.badge_layout(Vector2(72, 72), Vector2(5, 6), 3)
	check(lay.position == lay.position.floor() and lay.position.x >= 72 - 24 and lay.end.x <= 72 and lay.position.y >= 0 and lay.end.y <= 24, "glyph sits in the top-right 8px cell")
	var hidden: PixelIcon = UIKit.icon("potion_toxic")
	check(hidden.badge == null, "an unidentified potion is only its colour")
	gs.identify_mat("potion_toxic"); gs.identify_mat("potion_shielding"); gs.identify_mat("scroll_mapping")
	var shown: PixelIcon = UIKit.icon("potion_toxic")
	var shield_ic: PixelIcon = UIKit.icon("potion_shielding")
	var heal: PixelIcon = UIKit.icon("potion_healing")
	var scroll: PixelIcon = UIKit.icon("scroll_mapping")
	check(shown.badge is AtlasTexture and (shown.badge as AtlasTexture).region == UIKit.badge_rect("POTION_TOXICGAS"), "identifying toxic gas adds its glyph")
	check(shield_ic.badge is AtlasTexture and (shield_ic.badge as AtlasTexture).region == UIKit.badge_rect("POTION_SHIELDING"), "potion of shielding shows the blue shield")
	check(heal.badge is AtlasTexture and (heal.badge as AtlasTexture).region == UIKit.badge_rect("POTION_HEALING"), "a known potion shows its glyph")
	check(scroll.badge is AtlasTexture and (scroll.badge as AtlasTexture).region == UIKit.badge_rect("SCROLL_MAGICMAP"), "an identified scroll keeps its rune and gains the glyph")
	var plain: PixelIcon = UIKit.icon("GOLD")
	check(plain.badge == null, "materials without a type glyph stay a single sprite")
	var ring_unk: PixelIcon = UIKit.icon("ring_might")
	check(ring_unk.badge == null, "an unseen ring id without a known copy stays a plain gem")
	var r_uid: int = gs.add_gear("ring_might", true)
	var ring_known: PixelIcon = UIKit.icon("ring_might")
	check(ring_known.badge is AtlasTexture and (ring_known.badge as AtlasTexture).region == UIKit.badge_rect("RING_MIGHT"), "UIKit.icon resolves a known ring's glyph directly")
	var ring_suppressed: PixelIcon = UIKit.icon("ring_might", -1, "NONE")
	check(ring_suppressed.badge == null, "explicit NONE suppresses the glyph on an unidentified copy")
	gs.gear_by_uid(r_uid).erase("known")
	check(UIKit.gear_badge(gs.gear_by_uid(r_uid)) == "RING_MIGHT", "legacy gear entries without a known key still resolve their ring glyph")
	# SPD ItemSlot strength requirement on weapons and armor (":10", red when above hero Str)
	check(UIKit.str_text("worn_shortsword") == ":10" and UIKit.str_text("greatsword") == ":18", "weapons and armor format SPD strength requirement (:N)")
	check(UIKit.str_text("shortsword", {"id": "shortsword", "known": false}) == "12?" and UIKit.str_color("shortsword", 14, {"id": "shortsword", "known": false}) == Color("ff8800"), "unidentified weapon/armor shows N? in orange")
	check(UIKit.str_text("ring_might") == "" and UIKit.str_text("gold") == "", "rings and materials have no strength requirement text")
	check(UIKit.str_color("shortsword", 10) == Color("ff4444") and UIKit.str_color("shortsword", 12) == Color.WHITE, "strength requirement is red above hero Str and white once met")
	var cs = load("res://scripts/ui/camp_screen.gd").new()
	var sw_uid: int = gs.add_gear("shortsword", true, 2)
	var sw_slot: Button = cs.item_slot("shortsword", "W", "+2", func(): pass, Color.WHITE, "", gs.gear_by_uid(sw_uid))
	var sr: Label = sw_slot.get_node_or_null("StrReq")
	check(sr != null and sr.text == ":12" and sr.get_theme_color("font_color") == Color("ff4444"), "stash weapon slot shows :12 in red for a 10-Str hero")
	gs.heroes.warrior.str = 12
	var sw_ok: Button = cs.item_slot("shortsword", "W", "+2", func(): pass, Color.WHITE, "", gs.gear_by_uid(sw_uid))
	check(sw_ok.get_node("StrReq").text == ":12" and not sw_ok.get_node("StrReq").has_theme_color_override("font_color"), "stash weapon slot clears red once hero meets the Str requirement")
	var rg_slot: Button = cs.item_slot("ring_might", "", "", func(): pass, Color.WHITE, "", gs.gear_by_uid(r_uid))
	check(rg_slot.get_node_or_null("StrReq") == null, "ring slot does not add a Str label over its badge")
	var pd_w: Button = Paperdoll._slot("warrior", "weapon", "camp", func(): pass)
	var pd_c: Button = Paperdoll._slot("warrior", "class", "camp", func(): pass)
	check(pd_w.get_node_or_null("StrReq") != null and pd_w.get_node("StrReq").text == ":10" and pd_c.get_node_or_null("StrReq") == null, "paperdoll weapon slot shows :10 and class item slot does not")
	sw_slot.free(); sw_ok.free(); rg_slot.free(); pd_w.free(); pd_c.free(); cs.free()

func _glyph_rgb(sheet: Image, name: String) -> Vector3:
	var sub := sheet.get_region(Rect2i(UIKit.badge_rect(name)))
	var acc := Vector3.ZERO
	var n := 0
	for y in sub.get_height():
		for x in sub.get_width():
			var p := sub.get_pixel(x, y)
			if p.a > 0.2: acc += Vector3(p.r, p.g, p.b); n += 1
	return acc / maxf(1.0, float(n))

## Item icons in the delve backpack (potion/scroll buttons, carried rings) render at >= 32 px on cover and inner.
func test_icon_sizes(gs) -> void:
	print("[icon sizes]")
	var fs0 := UIKit.font_size
	var bad := []
	for fs in [14, 16, 24, 34]:
		UIKit.make_theme(fs)
		gs.new_game(); gs.add_mat("ration", 1); gs.add_mat("torch", 1)
		gs.start_run("warrior", {}, "sewers", 3)
		gs.run.pack["potion_toxic"] = 1; gs.run.pack["scroll_mapping"] = 1
		gs.run.pack_gear.append({"uid": 9100, "id": "ring_tenacity", "lvl": 0, "cracked": false, "known": false})
		var bp := VBoxContainer.new(); add_child(bp); HeroPanels.backpack(bp, func(): pass)
		await get_tree().process_frame
		var icons := bp.find_children("*", "PixelIcon", true, false)
		if icons.size() < 2: bad.append("fs%d: only %d icons" % [fs, icons.size()])
		for ic in icons:
			if ic.cell_px < 32 or ic.custom_minimum_size.x < 32 or ic.scale_k() < 2: bad.append("fs%d %s" % [fs, ic.cell_px])
		var pots := 0
		for b in bp.find_children("*", "Button", true, false):
			if not (b.text.contains("Potion") or b.text.contains("Scroll")): continue
			if b.text.begins_with("Use "): continue
			pots += 1
			if b.size.y > UIKit.btn_height() * 1.25 or b.size.x <= b.size.y:
				bad.append("fs%d '%s' %s" % [fs, b.text, b.size])
		if pots < 2: bad.append("fs%d: %d potion buttons" % [fs, pots])
		bp.free(); gs.end_run("abandon")
	UIKit.make_theme(fs0)
	check(bad.is_empty(), "backpack item icons are >= 32 px and potion buttons stay one line %s" % [bad.slice(0, 5)])

## Auto Battle plays ambushes and leaves every other card for the player. The setting still persists.
func test_full_auto(gs) -> void:
	print("[auto battle]")
	gs.new_game(); gs.add_mat("ration", 2); gs.add_mat("torch", 2)
	gs.start_run("warrior", {"ration": 2, "torch": 2}, "sewers", 5)
	var fight := Delve.combat_event(gs.run, Delve.rng_for(gs.run, 1), ["rat"])
	var garden: Dictionary = DB.specials.filter(func(x): return x.id == "sacrificial_fire")[0]
	var ds = load("res://scripts/ui/delve_screen.gd").new()
	ds.running = true
	var cards := [
		{"kind": "door", "door": {"a": {"text": "A", "kind": "combat", "mobs": ["rat"]}, "b": {"text": "B", "kind": "chest", "cost": {}, "reward": {}}}},
		{"kind": "special", "special": garden},
		{"kind": "floor_done"},
		{"kind": "campfire"},
		{"kind": "backpack"},
		{"kind": "talents"},
	]
	for card in cards:
		ds.pending = card
		ds._auto_tick(5.0)
		check(ds.pending == card, "auto battle does not choose %s" % card.kind)
	ds.pending = fight
	ds._auto_tick(0.2)
	check(ds.pending == fight, "an ambush stays up briefly before the fight starts")
	ds.running = false
	ds._auto_tick(5.0)
	check(ds.pending == fight, "pause holds an ambush instead of starting the fight")
	ds.free()
	gs.settings.full_auto = true
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(gs.settings.get("full_auto", false) == true, "Auto Battle setting persists in the save")
	var cs = load("res://scripts/ui/combat_screen.gd").new()
	cs.setup(fight, func(_r): pass)
	check(cs.auto, "Auto Battle starts the fight with auto battle on")
	gs.settings.full_auto = false
	var cs2 = load("res://scripts/ui/combat_screen.gd").new()
	cs2.setup(fight, func(_r): pass)
	check(not cs2.auto, "auto battle stays off when the toggle is off")
	cs.free(); cs2.free()
	gs.end_run("abandon")

## Closing an encounter card sets it aside so the bag and settings work; the bar cannot skip it.
func test_encounter_dismiss(gs) -> void:
	print("[encounter dismiss]")
	gs.new_game(); gs.add_mat("ration", 1); gs.add_mat("torch", 1)
	gs.start_run("warrior", {"ration": 1, "torch": 1}, "sewers", 5)
	gs.run.talent_prompted = true
	var fight := Delve.combat_event(gs.run, Delve.rng_for(gs.run, 1), ["rat"])
	var d = load("res://scripts/ui/delve_screen.gd").new()
	d.pending = fight; d.running = true
	add_child(d)
	d._show_card()
	check(_find_btn(d.card_host, "Close") != null and _find_btn(d.card_host, "Fight") != null, "ambush card has Close and Fight")
	var prog := float(gs.run.progress)
	d._dismiss_encounter()
	check(d.pending.is_empty() and d._under.get("kind", "") == "combat", "Close sets the fight aside")
	check(gs.run.get("pending_card", {}).get("kind", "") == "combat", "a closed fight stays in the save")
	d._process(1.0)
	check(is_equal_approx(float(gs.run.progress), prog) and d.pending.is_empty(), "the bar does not walk past a closed encounter")
	d._open_panel("backpack")
	check(d.pending.get("kind", "") == "backpack" and d._under.get("kind", "") == "combat", "the bag opens while a fight is waiting")
	d._open_panel("settings")
	check(d.pending.get("kind", "") == "settings" and d._under.get("kind", "") == "combat", "settings opens without dropping the fight")
	d._close_panel()
	check(d.pending.get("kind", "") == "combat" and d._under.is_empty(), "closing settings brings the fight back")
	d._dismiss_encounter()
	d._confirm_abandon()
	check(d.pending.get("kind", "") == "confirm_abandon" and d._under.get("kind", "") == "combat", "abandon confirm keeps the fight")
	d._cancel_abandon()
	check(d.pending.get("kind", "") == "combat", "Keep delving returns to the fight")
	d.queue_free()
	gs.end_run("abandon")

## After a fight, chest, or room, a window lists gains and losses and holds the bar until OK.
func test_encounter_summary(gs) -> void:
	print("[encounter summary]")
	gs.new_game(); gs.add_mat("ration", 1); gs.add_mat("torch", 1)
	gs.start_run("warrior", {"ration": 1, "torch": 1}, "sewers", 5)
	gs.run.talent_prompted = true
	var before := Delve.ledger(gs)
	gs.run.hp -= 3
	gs.pack_add("gold", 8)
	var dlt: Dictionary = Delve.ledger_delta(before, Delve.ledger(gs))
	check(dlt.got.has("+8 Gold") and dlt.lost.has("-3 HP"), "a ledger names gold gained and HP lost")
	gs.run.pack = {"gold": 10}
	gs.run.hp = int(before.hp)
	var scr = load("res://scripts/ui/delve_screen.gd").new()
	add_child(scr)
	scr.size = Vector2(968, 900)
	scr.running = true
	scr._choose_door({"kind": "chest", "text": "Locked chest", "cost": {"gold": 3}, "reward": {"gold": 7, "item": "shortsword"}})
	var txt := _node_text(scr.get_node("EncounterSummary"))
	check(scr._summary_open() and _find_btn(scr, "OK") != null and txt.contains("Locked chest") and txt.contains("Got") and txt.contains("Lost") and txt.contains("-3 Gold") and txt.contains("+7 Gold") and txt.contains("Shortsword"), "chest window lists the cost and the find, with OK")
	var prog := float(gs.run.progress)
	scr._process(1.0)
	check(is_equal_approx(float(gs.run.progress), prog), "the bar waits while the result window is open")
	scr._accept_summary()
	check(not scr._summary_open(), "OK closes the result window")
	gs.run.hp = 20
	gs.run.fights_won = 0
	scr._after_fight({"kind": "combat", "mobs": ["rat"]}, {"won": true, "hp": 14, "loot": 5, "fallen_loot": 2, "xp": 1, "boss_killed": false, "kills": 1, "traps_found": 0, "trap_ids": [], "potions_used": 1}, {})
	txt = _node_text(scr.get_node("EncounterSummary"))
	check(txt.contains("Victory") and txt.contains("+5 Gold") and txt.contains("-6 HP") and txt.contains("-1 Potion of Healing") and txt.contains("+2 Gold on the next floor") and txt.contains("+1 XP"), "fight window lists loot, damage, a potion drunk, and fallen gold")
	scr._accept_summary()
	scr._open_summary("Victory", PackedStringArray(["+14 Gold", "+13 XP"]), PackedStringArray())
	var list: ScrollContainer = scr.get_node("EncounterSummary").find_child("SummaryList", true, false)
	check(list.custom_minimum_size.y >= 5.0 * UIKit.font_size * 1.5, "a short victory gives each line room")
	await get_tree().process_frame
	var bar := list.get_v_scroll_bar()
	check(bar.max_value <= bar.page + 1.0, "a short victory fits without a scrollbar")
	scr._accept_summary()
	gs.settings.full_auto = true
	scr._open_summary("Victory", PackedStringArray(), PackedStringArray())
	scr._process(2.0)
	check(scr._summary_open(), "auto battle does not click through the result window")
	scr._accept_summary()
	gs.settings.full_auto = false
	gs.run.pack = {"gold": 6}
	gs.run.hp = 12
	scr._after_fight({"kind": "combat", "mobs": ["rat"]}, {"won": false, "hp": 0, "loot": 9, "fallen_loot": 0, "xp": 3, "boss_killed": false, "kills": 0, "traps_found": 0, "trap_ids": [], "potions_used": 0}, {})
	txt = _node_text(scr.get_node("EncounterSummary"))
	check(scr._summary_open() and not gs.run.is_empty() and txt.contains("Defeat") and txt.contains("-12 HP") and txt.contains("-6 Gold") and txt.contains("Shortsword") and not txt.contains("9 Gold"), "defeat window lists HP and the pack, and does not grant the fight's loot")
	check(txt.contains("return to the stash"), "defeat window says supplies go home")
	scr._process(2.0)
	check(scr._summary_open(), "a defeat stays up until OK, even with auto battle off")
	scr._accept_summary()
	check(gs.run.is_empty() and gs.last_result == "death", "OK after a defeat ends the expedition")
	scr.queue_free()

## A reward toast emitted before the floor menu opens must sit in the card, above the buttons.
func test_menu_toast(gs) -> void:
	print("[menu toast]")
	gs.new_game(); gs.add_mat("ration", 1); gs.add_mat("torch", 1)
	gs.start_run("warrior", {"ration": 1, "torch": 1}, "sewers", 5)
	gs.run.talent_prompted = true
	var host := ToastHost.new()
	var box := VBoxContainer.new(); host.toast_box = box; host.add_child(box)
	var holder := Control.new(); holder.size = Vector2(484, 1188); add_child(holder)
	holder.add_child(host)
	var d = load("res://scripts/ui/delve_screen.gd").new(); d.main = host
	holder.add_child(d); d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); d.size = holder.size
	await get_tree().process_frame
	check(d.window_toast("Level up! Warrior is now Lv2.") and box.get_child_count() == 0 and d.card_host.get_node_or_null("CardToast") == null, "no floating toast when the delve log is visible")
	var floater := UIKit.card(); floater.add_child(UIKit.label("Reward: Ash Wand")); box.add_child(floater)
	for i in 6: gs.log_line("Log line %d" % i, "info")
	d.pending = {"kind": "floor_done"}; d.apply_layout(true, holder.size)
	for i in 3: await get_tree().process_frame
	check(box.get_child_count() == 0, "opening the floor menu clears the floating toast")
	var toast: Node = d.card_host.get_node_or_null("CardToast")
	var log_node: Control = d.card_host.get_node_or_null("DelveLog")
	var descend = _find_btn(d.card_host, "Descend to floor %d" % (int(gs.run.floor) + 1))
	var close = _find_btn(d.card_host, "Close")
	check(toast != null and _node_text(toast).contains("Reward: Ash Wand"), "reward is shown inside the floor menu")
	check(descend != null and close != null, "floor menu buttons stay")
	check(log_node != null and log_node.get_child_count() == d.CARD_LOG_LINES and _node_text(log_node).contains("Log line 5") and not _node_text(log_node).contains("Log line 1"), "last few log lines stay visible under the encounter popup")
	if toast != null and descend != null and close != null and log_node != null:
		var tr: Rect2 = toast.get_global_rect(); var dr: Rect2 = descend.get_global_rect(); var cr: Rect2 = close.get_global_rect(); var lr: Rect2 = log_node.get_global_rect()
		check(tr.size.y > 2 and dr.size.y > 2 and cr.size.y > 2, "floor menu laid out (toast %s descend %s close %s)" % [tr, dr, cr])
		check(not tr.intersects(dr) and not tr.intersects(cr) and tr.end.y <= cr.position.y + 1.0, "toast sits above the menu buttons, not over them")
		check(not lr.intersects(dr) and lr.position.y >= dr.end.y - 1.0, "log sits below the encounter popup, not covered by it")
	d._show_card()
	check(box.get_child_count() == 0 and _node_text(d.card_host.get_node_or_null("CardToast")).contains("Reward: Ash Wand"), "rebuilding the menu keeps the toast in the card")
	check(d.window_toast("A hidden door! Secret cache: Ash Wand"), "a toast while the menu is open is taken")
	d._show_card()
	check(box.get_child_count() == 0 and _node_text(d.card_host.get_node("CardToast")).contains("A hidden door! Secret cache: Ash Wand"), "search result stays in the card after rebuild")
	d.pending = {}; d._show_card()
	check(box.get_child_count() == 0 and d.card_host.get_node_or_null("CardToast") == null, "returning to the delve log clears card toasts without floating")
	holder.queue_free()
	gs.end_run("abandon")

func _node_text(n: Node) -> String:
	if n == null: return ""
	var s := ""
	if n is Label: s = n.text
	for c in n.get_children(): s += " " + _node_text(c)
	return s

class ToastHost:
	extends Control
	var toast_box: Node
	func tip(_id: String) -> void:
		pass
	func tip_open() -> bool:
		return false

func _find_btn(n: Node, text: String):
	if n is Button and n.text == text: return n
	for ch in n.get_children():
		var r = _find_btn(ch, text)
		if r: return r
	return null

## Log lines carry SPD colours; key moments are logged; the alarm sound is never played.
func test_log_and_sounds(gs) -> void:
	print("[log + sounds]")
	gs.new_game(); gs.add_mat("ration", 1); gs.add_mat("torch", 1)
	gs.start_run("warrior", {}, "sewers", 5)
	for i in 30: Delve.advance(gs, 1.0)
	var joined := " ".join(gs.messages)
	check(int(gs.run.haul.get("gold", 0)) == 7 and int(gs.run.haul.get("dew", 0)) == 2, "gathering counts on the delve haul")
	check(gs.haul_line().begins_with("Collected this delve:") and gs.haul_line().contains("7 Gold") and gs.haul_line().contains("2 Dew Drop"), "haul line names gold and materials")
	check(not joined.contains("Picked up"), "small pickups stay out of the log")
	Delve.descend(gs)
	check(int(gs.run.haul.get("iron_ore", 0)) == 1 and not " ".join(gs.messages).contains("iron ore"), "floor ore joins the haul instead of a log line")
	var g_floor: int = int(gs.run.haul.gold)
	for i in 8: Delve.advance(gs, 1.0)
	check(int(gs.run.haul.gold) == g_floor + 2, "haul keeps counting across floors")
	check(gs.messages[-1].begins_with("You descend") or " ".join(gs.messages).contains("You descend to floor 2"), "floor change is logged")
	var res := {"won": true, "hp": int(gs.run.hp) - 3, "loot": 5, "fallen_loot": 0, "xp": 2, "boss_killed": false, "kills": 2, "traps_found": 1, "trap_ids": []}
	Delve.apply_fight_result(gs, {"kind": "combat", "mobs": ["rat", "rat"]}, res, {})
	var all := " ".join(gs.messages)
	check(all.contains("Victory: 2 kills, took 3 damage") and all.contains("Spotted 1 trap"), "fight damage/kills/traps logged")
	check(int(gs.run.haul.gold) == 14 and Delve.pay(gs, {"gold": 3}) and int(gs.run.pack.gold) == 11 and int(gs.run.haul.gold) == 14, "fight gold counts, and spending it does not shrink the haul")
	gs.run.torch = 10.0; gs.run.supplies.torch = 0
	Delve.advance(gs, 0.5)
	check(" ".join(gs.messages).contains("torch is burning low"), "torch warning logged")
	var ki: int = gs.messages.size() - 1
	for i in range(gs.messages.size()):
		if gs.messages[i].contains("torch is burning low"): ki = i
	check(gs.message_kinds[ki] == "warning" and gs.LOG_COLORS.has("positive") and gs.message_kinds.size() == gs.messages.size(), "log kinds map to SPD colours")
	Sfx.play("alert"); check(Sfx.last_played != "alert", "the alarm sound is never played")
	var used := []
	for f in ["res://scripts/ui/delve_screen.gd", "res://scripts/ui/grid_view.gd", "res://scripts/ui/combat_screen.gd", "res://scripts/core/delve.gd"]:
		if FileAccess.get_file_as_string(f).contains('Sfx.play("alert")'): used.append(f)
	check(used.is_empty(), "no code plays the alarm %s" % [used])
	var snap: int = int(gs.run.haul.gold)
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(int(gs.run.haul.gold) == snap and gs.haul_line().contains("%d Gold" % snap), "haul survives save/load")
	var old: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	old.run.erase("haul"); old.run.pack = {"gold": 9, "dew": 1}
	gs.from_dict(old)
	check(int(gs.run.haul.gold) == 9 and int(gs.run.haul.dew) == 1, "an old save seeds the haul from the pack")
	gs.end_run("abandon")

## Scrolls of Upgrade in the pack at death are owed (stacking) and return on the next boss kill by any hero.
func test_owed_sou(gs) -> void:
	print("[owed scrolls]")
	gs.new_game(); gs.add_mat("ration", 4); gs.add_mat("torch", 4)
	for cc in gs.heroes: gs.heroes[cc].unlocked = true
	gs.start_run("warrior", {}, "sewers", 5); gs.run.pack["scroll_upgrade"] = 2; gs.end_run("death")
	check(gs.owed_sou == 2, "2 scrolls owed after a death")
	gs.start_run("mage", {}, "sewers", 6); gs.run.pack["scroll_upgrade"] = 1; gs.end_run("death")
	check(gs.owed_sou == 3, "owed scrolls stack across deaths")
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.from_dict(d); check(gs.owed_sou == 3, "owed count persists in the save")
	d.erase("owed_sou"); gs.from_dict(d); check(gs.owed_sou == 0, "old saves load with nothing owed")
	gs.owed_sou = 3
	gs.start_run("rogue", {}, "sewers", 7)
	var res := {"won": true, "hp": int(gs.run.hp), "loot": 0, "fallen_loot": 0, "xp": 0, "boss_killed": true, "kills": 1, "traps_found": 0, "trap_ids": []}
	Delve.apply_fight_result(gs, {"kind": "combat", "boss": true, "mobs": ["goo"]}, res, {})
	check(gs.owed_sou == 0 and int(gs.run.pack.get("scroll_upgrade", 0)) >= 3, "the next boss kill returns all owed scrolls to the pack")
	check(" ".join(gs.messages).contains("lost Scrolls of Upgrade return"), "the return is logged")
	gs.end_run("abandon")

## Total wipe: every hero dead, all gear cracked, 0 resources. A delve must still start with usable starter
## gear and supplies, earn repair ore, and the Forge must offer a free Patch up (DECISIONS #104).
func test_total_wipe(gs) -> void:
	print("[total wipe]")
	gs.new_game()
	for cc in gs.heroes: gs.heroes[cc].unlocked = true
	for cc in gs.heroes:
		gs.heroes[cc].weapon = gs.add_gear(DB.heroes[cc].start_weapon, true, 2); gs.heroes[cc].armor = gs.add_gear("leather_armor", true, 1)
	for g in gs.gear: g.cracked = true
	for k in gs.mats.keys(): gs.mats[k] = 0
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))   # the reported save shape, loaded
	var hs: Dictionary = gs.hero_stats("warrior")
	check(hs.starter_weapon and hs.starter_armor and int(hs.dmg) > 0 and int(hs.dr) >= 1, "cracked gear falls back to starter weapon + cloth armor (dmg %d, DR %d)" % [hs.dmg, hs.dr])
	check(gs.can_patch_up() == "", "the Forge offers a free Patch up when no repair is affordable")
	var nc0: int = gs.cracked_gear().size()
	check(gs.patch_up() and gs.cracked_gear().size() == nc0 - 1, "Patch up repairs one item for free")
	check(gs.can_start_run("warrior") == "" and gs.start_run("warrior", {}, "sewers", 11), "a delve can start with 0 resources")
	check(int(gs.run.supplies.get("ration", 0)) >= 1 and int(gs.run.supplies.get("torch", 0)) >= 1, "relief ration + torch for a broke Camp")
	Delve.descend(gs)
	check(int(gs.run.pack.get("iron_ore", 0)) >= 1, "each floor yields repair ore")
	gs.end_run("abandon")
	# a full simulated run from the wipe: it either extracts with ore or, at worst, Patch up stays available
	var r := RunSim.play(gs, "warrior", {}, 4242)
	check(gs.mat("iron_ore") > 0 or gs.can_patch_up() == "" or gs.cracked_gear().is_empty(), "after a run from a wipe there is a path to repairs (%s, ore %d)" % [r.result, gs.mat("iron_ore")])

## DECISIONS #109: the Goo death spiral (0 potions, 0 gold) has a way out.
func test_goo_spiral(gs) -> void:
	print("[goo spiral]")
	gs.new_game()
	for cc in gs.heroes: gs.heroes[cc].unlocked = true
	for k in gs.mats.keys(): gs.mats[k] = 0
	check(gs.recipe("guild", "buy_healing").size() > 0 and gs.can_craft("guild", "buy_healing") != "", "Guild sells healing potions (not affordable at 0 gold)")
	gs.start_run("rogue", {}, "sewers", 5)
	gs.end_run("death")
	check(gs.mat("gold") >= gs.SAFETY_GOLD, "a death tops the stash up to the safety gold (%d)" % gs.mat("gold"))
	check(gs.can_craft("guild", "buy_healing") == "" and gs.craft("guild", "buy_healing") and gs.mat("potion_healing") == 1, "the safety gold buys a Potion of Healing")
	gs.mats.gold = 500; gs.start_run("rogue", {}, "sewers", 5); gs.end_run("death")
	check(gs.mat("gold") == 500, "the safety net never removes gold")
	gs.start_run("warrior", {}, "sewers", 5); gs.run.floor = 5
	var p0 := int(gs.run.supplies.get("potion_healing", 0))
	Delve.apply_fight_result(gs, {"mobs": ["goo"]}, {"won": true, "hp": 5, "loot": 0, "fallen_loot": 0, "xp": 0, "boss_killed": true, "kills": 1}, {})
	check(int(gs.run.supplies.potion_healing) == p0 + 1, "Goo always drops a Potion of Healing onto the belt")
	gs.end_run("extract")
	check(gs.mat("potion_healing") >= 2, "an unused Goo potion is banked in the stash")

## DECISIONS #110: food no longer caps depth.
func test_food_sources(gs) -> void:
	print("[food sources]")
	gs.new_game()
	gs.start_run("warrior", {}, "sewers", 5); gs.run.floor = 5
	var r0 := int(gs.run.supplies.get("ration", 0))
	Delve.apply_fight_result(gs, {"mobs": ["goo"]}, {"won": true, "hp": 5, "loot": 0, "fallen_loot": 0, "xp": 0, "boss_killed": true, "kills": 1}, {})
	check(int(gs.run.supplies.ration) == r0 + Delve.BOSS_RATIONS, "a boss kill adds %d rations to the belt" % Delve.BOSS_RATIONS)
	gs.end_run("abandon")
	var cr: Dictionary = gs.recipe("guild", "buy_ration_crate")
	check(int(cr.get("out_n", 0)) == 3 and int(cr.cost.gold) < 3 * int(gs.recipe("guild", "buy_ration").cost.gold), "Guild Lv2 ration crate: 3 rations, cheaper than 3 singles")
	gs.mats.gold = 100; gs.facilities.guild.level = 1
	check(gs.can_craft("guild", "buy_ration_crate") != "", "the crate needs Guild Lv2")

## DECISIONS #114: facility header shows level / max, the cap never sits below the level.
func test_facility_cap(gs) -> void:
	print("[facility cap]")
	gs.new_game()
	gs.facilities.guild.level = 2   # the reported state: level above the stored cap 1
	check(gs.facility_cap("guild") == 2, "a level above the stored cap counts as the cap")
	var t: String = gs.facility_title("Guild Hall", 2, gs.facility_cap("guild"), int(DB.facilities.guild.max))
	check(t.contains("Lv 2 / 3") and not t.contains("/ 1") and t.contains("cap 2"), "header shows level / max and the blocking cap (%s)" % t)
	check(gs.can_upgrade_facility("guild").begins_with("capped"), "level 2 at cap 2 is capped")
	gs.mats.scroll_upgrade = 1
	check(gs.apply_sou("guild") and gs.facility_cap("guild") == 3, "a Scroll raises the cap from the effective cap (2 -> 3)")
	gs.mats.gold = 1000
	check(gs.can_upgrade_facility("guild") == "" and gs.upgrade_facility("guild"), "upgrade allowed once the cap is raised")
	check(not gs.facility_title("Guild Hall", 3, 3, 3).contains("cap"), "no cap note at max level")
	check(gs.facility_title("Forge", 1, 2, 3) == "Forge   Lv 1 / 3", "no cap note while the cap is not blocking")
	gs.facilities.guild.level = 2; gs.facilities.guild.cap = 1
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(int(gs.facilities.guild.cap) == 2, "loading a save repairs cap < level")
	# hero slots show Lv + Str; tapping a second time opens Heroes
	gs.heroes.mage.unlocked = true; gs.heroes.mage.level = 4; gs.heroes.mage.str = 12
	var cs = load("res://scripts/ui/camp_screen.gd").new(); add_child(cs)
	var m_slot: Button = cs._hero_slot("mage")
	check(_node_text(m_slot).contains("Lv4") and _node_text(m_slot).contains("Str 12"), "hero slot shows level and Str (%s)" % _node_text(m_slot))
	m_slot.pressed.emit()
	check(cs.chosen_hero == "mage" and cs.open_name == "", "first tap selects the hero")
	var m_slot2: Button = cs._hero_slot("mage")
	m_slot2.pressed.emit()
	check(cs.open_name == "Heroes", "tapping the selected hero again opens Heroes")
	m_slot.free(); m_slot2.free(); cs.queue_free()

