## Codex: player-facing descriptions generated from data (mobs, traps, items), shared by the
## in-fight inspect toast and the Camp Codex tab. Discovery state lives in GameState.seen.
class_name Codex
extends RefCounted

static func ability_text(m: Dictionary) -> String:
	match m.get("ability", ""):
		"throw": return "Throws a spear at range %d-%d: red tile, %d dmg." % [m.throw_range[0], m.throw_range[1], int(m.dmg) + int(m.throw_bonus)]
		"pump": return "Every %d actions (%s below half HP) pumps up and slams all adjacent tiles for x%d." % [int(m.pump_every), int(m.get("pump_every_enraged", m.pump_every)), int(m.pump_mult)]
		"bone_burst": return "Bursts into bone shards %d tick after dying: 3x3 red area, %d dmg." % [int(m.burst_delay), m.burst_dmg]
		"steal": return "Steals %d gold on its first hit, then runs. Kill it to get the gold back." % m.steal_gold
		"zap": return "Zaps at range 2-4: red tile, %d dmg, every %d actions." % [m.zap_dmg, m.zap_cooldown]
		"chain": return "Once per fight, chains you from 2-3 tiles away and drags you next to it."
		"tengu": return "Throws shurikens (red tile, %d dmg) and teleports away every %d HP lost. Below half HP lobs 3x3 bombs (2-tick fuse, %d dmg)." % [m.throw_dmg, m.blink_every, m.bomb_dmg]
		"yog": return "Never moves (bites if you stand next to it). Every %d actions (%d below half HP) alternates hatching larva (2 marked tiles, 3 when enraged, only when none are left) and a gaze beam over your whole row and column (2-tick fuse, %d ignoring DR). Larva die with it." % [int(m.ability_every), int(m.ability_every_super), int(m.beam_dmg)]
		"dking": return "Every %d actions alternates raising the dead (2 marked tiles, Risen Dwarves appear in 2 ticks, only when none are left) and a shadow blast (3x3 on you, 2-tick fuse, %d ignoring DR). While his dwarves live he is lifelinked and takes only 2/3 damage. Below half HP: +3 dmg. Below 1/4: his throne cracks - no more summons. His dwarves crumble when he dies." % [int(m.ability_every), int(m.blast_dmg)]
		"dm300": return "Every %d actions (%d when supercharged below half HP, +2 DR) alternates rockfall (+ shape on you, 2-tick fuse, %d dmg) and a toxic gas line (1 tick, %d + %d poison)." % [int(m.ability_every), int(m.ability_every_super), int(m.rock_dmg), int(m.gas_dmg), int(m.gas_poison)]
	var extra := []
	if m.get("evade_unless_surprise", false): extra.append("Slips every hit that is not a Surprise (close a door behind you or circle tall grass).")
	if m.get("revive", false): extra.append("Rises again once with half HP, 2 ticks after dying - unless it was the last enemy standing.")
	if m.has("drain"): extra.append("Heals %d when its bite gets through." % int(m.drain))
	if m.has("bite_poison"): extra.append("Venomous bite: +%d poison." % int(m.bite_poison))
	if m.has("enraged_dmg") and m.get("ability", "") == "": extra.append("Enrages below half HP: %d dmg." % int(m.enraged_dmg))
	return " ".join(extra)

static func mob_line(id: String) -> String:
	var m: Dictionary = DB.mobs[id]
	var spd := "fast" if float(m.delay) < 1.0 else "normal speed"
	var t := "HP %d, dmg %d, DR %d, %s." % [m.ht, m.dmg, m.dr, spd]
	var a := ability_text(m)
	return t + (" " + a if a != "" else "")

## Where a mob shows up (biome names), for the codex.
static func mob_biomes(id: String) -> Array:
	var out := []
	for b in DB.biomes:
		var bd: Dictionary = DB.biomes[b]
		if bd.boss == id or bd.encounter_sets.any(func(s): return id in s.mobs): out.append(bd.name)
	if out.is_empty(): out.append("special rooms")
	return out

static func item_line(id: String) -> String:
	var it: Dictionary = DB.items[id]
	match it.type:
		"weapon": return "tier %d weapon, %d dmg%s, %d Str" % [it.tier, it.dmg, (", %.1f ticks" % it.delay) if float(it.get("delay", 1.0)) != 1.0 else "", it.str]
		"armor": return "tier %d armor, DR %d, +%d Barrier, %d Str" % [it.tier, it.dr, it.barrier, it.str]
		"wand": return "wand, bolt %d dmg (ignores DR), %d charges%s%s" % [it.bolt_dmg, it.charges, ", burns grass" if it.get("burns_grass", false) else "", ", chains through water" if it.get("chains_water", false) else ""]
		"ring":
			var bits := []
			if it.has("dmg_bonus"): bits.append("+%d dmg" % it.dmg_bonus)
			if it.has("barrier_bonus"): bits.append("+%d Barrier" % it.barrier_bonus)
			if it.has("dr_bonus"): bits.append("+%d DR" % it.dr_bonus)
			if it.has("gold_mult"): bits.append("+%d%% gold" % int(round((float(it.gold_mult) - 1.0) * 100)))
			if it.has("charges_bonus"): bits.append("+%d staff charge, +%d HP" % [it.charges_bonus, it.get("ht_bonus", 0)])
			return "ring, " + ", ".join(bits)
		"artifact": return "artifact, " + String(it.get("desc", ""))
	if it.get("heirloom", false): return "heirloom: a permanent class item that never cracks"
	return it.get("desc", it.type)

## Known if seen, or if it's the heirloom of an unlocked hero.
static func item_known(id: String) -> bool:
	if GameState.seen.has("item:" + id): return true
	for c in GameState.heroes:
		if GameState.heroes[c].unlocked and DB.heroes[c].get("heirloom", "") == id: return true
	return false
