## Combat: deterministic tactical combat model (no RNG, no nodes) so it can be simulated headless.
##
## Rules (see docs/BALANCE.md):
##  - SPD turn clock: each actor has `next` (time of next action). Hero acts on ties.
##    Moving/attacking costs the actor's delay (1.0 normal, 0.5 fast, 1.5 heavy weapons).
##  - Every attack hits for fixed damage. Physical damage - flat DR. Barrier absorbs before HP.
##    Chip rule: a hit fully blocked by DR still removes 1 Barrier.
##  - Surprise: attacking from a door or tall-grass tile = x surprise_mult (1.5, dagger 2.0), ignores DR, knockback.
##  - Telegraphs: red danger tiles resolve at a known time; step off them.
##  - Knockback into a chasm kills instantly (loot halved, recovered next floor).
##  - Traps (data/traps.json): '^' visible, '?' hidden until searched. Anyone stepping on one triggers it
##    (one-shot). Mobs know trap locations and path around them, but knockback can push them in.
class_name Combat
extends RefCounted

enum T { FLOOR, WALL, GRASS, DOOR, CHASM, WATER }
const SIZE := 8
const DIRS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
const BOLT_RANGE := 6

var terrain: Array = []
var units: Array = []
var hero: Dictionary
var time := 0.0
var log_lines: PackedStringArray = []
var events: Array = []          # visual/audio events since last drain_events()
var danger: Array = []          # [{pos, dmg, at, src, uid}]
var loot := 0
var fallen_loot := 0            # loot halved by chasm kills (recovered next floor)
var xp := 0
var over := false
var won := false
var boss_killed := false
var _uid := 0
var traps := {}                 # Vector2i -> {"id": String, "hidden": bool}
var trap_pool: Array = ["worn_dart", "gripping", "teleport"]
var kills := 0                  # meta stats reported in the fight result
var traps_found := 0
var trap_ids_seen: Array = []   # codex: trap types revealed or triggered

## room_rows: Array[String] 8x8; hs: GameState.hero_stats(); mob_ids fill spawn slots 1..4 in order (B = boss).
func setup(room_rows: Array, hs: Dictionary, hp: int, mob_ids: Array, darkness := false, pool := []) -> void:
	terrain.clear(); units.clear(); danger.clear(); log_lines.clear(); events.clear(); traps.clear()
	kills = 0; traps_found = 0; trap_ids_seen = []
	if not pool.is_empty(): trap_pool = pool
	time = 0.0; loot = 0; fallen_loot = 0; xp = 0; over = false; won = false; boss_killed = false; _uid = 0
	hero = {"uid": _next_uid(), "id": "hero", "name": hs.name, "hp": hp, "ht": hs.ht, "dmg": hs.dmg, "dr": hs.dr,
		"barrier": 0 if darkness else hs.barrier_max, "barrier_max": hs.barrier_max, "delay": hs.delay, "next": 0.0,
		"pos": Vector2i.ZERO, "sprite": hs.sprite, "fw": hs.fw, "fh": hs.fh, "surprise_mult": hs.get("surprise_mult", 1.5),
		"abilities": hs.get("abilities", []), "bolt": hs.get("bolt", {}), "charges": 0, "recharge_t": 0.0, "hero": true,
		"cloak": hs.get("cloak", {}), "cloak_charges": int(hs.get("cloak", {}).get("charges", 0)), "hidden_until": -1.0,
		"slams": 1 if "slam" in hs.get("abilities", []) else 0, "search_radius": int(hs.get("search_radius", 1)),
		"poison": 0, "keen_eyes": hs.get("keen_eyes", false), "perk": hs.get("perk", ""), "combo": 0}
	if not hero.bolt.is_empty(): hero.charges = hero.bolt.charges
	units.append(hero)
	var slots := {}
	for y in SIZE:
		var row := []
		for x in SIZE:
			var ch: String = room_rows[y][x]
			var t := T.FLOOR
			match ch:
				"#": t = T.WALL
				"\"": t = T.GRASS
				"+": t = T.DOOR
				"_": t = T.CHASM
				"~": t = T.WATER
				"H": hero.pos = Vector2i(x, y)
				"1","2","3","4": slots[int(ch) - 1] = Vector2i(x, y)
				"B": slots[0] = Vector2i(x, y)
				"^", "?":
					# trap type: deterministic from position so the same room always has the same traps
					traps[Vector2i(x, y)] = {"id": trap_pool[(x * 7 + y * 3) % trap_pool.size()], "hidden": ch == "?"}
					if ch == "^" and not (traps[Vector2i(x, y)].id in trap_ids_seen): trap_ids_seen.append(traps[Vector2i(x, y)].id)
			row.append(t)
		terrain.append(row)
	for i in mob_ids.size():
		var p: Vector2i = slots.get(i, _free_tile_near(Vector2i(SIZE - 2, SIZE - 2)))
		spawn(mob_ids[i], p)
	_log("A fight! Barrier %d, HP %d/%d%s." % [hero.barrier, hero.hp, hero.ht, " (darkness: no Barrier)" if darkness else ""])

# ------------------------------------------------------------------ persistence
## Serialise to JSON-safe data (Vector2i -> [x, y]) so a fight survives the app being killed.
func to_dict() -> Dictionary:
	var us := []
	for u in units:
		var d: Dictionary = u.duplicate(true); d.pos = [u.pos.x, u.pos.y]; us.append(d)
	var dz := []
	for d in danger:
		var e: Dictionary = d.duplicate(); e.pos = [d.pos.x, d.pos.y]; dz.append(e)
	var tr := []
	for k in traps: tr.append({"pos": [k.x, k.y], "id": traps[k].id, "hidden": traps[k].hidden})
	return {"terrain": terrain, "units": us, "danger": dz, "traps": tr, "trap_pool": trap_pool, "kills": kills, "traps_found": traps_found, "trap_ids_seen": trap_ids_seen, "time": time, "log": Array(log_lines), "loot": loot,
		"fallen_loot": fallen_loot, "xp": xp, "over": over, "won": won, "boss_killed": boss_killed, "uid": _uid}

