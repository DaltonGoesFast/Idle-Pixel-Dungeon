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
const FINAL_REST_HEAL := 0.6
const BOSS_RATIONS := 2       # rations every boss kill adds to the belt (DECISIONS #110)
const CAMPFIRE_REST := 50.0  # torch and satiety restored when pressing on from a boss campfire
const SEARCH_CHANCE := 50     # % to find a hidden door (Rogue: always)
const AUTO_STOP_HP := 0.3     # at or below this HP fraction Auto Battle turns off for manual control / Scroll of Passage
const CLOSE_CALL_HP := 0.1    # "Close Call" feat: win a fight at or below this HP fraction (DECISIONS #195)
const CROWD_KILLS := 6        # "Crowd Control" feat: kills in one fight
## Floor feelings (DECISIONS #237): XL / Secret / Traps. Per biome: at least 1, rarely 2; resets on new biome.
const FEELINGS := ["xl", "secret", "traps"]
const FEELING_TWO_CHANCE := 0.20
const SECRET_CACHE_GOLD_MULT := 1.5
const XL_LARGE_WEIGHT := 3
const FEELING_LOG := {
	"xl": "This dungeon floor seems unusually large.",
	"secret": "The atmosphere hints that this floor hides many secrets.",
	"traps": "The ground seems especially treacherous here.",
}

static func biome(run: Dictionary) -> Dictionary:
	return DB.biomes[run.biome]

static func rng_for(run: Dictionary, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(run.seed), int(run.floor), salt])
	return r

## Seed which non-boss floors in this biome get a feeling. Call on biome entry; resets the plan.
static func plan_biome_feelings(run: Dictionary) -> void:
	var b := biome(run)
	var boss := int(b.boss_floor)
	var fr: Array = b.floors
	var lo := maxi(int(fr[0]), int(run.floor))
	var eligible: Array = []
	for f in range(lo, boss):
		eligible.append(f)
	if eligible.is_empty():
		run.feeling_plan = {}; run.feeling = ""; return
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(run.seed), String(run.biome), 9001])
	var n := 2 if (eligible.size() >= 2 and r.randf() < FEELING_TWO_CHANCE) else 1
	n = mini(n, eligible.size())
	var pool_floors: Array = eligible.duplicate()
	var chosen: Array = []
	for _i in n:
		var idx := r.randi() % pool_floors.size()
		chosen.append(pool_floors[idx])
		pool_floors.remove_at(idx)
	var feel_pool: Array = FEELINGS.duplicate()
	var plan := {}
	for f in chosen:
		var fi := r.randi() % feel_pool.size()
		plan[str(int(f))] = String(feel_pool[fi])
		feel_pool.remove_at(fi)
		if feel_pool.is_empty(): feel_pool = FEELINGS.duplicate()
	run.feeling_plan = plan
	apply_feeling_for_floor(run)

static func apply_feeling_for_floor(run: Dictionary) -> void:
	var plan: Dictionary = run.get("feeling_plan", {})
	run.feeling = String(plan.get(str(int(run.floor)), ""))

static func feeling_log(feeling: String) -> String:
	return String(FEELING_LOG.get(feeling, ""))

static func log_feeling(gs) -> void:
	var msg := feeling_log(String(gs.run.get("feeling", "")))
	if msg != "": gs.log_line(msg, "highlight")

## Build this floor's event schedule.
static func plan_floor(run: Dictionary) -> void:
	# Old saves / first tick: seed the biome quota if missing (DECISIONS #237).
	if run.get("feeling_plan", {}).is_empty() and int(run.floor) < int(biome(run).boss_floor):
		plan_biome_feelings(run)
	else:
		apply_feeling_for_floor(run)
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
	_apply_feeling_to_schedule(run)
	run.next_event = 0
	run.progress = 0.0
	run.gather = 0
	run.starve = 0

## Force a special (and sticky special id) when the floor feeling needs one.
static func _apply_feeling_to_schedule(run: Dictionary) -> void:
	var feel := String(run.get("feeling", ""))
	if feel == "" or int(run.floor) == int(biome(run).boss_floor): return
	var evs: Array = run.events
	var has_special := false
	for e in evs:
		if String(e.kind) == "special": has_special = true; break
	if not has_special:
		for i in range(evs.size() - 1, -1, -1):
			if String(evs[i].kind) != "boss":
				evs[i].kind = "special"
				break
	var force := ""
	match feel:
		"secret": force = "odd_wall"
		"traps": force = "trap_vault"
	if force == "": return
	for e in evs:
		if String(e.kind) == "special":
			e.force_special = force
			break

