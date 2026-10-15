## GameState: the persistent account (Camp, Stash, heroes, facilities, timers) and the active run.
## Pure data + rules; UI screens call these methods and listen to `changed`.
## Everything here is serialisable through to_dict()/from_dict() (see SaveSystem).
extends Node

signal changed
signal toast(text: String)
signal settings_changed

const PACK_MATS := ["gold","dew","iron_ore","dark_gold","seeds","arcane_resin","iron_key","potion_strength","scroll_upgrade"]
const SUPPLY_KEYS := ["ration","torch","potion_healing","scroll_passage","elixir_starter"]

var mats: Dictionary = {}          # stash materials & consumables
var gear: Array = []               # [{uid,id,lvl,cracked,known}]
var next_uid := 1
var heroes: Dictionary = {}        # class -> hero dict
var facilities: Dictionary = {}    # id -> {level, cap}
var id_queue: Array = []           # [{uid, ready_at}]
var boss_kills: Dictionary = {}    # class -> [biome ids]  (first kill per class drops a Scroll of Upgrade)
## text_scale multiplies the UI font size; haptics = vibrate on hits/traps (Android); dev_tools shows the Developer section.
var settings := {"sfx": 0.8, "music": 0.5, "haptics": true, "text_scale": 1.0, "dev_tools": false, "tutorial": true,
	"delve_speed": 1.0}
const STATS_DEFAULT := {"potions_brewed": 0, "deepest_floor": 0, "runs": 0, "deaths": 0, "extractions": 0, "kills": 0,
	"traps_found": 0, "hidden_doors": 0, "goo_kills": 0, "tengu_kills": 0}
var stats := STATS_DEFAULT.duplicate()
var milestones_claimed: Array = []  # milestone ids already rewarded
var seen: Dictionary = {}          # codex discoveries: "mob:rat", "trap:worn_dart", "item:dagger" -> true
var tutorial_done: Array = []      # onboarding steps already shown
var last_result := ""              # "extract" / "death" / "abandon" of the run that just ended (not saved)
var run: Dictionary = {}           # empty when no expedition is active
var time_offset := 0.0             # tests / debug can fast-forward wall-clock time
var messages: PackedStringArray = []

func _ready() -> void:
	if heroes.is_empty(): new_game()

func now() -> float:
	return Time.get_unix_time_from_system() + time_offset

func say(t: String) -> void:
	messages.append(t)
	if messages.size() > 80: messages.remove_at(0)
	toast.emit(t)

func touch() -> void:
	if not heroes.is_empty(): check_milestones()
	changed.emit()

# ---------------------------------------------------------------- setup
func new_game() -> void:
	mats = {"gold": 30, "ration": 2, "torch": 2, "potion_healing": 1, "iron_key": 1, "seeds": 2}
	gear = []; next_uid = 1; id_queue = []; boss_kills = {}; run = {}; time_offset = 0.0
	stats = STATS_DEFAULT.duplicate(); milestones_claimed = []; seen = {}; tutorial_done = []
	facilities = {}
	for f in DB.facilities: facilities[f] = {"level": 1, "cap": 1}
	heroes = {}
	for c in DB.heroes:
		var h: Dictionary = DB.heroes[c]
		heroes[c] = {"class": c, "unlocked": h.unlocked_by_default, "level": 1, "xp": 0, "str": 10,
			"weapon": add_gear(h.start_weapon), "armor": add_gear(h.start_armor), "ring": 0,
			"wand": "wand_magic_missile" if c == "mage" else "", "cleared": [], "patrol": {}}

func add_gear(id: String, known := true, lvl := 0) -> int:
	var g := {"uid": next_uid, "id": id, "lvl": lvl, "cracked": false, "known": known}
	if known: seen["item:" + id] = true
	next_uid += 1
	gear.append(g)
	return g.uid

func gear_by_uid(uid: int) -> Dictionary:
	for g in gear:
		if g.uid == uid: return g
	return {}

func gear_name(g: Dictionary) -> String:
	if g.is_empty(): return "-"
	var d := DB.item(g.id)
	var n: String = d.name if g.known else d.get("unknown_name", "Unknown " + d.type)
	if g.lvl > 0 and g.known: n += " +%d" % g.lvl
	if g.cracked: n += " (cracked)"
	return n

