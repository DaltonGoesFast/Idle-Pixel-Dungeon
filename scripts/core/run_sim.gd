## RunSim: plays an entire expedition with CombatBot and simple card choices. Used for balance reports
## (tests/run_tests.gd [fullrun]) - answers "how often does a fresh hero clear the Sewers?".
class_name RunSim
extends RefCounted

## Returns {result: "extract"|"death", floor, level, hp, fights, gold}
static func play(gs, hero: String, loadout: Dictionary, seed: int) -> Dictionary:
	gs.start_run(hero, loadout, "sewers", seed)
	var fights := 0
	var guard := 0
	while guard < 5000:
		guard += 1
		var run: Dictionary = gs.run
		if Delve.floor_done(run):
			if Delve.is_campfire(run):
				var out := _summary(gs, "extract", fights); gs.end_run("extract"); return out
			Delve.descend(gs); continue
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
					var cost: Dictionary = o.get("cost", {})
					if cost.has("hp") and int(run.hp) < 12: continue
					if Delve.pay(gs, cost): Delve.reward(gs, o.reward); picked = true; break
				continue
		if ev.kind != "combat": continue
		fights += 1
		if ev.get("boss", false): run["boss_entry"] = "Lv%d hp%d/%d pots%d" % [gs.heroes[hero].level, run.hp, gs.hero_stats(hero).ht, int(run.supplies.get("potion_healing", 0))]
		var c := Combat.new()
		c.setup(ev.room, gs.hero_stats(hero), int(run.hp), ev.mobs, Delve.darkness(run))
		var pots := int(run.supplies.get("potion_healing", 0))
		var r := CombatBot.play(c, pots, int(DB.materials.potion_healing.heal))
		run.supplies.potion_healing = pots - int(r.potions_used)
		var res := {"won": c.won, "hp": c.hero.hp, "loot": c.loot, "fallen_loot": c.fallen_loot, "xp": c.xp, "boss_killed": c.boss_killed}
		if not Delve.apply_fight_result(gs, ev, res, reward):
			var out := _summary(gs, "death", fights); gs.end_run("death"); return out
	var o := _summary(gs, "timeout", fights); gs.end_run("abandon"); return o

static func _summary(gs, result: String, fights: int) -> Dictionary:
	return {"result": result, "floor": int(gs.run.floor), "level": int(gs.heroes[gs.run.hero].level), "hp": int(gs.run.hp),
		"fights": fights, "gold": int(gs.run.pack.get("gold", 0)), "boss_entry": gs.run.get("boss_entry", "")}