func from_dict(d: Dictionary) -> void:
	terrain = []
	for row in d.terrain: terrain.append(row.map(func(t): return int(t)))
	units = []
	for u in d.units:
		var x: Dictionary = u.duplicate(true)
		x.pos = Vector2i(int(u.pos[0]), int(u.pos[1]))
		for k in ["uid", "hp", "ht", "dmg", "dr", "barrier", "barrier_max", "charges", "cloak_charges", "cooldown", "acts", "exp", "loot", "pump_count", "poison", "search_radius", "stolen", "slams", "bombs", "blinks", "steal_gold", "abil", "abil_n", "combo"]:
			if x.has(k): x[k] = int(x[k])
		units.append(x)
		if x.has("hero"): hero = x
	danger = []
	for e in d.danger:
		var y: Dictionary = e.duplicate(); y.pos = Vector2i(int(e.pos[0]), int(e.pos[1])); y.dmg = int(e.dmg); y.uid = int(e.uid); danger.append(y)
	traps = {}
	for t in d.get("traps", []): traps[Vector2i(int(t.pos[0]), int(t.pos[1]))] = {"id": t.id, "hidden": t.hidden}
	trap_pool = Array(d.get("trap_pool", trap_pool))
	kills = int(d.get("kills", 0)); traps_found = int(d.get("traps_found", 0)); trap_ids_seen = Array(d.get("trap_ids_seen", []))
	time = float(d.time); log_lines = PackedStringArray(d.log); loot = int(d.loot); fallen_loot = int(d.fallen_loot)
	xp = int(d.xp); over = d.over; won = d.won; boss_killed = d.boss_killed; _uid = int(d.uid); events = []

func _next_uid() -> int:
	_uid += 1
	return _uid

func spawn(id: String, p: Vector2i) -> Dictionary:
	var m: Dictionary = DB.mobs[id].duplicate(true)
	m.id = id; m.uid = _next_uid(); m.hp = int(m.ht); m.pos = p; m.next = float(m.delay); m.cooldown = 0; m.acts = 0
	m.charging = false; m.poison = 0
	units.append(m)
	return m

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 80: log_lines.remove_at(0)

func _ev(e: Dictionary) -> void:
	events.append(e)

func drain_events() -> Array:
	var e := events
	events = []
	return e