func equipped_by(uid: int) -> String:
	for c in heroes:
		var h: Dictionary = heroes[c]
		if h.weapon == uid or h.armor == uid or h.ring == uid: return c
	return ""

func mat(id: String) -> int:
	return int(mats.get(id, 0))

func add_mat(id: String, n: int) -> void:
	mats[id] = mat(id) + n

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if mat(k) < int(cost[k]): return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_afford(cost): return false
	for k in cost: mats[k] = mat(k) - int(cost[k])
	return true

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost: parts.append("%d %s" % [cost[k], DB.mat_name(k)])
	return ", ".join(parts)

# ---------------------------------------------------------------- hero stats
func xp_to_next(level: int) -> int:
	return 5 + level * 5   # SPD Hero.maxExp()

## Derived combat stats for a hero with current equipment.
func hero_stats(c: String) -> Dictionary:
	var h: Dictionary = heroes[c]
	var def: Dictionary = DB.heroes[c]
	var w := gear_by_uid(h.weapon); var a := gear_by_uid(h.armor); var r := gear_by_uid(h.ring)
	# cracked/missing weapon: fight with the class's starting weapon stats (bare minimum)
	var wd := DB.item(w.id) if not w.is_empty() and not w.cracked else DB.item(def.start_weapon)
	var ad := DB.item(a.id) if not a.is_empty() and not a.cracked else {}
	var wl := int(w.get("lvl", 0)); var al := int(a.get("lvl", 0))
	var dmg := int(wd.dmg) + wl * (int(wd.tier) + 1) / 2          # upgrades: +((tier+1)/2) per level
	var dr := int(ad.get("dr", 0)) + al
	var barrier := int(def.base_barrier) + int(def.heirloom_barrier) + int(ad.get("barrier", 0)) + al
	# Strength gate: each missing point costs 2 damage / 1 DR (SPD-like penalty, deterministic)
	var str_short := maxi(0, int(wd.get("str", 10)) - int(h.str))
	dmg = maxi(1, dmg - 2 * str_short)
	dr = maxi(0, dr - maxi(0, int(ad.get("str", 10)) - int(h.str)))
	if not r.is_empty() and r.known and not r.cracked:
		var rd := DB.item(r.id)
		dmg += int(rd.get("dmg_bonus", 0)); barrier += int(rd.get("barrier_bonus", 0))
	var s := {"class": c, "name": def.name, "sprite": def.sprite, "fw": def.fw, "fh": def.fh,
		"ht": int(def.base_ht) + int(def.ht_per_level) * (int(h.level) - 1),
		"dmg": dmg, "dr": dr, "barrier_max": barrier, "delay": float(wd.get("delay", 1.0)),
		"surprise_mult": float(wd.get("surprise_mult", 1.5)), "abilities": def.abilities,
		"search_radius": int(def.get("search_radius", 1)), "keen_eyes": def.get("keen_eyes", false)}
	if "bolt" in def.abilities and h.wand != "":
		var wn := DB.item(h.wand)
		s.bolt = {"dmg": int(wn.bolt_dmg) + int(h.level) / 2, "charges": int(wn.charges) + int(h.level) / int(def.get("charge_per_levels", 99)), "recharge": int(wn.recharge),
			"burns_grass": wn.get("burns_grass", false), "chains_water": wn.get("chains_water", false), "name": wn.name, "magic": true}
	if "shoot" in def.abilities:
		# SPD Spirit Bow: (1 + lvl/5) - (6 + lvl/2.5), collapsed to the average
		var lv := int(h.level)
		s.bolt = {"dmg": (1 + lv / 5 + 6 + int(lv / 2.5)) / 2, "charges": 0, "infinite": true, "recharge": 0,
			"name": "the Spirit Bow", "magic": false}
	if "cloak" in def.abilities:
		s.cloak = {"charges": int(def.cloak_charges), "ticks": float(def.cloak_ticks)}
	return s

func power_rating(c: String) -> int:
	var s := hero_stats(c)
	return int(heroes[c].str) + int(s.dmg / 3) + s.dr

