## Delve: rules for the UI-driven exploration phase, operating on GameState.run.
## The bar ticks 0..100% per floor; torch/satiety drain; events fire every ~20-25%.
## Event content is chosen with a seeded RNG (run.seed + floor), so a run is reproducible.
class_name Delve
extends RefCounted

const EVENT_POINTS := [22.0, 45.0, 68.0, 90.0]
const TORCH_DRAIN := 0.4      # per 1% progress (100% floor = 40 torch; 5 floors = 200 = start + 2 torches)
const SATIETY_DRAIN := 0.4    # per 1% progress
const TORCH_RESTORE := 60.0
const RATION_RESTORE := 70.0
const FLOOR_REST_HEAL := 0.2  # fraction of HT healed when descending
const SEARCH_TORCH := 10.0    # torch spent searching a cleared floor for hidden doors
const CAMPFIRE_REST := 50.0  # torch and satiety restored when pressing on from a boss campfire
const SEARCH_CHANCE := 50     # % to find a hidden door (Rogue: always)

static func biome(run: Dictionary) -> Dictionary:
	return DB.biomes[run.biome]

static func rng_for(run: Dictionary, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(run.seed), int(run.floor), salt])
	return r

## Build this floor's event schedule.
static func plan_floor(run: Dictionary) -> void:
	var b := biome(run)
	var r := rng_for(run, 1)
	var evs := []
	var w: Dictionary = b.event_weights
	for i in EVENT_POINTS.size():
		var at: float = EVENT_POINTS[i] + r.randf_range(-2.0, 2.0)
		var kind := "combat"
		if int(run.floor) == int(b.boss_floor) and i == EVENT_POINTS.size() - 1:
			kind = "boss"
		elif i > 0:
			var roll := r.randi_range(1, int(w.combat) + int(w.door) + int(w.special))
			kind = "combat" if roll <= int(w.combat) else ("door" if roll <= int(w.combat) + int(w.door) else "special")
		evs.append({"at": at, "kind": kind, "salt": i})
	run.events = evs
	run.next_event = 0
	run.progress = 0.0
	run.gather = 0
	run.starve = 0

## Advance progress by `pct`. Returns an event dictionary to present, or {} if none / floor done.
static func advance(gs, pct: float) -> Dictionary:
	var run: Dictionary = gs.run
	if run.events.is_empty(): plan_floor(run)
	var before: float = run.progress
	run.progress = minf(100.0, before + pct)
	var d: float = run.progress - before
	run.torch = maxf(0.0, run.torch - d * TORCH_DRAIN)
	run.satiety = maxf(0.0, run.satiety - d * SATIETY_DRAIN)
	# auto-use supplies when low (decision: no micromanagement in the delve)
	if run.torch < 20.0 and int(run.supplies.get("torch", 0)) > 0:
		run.supplies.torch -= 1; run.torch = minf(100.0, run.torch + TORCH_RESTORE); gs.say("Lit a fresh torch.")
	if run.satiety < 20.0 and int(run.supplies.get("ration", 0)) > 0:
		run.supplies.ration -= 1; run.satiety = minf(100.0, run.satiety + RATION_RESTORE); gs.say("Ate a ration.")
	# passive gathering: +1 gold every 4%, +1 dew every 12%
	var step := int(run.progress / 4.0)
	while run.gather < step:
		run.gather += 1
		gs.pack_add("gold", 1)
		if run.gather % 3 == 0: gs.pack_add("dew", 1)
	# starvation: -1 HP per 5% while satiety is 0 (never kills: leaves 1 HP)
	if run.satiety <= 0.0:
		var s := int(run.progress / 5.0)
		while run.starve < s:
			run.starve += 1; run.hp = maxi(1, int(run.hp) - 1)
	# fixed Strength potion milestones
	for m in biome(run).strength_potions_at:
		var key := "%d_%d" % [int(m[0]), int(m[1])]
		if int(run.floor) == int(m[0]) and run.progress >= float(m[1]) and not (key in run.milestones_done):
			run.milestones_done.append(key)
			gs.heroes[run.hero].str += 1
			gs.say("Found a Potion of Strength! %s is now %d Str." % [gs.heroes[run.hero].class.capitalize(), gs.heroes[run.hero].str])
	if run.next_event < run.events.size() and run.progress >= float(run.events[run.next_event].at):
		var ev: Dictionary = run.events[run.next_event]
		run.next_event += 1
		return build_event(run, ev)
	return {}