## Advance progress by `pct`. Returns an event dictionary to present, or {} if none / floor done.
static func advance(gs, pct: float) -> Dictionary:
	var run: Dictionary = gs.run
	if run.events.is_empty(): plan_floor(run)
	var before: float = run.progress
	run.progress = minf(100.0, before + pct)
	var d: float = run.progress - before
	run.torch = maxf(0.0, run.torch - d * TORCH_DRAIN)
	run.satiety = maxf(0.0, run.satiety - d * SATIETY_DRAIN * _hunger(gs))   # Horn of Plenty slows this
	# auto-use supplies when low (decision: no micromanagement in the delve)
	if run.torch < 20.0 and int(run.supplies.get("torch", 0)) > 0:
		run.supplies.torch -= 1; run.torch = minf(100.0, run.torch + TORCH_RESTORE); gs.say("Lit a fresh torch.")
	if run.satiety < 20.0 and int(run.supplies.get("ration", 0)) > 0:
		run.supplies.ration -= 1; run.satiety = minf(100.0, run.satiety + RATION_RESTORE); gs.say("Ate a ration."); gs.add_stat("rations_eaten", 1); gs._mystical_meal()
	# passive gathering: biome-scaled gold every 8%, dew on a biome interval (DECISIONS #230)
	# counted on the pinned haul line; individual drips are not logged
	var step := int(run.progress / 4.0)
	var gold_n := biome_gold_per_tick(String(run.biome))
	var dew_every := biome_dew_interval(String(run.biome))
	while run.gather < step:
		run.gather += 1
		if run.gather % 2 == 0:
			gs.pack_add("gold", gold_n)
		if dew_every > 0 and run.gather % dew_every == 0:
			gs.pack_add("dew", 1)
	# torch / food warnings, once per threshold per floor (DECISIONS #101)
	var warns: Array = run.get("warned", [])
	var wk := func(k: String, cond: bool, text: String, kind: String):
		var key := "%s_%d" % [k, int(run.floor)]
		if cond and not (key in warns): warns.append(key); gs.log_line(text, kind)
	wk.call("torch30", run.torch < 30.0 and int(run.supplies.get("torch", 0)) == 0, "Warning: your torch is burning low.", "warning")
	wk.call("dark", run.torch <= 0.0, "Your torch is out - it is dark.", "warning")
	wk.call("food30", run.satiety < 30.0 and int(run.supplies.get("ration", 0)) == 0, "You are hungry and out of rations.", "warning")
	wk.call("starve", run.satiety <= 0.0, "You are starving!", "negative")
	run.warned = warns
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
			# once per hero life, like SPD's fixed 10 potions per game: repeat delves no longer stack Str (DECISIONS #129)
			var found: Array = gs.heroes[run.hero].get("str_found", [])
			if key in found: continue
			found.append(key); gs.heroes[run.hero].str_found = found
			gs.heroes[run.hero].str += 1
			gs.say("Found a Potion of Strength! %s is now %d Str." % [gs.heroes[run.hero].class.capitalize(), gs.heroes[run.hero].str])
	if run.next_event < run.events.size() and run.progress >= float(run.events[run.next_event].at):
		var ev: Dictionary = run.events[run.next_event]
		run.next_event += 1
		var built := build_event(run, ev)
		# Scroll of Teleportation: the next non-boss fight is skipped
		if run.get("skip_card", false) and built.get("kind", "") == "combat" and not built.get("boss", false):
			run.skip_card = false; gs.say("Teleported past a fight!")
			return {}
		return built
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
			var forced := String(ev.get("force_special", ""))
			if forced != "":
				for s in DB.specials:
					if String(s.id) == forced:
						return {"kind": "special", "special": s}
			var ss := _for_biome(DB.specials, run)
			if String(run.get("feeling", "")) == "traps":
				for s in ss:
					if String(s.id) == "trap_vault":
						return {"kind": "special", "special": s}
			return {"kind": "special", "special": ss[r.randi() % ss.size()]}
	return combat_event(run, r)

## Entries for this biome; an optional "min_floor" keeps tougher rooms off the first floors (DECISIONS #154).
static func _for_biome(list: Array, run: Dictionary) -> Array:
	return list.filter(func(x): return run.biome in x.get("biomes", [run.biome]) and int(run.floor) >= int(x.get("min_floor", 0)))

## Rooms used for ordinary fights. Sewers/Prison keep shared 8x8s; later biomes use larger maps only.
## XL floors weight large maps ~3x (DECISIONS #237).
static func room_pool(run: Dictionary) -> Array:
	var biome_id := String(run.biome)
	var own: Array = DB.biome_rooms.get(biome_id, [])
	var pool: Array
	match biome_id:
		"sewers":
			pool = DB.rooms + own
		"prison":
			pool = DB.rooms + own + own   # 10x10s listed twice so they show up often
		"caves", "city", "halls":
			pool = own if not own.is_empty() else DB.rooms
		_:
			pool = DB.rooms + own
	if String(run.get("feeling", "")) != "xl": return pool
	var weighted: Array = []
	for rm in pool:
		weighted.append(rm)
		if is_large_room(rm):
			for _i in XL_LARGE_WEIGHT - 1:
				weighted.append(rm)
	return weighted

## True for the 10x10 / 12x12 maps (anything wider or taller than the classic 8x8).
static func is_large_room(room: Array) -> bool:
	if room.is_empty(): return false
	return room.size() > Combat.SIZE or String(room[0]).length() > Combat.SIZE

## Digit spawn slots (1-8) in a room map. Boss marker B counts as one slot.
static func room_slot_count(room: Array) -> int:
	var n := 0
	for row in room:
		for i in String(row).length():
			var ch := String(row)[i]
			if ch in "12345678B": n += 1
	return n

## True when the room has a real doorway (floor/grass on two opposite sides, walls on the other two).
static func room_has_door(room: Array) -> bool:
	var hh := room.size()
	if hh == 0: return false
	var ww := String(room[0]).length()
	for y in hh:
		var row := String(room[y])
		for x in ww:
			if row[x] != "+": continue
			var n := _room_ch(room, x, y - 1); var s := _room_ch(room, x, y + 1)
			var e := _room_ch(room, x + 1, y); var w := _room_ch(room, x - 1, y)
			var ns_open := _room_open(n) and _room_open(s)
			var ew_open := _room_open(e) and _room_open(w)
			var ns_wall := n == "#" and s == "#"
			var ew_wall := e == "#" and w == "#"
			if (ns_open and ew_wall) or (ew_open and ns_wall): return true
	return false

static func _room_ch(room: Array, x: int, y: int) -> String:
	if y < 0 or y >= room.size(): return "#"
	var row := String(room[y])
	if x < 0 or x >= row.length(): return "#"
	return row[x]

