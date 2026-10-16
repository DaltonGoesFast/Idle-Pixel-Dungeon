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
	run.satiety = maxf(0.0, run.satiety - d * SATIETY_DRAIN * _hunger(gs))   # Horn of Plenty slows this
	# auto-use supplies when low (decision: no micromanagement in the delve)
	if run.torch < 20.0 and int(run.supplies.get("torch", 0)) > 0:
		run.supplies.torch -= 1; run.torch = minf(100.0, run.torch + TORCH_RESTORE); gs.say("Lit a fresh torch.")
	if run.satiety < 20.0 and int(run.supplies.get("ration", 0)) > 0:
		run.supplies.ration -= 1; run.satiety = minf(100.0, run.satiety + RATION_RESTORE); gs.say("Ate a ration.")
	# passive gathering: +1 gold every 4%, +1 dew every 12%
	# counted on the pinned haul line; individual drips are not logged
	var step := int(run.progress / 4.0)
	while run.gather < step:
		run.gather += 1
		gs.pack_add("gold", 1)
		if run.gather % 3 == 0: gs.pack_add("dew", 1)
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
			var ss := _for_biome(DB.specials, run)
			return {"kind": "special", "special": ss[r.randi() % ss.size()]}
	return combat_event(run, r)

static func _for_biome(list: Array, run: Dictionary) -> Array:
	return list.filter(func(x): return run.biome in x.get("biomes", [run.biome]))

## Rooms used for ordinary fights. Sewers/Prison keep shared 8x8s; later biomes use larger maps only.
static func room_pool(run: Dictionary) -> Array:
	var biome_id := String(run.biome)
	var own: Array = DB.biome_rooms.get(biome_id, [])
	match biome_id:
		"sewers":
			return DB.rooms + own
		"prison":
			return DB.rooms + own + own   # 10x10s listed twice so they show up often
		"caves", "city", "halls":
			return own if not own.is_empty() else DB.rooms
		_:
			return DB.rooms + own

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
	run.fighting_goo = "goo" in ev.mobs
	if run.fighting_goo: _weaken_goo(gs, c)
	if int(run.get("shield_next", 0)) > 0:   # Potion of Shielding (SPD-like cap: Barrier <= max HP)
		c.hero.barrier = mini(int(c.hero.ht), int(c.hero.barrier) + int(run.shield_next)); run.shield_next = 0
		c._log("Your shield shimmers: +Barrier.")
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
		# prefer encounters introduced recently so floors feel different
		var pick: Dictionary = sets[r.randi() % sets.size()]
		mobs = pick.mobs
	var rooms := room_pool(run)
	if "snake" in mobs:
		var with_door: Array = rooms.filter(func(rm): return room_has_door(rm))
		if not with_door.is_empty(): rooms = with_door
	var room: Array = rooms[r.randi() % rooms.size()]
	return {"kind": "combat", "room": room, "mobs": fill_mobs(mobs, room)}

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

static func pay_possible(gs, cost: Dictionary) -> bool:
	var run: Dictionary = gs.run
	for k in cost:
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
		var n := int(cost[k])
		if k == "hp": run.hp -= n; continue
		if k == "torch_fuel": run.torch = float(run.torch) - n; continue
		if k == "satiety": run.satiety = float(run.satiety) - n; continue
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
				if rw[k] in ["potion", "scroll"]:
					var cands: Array = gs.unknown_mats().filter(func(m): return DB.materials[m].kind == rw[k])
					var mid: String = cands[(int(run.seed) + int(run.floor) * 7 + int(gs.next_uid)) % cands.size()]
					gs.pack_add(mid, 1); gs.next_uid += 1
					parts.append(DB.mat_name(mid)); continue
				var pool: Array = ["ring_might", "ring_tenacity", "ring_evasion", "ring_wealth", "ring_energy"] if rw[k] == "ring" else ["wand_magic_missile", "wand_firebolt", "wand_lightning"]
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
		gear.append({"uid": int(g.uid), "name": gs.gear_name(g), "known": bool(g.known)})
	var over: Array = []
	for g in run.get("overflow", []):
		over.append({"uid": int(g.uid), "name": gs.gear_name(g), "known": bool(g.known), "overflow": true})
	return {"hp": int(run.hp), "torch": int(round(float(run.torch))), "satiety": int(round(float(run.satiety))),
		"pack": run.pack.duplicate(), "supplies": run.supplies.duplicate(), "iron_key": gs.mat("iron_key"),
		"gear": gear, "overflow": over, "xp": int(h.xp), "level": int(h.level),
		"pending_loot": int(run.get("pending_loot", 0))}