static func darkness(run: Dictionary) -> bool:
	return float(run.torch) <= 0.0

static func floor_done(run: Dictionary) -> bool:
	return float(run.progress) >= 100.0 and int(run.next_event) >= run.events.size()

static func is_campfire(run: Dictionary) -> bool:
	return int(run.floor) == int(biome(run).boss_floor) and run.boss_dead

## Concrete event: {"kind": "combat", "room": [...], "mobs": [...]} | {"kind":"door", "door":{}} | {"kind":"special","special":{}}
static func build_event(run: Dictionary, ev: Dictionary) -> Dictionary:
	var r := rng_for(run, 10 + int(ev.salt))
	match ev.kind:
		"boss":
			return {"kind": "combat", "boss": true, "room": DB.boss_rooms[int(biome(run).get("boss_room", 0))], "mobs": [biome(run).boss]}
		"door":
			var ds := _for_biome(DB.doors, run)
			return {"kind": "door", "door": ds[r.randi() % ds.size()]}
		"special":
			var ss := _for_biome(DB.specials, run)
			return {"kind": "special", "special": ss[r.randi() % ss.size()]}
	return combat_event(run, r)

static func _for_biome(list: Array, run: Dictionary) -> Array:
	return list.filter(func(x): return run.biome in x.get("biomes", [run.biome]))

## Rooms used for ordinary fights: the shared set plus the biome's own rooms.
static func room_pool(run: Dictionary) -> Array:
	return DB.rooms + DB.biome_rooms.get(run.biome, [])

## Build a Combat for an event in the current run (shared by CombatScreen and RunSim).
static func new_combat(gs, ev: Dictionary) -> Combat:
	var run: Dictionary = gs.run
	for m in ev.mobs: gs.discover("mob:" + m)
	var c := Combat.new()
	c.setup(ev.room, gs.hero_stats(run.hero), int(run.hp), ev.mobs, darkness(run), biome(run).get("traps", []))
	return c

static func combat_event(run: Dictionary, r: RandomNumberGenerator, mobs := []) -> Dictionary:
	if mobs.is_empty():
		var sets: Array = biome(run).encounter_sets.filter(func(s): return int(s.min_floor) <= int(run.floor))
		# prefer encounters introduced recently so floors feel different
		var pick: Dictionary = sets[r.randi() % sets.size()]
		mobs = pick.mobs
	var rooms := room_pool(run)
	return {"kind": "combat", "room": rooms[r.randi() % rooms.size()], "mobs": mobs}

static func pay_possible(gs, cost: Dictionary) -> bool:
	var run: Dictionary = gs.run
	for k in cost:
		var n := int(cost[k])
		if k == "hp":
			if int(run.hp) <= n: return false
		elif k == "torch_fuel":
			if float(run.torch) < n: return false
		elif int(run.supplies.get(k, 0)) + int(run.pack.get(k, 0)) + (gs.mat(k) if k == "iron_key" else 0) < n:
			return false
	return true

## Pay a cost from run supplies / pack / hp. Returns false (and pays nothing) if unaffordable.
static func pay(gs, cost: Dictionary) -> bool:
	if not pay_possible(gs, cost): return false
	var run: Dictionary = gs.run
	for k in cost:
		var n := int(cost[k])
		if k == "hp": run.hp -= n; continue
		if k == "torch_fuel": run.torch = float(run.torch) - n; continue
		var from_sup := mini(n, int(run.supplies.get(k, 0)))
		if from_sup > 0: run.supplies[k] -= from_sup; n -= from_sup
		var from_pack := mini(n, int(run.pack.get(k, 0)))
		if from_pack > 0: run.pack[k] -= from_pack; n -= from_pack
		if n > 0: gs.add_mat(k, -n)
	return true

## Rewards go into the pack (lost on death). item_unknown spawns an un-ID'd ring/wand.
static func reward(gs, rw: Dictionary) -> String:
	var run: Dictionary = gs.run
	var parts := []
	for k in rw:
		match k:
			"item_unknown":
				var pool: Array = ["ring_might", "ring_tenacity"] if rw[k] == "ring" else ["wand_magic_missile", "wand_firebolt", "wand_lightning"]
				var id: String = pool[(int(run.seed) + int(run.floor) + run.pack_gear.size()) % pool.size()]
				run.pack_gear.append(_new_gear(gs, id, false))
				parts.append(DB.item(id).unknown_name)
			"item":
				run.pack_gear.append(_new_gear(gs, rw[k], true))
				parts.append(DB.item(rw[k]).name)
			_:
				if k in ["torch", "ration"]:
					run.supplies[k] = int(run.supplies.get(k, 0)) + int(rw[k])  # usable right away
				else: gs.pack_add(k, int(rw[k]))
				parts.append("%d %s" % [rw[k], DB.mat_name(k)])
	return ", ".join(parts)