static func _room_open(ch: String) -> bool:
	return ch != "#" and ch != "_"

## Repeat the encounter's own mobs until every spawn slot is filled. Only rooms larger than 8x8
## grow this way; an 8x8 keeps the rolled encounter as is (a lone crab stays one crab, DECISIONS #137).
static func fill_mobs(mobs: Array, room: Array) -> Array:
	if not is_large_room(room): return mobs
	var need := room_slot_count(room)
	if need <= mobs.size() or mobs.is_empty(): return mobs
	var out: Array = mobs.duplicate()
	var i := 0
	while out.size() < need:
		out.append(mobs[i % mobs.size()]); i += 1
	return out

## Build a Combat for an event in the current run (shared by CombatScreen and RunSim).
static func new_combat(gs, ev: Dictionary) -> Combat:
	var run: Dictionary = gs.run
	for m in ev.mobs: gs.discover("mob:" + m)
	var c := Combat.new()
	c.setup(ev.room, gs.hero_stats(run.hero), int(run.hp), ev.mobs, darkness(run), biome(run).get("traps", []))
	c.floor = int(run.get("floor", 1))
	c.purse = int(run.pack.get("gold", 0))
	run.fighting_goo = "goo" in ev.mobs
	if run.fighting_goo: _weaken_goo(gs, c)
	if int(run.get("shield_next", 0)) > 0:   # Potion of Shielding: stacks then clamps to ht/2 like gear Barrier (DECISIONS #221)
		c.hero.barrier = mini(int(c.hero.ht) / 2, int(c.hero.barrier) + int(run.shield_next)); run.shield_next = 0
		c._log("Your shield shimmers: +Barrier.")
	if not run.get("next_fx", {}).is_empty():
		c.apply_fx(run.next_fx); run.next_fx = {}
	return c

## Goo grudge (DECISIONS #131): Goo is SPD-strength (HT 90) but each earlier loss to it leaves it 15 HT weaker,
## down to GOO_MIN_HT; at the floor it no longer enrages, so a struggling new player is never stuck. Reset when Goo is killed.
const GOO_MIN_HT := 70
static func goo_ht(gs) -> int:
	return maxi(GOO_MIN_HT, int(DB.mobs.goo.ht) - 15 * int(gs.stats.get("goo_losses", 0)))

static func _weaken_goo(gs, c: Combat) -> void:
	var ht := goo_ht(gs)
	for u in c.enemies():
		if u.get("id", "") == "goo" and ht < int(u.ht):
			u.ht = ht; u.hp = mini(int(u.hp), ht)
			c._log("Goo still bears the wounds of your last fight (HP %d)." % ht)
			if ht <= GOO_MIN_HT: u.erase("enraged_dmg"); u.pump_every_enraged = int(u.pump_every)   # worn out: no enrage

## Horn of Plenty: satiety drain multiplier (cached per floor to keep hero_stats out of the per-frame tick).
static func _hunger(gs) -> float:
	var run: Dictionary = gs.run
	if int(run.get("_hunger_floor", -1)) != int(run.floor):
		run._hunger_floor = int(run.floor); run._hunger = float(gs.hero_stats(run.hero).get("hunger_mult", 1.0))
	return float(run.get("_hunger", 1.0))

static func combat_event(run: Dictionary, r: RandomNumberGenerator, mobs := []) -> Dictionary:
	if mobs.is_empty():
		var sets: Array = biome(run).encounter_sets.filter(func(s): return int(s.min_floor) <= int(run.floor))
		# XL: prefer denser packs; otherwise flat pick (comment once hoped for "recent" bias)
		if String(run.get("feeling", "")) == "xl":
			mobs = _pick_dense_pack(sets, r)
		else:
			mobs = sets[r.randi() % sets.size()].mobs
	var rooms := room_pool(run)
	if "snake" in mobs:
		var with_door: Array = rooms.filter(func(rm): return room_has_door(rm))
		if not with_door.is_empty(): rooms = with_door
	var room: Array
	if String(run.get("feeling", "")) == "traps":
		room = _pick_trap_room(rooms, r)
	else:
		room = rooms[r.randi() % rooms.size()]
	return {"kind": "combat", "room": room, "mobs": fill_mobs(mobs, room)}

## Weight encounter packs by mob count (XL floors).
static func _pick_dense_pack(sets: Array, r: RandomNumberGenerator) -> Array:
	if sets.is_empty(): return []
	var total := 0
	for s in sets:
		total += maxi(1, (s.mobs as Array).size())
	var roll := r.randi_range(1, total)
	var acc := 0
	for s in sets:
		acc += maxi(1, (s.mobs as Array).size())
		if roll <= acc: return s.mobs
	return sets[sets.size() - 1].mobs

## Visible + hidden trap glyphs in a room map.
static func room_trap_count(room: Array) -> int:
	var n := 0
	for row in room:
		for i in String(row).length():
			var ch := String(row)[i]
			if ch == "^" or ch == "?": n += 1
	return n

## Prefer trap-dense authored rooms on Traps floors (no map mutation).
static func _pick_trap_room(rooms: Array, r: RandomNumberGenerator) -> Array:
	if rooms.is_empty(): return []
	var total := 0
	var weights: Array = []
	for rm in rooms:
		var w := 1 + room_trap_count(rm) * 3
		weights.append(w); total += w
	var roll := r.randi_range(1, total)
	var acc := 0
	for i in rooms.size():
		acc += int(weights[i])
		if roll <= acc: return rooms[i]
	return rooms[rooms.size() - 1]