## Increases between two ledgers are gained; decreases are lost. Gear is matched by uid.
static func ledger_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var got: PackedStringArray = []
	var lost: PackedStringArray = []
	_delta_num(got, lost, int(after.hp) - int(before.hp), "HP")
	_delta_num(got, lost, int(after.torch) - int(before.torch), "Torch")
	_delta_num(got, lost, int(after.satiety) - int(before.satiety), "Food")
	_delta_num(got, lost, int(after.pending_loot) - int(before.pending_loot), "Gold on the next floor")
	_bag_delta(got, lost, before.pack, after.pack)
	_bag_delta(got, lost, before.supplies, after.supplies)
	_delta_num(got, lost, int(after.iron_key) - int(before.iron_key), DB.display_name("iron_key"))
	if int(after.level) > int(before.level): got.append("Level %d" % int(after.level))
	else: _delta_num(got, lost, int(after.xp) - int(before.xp), "XP")
	var bg := _gear_map(before)
	var ag := _gear_map(after)
	for uid in ag:
		if not bg.has(uid):
			var nm: String = ag[uid].name
			if ag[uid].get("overflow", false): nm += " (backpack full)"
			got.append(nm)
		elif not bg[uid].known and ag[uid].known:
			got.append("Identified " + ag[uid].name)
	for uid in bg:
		if not ag.has(uid): lost.append(bg[uid].name)
	return {"got": got, "lost": lost}

static func _gear_map(led: Dictionary) -> Dictionary:
	var m := {}
	for g in led.gear: m[int(g.uid)] = g
	for g in led.overflow: m[int(g.uid)] = g
	return m

static func _bag_delta(got: PackedStringArray, lost: PackedStringArray, before: Dictionary, after: Dictionary) -> void:
	var keys := {}
	for k in before: keys[String(k)] = true
	for k in after: keys[String(k)] = true
	var names: Array = keys.keys()
	names.sort()
	for k in names:
		_delta_num(got, lost, int(after.get(k, 0)) - int(before.get(k, 0)), DB.display_name(k))

static func _delta_num(got: PackedStringArray, lost: PackedStringArray, d: int, label: String) -> void:
	if d > 0: got.append("+%d %s" % [d, label])
	elif d < 0: lost.append("-%d %s" % [-d, label])

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
	if pots > 0: lost.append("-%d %s" % [pots, DB.display_name("potion_healing")])
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
		if g.get("owned", false): lost.append("%s cracks" % gs.gear_name(g))
		else: lost.append(gs.gear_name(g))
	var h: Dictionary = gs.heroes[run.hero]
	for slot in ["weapon", "armor", "ring", "artifact"]:
		var g: Dictionary = gs.gear_by_uid(int(h.get(slot, 0)))
		if g.is_empty() or DB.item(g.id).get("heirloom", false): continue
		lost.append("%s cracks" % gs.gear_name(g))
	if int(h.level) > 1: lost.append("Level reset to 1")
	if int(h.str) != 10: lost.append("Strength reset to 10")
	var pots := int(res.get("potions_used", 0))
	if pots > 0: lost.append("-%d %s" % [pots, DB.display_name("potion_healing")])
	var note := ""
	for k in run.supplies:
		if int(run.supplies[k]) > 0: note = "Unused supplies return to the stash."; break
	if int(run.pack.get("scroll_upgrade", 0)) > 0:
		note = (note + " " if note != "" else "") + "Scrolls of Upgrade return on the next boss kill."
	return {"got": PackedStringArray(), "lost": lost, "note": note}

