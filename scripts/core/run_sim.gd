## RunSim: plays an entire expedition with CombatBot and simple card choices. Used for balance reports
## (tests/run_tests.gd [fullrun]) - answers "how often does a fresh hero clear the Sewers?".
class_name RunSim
extends RefCounted

## Returns {result: "extract"|"death", floor, level, hp, fights, gold}
## deep = true: continue past the Goo campfire into the Prison instead of extracting.
## last_biome: with deep, stop (extract) at this biome's campfire instead of going further.
static func play(gs, hero: String, loadout: Dictionary, seed: int, deep := false, last_biome := "") -> Dictionary:
	gs.start_run(hero, loadout, "sewers", seed)
	var fights := 0
	var guard := 0
	while guard < 5000:
		guard += 1
		var run: Dictionary = gs.run
		if Delve.floor_done(run):
			if Delve.is_campfire(run):
				if deep and Delve.next_biome(run) != "" and run.biome != last_biome:
					Delve.continue_deeper(gs); continue
				var out := _summary(gs, "extract", fights); gs.end_run("extract"); return out
			if Delve.can_search_floor(run) and float(run.torch) > 40.0: Delve.search_floor(gs)
			Delve.descend(gs); continue
		while not run.get("overflow", []).is_empty(): gs.resolve_overflow(-1)
		gs.auto_pick_talents(hero)
		var ev := Delve.advance(gs, 1.0)
		if ev.is_empty(): continue
		var reward := {}
		match ev.kind:
			"door":
				var a: Dictionary = ev.door.a; var b: Dictionary = ev.door.b
				if b.kind == "chest" and Delve.pay_possible(gs, b.get("cost", {})):
					Delve.pay(gs, b.cost); Delve.reward(gs, b.reward); continue
				if a.kind == "combat":
					reward = a.get("reward", {})
					ev = Delve.combat_event(run, Delve.rng_for(run, 77), a.mobs)
				else: continue
			"special":
				var picked := false
				for o in ev.special.options:
					if o.has("fight") or not o.has("reward"): continue
					if o.has("requires_class") and o.requires_class != hero: continue
					var cost: Dictionary = o.get("cost", {})
					if cost.has("hp") and int(run.hp) < 12: continue
					if Delve.pay(gs, cost): Delve.reward(gs, o.reward); picked = true; break
				continue
		if ev.kind != "combat": continue
		fights += 1
		if ev.get("boss", false): run["boss_entry"] = "Lv%d hp%d/%d pots%d" % [gs.heroes[hero].level, run.hp, gs.hero_stats(hero).ht, int(run.supplies.get("potion_healing", 0))]
		var c := Delve.new_combat(gs, ev)
		var pots := int(run.supplies.get("potion_healing", 0))
		var r := CombatBot.play(c, pots, gs.potion_heal(hero))
		run.supplies.potion_healing = pots - int(r.potions_used)
		var res := {"won": c.won, "hp": c.hero.hp, "loot": c.loot, "fallen_loot": c.fallen_loot, "xp": c.xp, "boss_killed": c.boss_killed, "kills": c.kills, "traps_found": c.traps_found, "trap_ids": c.trap_ids_seen}
		if not res.won and OS.has_environment("SIM_DEBUG"):  # SIM_DEBUG=1 godot ... run_tests.tscn: explain every death
			print("    died f%d L%d vs %s hp_in=%d torch=%d sat=%d pots=%d" % [run.floor, gs.heroes[hero].level, ev.mobs, int(run.hp), int(run.torch), int(run.satiety), pots])
			if OS.get_environment("SIM_DEBUG") == "2": print("      ", "\n      ".join(c.log_lines.slice(-30)))
		if not Delve.apply_fight_result(gs, ev, res, reward):
			var out := _summary(gs, "death", fights); gs.end_run("death"); return out
	var o := _summary(gs, "timeout", fights); gs.end_run("abandon"); return o

static func _summary(gs, result: String, fights: int) -> Dictionary:
	return {"result": result, "floor": int(gs.run.floor), "level": int(gs.heroes[gs.run.hero].level), "hp": int(gs.run.hp),
		"fights": fights, "biome": gs.run.biome, "gold": int(gs.run.pack.get("gold", 0)), "boss_entry": gs.run.get("boss_entry", "")}