## Fight behind a special-room option: "fight" is "biome" (this floor's encounter pool) or a mob list.
## An optional "room" gives the fight its own map, e.g. the Trapped Vault's trap floor (DECISIONS #151).
static func special_fight_event(run: Dictionary, o: Dictionary) -> Dictionary:
	var r := rng_for(run, 55)
	var mobs: Array = [] if typeof(o.fight) == TYPE_STRING else o.fight
	if not o.has("room"): return combat_event(run, r, mobs)
	if mobs.is_empty():
		var sets: Array = biome(run).encounter_sets.filter(func(s): return int(s.min_floor) <= int(run.floor))
		mobs = sets[r.randi() % sets.size()].mobs
	return {"kind": "combat", "room": o.room, "mobs": fill_mobs(mobs, o.room)}

## Biome gold drip per gold tick (every 8% of a floor; Sewers 1 ... Halls 5).
static func biome_gold_per_tick(biome: String) -> int:
	match biome:
		"prison": return 2
		"caves": return 3
		"city": return 4
		"halls": return 5
		_: return 1

## Gather ticks (4% each) between dew drops. Sewers ~1/floor (~5/delve); denser later.
static func biome_dew_interval(biome: String) -> int:
	match biome:
		"prison": return 16
		"caves": return 12
		"city": return 10
		"halls": return 8
		_: return 25

## Flat `hp` or percent `hp_pct` (floor max(5, pct * HT)). Plan 12 C.
static func event_hp_cost(gs, cost: Dictionary) -> int:
	if cost.has("hp_pct"):
		return maxi(5, int(float(gs.hero_stats(gs.run.hero).ht) * float(cost.hp_pct)))
	return int(cost.get("hp", 0))

static func pay_possible(gs, cost: Dictionary) -> bool:
	var run: Dictionary = gs.run
	for k in cost:
		if k == "hp_pct":
			if int(run.hp) <= event_hp_cost(gs, cost): return false
			continue
		var n := int(cost[k])
		if k == "hp":
			if int(run.hp) <= n: return false
		elif k == "torch_fuel":
			if float(run.torch) < n: return false
		elif k == "satiety":
			if float(run.satiety) < n: return false
		elif int(run.supplies.get(k, 0)) + int(run.pack.get(k, 0)) + (gs.mat(k) if k == "iron_key" else 0) < n:
			return false
	return true

## Pay a cost from run supplies / pack / hp. Returns false (and pays nothing) if unaffordable.
static func pay(gs, cost: Dictionary) -> bool:
	if not pay_possible(gs, cost): return false
	var run: Dictionary = gs.run
	for k in cost:
		if k == "hp_pct":
			run.hp -= event_hp_cost(gs, cost); continue
		var n := int(cost[k])
		if k == "hp": run.hp -= n; continue
		if k == "torch_fuel": run.torch = float(run.torch) - n; continue
		if k == "satiety": run.satiety = float(run.satiety) - n; continue
		var from_sup := mini(n, int(run.supplies.get(k, 0)))
		if from_sup > 0: run.supplies[k] -= from_sup; n -= from_sup
		var from_pack := mini(n, int(run.pack.get(k, 0)))
		if from_pack > 0: run.pack[k] -= from_pack; n -= from_pack
		if n > 0: gs.add_mat(k, -n)
		if k == "gold": gs.add_stat("gold_spent", int(cost[k]))
	return true

## Rewards go into the pack (lost on death). item_unknown spawns an un-ID'd ring/wand; weapon a found weapon.
static func reward(gs, rw: Dictionary) -> String:
	var run: Dictionary = gs.run
	var parts := []
	for k in rw:
		match k:
			"item_unknown":
				if rw[k] in ["potion", "scroll"]:
					var cands: Array = gs.unknown_mats().filter(func(m): return DB.materials[m].kind == rw[k])
					var mid: String = cands[(int(run.seed) + int(run.floor) * 7 + int(gs.next_uid)) % cands.size()]
					gs.pack_add(mid, 1); gs.next_uid += 1
					parts.append(DB.mat_name(mid)); continue
				var pool: Array = ["ring_might", "ring_tenacity", "ring_evasion", "ring_wealth", "ring_energy", "ring_furor", "ring_haste", "ring_sharpshooting", "ring_elements", "ring_force"] if rw[k] == "ring" else ["wand_magic_missile", "wand_firebolt", "wand_lightning", "wand_frost", "wand_corrosion", "wand_blast_wave", "wand_disintegration", "wand_transfusion", "wand_prismatic_light", "wand_regrowth"]
				var id: String = pool[(int(run.seed) + int(run.floor) + run.pack_gear.size()) % pool.size()]
				_stow(gs, _new_gear(gs, id, false))
				parts.append(DB.item(id).unknown_name)
			"heal_pct":   # special rooms (DECISIONS #86)
				var ht := int(gs.hero_stats(run.hero).ht); var before := int(run.hp)
				run.hp = mini(ht, int(run.hp) + int(ceil(ht * float(rw[k]) / 100.0))); parts.append("+%d HP" % (int(run.hp) - before))
			"satiety":
				run.satiety = minf(100.0, float(run.satiety) + float(rw[k])); parts.append("well fed")
			"identify_pack":
				var n := 0
				for g in run.pack_gear:
					if not g.known: g.known = true; gs.discover("item:" + g.id); n += 1
				for m in gs.unknown_mats():
					if int(run.pack.get(m, 0)) > 0 and not gs.is_mat_known(m): gs.identify_mat(m); n += 1
				parts.append("identified %d" % n)
			"artifact":
				var owned: Array = gs.gear.map(func(g): return g.id) + run.pack_gear.map(func(g): return g.id)
				var arts: Array = DB.items.keys().filter(func(x): return DB.items[x].get("type", "") == "artifact" and not (x in owned))
				if arts.is_empty(): gs.pack_add("gold", 40); parts.append("40 Gold")
				else:
					var aid: String = arts[(int(run.seed) + int(run.floor)) % arts.size()]
					_stow(gs, _new_gear(gs, aid, true)); parts.append(DB.item(aid).name)
			"item":
				_stow(gs, _new_gear(gs, rw[k], true))
				parts.append(DB.item(rw[k]).name)
			"weapon":   # a found weapon: SPD's tier odds for this floor, any weapon of that tier, known +0 (DECISIONS #208)
				for i in int(rw[k]):
					var wid := random_weapon(gs)
					_stow(gs, _new_gear(gs, wid, true)); parts.append(DB.item(wid).name)
			_:
				if k in ["torch", "ration"]:
					run.supplies[k] = int(run.supplies.get(k, 0)) + int(rw[k])  # usable right away
				else: gs.pack_add(k, int(rw[k]))
				parts.append("%d %s" % [rw[k], DB.mat_name(k)])
	return ", ".join(parts)