## Backpack full (GameState.BACKPACK_SLOTS): the item waits in run.overflow for a drop/leave decision.
static func _stow(gs, g: Dictionary) -> void:
	if gs.backpack_full():
		if not gs.run.has("overflow"): gs.run.overflow = []
		gs.run.overflow.append(g); gs.say("Backpack full! Drop something or leave %s." % gs.gear_name(g))
	else: gs.run.pack_gear.append(g)

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
	gs.touch()

## Apply a finished fight to the run (shared by DelveScreen and the full-run simulator).
## Returns false if the hero died (caller should end the run with "death").
static func apply_fight_result(gs, ev: Dictionary, res: Dictionary, reward: Dictionary) -> bool:
	var run: Dictionary = gs.run
	gs.add_stat("kills", int(res.get("kills", 0))); gs.add_stat("traps_found", int(res.get("traps_found", 0)))
	for t in res.get("trap_ids", []): gs.discover("trap:" + t)
	if int(res.get("traps_found", 0)) > 0: gs.log_line("Spotted %d trap%s." % [res.traps_found, "" if int(res.traps_found) == 1 else "s"], "warning")
	var taken := maxi(0, int(run.hp) - int(res.hp))
	if not res.won:
		gs.log_line("Defeated by %s." % ", ".join(ev.get("mobs", []).map(func(m): return DB.mobs[m].name)), "negative"); return false
	gs.log_line("Victory: %d kill%s, took %d damage, +%d gold, +%d xp." % [int(res.get("kills", 0)), "" if int(res.get("kills", 0)) == 1 else "s", taken, int(res.loot), int(res.xp)], "positive")
	run.hp = int(res.hp)
	gs.pack_add("gold", int(round(int(res.loot) * float(gs.hero_stats(run.hero).get("gold_mult", 1.0)))))   # Ring of Wealth
	# every 4th won fight drops an unknown potion or scroll (SPD-style consumable loot, DECISIONS #80)
	run.fights_won = int(run.get("fights_won", 0)) + 1
	if run.fights_won % 4 == 0:
		gs.say("Found: " + reward(gs, {"item_unknown": "potion" if (run.fights_won / 4) % 2 == 1 else "scroll"}))
	run.pending_loot = int(run.pending_loot) + int(res.fallen_loot)
	if gs.grant_xp(run.hero, int(res.xp)):
		gs.say("Level up! %s is now Lv%d." % [DB.heroes[run.hero].name, gs.heroes[run.hero].level])
		run.hp = mini(gs.hero_stats(run.hero).ht, int(run.hp) + int(DB.heroes[run.hero].ht_per_level))
	if not reward.is_empty(): gs.say("Reward: " + reward(gs, reward))
	if res.boss_killed:
		run.boss_dead = true
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

## True when the hero's HP in the run is at or below the low-HP danger threshold (30% of max HP).
static func close_to_dying(gs) -> bool:
	if gs.run.is_empty(): return false
	var ht: int = gs.hero_stats(gs.run.hero).ht
	return int(gs.run.hp) <= int(ceil(float(ht) * AUTO_STOP_HP))

## Total Scrolls of Passage carried in supplies or pack.
static func scroll_passage_count(gs) -> int:
	if gs.run.is_empty(): return 0
	return int(gs.run.get("supplies", {}).get("scroll_passage", 0)) + int(gs.run.get("pack", {}).get("scroll_passage", 0))

## Consume a Scroll of Passage and extract to Camp (works from the delve bar, an encounter card, or mid-fight).
static func use_scroll_passage(gs) -> bool:
	if scroll_passage_count(gs) <= 0: return false
	if int(gs.run.get("supplies", {}).get("scroll_passage", 0)) > 0:
		gs.run.supplies.scroll_passage = int(gs.run.supplies.scroll_passage) - 1
	else:
		gs.run.pack.scroll_passage = int(gs.run.pack.scroll_passage) - 1
	gs.run.erase("active_fight")
	gs.run.erase("pending_card")
	Sfx.play("read")
	gs.end_run("extract")
	return true

