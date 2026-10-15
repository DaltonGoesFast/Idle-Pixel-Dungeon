## Codex: player-facing descriptions generated from data (mobs, traps, items), shared by the
## in-fight inspect toast and the Camp Codex tab. Discovery state lives in GameState.seen.
class_name Codex
extends RefCounted

static func ability_text(m: Dictionary) -> String:
	match m.get("ability", ""):
		"throw": return "Throws a spear at range %d-%d: red tile, %d dmg." % [m.throw_range[0], m.throw_range[1], int(m.dmg) + int(m.throw_bonus)]
		"pump": return "Every %d actions (%s below half HP) pumps up and slams all adjacent tiles for x%d." % [m.pump_every, m.get("pump_every_enraged", m.pump_every), m.pump_mult]
		"bone_burst": return "Bursts into bone shards %d tick after dying: 3x3 red area, %d dmg." % [int(m.burst_delay), m.burst_dmg]
		"steal": return "Steals %d gold on its first hit, then runs. Kill it to get the gold back." % m.steal_gold
		"zap": return "Zaps at range 2-4: red tile, %d dmg, every %d actions." % [m.zap_dmg, m.zap_cooldown]
		"chain": return "Once per fight, chains you from 2-3 tiles away and drags you next to it."
		"tengu": return "Throws shurikens (red tile, %d dmg) and teleports away every %d HP lost. Below half HP lobs 3x3 bombs (2-tick fuse, %d dmg)." % [m.throw_dmg, m.blink_every, m.bomb_dmg]
	return ""

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
	return out