## A snapshot of everything an encounter can give or take, so the result window can list the difference.
static func ledger(gs) -> Dictionary:
	var run: Dictionary = gs.run
	var h: Dictionary = gs.heroes[run.hero]
	var gear: Array = []
	for g in run.pack_gear:
		gear.append({"uid": int(g.uid), "id": String(g.id), "name": gs.gear_name(g), "known": bool(g.known)})
	var over: Array = []
	for g in run.get("overflow", []):
		over.append({"uid": int(g.uid), "id": String(g.id), "name": gs.gear_name(g), "known": bool(g.known), "overflow": true})
	return {"hp": int(run.hp), "torch": int(round(float(run.torch))), "satiety": int(round(float(run.satiety))),
		"pack": run.pack.duplicate(), "supplies": run.supplies.duplicate(), "iron_key": gs.mat("iron_key"),
		"gear": gear, "overflow": over, "xp": int(h.xp), "level": int(h.level),
		"pending_loot": int(run.get("pending_loot", 0))}

## Increases between two ledgers are gained; decreases are lost. Gear is matched by uid.
## `icons` maps a line to the SPD sprite shown next to it on result cards (DECISIONS #217): {id, known, drop}.
## id is an items.png key (gold, a material, a gear id); drop marks a found item (potion, scroll, gear, material) as
## opposed to a counter (gold, HP, XP). Lines with no sprite (HP, Torch, Food, XP, Level) are not in the map.
static func ledger_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var got: PackedStringArray = []
	var lost: PackedStringArray = []
	var icons := {}
	_delta_num(got, lost, int(after.hp) - int(before.hp), "HP")
	_delta_num(got, lost, int(after.torch) - int(before.torch), "Torch")
	_delta_num(got, lost, int(after.satiety) - int(before.satiety), "Food")
	_delta_num(got, lost, int(after.pending_loot) - int(before.pending_loot), "Gold on the next floor", icons, "gold")
	_bag_delta(got, lost, before.pack, after.pack, icons)
	_bag_delta(got, lost, before.supplies, after.supplies, icons)
	_delta_num(got, lost, int(after.iron_key) - int(before.iron_key), DB.display_name("iron_key"), icons, "iron_key", true)
	if int(after.level) > int(before.level): got.append("Level %d" % int(after.level))
	else: _delta_num(got, lost, int(after.xp) - int(before.xp), "XP")
	var bg := _gear_map(before)
	var ag := _gear_map(after)
	for uid in ag:
		if not bg.has(uid):
			var nm: String = ag[uid].name
			if ag[uid].get("overflow", false): nm += " (backpack full)"
			got.append(nm)
			icons[nm] = {"id": String(ag[uid].get("id", "")), "known": bool(ag[uid].known), "drop": true}
		elif not bg[uid].known and ag[uid].known:
			got.append("Identified " + ag[uid].name)
			icons["Identified " + ag[uid].name] = {"id": String(ag[uid].get("id", "")), "known": true, "drop": true}
	for uid in bg:
		if not ag.has(uid):
			lost.append(bg[uid].name)
			icons[bg[uid].name] = {"id": String(bg[uid].get("id", "")), "known": bool(bg[uid].known), "drop": true}
	return {"got": got, "lost": lost, "icons": icons}

static func _gear_map(led: Dictionary) -> Dictionary:
	var m := {}
	for g in led.gear: m[int(g.uid)] = g
	for g in led.overflow: m[int(g.uid)] = g
	return m

static func _bag_delta(got: PackedStringArray, lost: PackedStringArray, before: Dictionary, after: Dictionary, icons := {}) -> void:
	var keys := {}
	for k in before: keys[String(k)] = true
	for k in after: keys[String(k)] = true
	var names: Array = keys.keys()
	names.sort()
	for k in names:
		_delta_num(got, lost, int(after.get(k, 0)) - int(before.get(k, 0)), DB.display_name(k), icons, k, k != "gold")

static func _delta_num(got: PackedStringArray, lost: PackedStringArray, d: int, label: String, icons := {}, icon_id := "", drop := false) -> void:
	var line := ""
	if d > 0: line = "+%d %s" % [d, label]; got.append(line)
	elif d < 0: line = "-%d %s" % [-d, label]; lost.append(line)
	if line != "" and icon_id != "": icons[line] = {"id": icon_id, "known": true, "drop": drop}