func can_equip(c: String, uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty(): return "missing"
	if g.cracked: return "cracked - repair at the Blacksmith"
	if not g.known and DB.item(g.id).type == "ring": return "unidentified - use the Enchanter's Desk"
	var d := DB.item(g.id)
	if d.get("heirloom", false) and DB.heroes[c].heirloom != g.id: return "heirloom of another class"
	var other := equipped_by(uid)
	if other != "" and other != c: return "equipped by " + DB.heroes[other].name
	if not run.is_empty() and run.hero == c: return "hero is on an expedition"
	return ""

func equip(c: String, uid: int) -> bool:
	if can_equip(c, uid) != "": return false
	var t: String = DB.item(gear_by_uid(uid).id).type
	match t:
		"weapon": heroes[c].weapon = uid
		"armor": heroes[c].armor = uid
		"ring": heroes[c].ring = uid
		_: return false
	touch(); return true

func grant_xp(c: String, n: int) -> bool:
	var h: Dictionary = heroes[c]
	h.xp += n
	var up := false
	while h.xp >= xp_to_next(h.level):
		h.xp -= xp_to_next(h.level); h.level += 1; up = true
	return up

# ---------------------------------------------------------------- facilities & crafting
func facility_level(id: String) -> int:
	return int(facilities[id].level)

func facility_upgrade_cost(id: String) -> Dictionary:
	var base: Dictionary = DB.facilities[id].upgrade_cost
	var o := {}
	for k in base: o[k] = int(base[k]) * facility_level(id)
	return o

func can_upgrade_facility(id: String) -> String:
	var f: Dictionary = facilities[id]
	if f.level >= int(DB.facilities[id].max): return "max level"
	if f.level >= f.cap: return "capped - apply a Scroll of Upgrade"
	if not can_afford(facility_upgrade_cost(id)): return "need " + cost_text(facility_upgrade_cost(id))
	return ""

func upgrade_facility(id: String) -> bool:
	if can_upgrade_facility(id) != "": return false
	pay(facility_upgrade_cost(id)); facilities[id].level += 1
	say("%s upgraded to level %d." % [DB.facilities[id].name, facilities[id].level]); touch(); return true

func apply_sou(id: String) -> bool:
	var f: Dictionary = facilities[id]
	if mat("scroll_upgrade") < 1 or f.cap >= int(DB.facilities[id].max): return false
	add_mat("scroll_upgrade", -1); f.cap += 1
	say("Scroll of Upgrade: %s cap raised to %d." % [DB.facilities[id].name, f.cap]); touch(); return true

func recipe(fac: String, rid: String) -> Dictionary:
	for r in DB.recipes.get(fac, []):
		if r.id == rid: return r
	return {}

func can_craft(fac: String, rid: String) -> String:
	var r := recipe(fac, rid)
	if r.is_empty(): return "unknown recipe"
	if facility_level(fac) < int(r.min_level): return "needs %s Lv%d" % [DB.facilities[fac].name, r.min_level]
	if not can_afford(r.cost): return "need " + cost_text(r.cost)
	return ""

func craft(fac: String, rid: String) -> bool:
	if can_craft(fac, rid) != "": return false
	var r := recipe(fac, rid)
	pay(r.cost)
	if r.has("out"): add_gear(r.out); say("Forged " + DB.display_name(r.out) + ".")
	else: add_mat(r.out_mat, 1); say("Made " + DB.mat_name(r.out_mat) + ".")
	if fac == "alchemy": stats.potions_brewed += 1
	check_unlocks()
	touch(); return true

func item_upgrade_cost(uid: int) -> Dictionary:
	return {"iron_ore": 4 * (int(gear_by_uid(uid).lvl) + 1)}

func can_upgrade_item(uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty() or not (DB.item(g.id).type in ["weapon", "armor"]): return "not upgradable"
	if g.cracked: return "repair first"
	if g.lvl >= facility_level("blacksmith"): return "Blacksmith cap +%d" % facility_level("blacksmith")
	if not can_afford(item_upgrade_cost(uid)): return "need " + cost_text(item_upgrade_cost(uid))
	return ""

func upgrade_item(uid: int) -> bool:
	if can_upgrade_item(uid) != "": return false
	pay(item_upgrade_cost(uid)); gear_by_uid(uid).lvl += 1
	say("Upgraded " + gear_name(gear_by_uid(uid)) + "."); touch(); return true

func repair_cost(uid: int) -> Dictionary:
	var g := gear_by_uid(uid)
	return {"iron_ore": 2 + int(DB.item(g.id).get("tier", 1)) + int(g.lvl)}

func repair(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or not g.cracked or not pay(repair_cost(uid)): return false
	g.cracked = false; say("Repaired " + gear_name(g) + "."); touch(); return true

## Drink a Starter Elixir at the elevator: raises a level-1 hero to the Sewers baseline (Lv3).
func use_elixir(c: String) -> bool:
	var h: Dictionary = heroes[c]
	if mat("elixir_starter") < 1 or h.level >= 3: return false
	add_mat("elixir_starter", -1); h.level = 3; h.xp = 0
	say(DB.heroes[c].name + " drinks a Starter Elixir (Lv3)."); touch(); return true

func imbue_wand(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or DB.item(g.id).type != "wand" or not g.known: return false
	var old: String = heroes.mage.wand
	heroes.mage.wand = g.id
	gear.erase(g)
	if old != "": add_gear(old)
	say("Imbued %s into the Mage's Staff." % DB.item(g.id).name); touch(); return true

# ---------------------------------------------------------------- Enchanter's Desk
func identify_seconds() -> float:
	return maxf(60.0, 600.0 - 180.0 * (facility_level("enchanter") - 1))   # 10 / 7 / 4 minutes

func enqueue_identify(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or g.known: return false
	for q in id_queue:
		if q.uid == uid: return false
	var start := now()
	if not id_queue.is_empty(): start = maxf(start, float(id_queue.back().ready_at))
	id_queue.append({"uid": uid, "ready_at": start + identify_seconds()})
	touch(); return true

## Finishes any identifications whose time has passed. Returns identified uids.
func tick_identify() -> Array:
	var done := []
	for q in id_queue.duplicate():
		if float(q.ready_at) <= now():
			var g := gear_by_uid(q.uid)
			if not g.is_empty():
				g.known = true; seen["item:" + g.id] = true; done.append(q.uid); say("Identified: " + gear_name(g))
			id_queue.erase(q)
	if not done.is_empty(): touch()
	return done

# ---------------------------------------------------------------- Offline Patrols
func patrol_max_hours() -> float:
	return [2.0, 4.0, 8.0][clampi(facility_level("guild") - 1, 0, 2)]

func can_patrol(c: String, biome: String) -> String:
	var h: Dictionary = heroes[c]
	if not h.unlocked: return "locked"
	if not h.patrol.is_empty(): return "already patrolling"
	if not run.is_empty() and run.hero == c: return "on an expedition"
	if not (biome in h.cleared): return "clear %s first" % DB.biomes[biome].name
	return ""

func start_patrol(c: String, biome: String) -> bool:
	if can_patrol(c, biome) != "": return false
	heroes[c].patrol = {"biome": biome, "start": now()}
	say("%s sets out to patrol the %s." % [DB.heroes[c].name, DB.biomes[biome].name]); touch(); return true

## Efficiency: hero power vs biome strength gate, clamped 0.25..1.25.
func patrol_efficiency(c: String, biome: String) -> float:
	return clampf(float(power_rating(c)) / (float(DB.biomes[biome].str_gate) + 2.0), 0.25, 1.25)

func patrol_preview(c: String) -> Dictionary:
	var p: Dictionary = heroes[c].patrol
	if p.is_empty(): return {}
	var b: Dictionary = DB.biomes[p.biome]
	var hours := clampf((now() - float(p.start)) / 3600.0, 0.0, patrol_max_hours())
	var eff := patrol_efficiency(c, p.biome)
	var out := {}
	for k in b.patrol_yield_per_hour: out[k] = int(floor(float(b.patrol_yield_per_hour[k]) * hours * eff))
	out["_curios"] = int(floor(hours / float(b.patrol_curio_every_hours)))
	out["_hours"] = hours
	return out

func collect_patrol(c: String) -> Dictionary:
	var y := patrol_preview(c)
	if y.is_empty(): return {}
	for k in y:
		if not String(k).begins_with("_"): add_mat(k, y[k])
	for i in y._curios: add_gear(["ring_might", "ring_tenacity"][(next_uid + i) % 2], false)
	heroes[c].patrol = {}
	say("%s returns from patrol (%.1fh)." % [DB.heroes[c].name, y._hours]); touch()
	return y

# ---------------------------------------------------------------- expeditions
func belt_size() -> int:
	return facility_level("alchemy") + 1

func can_start_run(c: String) -> String:
	var h: Dictionary = heroes[c]
	if not h.unlocked: return "locked: " + DB.heroes[c].get("unlock", "")
	if not run.is_empty(): return "an expedition is already active"
	if not h.patrol.is_empty(): return "hero is on patrol"
	return ""

## loadout: {ration:n, torch:n, potion_healing:n, scroll_passage:n}; taken out of the stash.
func start_run(c: String, loadout: Dictionary, biome := "sewers", seed := -1) -> bool:
	if can_start_run(c) != "": return false
	var sup := {}
	for k in SUPPLY_KEYS:
		var n := mini(int(loadout.get(k, 0)), mat(k))
		if k == "potion_healing": n = mini(n, belt_size())
		sup[k] = n; add_mat(k, -n)
	var s := hero_stats(c)
	run = {"hero": c, "biome": biome, "floor": 1, "progress": 0.0, "torch": 100.0, "satiety": 100.0,
		"hp": s.ht, "pack": {}, "pack_gear": [], "supplies": sup, "seed": seed if seed >= 0 else int(now()) % 100000,
		"events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false}
	stats.runs += 1; note_floor(1)
	say("%s descends into the %s." % [s.name, DB.biomes[biome].name]); touch(); return true

func pack_add(id: String, n: int) -> void:
	if run.is_empty(): add_mat(id, n); return  # no expedition: straight to the stash
	run.pack[id] = int(run.pack.get(id, 0)) + n

## result: "extract" keeps everything; "death" loses pack, cracks gear, resets hero; "abandon" loses pack.
func end_run(result: String) -> void:
	if run.is_empty(): return
	last_result = result
	var c: String = run.hero
	var h: Dictionary = heroes[c]
	# unused supplies always go back to the stash (they were never "found")
	for k in run.supplies: add_mat(k, int(run.supplies[k]))
	match result:
		"extract":
			for k in run.pack: add_mat(k, int(run.pack[k]))
			for g in run.pack_gear: gear.append(g)
			stats.extractions += 1
			say("Extracted! The pack is banked at Camp.")
		"death":
			stats.deaths += 1
			for slot in ["weapon", "armor", "ring"]:
				var g := gear_by_uid(int(h[slot]))
				# heirlooms (Mage's Staff...) are permanent and never crack
				if not g.is_empty() and not DB.item(g.id).get("heirloom", false): g.cracked = true
			h.level = 1; h.xp = 0; h.str = 10
			say("%s fell. Pack lost, gear cracked, back to Lv1 / 10 Str." % DB.heroes[c].name)
		"abandon":
			say("Expedition abandoned. Unbanked loot lost.")
	run = {}
	touch()

func record_boss_kill(c: String, biome: String) -> bool:
	var kills: Array = boss_kills.get(c, [])
	var first := not (biome in kills)
	if first:
		kills.append(biome); boss_kills[c] = kills
		pack_add("scroll_upgrade", 1)
	if not (biome in heroes[c].cleared): heroes[c].cleared.append(biome)
	var key: String = DB.biomes[biome].boss + "_kills"
	if stats.has(key): stats[key] += 1
	check_unlocks()
	return first

## Class unlock milestones (DECISIONS.md #11, #31)
func check_unlocks() -> void:
	for c in heroes:
		var rule: Dictionary = DB.heroes[c].get("unlock_rule", {})
		if rule.is_empty() or heroes[c].unlocked: continue
		if stat_value(rule.stat) >= int(rule.goal):
			heroes[c].unlocked = true
			say("The %s has joined the Camp!" % DB.heroes[c].name)

# ---------------------------------------------------------------- meta-progression
## Progress toward a milestone stat (see data/milestones.json).
func stat_value(stat: String) -> int:
	if stat.begins_with("boss:"): return int(stats.get(stat.substr(5) + "_kills", 0))
	if stat.begins_with("cleared:"):
		var b := stat.substr(8)
		return heroes.values().filter(func(h): return b in h.cleared).size()
	return int(stats.get(stat, 0))

## Grant every newly reached milestone (once). Returns the ids granted.
func check_milestones() -> Array:
	var got := []
	for m in DB.milestones:
		if m.id in milestones_claimed or stat_value(m.stat) < int(m.goal): continue
		milestones_claimed.append(m.id); got.append(m.id)
		for k in m.reward: add_mat(k, int(m.reward[k]))
		say("Milestone: %s! Reward: %s" % [m.name, cost_text(m.reward)])
		Sfx.play("badge")
	return got

func add_stat(k: String, n: int) -> void:
	stats[k] = int(stats.get(k, 0)) + n

## Tutorial: should tip `id` be shown now?
func wants_tip(id: String) -> bool:
	return bool(settings.get("tutorial", true)) and DB.tips.has(id) and not (id in tutorial_done)

## Codex: remember that the player has encountered something.
func discover(key: String) -> void:
	if not seen.has(key): seen[key] = true

func set_setting(k: String, v) -> void:
	settings[k] = v
	settings_changed.emit()

func note_floor(f: int) -> void:
	if f > int(stats.deepest_floor):
		stats.deepest_floor = f; check_unlocks()

# ---------------------------------------------------------------- persistence
func to_dict() -> Dictionary:
	return {"mats": mats, "gear": gear, "next_uid": next_uid, "heroes": heroes, "facilities": facilities,
		"id_queue": id_queue, "boss_kills": boss_kills, "settings": settings, "run": run, "stats": stats,
		"milestones_claimed": milestones_claimed, "seen": seen, "tutorial_done": tutorial_done}

func from_dict(d: Dictionary) -> void:
	new_game()
	mats = d.get("mats", mats); gear = d.get("gear", gear); next_uid = int(d.get("next_uid", next_uid))
	for c in d.get("heroes", {}):
		if heroes.has(c): heroes[c].merge(d.heroes[c], true)
	for f in d.get("facilities", {}):
		if facilities.has(f): facilities[f].merge(d.facilities[f], true)
	id_queue = d.get("id_queue", []); boss_kills = d.get("boss_kills", {})
	settings.merge(d.get("settings", {}), true); run = d.get("run", {})
	stats.merge(d.get("stats", {}), true)
	milestones_claimed = Array(d.get("milestones_claimed", [])); seen = d.get("seen", {}); tutorial_done = Array(d.get("tutorial_done", []))
	settings.text_scale = float(settings.text_scale); settings.delve_speed = float(settings.delve_speed)
	for k in stats: stats[k] = int(stats[k])
	_fix_types()
	touch()

## JSON turns every number into float; normalise ints we compare/use as keys.
func _fix_types() -> void:
	next_uid = int(next_uid)
	for k in mats: mats[k] = int(mats[k])
	for g in gear:
		g.uid = int(g.uid); g.lvl = int(g.lvl)
	for c in heroes:
		var h: Dictionary = heroes[c]
		for k in ["level", "xp", "str", "weapon", "armor", "ring"]: h[k] = int(h[k])
	for f in facilities:
		facilities[f].level = int(facilities[f].level); facilities[f].cap = int(facilities[f].cap)
	for q in id_queue: q.uid = int(q.uid)
	if not run.is_empty():
		for k in ["floor", "next_event", "gather", "starve", "seed", "hp", "pending_loot"]: run[k] = int(run.get(k, 0))
		for k in run.pack: run.pack[k] = int(run.pack[k])
		for k in run.supplies: run.supplies[k] = int(run.supplies[k])
		for g in run.pack_gear:
			g.uid = int(g.uid); g.lvl = int(g.lvl)
		if run.has("pending_card") and run.pending_card.has("room"):
			run.pending_card.room = Array(run.pending_card.room); run.pending_card.mobs = Array(run.pending_card.mobs)
		if run.has("active_fight"):
			# rooms/mob lists come back as plain arrays; Combat.from_dict handles the combat itself
			var ev: Dictionary = run.active_fight.event
			ev.room = Array(ev.room); ev.mobs = Array(ev.mobs)