# ------------------------------------------------------------------ queries
func tile(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= SIZE or p.y >= SIZE: return T.WALL
	return terrain[p.y][p.x]

func unit_at(p: Vector2i):
	for u in units:
		if u.hp > 0 and u.pos == p: return u
	return null

func enemies() -> Array:
	return units.filter(func(u): return not u.has("hero") and u.hp > 0)

func passable(p: Vector2i) -> bool:
	var t := tile(p)
	return t != T.WALL and t != T.CHASM

func visible_trap(p: Vector2i) -> bool:
	return traps.has(p) and not traps[p].hidden

func is_danger(p: Vector2i) -> bool:
	for d in danger:
		if d.pos == p: return true
	return false

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Clear straight-ish line (Bresenham) with no walls/units between a and b.
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var pts := _line(a, b)
	for i in range(1, pts.size() - 1):
		var p: Vector2i = pts[i]
		if tile(p) == T.WALL or unit_at(p) != null: return false
	return true

static func _line(a: Vector2i, b: Vector2i) -> Array:
	var pts := []
	var dx := absi(b.x - a.x); var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1; var sy := 1 if a.y < b.y else -1
	var err := dx + dy; var p := a
	while true:
		pts.append(p)
		if p == b: break
		var e2 := 2 * err
		if e2 >= dy: err += dy; p.x += sx
		if e2 <= dx: err += dx; p.y += sy
	return pts

func has_ranged() -> bool:
	return not hero.bolt.is_empty() and (hero.bolt.get("infinite", false) or hero.charges > 0)

func hidden() -> bool:
	return float(hero.hidden_until) > time

func can_bolt(target: Vector2i) -> bool:
	if not has_ranged(): return false
	var u = unit_at(target)
	return u != null and u != hero and cheb(hero.pos, target) <= BOLT_RANGE and line_clear(hero.pos, target)

func surprise_ready() -> bool:
	var t := tile(hero.pos)
	return t == T.DOOR or t == T.GRASS or hidden()

# ------------------------------------------------------------------ damage
## Damage to the hero: flat DR -> Barrier -> HP. Chip rule on fully blocked hits.
func hit_hero(raw: int, src: String, pierce := false) -> void:
	var dmg := raw if pierce else maxi(0, raw - int(hero.dr))
	if dmg == 0:
		if hero.barrier > 0:
			hero.barrier -= 1
			_log("%s's hit is blocked (chip: -1 Barrier)." % src)
			_ev({"t": "hit", "uid": hero.uid, "amount": 1, "kind": "chip", "pos": hero.pos})
		else:
			_log("%s's hit is fully blocked." % src)
			_ev({"t": "hit", "uid": hero.uid, "amount": 0, "kind": "block", "pos": hero.pos})
		return
	var absorbed := mini(dmg, int(hero.barrier))
	hero.barrier -= absorbed
	hero.hp -= dmg - absorbed
	_log("%s hits for %d (%d Barrier, %d HP)." % [src, dmg, absorbed, dmg - absorbed])
	_ev({"t": "hit", "uid": hero.uid, "amount": dmg, "kind": "hp" if dmg > absorbed else "barrier", "pos": hero.pos})
	if hero.hp <= 0:
		hero.hp = 0; over = true; won = false
		_log("%s falls..." % hero.name)
		_ev({"t": "die", "uid": hero.uid, "pos": hero.pos})

func hit_mob(m: Dictionary, raw: int, surprise := false, magic := false) -> void:
	var dmg: int
	if surprise: dmg = int(raw * float(hero.surprise_mult))
	elif magic: dmg = raw
	else: dmg = maxi(0, raw - int(m.dr))
	# King of Dwarves lifelink (SPD): while his risen dwarves live, he takes 2/3 damage (DECISIONS #79)
	if m.get("ability", "") == "dking" and dmg > 0 and _king_linked():
		dmg = int(ceil(dmg * 2.0 / 3.0))
		_log("The lifelink absorbs a third of the blow!")
	m.hp -= dmg
	_log("%s%s takes %d." % ["SURPRISE! " if surprise else "", m.name, dmg])
	_ev({"t": "hit", "uid": m.uid, "amount": dmg, "kind": "surprise" if surprise else ("magic" if magic else "hp"), "pos": m.pos})
	if m.hp <= 0:
		_kill(m, false)
	elif surprise and not m.get("boss", false):
		knockback(m, m.pos - hero.pos)
	elif m.get("ability", "") == "tengu":
		_tengu_hurt(m)

func knockback(m: Dictionary, dir: Vector2i) -> void:
	dir = Vector2i(signi(dir.x), signi(dir.y))
	var dest: Vector2i = m.pos + dir
	var t := tile(dest)
	if m.get("boss", false):
		_log("%s is too heavy to move." % m.name); return
	if t == T.CHASM:
		var from: Vector2i = m.pos
		m.pos = dest
		_ev({"t": "move", "uid": m.uid, "from": from, "to": dest})
		_ev({"t": "sfx", "name": "falling"})
		_log("%s is knocked into the chasm!" % m.name)
		_kill(m, true)
	elif t == T.WALL or unit_at(dest) != null:
		m.hp -= 1
		_log("%s slams into an obstacle (1)." % m.name)
		_ev({"t": "hit", "uid": m.uid, "amount": 1, "kind": "hp", "pos": m.pos})
		if m.hp <= 0: _kill(m, false)
	else:
		_place(m, dest)

## Move a unit (hero or mob) and fire any trap on the destination tile.
func _place(u: Dictionary, dest: Vector2i) -> void:
	_ev({"t": "move", "uid": u.uid, "from": u.pos, "to": dest})
	u.pos = dest
	if u == hero and hero.get("keen_eyes", false): _reveal(dest, 1, false)
	if traps.has(dest): _trigger(dest, u)

func _trigger(p: Vector2i, u: Dictionary) -> void:
	var tr: Dictionary = DB.traps[traps[p].id]
	if not (traps[p].id in trap_ids_seen): trap_ids_seen.append(traps[p].id)
	traps.erase(p)
	_log("%s triggers a %s!" % [u.name, tr.name])
	_ev({"t": "trap", "pos": p}); _ev({"t": "sfx", "name": "trap"})
	var is_hero := u == hero
	if tr.has("dmg"):
		if is_hero: hit_hero(int(tr.dmg), tr.name)
		else: _trap_hit(u, int(tr.dmg))
	if u.hp <= 0: return
	if tr.has("root"):
		u.next = float(u.next) + float(tr.root); _log("%s is held fast." % u.name)
	if tr.has("poison"):
		u.poison = int(u.get("poison", 0)) + int(tr.poison); _ev({"t": "sfx", "name": "debuff"})
	if tr.get("teleport", false):
		var far := _farthest_free(hero.pos if not is_hero else _nearest_enemy_pos())
		_ev({"t": "sfx", "name": "teleport"})
		_ev({"t": "move", "uid": u.uid, "from": u.pos, "to": far, "blink": true})
		u.pos = far

func _trap_hit(m: Dictionary, dmg: int) -> void:
	var d := maxi(0, dmg - int(m.dr))
	m.hp -= d
	_ev({"t": "hit", "uid": m.uid, "amount": d, "kind": "hp", "pos": m.pos})
	_log("%s takes %d." % [m.name, d])
	if m.hp <= 0: _kill(m, false)

## Poison ticks once per action of its victim: 1 damage, ignores DR and Barrier.
func _tick_poison(u: Dictionary) -> void:
	if int(u.get("poison", 0)) <= 0: return
	u.poison -= 1
	if u == hero:
		hero.hp -= 1
		_ev({"t": "hit", "uid": hero.uid, "amount": 1, "kind": "poison", "pos": hero.pos})
		if hero.hp <= 0:
			hero.hp = 0; over = true; won = false; _log("%s succumbs to poison..." % hero.name)
			_ev({"t": "die", "uid": hero.uid, "pos": hero.pos})
	else:
		u.hp -= 1
		_ev({"t": "hit", "uid": u.uid, "amount": 1, "kind": "poison", "pos": u.pos})
		if u.hp <= 0: _kill(u, false)

## Reveal hidden traps within radius. Returns how many were found.
func _reveal(center: Vector2i, radius: int, loud := true) -> int:
	var n := 0
	for k in traps:
		if traps[k].hidden and cheb(k, center) <= radius:
			traps[k].hidden = false; n += 1; traps_found += 1
			if not (traps[k].id in trap_ids_seen): trap_ids_seen.append(traps[k].id)
			_ev({"t": "reveal", "pos": k})
	if n > 0:
		_log("Found %d hidden trap%s!" % [n, "" if n == 1 else "s"]); _ev({"t": "sfx", "name": "secret"})
	elif loud: _log("You search but find nothing.")
	return n

func _nearest_enemy_pos() -> Vector2i:
	var best := hero.pos as Vector2i; var bd := 999
	for e in enemies():
		if cheb(e.pos, hero.pos) < bd: bd = cheb(e.pos, hero.pos); best = e.pos
	return best

## Free, trap-free tile farthest from `from` (ties: lowest y, then x) - deterministic.
func _farthest_free(from: Vector2i) -> Vector2i:
	var best := from; var bd := -1
	for y in SIZE:
		for x in SIZE:
			var c := Vector2i(x, y)
			if not passable(c) or unit_at(c) != null or traps.has(c) or is_danger(c): continue
			if cheb(c, from) > bd: bd = cheb(c, from); best = c
	return best

func _kill(m: Dictionary, chasm: bool) -> void:
	m.hp = 0
	kills += 1
	var l := int(m.loot) + int(m.get("stolen", 0))
	xp += int(m.exp)
	if chasm:
		fallen_loot += int(l / 2.0)
		_log("%s falls. Its loot (%d) drops to the next floor." % [m.name, int(l / 2.0)])
		_ev({"t": "fall", "uid": m.uid, "pos": m.pos})
	else:
		loot += l
		_log("%s dies. +%d gold" % [m.name, l])
		_ev({"t": "die", "uid": m.uid, "pos": m.pos})
	danger = danger.filter(func(d): return d.uid != m.uid)
	if m.get("boss", false):
		boss_killed = true
		# the King's risen dwarves crumble with him
		for e in enemies():
			if e.get("summoned", false):
				e.hp = 0; _log("%s crumbles to dust." % e.name); _ev({"t": "die", "uid": e.uid, "pos": e.pos})
	# Dwarven Ghoul: rises again (once) 2 ticks later unless it was the last enemy standing (SPD rule)
	if m.get("revive", false) and not m.get("revived", false) and not chasm and not enemies().is_empty():
		danger.append({"pos": m.pos, "dmg": 3, "at": time + 2.0, "src": "Rising ghoul", "uid": -m.uid, "spawn": m.id, "spawn_hp": 0.5})
		_log("%s twitches... it will rise again in 2 ticks! (red tile)" % m.name); _ev({"t": "telegraph", "uid": m.uid})
	if hero.get("perk", "") == "soul_heal" and hero.hp > 0:
		var hl := mini(int(hero.ht) - int(hero.hp), maxi(2, int(int(m.ht) * 0.2)))
		if hl > 0:
			hero.hp += hl; _log("Soul siphon: +%d HP." % hl)
			_ev({"t": "heal", "uid": hero.uid, "amount": hl, "pos": hero.pos})
	# Skeleton: bones burst a moment after death (telegraphed 3x3)
	if m.get("ability", "") == "bone_burst" and not chasm:
		for d in [Vector2i.ZERO] + DIRS:
			if tile(m.pos + d) != T.WALL:
				danger.append({"pos": m.pos + d, "dmg": int(m.burst_dmg), "at": time + float(m.burst_delay), "src": "Bone shards", "uid": -m.uid})
		_log("%s's bones start to rattle! (red tiles)" % m.name); _ev({"t": "telegraph", "uid": m.uid})
	if enemies().is_empty():
		over = true; won = true
		danger.clear()
		_log("Room cleared!")

## Lightning conducts through connected shallow water: everyone standing in it (hero included!) takes damage.
func _shock(p: Vector2i, dmg: int) -> void:
	var q := [p]; var seen := {p: true}
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		_ev({"t": "shock", "pos": c})
		var u = unit_at(c)
		if c != p and u != null:
			if u == hero: hit_hero(dmg / 2, "Your own lightning", true)
			else: hit_mob(u, dmg, false, true)
		for d in DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and tile(n) == T.WATER:
				seen[n] = true; q.append(n)
	_ev({"t": "sfx", "name": "lightning"})

func _burn(p: Vector2i) -> void:
	# fire spreads across connected tall grass
	var q := [p]; var seen := {p: true}
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if tile(c) != T.GRASS and c != p: continue
		if tile(c) == T.GRASS: terrain[c.y][c.x] = T.FLOOR
		_ev({"t": "burn", "pos": c})
		var u = unit_at(c)
		if u != null and u != hero: hit_mob(u, 3, false, true)
		elif u == hero: hit_hero(3, "Fire", true)
		for d in DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and tile(n) == T.GRASS:
				seen[n] = true; q.append(n)

# ------------------------------------------------------------------ hero actions
## Tap a tile: adjacent enemy = attack (or shove), adjacent free tile = move, distant enemy = bolt (if able).
## Returns true if time passed.
func hero_tap(p: Vector2i, mode := "") -> bool:
	if over: return false
	var u = unit_at(p)
	if mode == "bolt" or (cheb(p, hero.pos) > 1 and u != null and u != hero):
		return hero_bolt(p)
	if cheb(p, hero.pos) != 1: return false
	if u != null and u != hero:
		if mode == "shove":
			_log("%s shoves %s." % [hero.name, u.name])
			_ev({"t": "sfx", "name": "hit_crush"})
			knockback(u, p - hero.pos)
			_end_hero_turn(1.0)
			return true
		_ev({"t": "attack", "uid": hero.uid, "to": p})
		var sur := surprise_ready()
		_break_cloak()
		hit_mob(u, _melee_dmg(), sur)
		_melee_perks()
		_end_hero_turn(float(hero.delay))
		return true
	if passable(p) and u == null:
		_place(hero, p)
		_end_hero_turn(1.0)
		return true
	return false

## Subclass perks (DECISIONS #61)
func _melee_dmg() -> int:
	var d := int(hero.dmg)
	match hero.get("perk", ""):
		"rage":
			if int(hero.hp) * 2 < int(hero.ht): d = int(d * 1.2)
		"combo": d += mini(int(hero.combo), 3)
	return d

func _melee_perks() -> void:
	match hero.get("perk", ""):
		"combo": hero.combo = int(hero.combo) + 1
		"battle_recharge":
			hero.combo = int(hero.combo) + 1
			if hero.combo % 5 == 0 and not hero.bolt.is_empty() and int(hero.charges) < int(hero.bolt.charges):
				hero.charges += 1; _log("The staff hums: +1 charge.")

func hero_bolt(p: Vector2i) -> bool:
	if not can_bolt(p): return false
	var u = unit_at(p)
	var magic: bool = hero.bolt.get("magic", true)
	if not hero.bolt.get("infinite", false): hero.charges -= 1
	_log("%s fires %s." % [hero.name, hero.bolt.name])
	_ev({"t": "bolt", "from": hero.pos, "to": p, "magic": magic})
	var sur := surprise_ready() and not magic
	_break_cloak()
	var hp_before := int(u.hp)
	hit_mob(u, int(hero.bolt.dmg), sur, magic or hero.bolt.get("pierce", false))
	if hero.get("perk", "") == "soul_heal" and magic and hero.hp > 0 and hero.hp < hero.ht:
		var sh := mini(int(hero.ht) - int(hero.hp), maxi(1, (hp_before - maxi(0, int(u.hp))) / 3))
		hero.hp += sh; _log("Soul siphon: +%d HP." % sh)
	if hero.bolt.get("chains_water", false) and tile(p) == T.WATER:
		_shock(p, int(hero.bolt.dmg))
	if hero.bolt.get("burns_grass", false):
		for d in [Vector2i.ZERO] + DIRS:
			if tile(p + d) == T.GRASS: _burn(p + d); break
	_end_hero_turn(1.0)
	return true

## Warrior: Slam (1 per fight, 1.5 ticks). Hits every adjacent enemy for half damage (ignores DR) and knocks them all back.
func hero_slam() -> bool:
	if over or not ("slam" in hero.abilities) or int(hero.get("slams", 0)) <= 0: return false
	var adj := enemies().filter(func(e): return cheb(e.pos, hero.pos) == 1)
	if adj.is_empty(): return false
	hero.slams -= 1
	_log("%s SLAMS the ground!" % hero.name)
	_ev({"t": "sfx", "name": "rocks"}); _ev({"t": "slam", "pos": hero.pos})
	for e in adj:
		if e.hp <= 0: continue
		hit_mob(e, maxi(1, int(hero.dmg) / 2), false, true)
		if e.hp > 0: knockback(e, e.pos - hero.pos)
	_end_hero_turn(1.5)
	return true

## Rogue: Cloak of Shadows. Enemies lose track of you; your next attack is a Surprise.
func hero_cloak() -> bool:
	if over or hero.cloak.is_empty() or int(hero.cloak_charges) <= 0 or hidden(): return false
	hero.cloak_charges -= 1
	hero.hidden_until = hero.next + float(hero.cloak.ticks) + 1.0
	_log("%s vanishes into the shadows." % hero.name)
	_ev({"t": "sfx", "name": "meld"}); _ev({"t": "cloak", "uid": hero.uid})
	_end_hero_turn(1.0)
	return true

func _break_cloak() -> void:
	if hidden():
		hero.hidden_until = -1.0
		_log("%s strikes from the shadows!" % hero.name)

## Search: 2 ticks, reveals hidden traps within the hero's search radius (Rogue/Huntress see further).
func hero_search() -> bool:
	if over: return false
	hero.searched = true
	_log("%s searches carefully..." % hero.name); _ev({"t": "sfx", "name": "scan"}); _ev({"t": "search", "pos": hero.pos, "r": int(hero.search_radius) + 1})
	_reveal(hero.pos, int(hero.search_radius) + 1)
	_end_hero_turn(2.0)
	return true

func hidden_trap_count() -> int:
	return traps.values().filter(func(t): return t.hidden).size()

## Mid-fight gear swap (backpack): refresh the hero's derived stats, keep HP/Barrier/charges sensible.
func apply_stats(hs: Dictionary) -> void:
	hero.ht = int(hs.ht); hero.hp = mini(int(hero.hp), int(hero.ht))
	hero.dmg = int(hs.dmg); hero.dr = int(hs.dr); hero.delay = float(hs.delay)
	hero.barrier_max = int(hs.barrier_max); hero.barrier = mini(int(hero.barrier), int(hero.barrier_max))
	hero.surprise_mult = float(hs.get("surprise_mult", 1.5)); hero.search_radius = int(hs.get("search_radius", 1))
	var nb: Dictionary = hs.get("bolt", {})
	if not nb.is_empty():
		hero.bolt = nb; hero.charges = mini(int(hero.charges), int(nb.get("charges", 0)))

func hero_wait() -> void:
	if over: return
	_log("%s waits." % hero.name)
	_end_hero_turn(1.0)

func hero_heal(amount: int) -> void:
	if over: return
	hero.hp = mini(int(hero.ht), int(hero.hp) + amount)
	_log("%s drinks a potion (+%d HP)." % [hero.name, amount])
	_ev({"t": "heal", "uid": hero.uid, "amount": amount, "pos": hero.pos})
	_end_hero_turn(1.0)

func _end_hero_turn(cost: float) -> void:
	hero.next += cost
	if hero.get("perk", "") == "grass_heal" and tile(hero.pos) == T.GRASS and hero.hp < hero.ht: hero.hp += 1
	_tick_poison(hero)
	if not over: run_until_hero()

## Advance the deterministic clock until it is the hero's turn again.
func run_until_hero() -> void:
	var guard := 0
	while not over and guard < 500:
		guard += 1
		var best = null
		for u in enemies():
			if best == null or u.next < best.next or (u.next == best.next and u.uid < best.uid): best = u
		var dz_t := INF
		for d in danger: dz_t = minf(dz_t, d.at)
		var t_mob: float = INF if best == null else best.next
		var t_next := minf(t_mob, dz_t)
		if t_next >= hero.next: break
		time = t_next
		if dz_t <= t_mob:
			_resolve_danger()
		else:
			_mob_act(best)
			best.next += best.delay
	time = hero.next
	_recharge()

func _recharge() -> void:
	if hero.bolt.is_empty(): return
	if hero.charges < int(hero.bolt.charges):
		hero.recharge_t += 1.0
		if hero.recharge_t >= float(hero.bolt.recharge):
			hero.recharge_t = 0.0; hero.charges += 1

func _resolve_danger() -> void:
	for d in danger.duplicate():
		if d.at <= time:
			danger.erase(d)
			_ev({"t": "blast", "pos": d.pos})
			if hero.pos == d.pos:
				hit_hero(d.dmg, d.src, d.get("pierce", false))
				if d.has("poison") and not over:
					hero.poison = int(hero.get("poison", 0)) + int(d.poison); _ev({"t": "sfx", "name": "debuff"})
			elif d.get("hits_mobs", false):
				var u = unit_at(d.pos)
				if u != null and u != hero: _trap_hit(u, int(d.dmg))
			if over: return
			if d.has("spawn") and not over:
				var sp: Vector2i = d.pos if unit_at(d.pos) == null else _free_tile_near(d.pos)
				if sp.x >= 0 and unit_at(sp) == null:
					var nm := spawn(String(d.spawn), sp)
					if d.has("spawn_hp"): nm.hp = maxi(1, int(int(nm.ht) * float(d.spawn_hp))); nm.revived = true
					if d.get("summoned", false): nm.summoned = true
					nm.next = time + float(nm.delay)
					_log("%s rises!" % nm.name); _ev({"t": "spawn", "uid": nm.uid, "pos": sp})
	# a mob that finished charging stops charging
	for m in enemies():
		if m.charging and danger.filter(func(d): return d.uid == m.uid).is_empty(): m.charging = false

func _mob_act(m: Dictionary) -> void:
	m.acts += 1
	_tick_poison(m)
	if m.hp <= 0 or over: return
	if m.charging: return  # waits for its telegraph to resolve
	if m.has("enraged_dmg") and int(m.hp) * 2 <= int(m.ht) and int(m.dmg) != int(m.enraged_dmg):
		m.dmg = int(m.enraged_dmg); _log("%s is enraged! (dmg %d)" % [m.name, m.dmg])
	if m.has("hp_flee") and int(m.get("stolen", 0)) > 0:
		_flee(m); return
	match m.get("ability", ""):
		"throw":
			var rng: Array = m.throw_range
			if not hidden() and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= int(rng[0]) and cheb(m.pos, hero.pos) <= int(rng[1]) and line_clear(m.pos, hero.pos):
				danger.append({"pos": hero.pos, "dmg": int(m.dmg) + int(m.throw_bonus), "at": m.next + 1.0, "src": m.name + "'s spear", "uid": m.uid})
				m.cooldown = int(m.throw_cooldown)
				_log("%s winds up a throw! (red tile)" % m.name)
				_ev({"t": "telegraph", "uid": m.uid})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"zap":
			# DM-100: telegraphed lightning bolt (ignores DR); conducts through water to the hero
			if not hidden() and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 2 and cheb(m.pos, hero.pos) <= 4 and line_clear(m.pos, hero.pos):
				danger.append({"pos": hero.pos, "dmg": int(m.zap_dmg), "at": m.next + 1.0, "src": m.name + "'s lightning", "uid": m.uid, "pierce": m.get("zap_magic", false)})
				m.cooldown = int(m.zap_cooldown)
				_log("%s crackles with energy! (red tile)" % m.name)
				_ev({"t": "telegraph", "uid": m.uid}); _ev({"t": "sfx", "name": "chargeup"})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"chain":
			# Prison Guard: once per fight, yanks the hero next to it
			if not hidden() and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 2 and cheb(m.pos, hero.pos) <= 3 and line_clear(m.pos, hero.pos):
				var pts := _line(hero.pos, m.pos)
				var dest: Vector2i = pts[pts.size() - 2]
				if passable(dest) and unit_at(dest) == null:
					m.cooldown = 999
					_log("%s's chain drags %s in!" % [m.name, hero.name]); _ev({"t": "sfx", "name": "chains"})
					_place(hero, dest)
					return
		"tengu":
			if _tengu_act(m): return
		"dm300":
			if _dm300_act(m): return
		"dking":
			if _dking_act(m): return
		"yog":
			if _yog_act(m): return
		"pump":
			var every := int(m.pump_every)
			if int(m.hp) * 2 <= int(m.ht) and m.has("pump_every_enraged"): every = int(m.pump_every_enraged)
			m.pump_count = int(m.get("pump_count", 0)) + 1
			if m.pump_count >= every:
				m.pump_count = 0
				var dmg := int(m.dmg) * int(m.pump_mult)
				for d in DIRS:
					var p: Vector2i = m.pos + d
					if tile(p) != T.WALL: danger.append({"pos": p, "dmg": dmg, "at": m.next + 1.0, "src": m.name + "'s slam", "uid": m.uid})
				m.charging = true
				_log("%s pumps itself up! (step away from the red tiles)" % m.name)
				_ev({"t": "telegraph", "uid": m.uid}); _ev({"t": "sfx", "name": "chargeup"})
				return
			if int(m.hp) * 2 <= int(m.ht) and m.has("enraged_dmg"):
				m.dmg = int(m.enraged_dmg)
	if hidden():
		return  # lost track of the hero: searches in place
	if cheb(m.pos, hero.pos) == 1:
		_ev({"t": "attack", "uid": m.uid, "to": hero.pos})
		var hp_before: int = hero.hp + hero.barrier
		hit_hero(int(m.dmg), m.name)
		var dealt: int = hp_before - (hero.hp + hero.barrier)
		if m.has("drain") and dealt > 0 and m.hp < m.ht:
			var h := mini(int(m.drain), int(m.ht) - int(m.hp)); m.hp += h
			_ev({"t": "heal", "uid": m.uid, "amount": h, "pos": m.pos}); _log("%s drinks your blood (+%d)." % [m.name, h])
		if m.has("bite_poison") and dealt > 0 and not over:
			hero.poison = int(hero.get("poison", 0)) + int(m.bite_poison); _log("The bite is venomous!"); _ev({"t": "sfx", "name": "debuff"})
		if m.get("ability", "") == "steal" and int(m.get("stolen", 0)) == 0 and not over:
			m.stolen = int(m.steal_gold)
			_log("%s snatches %d gold and runs! Kill it to get it back." % [m.name, m.stolen]); _ev({"t": "sfx", "name": "gold"})
		return
	if m.get("stationary", false): return   # Yog-Dzewa never moves
	var step = path_step(m.pos, hero.pos, false, true)
	if step != null:
		_place(m, step)

## Thief: after stealing, runs to the tile farthest from the hero.
func _flee(m: Dictionary) -> void:
	var best = null; var bd := cheb(m.pos, hero.pos)
	for d in DIRS:
		var n: Vector2i = m.pos + d
		if passable(n) and unit_at(n) == null and not traps.has(n) and cheb(n, hero.pos) > bd: bd = cheb(n, hero.pos); best = n
	if best != null: _place(m, best)
	elif cheb(m.pos, hero.pos) == 1: hit_hero(int(m.dmg), m.name)

## Tengu (SPD Prison boss). Phase 1: throws telegraphed shurikens from range, blinks away after being hurt.
## Phase 2 (<= half HP): also lobs bombs - a 3x3 red area that blows up 2 ticks later (bombs hurt mobs too).
## Returns true if it used its turn.
func _tengu_act(m: Dictionary) -> bool:
	if hidden(): return false
	var d := cheb(m.pos, hero.pos)
	var enraged := int(m.hp) * 2 <= int(m.ht)
	m.bombs = int(m.get("bombs", 0)) + 1
	if enraged and m.bombs >= int(m.bomb_every):
		m.bombs = 0
		for o in [Vector2i.ZERO] + DIRS:
			if tile(hero.pos + o) != T.WALL:
				danger.append({"pos": hero.pos + o, "dmg": int(m.bomb_dmg), "at": m.next + 2.0, "src": "Tengu's bomb", "uid": m.uid, "hits_mobs": true})
		_log("Tengu lobs a bomb! (2 ticks - get clear of the red area)")
		_ev({"t": "telegraph", "uid": m.uid}); _ev({"t": "sfx", "name": "blast"})
		return true
	if d >= 2 and m.cooldown <= 0 and line_clear(m.pos, hero.pos):
		danger.append({"pos": hero.pos, "dmg": int(m.throw_dmg), "at": m.next + 1.0, "src": "Tengu's shuriken", "uid": m.uid})
		m.cooldown = int(m.throw_cooldown)
		_log("Tengu readies a shuriken! (red tile)")
		_ev({"t": "telegraph", "uid": m.uid}); _ev({"t": "sfx", "name": "hit_stab"})
		return true
	m.cooldown = maxi(0, int(m.cooldown) - 1)
	return false

## DM-300 (SPD Caves boss), simple version. Alternates two telegraphed abilities every `ability_every` actions:
##  rockfall - a plus-shaped 5-tile area centred on the hero, 2-tick warning (rock_dmg);
##  toxic vent - the line from DM-300 to the hero, 1 tick, low damage (ignores DR) + poison.
## Below half HP it SUPERCHARGES once: +2 DR and abilities every `ability_every_super` actions.
func _dm300_act(m: Dictionary) -> bool:
	if hidden(): return false
	var sup := int(m.hp) * 2 <= int(m.ht)
	if sup and not m.get("supercharged", false):
		m.supercharged = true; m.dr = int(m.dr) + 2
		_log("DM-300 SUPERCHARGES! (+2 DR, abilities come faster)"); _ev({"t": "sfx", "name": "chargeup"}); _ev({"t": "telegraph", "uid": m.uid})
	m.abil = int(m.get("abil", 0)) + 1
	if m.abil < int(m.ability_every_super if sup else m.ability_every): return false
	m.abil = 0
	m.abil_n = int(m.get("abil_n", 0)) + 1
	if m.abil_n % 2 == 1:
		for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if tile(hero.pos + o) != T.WALL:
				danger.append({"pos": hero.pos + o, "dmg": int(m.rock_dmg), "at": m.next + 2.0, "src": "Falling rocks", "uid": m.uid, "hits_mobs": true})
		_log("DM-300 shakes the ceiling! Rocks will fall in 2 ticks (red tiles)."); _ev({"t": "sfx", "name": "rocks"})
	else:
		var pts := _line(m.pos, hero.pos)
		for i in range(1, pts.size()):
			if tile(pts[i]) == T.WALL: break
			danger.append({"pos": pts[i], "dmg": int(m.gas_dmg), "at": m.next + 1.0, "src": "Toxic gas", "uid": m.uid, "pierce": true, "poison": int(m.gas_poison)})
		_log("DM-300 vents toxic gas at you! (red line, 1 tick)"); _ev({"t": "sfx", "name": "gas"})
	_ev({"t": "telegraph", "uid": m.uid})
	return true

## King of Dwarves: every few actions alternates
##  raise the dead - marks 2 free tiles near the hero; 2 ticks later Risen Dwarves appear there (4 dmg if you stand on one);
##  shadow blast - 3x3 on the hero, 2 ticks (one step can't clear a 3x3 in 1), blast_dmg ignoring DR.
## Below half HP he ENRAGES once (+3 dmg, abilities every `ability_every_super`). Minions die with him.
func _king_linked() -> bool:
	return enemies().any(func(e): return e.get("summoned", false) and e.hp > 0)

## King of Dwarves, 3 phases (DECISIONS #79):
##   1 (> 1/2 HP) raise dead / shadow blast every 3 actions; risen dwarves lifelink him (he takes 2/3 damage)
##   2 (<= 1/2)   enraged: +3 dmg
##   3 (<= 1/4)   the throne cracks: no more summons, blasts only, lifelink gone
func _dking_act(m: Dictionary) -> bool:
	if hidden(): return false
	var phase := 1
	if int(m.hp) * 4 <= int(m.ht): phase = 3
	elif int(m.hp) * 2 <= int(m.ht): phase = 2
	var enr := false   # fixed cadence: faster blasts left the hero no turn to strike back (DECISIONS #79)
	if phase >= 2 and not m.get("enraged", false):
		m.enraged = true; m.dmg = int(m.dmg) + 3
		_log("The King of Dwarves roars in fury! (phase 2: +3 dmg)"); _ev({"t": "sfx", "name": "chargeup"}); _ev({"t": "telegraph", "uid": m.uid})
	if phase == 3 and not m.get("phase3", false):
		m.phase3 = true
		_log("The King's throne cracks! (phase 3: no more summons, his lifelink is broken)"); _ev({"t": "sfx", "name": "hit_crush"}); _ev({"t": "telegraph", "uid": m.uid})
	m.abil = int(m.get("abil", 0)) + 1
	if m.abil < int(m.ability_every_super if enr else m.ability_every): return false
	m.abil = 0
	m.abil_n = int(m.get("abil_n", 0)) + 1
	if not m.get("phase3", false) and m.abil_n % 2 == 1 and enemies().filter(func(e): return e.get("summoned", false)).is_empty():
		var spots := []
		for d in DIRS + [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var q: Vector2i = hero.pos + d
			if spots.size() >= int(m.summon_n): break
			if passable(q) and unit_at(q) == null and not is_danger(q): spots.append(q)
		for q in spots:
			danger.append({"pos": q, "dmg": 4, "at": m.next + 2.0, "src": "Rising dead", "uid": m.uid, "spawn": m.summon, "summoned": true})
		_log("The King raises the dead! Dwarves will rise in 2 ticks (red tiles)."); _ev({"t": "sfx", "name": "bones"})
	else:
		for y in range(-1, 2):
			for x in range(-1, 2):
				var q: Vector2i = hero.pos + Vector2i(x, y)
				if tile(q) != T.WALL:
					danger.append({"pos": q, "dmg": int(m.blast_dmg), "at": m.next + 2.0, "src": "Shadow blast", "uid": m.uid, "pierce": true})
		_log("The King gathers shadow around you! (3x3 red tiles, 2 ticks - get out!)"); _ev({"t": "sfx", "name": "zap"})
	_ev({"t": "telegraph", "uid": m.uid})
	return true

## Yog-Dzewa (DECISIONS #77): immobile; alternates raising larva (only when none are left) and a gaze beam
## over the hero's whole row + column (2-tick fuse, ignores DR). Below half HP: faster and 3 larva.
func _yog_act(m: Dictionary) -> bool:
	if hidden(): return false
	var enr := int(m.hp) * 2 <= int(m.ht)
	if enr and not m.get("enraged", false):
		m.enraged = true; m.summon_n = int(m.summon_n) + 1
		_log("Yog-Dzewa's eye burns brighter! (abilities come faster)"); _ev({"t": "sfx", "name": "chargeup"}); _ev({"t": "telegraph", "uid": m.uid})
	m.abil = int(m.get("abil", 0)) + 1
	if m.abil < int(m.ability_every_super if enr else m.ability_every): return false
	m.abil = 0
	m.abil_n = int(m.get("abil_n", 0)) + 1
	if m.abil_n % 2 == 1 and enemies().filter(func(e): return e.get("summoned", false)).is_empty():
		var spots := []
		for d in DIRS + [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var q: Vector2i = hero.pos + d
			if spots.size() >= int(m.summon_n): break
			if passable(q) and unit_at(q) == null and not is_danger(q): spots.append(q)
		for q in spots:
			danger.append({"pos": q, "dmg": 4, "at": m.next + 2.0, "src": "Larva hatching", "uid": m.uid, "spawn": m.summon, "summoned": true})
		_log("Yog-Dzewa spawns larva! (red tiles, 2 ticks)"); _ev({"t": "sfx", "name": "bones"})
	else:
		for i in SIZE:
			for q in [Vector2i(i, hero.pos.y), Vector2i(hero.pos.x, i)]:
				if tile(q) != T.WALL and not is_danger(q) and q != m.pos:
					danger.append({"pos": q, "dmg": int(m.beam_dmg), "at": m.next + 2.0, "src": "Yog's gaze", "uid": m.uid, "pierce": true})
		_log("Yog-Dzewa's gaze sweeps your row and column! (2 ticks - step off the line)"); _ev({"t": "sfx", "name": "zap"})
	_ev({"t": "telegraph", "uid": m.uid})
	return true

## Called after Tengu takes damage: every `blink_every` HP lost it teleports to the far side of the arena.
func _tengu_hurt(m: Dictionary) -> void:
	var lost := int(m.ht) - int(m.hp)
	var marks := lost / int(m.blink_every)
	if marks > int(m.get("blinks", 0)) and m.hp > 0:
		m.blinks = marks
		var far := _farthest_free(hero.pos)
		_log("Tengu vanishes in a puff of smoke!"); _ev({"t": "sfx", "name": "puff"})
		_ev({"t": "move", "uid": m.uid, "from": m.pos, "to": far, "blink": true})
		m.pos = far
		danger = danger.filter(func(z): return z.uid != m.uid or z.get("hits_mobs", false))

## First step of a shortest 8-way path from `from` to a tile adjacent to `to`. null if none.
## avoid_traps: mobs know every trap; known_only restricts that to revealed traps (hero-side pathing).
func path_step(from: Vector2i, to: Vector2i, avoid_danger := false, avoid_traps := false, known_only := false):
	var prev := {from: from}
	var q := [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if cheb(c, to) == 1:
			if c == from: return null
			while prev[c] != from: c = prev[c]
			return c
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not passable(n) or unit_at(n) != null: continue
			if avoid_danger and is_danger(n): continue
			if avoid_traps and traps.has(n) and not (known_only and traps[n].hidden): continue
			prev[n] = c; q.append(n)
	return null

func _free_tile_near(p: Vector2i) -> Vector2i:
	for r in range(0, SIZE):
		for y in range(p.y - r, p.y + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				var c := Vector2i(x, y)
				if passable(c) and unit_at(c) == null: return c
	return p