## Fight loot versus damage. In-fight healing is netted into one HP line; heals after the fight stay separate.
static func fight_changes(before: Dictionary, after: Dictionary, res: Dictionary) -> Dictionary:
	var shifted: Dictionary = before.duplicate(true)
	shifted.hp = int(res.hp)
	var d := ledger_delta(shifted, after)
	var got: PackedStringArray = []
	var lost: PackedStringArray = []
	var dmg := maxi(0, int(before.hp) - int(res.hp))
	var healed := maxi(0, int(res.hp) - int(before.hp))
	if dmg > 0: lost.append("-%d HP" % dmg)
	if healed > 0: got.append("+%d HP" % healed)
	for line in d.got: got.append(line)
	for line in d.lost: lost.append(line)
	var pots := int(res.get("potions_used", 0))
	if pots > 0:
		var pl := "-%d %s" % [pots, DB.display_name("potion_healing")]
		lost.append(pl); d.icons[pl] = {"id": "potion_healing", "known": true, "drop": true}
	d.got = got
	d.lost = lost
	return d

## What a death takes. Supplies are not listed: they go back to the stash.
static func defeat_changes(gs, before: Dictionary, res: Dictionary) -> Dictionary:
	var lost: PackedStringArray = []
	var dmg := maxi(0, int(before.hp) - int(res.get("hp", before.hp)))
	if dmg > 0: lost.append("-%d HP" % dmg)
	var run: Dictionary = gs.run
	var keys: Array = run.pack.keys()
	keys.sort()
	for k in keys:
		var n := int(run.pack[k])
		if n > 0: lost.append("-%d %s" % [n, DB.display_name(String(k))])
	for g in run.pack_gear:
		if g.get("owned", false):
			if gs._never_cracks(String(g.id)): continue   # starters / heirlooms never crack (DECISIONS #221)
			lost.append("%s cracks" % gs.gear_name(g))
		else: lost.append(gs.gear_name(g))
	var h: Dictionary = gs.heroes[run.hero]
	# Camp armor/weapon never crack; only personal found weapons + rings/artifacts (DECISIONS #234)
	for slot in ["weapon", "ring", "artifact"]:
		var g: Dictionary = gs.gear_by_uid(int(h.get(slot, 0)))
		if g.is_empty() or g.get("camp", false) or gs._never_cracks(String(g.id)): continue
		lost.append("%s cracks" % gs.gear_name(g))
	if int(h.level) > 1: lost.append("Level reset to 1")
	if int(h.str) != 10: lost.append("Strength reset to 10")
	if not h.get("cleared", []).is_empty(): lost.append("Biomes locked")
	var pots := int(res.get("potions_used", 0))
	if pots > 0: lost.append("-%d %s" % [pots, DB.display_name("potion_healing")])
	var note := ""
	for k in run.supplies:
		if int(run.supplies[k]) > 0: note = "Unused supplies return to the stash."; break
	if int(run.pack.get("scroll_upgrade", 0)) > 0:
		note = (note + " " if note != "" else "") + "Scrolls of Upgrade return on the next boss kill."
	return {"got": PackedStringArray(), "lost": lost, "note": note}

## Backpack full (GameState.BACKPACK_SLOTS): the item waits in run.overflow for a drop/leave decision.
## The weapon a chest or statue gives here: seeded by the run, floor and item count, so a reload finds the same one.
static func random_weapon(gs) -> String:
	var r := rng_for(gs.run, 7919 + int(gs.next_uid))
	return Weapons.random_for_floor(int(gs.run.floor), int(r.randi() % 1000000))

static func _stow(gs, g: Dictionary) -> void:
	# Forge weapon/armor outfit the party at Camp (DECISIONS #234) - absorb instead of packing.
	var id := String(g.id)
	if gs.is_forge_weapon(id) or gs.is_forge_armor(id):
		gs._absorb_into_camp(g)
		var uid: int = gs.CAMP_ARMOR_UID if gs.is_forge_armor(id) else gs.CAMP_WEAPON_UID
		gs.say("Camp gear updated: %s." % gs.gear_name(gs.gear_by_uid(uid)))
		gs.touch()
		return
	if DB.item(id).type == "armor":
		return   # no found armor; drop silently
	if gs.backpack_full():
		if not gs.run.has("overflow"): gs.run.overflow = []
		gs.run.overflow.append(g); gs.say("Backpack full! Drop something or leave %s." % gs.gear_name(g))
	else: gs.run.pack_gear.append(g)

static func _new_gear(gs, id: String, known: bool) -> Dictionary:
	gs.add_stat("items_found", 1)
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
	var secret_feel := String(run.get("feeling", "")) == "secret"
	var found: bool = run.hero == "rogue" or secret_feel or rng_for(run, 31).randi_range(1, 100) <= SEARCH_CHANCE
	if not found: return "You search every wall... nothing this time."
	gs.add_stat("hidden_doors", 1)
	var cache: Dictionary = biome(run).secret_cache.duplicate()
	if secret_feel and cache.has("gold"):
		cache.gold = int(ceil(float(cache.gold) * SECRET_CACHE_GOLD_MULT))
	return "A hidden door! Secret cache: " + reward(gs, cache)

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
	plan_biome_feelings(run)   # quota resets per biome (DECISIONS #237); floor still the old boss until descend
	descend(gs)
	gs.say("You enter the %s. Traps lurk on these floors - search before you step." % biome(run).name)

## Spare ration when leaving an XL floor (once).
static func _grant_xl_clear_reward(gs) -> void:
	var run: Dictionary = gs.run
	if String(run.get("feeling", "")) != "xl": return
	if int(run.get("xl_ration_floor", -1)) == int(run.floor): return
	run.xl_ration_floor = int(run.floor)
	run.supplies.ration = int(run.supplies.get("ration", 0)) + 1
	gs.log_line("The sprawling floor yields a spare ration.", "positive")