static func _new_gear(gs, id: String, known: bool) -> Dictionary:
	var g := {"uid": gs.next_uid, "id": id, "lvl": 0, "cracked": false, "known": known}
	if known: gs.discover("item:" + id)
	gs.next_uid += 1
	return g

## Search a cleared floor for a hidden door (once per floor). Returns the message to show.
static func search_floor(gs) -> String:
	var run: Dictionary = gs.run
	if int(run.get("searched_floor", 0)) == int(run.floor) or float(run.torch) < SEARCH_TORCH: return ""
	run.searched_floor = int(run.floor)
	run.torch = float(run.torch) - SEARCH_TORCH
	var found: bool = run.hero == "rogue" or rng_for(run, 31).randi_range(1, 100) <= SEARCH_CHANCE
	if not found: return "You search every wall... nothing this time."
	gs.add_stat("hidden_doors", 1)
	return "A hidden door! Secret cache: " + reward(gs, biome(run).secret_cache)

static func can_search_floor(run: Dictionary) -> bool:
	return int(run.get("searched_floor", 0)) != int(run.floor) and float(run.torch) >= SEARCH_TORCH

## At a boss campfire: the next biome, or "" if this is the deepest one in the build.
static func next_biome(run: Dictionary) -> String:
	var n: String = biome(run).get("next", "")
	return n if DB.biomes.has(n) else ""

## Leave the boss campfire for the next biome (keeps the pack - nothing is banked).
static func continue_deeper(gs) -> void:
	var run: Dictionary = gs.run
	run.biome = next_biome(run)
	run.boss_dead = false
	# resting at the campfire: half a torch and half a meal (DECISIONS #57)
	run.torch = minf(100.0, float(run.torch) + CAMPFIRE_REST); run.satiety = minf(100.0, float(run.satiety) + CAMPFIRE_REST)
	descend(gs)
	gs.say("You enter the %s. Traps lurk on these floors - search before you step." % biome(run).name)

## Move to the next floor: heal a little, recover chasm loot.
static func descend(gs) -> void:
	var run: Dictionary = gs.run
	run.floor += 1
	gs.note_floor(int(run.floor))
	var ht: int = gs.hero_stats(run.hero).ht
	run.hp = mini(ht, int(run.hp) + int(ceil(ht * FLOOR_REST_HEAL)))
	if int(run.pending_loot) > 0:
		gs.pack_add("gold", int(run.pending_loot)); gs.say("Recovered %d gold that fell from above." % run.pending_loot)
		run.pending_loot = 0
	plan_floor(run)
	gs.touch()

## Apply a finished fight to the run (shared by DelveScreen and the full-run simulator).
## Returns false if the hero died (caller should end the run with "death").
static func apply_fight_result(gs, ev: Dictionary, res: Dictionary, reward: Dictionary) -> bool:
	var run: Dictionary = gs.run
	gs.add_stat("kills", int(res.get("kills", 0))); gs.add_stat("traps_found", int(res.get("traps_found", 0)))
	for t in res.get("trap_ids", []): gs.discover("trap:" + t)
	if not res.won: return false
	run.hp = int(res.hp)
	gs.pack_add("gold", int(res.loot))
	run.pending_loot = int(run.pending_loot) + int(res.fallen_loot)
	if gs.grant_xp(run.hero, int(res.xp)):
		gs.say("Level up! %s is now Lv%d." % [DB.heroes[run.hero].name, gs.heroes[run.hero].level])
		run.hp = mini(gs.hero_stats(run.hero).ht, int(run.hp) + int(DB.heroes[run.hero].ht_per_level))
	if not reward.is_empty(): gs.say("Reward: " + reward(gs, reward))
	if res.boss_killed:
		run.boss_dead = true
		if gs.record_boss_kill(run.hero, run.biome): gs.say("First %s kill for this class: Scroll of Upgrade!" % DB.mobs[ev.mobs[0]].name)
	gs.touch()
	return true
