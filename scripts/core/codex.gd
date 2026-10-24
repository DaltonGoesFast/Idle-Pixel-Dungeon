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
	if m.get("evade_unless_surprise", false): extra.append("Slips melee hits that are not a Surprise (close a door or circle tall grass). Magic always hits; it slips only the first bow shot.")
	if m.get("revive", false): extra.append("Rises again once with half HP, 2 ticks after dying - unless it was the last enemy standing.")
	if m.has("drain"): extra.append("Heals %d when its bite gets through." % int(m.drain))
	if m.has("drain_over"): extra.append("Heals by the damage its bite deals beyond %d." % int(m.drain_over))
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
		"weapon":   # SPD numbers (DECISIONS #207)
			var wb := ["tier %d weapon, %d-%d (%d dmg)" % [int(it.tier), Weapons.min_dmg(it, 0), Weapons.max_dmg(it, 0), Weapons.dmg(it, 0)]]
			if float(it.get("delay", 1.0)) != 1.0: wb.append("%s ticks" % Weapons._num(float(it.delay)))
			if Weapons.reach(it) > 1: wb.append("reach %d" % Weapons.reach(it))
			if Weapons.acc(it) != 1.0: wb.append("accurate" if Weapons.acc(it) > 1.0 else "inaccurate")
			if it.has("block"): wb.append("blocks 0-%d" % Weapons.block_max(it, 0))
			if it.has("surprise_pct"): wb.append("strong surprise, pierces 50% DR on surprise")
			if it.get("no_surprise", false): wb.append("no surprise")
			wb.append("%d Str" % int(it.str))
			return ", ".join(wb)
		"armor": return "tier %d armor, DR %d, +%d Barrier, %d Str" % [it.tier, it.dr, it.barrier, it.str]
		"wand": return "wand, bolt %d dmg (ignores DR), %d charges%s%s" % [it.bolt_dmg, it.charges, ", burns grass" if it.get("burns_grass", false) else "", ", chains through water" if it.get("chains_water", false) else ""] + _wand_extra(it)
		"ring":
			var bits := []
			if it.has("dmg_bonus"): bits.append("+%d dmg" % it.dmg_bonus)
			if it.has("str_bonus"): bits.append("+%d Strength" % it.str_bonus)
			if it.has("ht_bonus") and not it.has("charges_bonus"): bits.append("+%d max HP" % it.ht_bonus)
			if it.has("barrier_bonus"): bits.append("+%d Barrier" % it.barrier_bonus)
			if it.has("dr_bonus"): bits.append("+%d DR" % it.dr_bonus)
			if it.has("gold_mult"): bits.append("+%d%% gold" % int(round((float(it.gold_mult) - 1.0) * 100)))
			if it.has("delay_mult"): bits.append("%d%% faster melee" % int(round((1.0 - float(it.delay_mult)) * 100)))
			if it.has("move_cost"): bits.append("%d%% faster steps" % int(round((1.0 - float(it.move_cost)) * 100)))
			if it.has("bolt_bonus"): bits.append("+%d ranged dmg" % it.bolt_bonus)
			if it.has("elem_resist"): bits.append("-%d%% magic dmg taken" % int(round((1.0 - float(it.elem_resist)) * 100)))
			if it.has("force_bonus"): bits.append("Tier-1 weapons hit like the sword your Strength can equip")
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

static func _wand_extra(it: Dictionary) -> String:
	var b := []
	if it.has("chill"): b.append("chills %.0f tick" % float(it.chill))
	if it.has("corrode"): b.append("%d poison" % int(it.corrode))
	if it.has("blast"): b.append("knockback")
	if it.get("pierce_line", false): b.append("pierces every enemy on the line")
	if it.has("transfuse"): b.append("heals you %d" % int(it.transfuse))
	if it.has("reveal"): b.append("reveals traps")
	if it.has("root"): b.append("roots %.0f ticks, grows grass" % float(it.root))
	return "" if b.is_empty() else ", " + ", ".join(b)

## Artifact stat lines for camp item details (DECISIONS #164): current value at the item's level, the per-level step,
## and level / Desk cap / XP progress. Keys: [label, unit, scale] (scale 100 shows a multiplier as a percent).
const ARTIFACT_STATS := {"ht_bonus": ["Max HP", "", 1.0], "search_add": ["Search radius", "", 1.0], "hunger_mult": ["Hunger", "%", 100.0],
	"thorns": ["Thorns", " dmg", 1.0], "freeze_start": ["Opening freeze", " ticks", 1.0], "grass_root": ["Grass root", " ticks", 1.0],
	"chain_root": ["Chain hold", " ticks", 1.0], "loot_mult": ["Fight gold", "%", 100.0]}
static func artifact_lines(g: Dictionary, cap: int, _xp_per := 8) -> Array:
	var d: Dictionary = DB.item(g.id); var out := []
	if d.get("type", "") != "artifact" or d.get("heirloom", false): return out
	var lv := int(g.get("lvl", 0)); var pl: Dictionary = d.get("per_level", {})
	for k in ARTIFACT_STATS:
		if not d.has(k) and not pl.has(k): continue
		var spec: Array = ARTIFACT_STATS[k]
		var base := float(d.get(k, 0.0)); var step := float(pl.get(k, 0.0)); var v := base + step * lv
		var ints: bool = k in ["ht_bonus", "search_add", "thorns"]
		if ints: v = floor(v)
		var txt: String
		if spec[2] == 100.0:
			txt = "%s %+d%%" % [spec[0], int(round((v - 1.0) * 100))]
			if step != 0.0: txt += " (%+d%% per level)" % int(round(step * 100))
		elif ints:
			txt = "%s %d%s" % [spec[0], int(v), spec[1]]
			if step != 0.0: txt += " (+1 every %d levels)" % int(round(1.0 / step)) if step < 1.0 else " (+%d per level)" % int(step)
		else:
			txt = "%s %s%s" % [spec[0], str(snappedf(v, 0.01)), spec[1]]
			if step != 0.0: txt += " (+%s per level)" % str(snappedf(step, 0.01))
		out.append(txt)
	var hours := int(floor(float(g.get("use_hours", 0.0))))
	if lv >= cap: out.append("Level +%d (Desk cap +%d: upgrade the Enchanter's Desk to grow; %dh banked)" % [lv, cap, hours])
	else: out.append("Level +%d / cap +%d - %d / 24h use to +%d" % [lv, cap, hours, lv + 1])
	return out