## Move to the next floor: heal a little, recover chasm loot.
static func descend(gs) -> void:
	var run: Dictionary = gs.run
	_grant_xl_clear_reward(gs)
	run.floor += 1
	gs.note_floor(int(run.floor))
	Telemetry.track("floor_reached", {"class": String(run.hero), "biome": String(run.biome), "floor": int(run.floor), "hp": int(run.hp),
		"torch": int(float(run.torch)), "satiety": int(float(run.satiety)), "gold": int(run.pack.get("gold", 0))})
	var ht: int = gs.hero_stats(run.hero).ht
	gs.log_line("You descend to floor %d." % int(run.floor), "highlight")
	# a guaranteed scrap of iron per floor: repair ore always trickles in, even on Sewers 1-5 (DECISIONS #104)
	gs.pack_add("iron_ore", 1)
	var heal := FLOOR_REST_HEAL
	# the last boss floor (Yog): a quiet antechamber restores more (DECISIONS #92)
	if next_biome(run) == "" and int(run.floor) == int(biome(run).boss_floor): heal = FINAL_REST_HEAL
	run.hp = mini(ht, int(run.hp) + int(ceil(ht * heal)))
	if int(run.pending_loot) > 0:
		gs.pack_add("gold", int(run.pending_loot)); gs.say("Recovered %d gold that fell from above." % run.pending_loot)
		run.pending_loot = 0
	plan_floor(run)
	log_feeling(gs)
	gs.touch()

## Gold escaped thieves carried off (clamped to what the pack actually holds).
static func _apply_gold_debt(gs, res: Dictionary) -> void:
	var debt := int(res.get("gold_debt", 0))
	if debt <= 0: return
	var have := int(gs.run.pack.get("gold", 0))
	var take := mini(debt, have)
	if take <= 0: return
	gs.pack_add("gold", -take)
	gs.log_line("A thief escaped with %d gold." % take, "negative")

## Apply a finished fight to the run (shared by DelveScreen and the full-run simulator).
## Returns false if the hero died (caller should end the run with "death").
static func apply_fight_result(gs, ev: Dictionary, res: Dictionary, reward: Dictionary) -> bool:
	var run: Dictionary = gs.run
	gs.add_stat("kills", int(res.get("kills", 0))); gs.add_stat("traps_found", int(res.get("traps_found", 0)))
	record_fight_stats(gs, ev, res)
	track_fight(gs, ev, res)
	for t in res.get("trap_ids", []): gs.discover("trap:" + t)
	if int(res.get("traps_found", 0)) > 0: gs.log_line("Spotted %d trap%s." % [res.traps_found, "" if int(res.traps_found) == 1 else "s"], "warning")
	var taken := maxi(0, int(run.hp) - int(res.hp))
	if not res.won:
		_apply_gold_debt(gs, res)
		gs.log_line("Defeated by %s." % ", ".join(ev.get("mobs", []).map(func(m): return DB.mobs[m].name)), "negative"); return false
	gs.log_line("Victory: %d kill%s, took %d damage, +%d gold, +%d xp." % [int(res.get("kills", 0)), "" if int(res.get("kills", 0)) == 1 else "s", taken, int(res.loot), int(res.xp)], "positive")
	run.hp = int(res.hp)
	gs.pack_add("gold", int(round(int(res.loot) * float(gs.hero_stats(run.hero).get("gold_mult", 1.0)) * float(gs.hero_stats(run.hero).get("loot_mult", 1.0)))))   # Ring of Wealth
	_apply_gold_debt(gs, res)
	# every 4th won fight drops an unknown potion or scroll (SPD-style consumable loot, DECISIONS #80)
	run.fights_won = int(run.get("fights_won", 0)) + 1
	if gs.cloak_cap(run.hero) > 0:   # Cloak of Shadows: charges persist, a cleared fight gives 1 back (DECISIONS #206)
		var got: int = gs.cloak_after_fight(int(res.get("cloak_charges", gs.cloak_charges(run.hero))))
		if got > 0: gs.log_line("The Cloak of Shadows recharges (%d/%d)." % [int(run.cloak_charges), gs.cloak_cap(run.hero)], "positive")
	if run.fights_won % 4 == 0:
		gs.say("Found: " + reward(gs, {"item_unknown": "potion" if (run.fights_won / 4) % 2 == 1 else "scroll"}))
	run.pending_loot = int(run.pending_loot) + int(res.fallen_loot)
	if gs.grant_xp(run.hero, int(res.xp)):
		gs.say("Level up! %s is now Lv%d." % [DB.heroes[run.hero].name, gs.heroes[run.hero].level])
		run.hp = mini(gs.hero_stats(run.hero).ht, int(run.hp) + int(DB.heroes[run.hero].ht_per_level))
	if not reward.is_empty(): gs.say("Reward: " + reward(gs, reward))
	if res.boss_killed:
		run.boss_dead = true
		gs.add_artifact_use(run.hero, gs.ARTIFACT_BOSS_HOURS)   # every boss kill, including repeats (DECISIONS #223)
		# boss larders: every boss leaves rations on the belt so a healthy hero can press on (DECISIONS #110)
		run.supplies.ration = int(run.supplies.get("ration", 0)) + BOSS_RATIONS
		gs.say("The boss's larder: +%d Rations." % BOSS_RATIONS, "positive")
		# bosses drop an artifact you don't own yet (DECISIONS #80)
		var owned: Array = gs.gear.map(func(g): return g.id) + run.pack_gear.map(func(g): return g.id)
		var arts: Array = DB.items.keys().filter(func(k): return DB.items[k].get("type", "") == "artifact" and not (k in owned))
		if not arts.is_empty(): gs.say("The boss drops: " + reward(gs, {"item": arts[0]}))
		gs.grant_owed_sou()
		# Goo always leaves a Potion of Healing on the belt; unused, it goes back to the stash (DECISIONS #109)
		if ev.mobs[0] == "goo":
			gs.stats.goo_losses = 0
			run.supplies.potion_healing = int(run.supplies.get("potion_healing", 0)) + 1
			gs.say("Goo leaves behind a Potion of Healing.", "positive")
		if gs.record_boss_kill(run.hero, run.biome): gs.say("First %s kill for this class: Scroll of Upgrade!" % DB.mobs[ev.mobs[0]].name)
	gs.touch()
	return true

## Telemetry for one fight (DECISIONS #197): fight_end always, boss_fight for bosses, and the death cause.
static func track_fight(gs, ev: Dictionary, res: Dictionary) -> void:
	var run: Dictionary = gs.run
	if run.is_empty(): return
	var c := String(run.hero)
	var mobs: Array = ev.get("mobs", [])
	var won := bool(res.get("won", false))
	var boss: bool = bool(ev.get("boss", false)) or (not mobs.is_empty() and bool(DB.mobs.get(String(mobs[0]), {}).get("boss", false)))
	var gl: int = gs.patrol_gear_level(c)
	var p := {"class": c, "biome": String(run.biome), "floor": int(run.floor), "enemies": mobs, "result": "win" if won else "loss",
		"turns": int(res.get("turns", 0)), "hp_before": int(run.hp), "hp_after": int(res.get("hp", 0)), "hp_lost": int(res.get("hp_lost", 0)),
		"dmg_in": int(res.get("dmg_in", 0)), "dmg_out": int(res.get("dmg_out", 0)), "auto_battle": bool(res.get("auto_used", false)),
		"surprises": int(res.get("surprises", 0)), "potions": int(res.get("potions_fight", res.get("potions_used", 0))),
		"kills": int(res.get("kills", 0)), "boss": boss, "hero_level": int(gs.heroes[c].level), "gear_level": gl}
	Telemetry.track("fight_end", p)
	if boss and not mobs.is_empty():
		var key := "boss_tries_%s_%s" % [String(mobs[0]), c]
		gs.add_stat(key, 1)
		Telemetry.track("boss_fight", {"class": c, "boss": String(mobs[0]), "biome": String(run.biome), "result": p.result, "gear_level": gl,
			"hero_level": p.hero_level, "attempt": int(gs.stats.get(key, 1)), "turns": p.turns, "hp_lost": p.hp_lost, "auto_battle": p.auto_battle})
	if not won: run.death_cause = ("boss:" if boss else "fight:") + ",".join(mobs.map(func(m): return String(m)))

## Milestone counters from one fight (DECISIONS #195): kills per mob, surprise attacks, potions drunk, and the feats.
## Feats need a won fight: a boss with no HP lost (Barrier soaking a hit is fine), a boss with no Auto Battle,
## a boss with no potion, a win at 10% HP or less, or 6+ kills in one fight.
static func record_fight_stats(gs, ev: Dictionary, res: Dictionary) -> void:
	var ids: Dictionary = res.get("kill_ids", {})
	for mob in ids: gs.add_stat("kill_" + String(mob), int(ids[mob]))
	gs.add_stat("surprises", int(res.get("surprises", 0)))
	# potions_fight comes from the Combat state, so it survives an app kill mid-fight; potions_used is the screen's own count
	var pots := int(res.get("potions_fight", res.get("potions_used", 0)))
	gs.add_stat("potions_drunk", pots)
	if not res.get("won", false): return
	if res.get("boss_killed", false):
		if res.has("hp_lost") and int(res.hp_lost) <= 0: gs.add_stat("feat_flawless_boss", 1)
		if res.has("auto_used") and not res.auto_used: gs.add_stat("feat_manual_boss", 1)
		if pots == 0: gs.add_stat("feat_dry_boss", 1)
	var ht: int = int(gs.hero_stats(gs.run.hero).ht) if not gs.run.is_empty() else 0
	if ht > 0 and int(res.hp) > 0 and float(res.hp) <= ht * CLOSE_CALL_HP: gs.add_stat("feat_close_call", 1)
	if int(res.get("kills", 0)) >= CROWD_KILLS: gs.add_stat("feat_crowd", 1)

## True when the hero's HP in the run is at or below the low-HP danger threshold (30% of max HP).
static func close_to_dying(gs) -> bool:
	if gs.run.is_empty(): return false
	var ht: int = gs.hero_stats(gs.run.hero).ht
	return int(gs.run.hp) <= int(ceil(float(ht) * AUTO_STOP_HP))

## Total Scrolls of Passage carried in supplies or pack.
static func scroll_passage_count(gs) -> int:
	if gs.run.is_empty(): return 0
	return int(gs.run.get("supplies", {}).get("scroll_passage", 0)) + int(gs.run.get("pack", {}).get("scroll_passage", 0))

## Confirm body for reading a Scroll of Passage (DECISIONS #202).
static func passage_text() -> String:
	return "This returns you to Camp and banks everything in your pack."

## Consume a Scroll of Passage and extract to Camp (works from the delve bar, an encounter card, or mid-fight).
static func use_scroll_passage(gs) -> bool:
	if scroll_passage_count(gs) <= 0: return false
	if int(gs.run.get("supplies", {}).get("scroll_passage", 0)) > 0:
		gs.run.supplies.scroll_passage = int(gs.run.supplies.scroll_passage) - 1
		if gs.run.get("free_passage", false):   # DECISIONS #226: spending the Camp's free scroll counts toward the cap
			gs.run.free_passage = false
			gs.note_free_passage_use()
	else:
		gs.run.pack.scroll_passage = int(gs.run.pack.scroll_passage) - 1
	gs.run.erase("active_fight")
	gs.run.erase("pending_card")
	Sfx.play("read")
	gs.end_run("extract")
	return true

