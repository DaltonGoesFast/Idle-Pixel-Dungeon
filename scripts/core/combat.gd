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

## room_rows: Array[String] 8x8; hs: GameState.hero_stats(); mob_ids fill spawn slots 1..4 in order (B = boss).
func setup(room_rows: Array, hs: Dictionary, hp: int, mob_ids: Array, darkness := false) -> void:
	terrain.clear(); units.clear(); danger.clear(); log_lines.clear(); events.clear()
	time = 0.0; loot = 0; fallen_loot = 0; xp = 0; over = false; won = false; boss_killed = false; _uid = 0
	hero = {"uid": _next_uid(), "id": "hero", "name": hs.name, "hp": hp, "ht": hs.ht, "dmg": hs.dmg, "dr": hs.dr,
		"barrier": 0 if darkness else hs.barrier_max, "barrier_max": hs.barrier_max, "delay": hs.delay, "next": 0.0,
		"pos": Vector2i.ZERO, "sprite": hs.sprite, "fw": hs.fw, "fh": hs.fh, "surprise_mult": hs.get("surprise_mult", 1.5),
		"abilities": hs.get("abilities", []), "bolt": hs.get("bolt", {}), "charges": 0, "recharge_t": 0.0, "hero": true,
		"cloak": hs.get("cloak", {}), "cloak_charges": int(hs.get("cloak", {}).get("charges", 0)), "hidden_until": -1.0,
		"slams": 1 if "slam" in hs.get("abilities", []) else 0}
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
	return {"terrain": terrain, "units": us, "danger": dz, "time": time, "log": Array(log_lines), "loot": loot,
		"fallen_loot": fallen_loot, "xp": xp, "over": over, "won": won, "boss_killed": boss_killed, "uid": _uid}

func from_dict(d: Dictionary) -> void:
	terrain = []
	for row in d.terrain: terrain.append(row.map(func(t): return int(t)))
	units = []
	for u in d.units:
		var x: Dictionary = u.duplicate(true)
		x.pos = Vector2i(int(u.pos[0]), int(u.pos[1]))
		for k in ["uid", "hp", "ht", "dmg", "dr", "barrier", "barrier_max", "charges", "cloak_charges", "cooldown", "acts", "exp", "loot"]:
			if x.has(k): x[k] = int(x[k])
		units.append(x)
		if x.has("hero"): hero = x
	danger = []
	for e in d.danger:
		var y: Dictionary = e.duplicate(); y.pos = Vector2i(int(e.pos[0]), int(e.pos[1])); y.dmg = int(e.dmg); y.uid = int(e.uid); danger.append(y)
	time = float(d.time); log_lines = PackedStringArray(d.log); loot = int(d.loot); fallen_loot = int(d.fallen_loot)
	xp = int(d.xp); over = d.over; won = d.won; boss_killed = d.boss_killed; _uid = int(d.uid); events = []

func _next_uid() -> int:
	_uid += 1
	return _uid

func spawn(id: String, p: Vector2i) -> Dictionary:
	var m: Dictionary = DB.mobs[id].duplicate(true)
	m.id = id; m.uid = _next_uid(); m.hp = int(m.ht); m.pos = p; m.next = float(m.delay); m.cooldown = 0; m.acts = 0
	m.charging = false
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
	m.hp -= dmg
	_log("%s%s takes %d." % ["SURPRISE! " if surprise else "", m.name, dmg])
	_ev({"t": "hit", "uid": m.uid, "amount": dmg, "kind": "surprise" if surprise else ("magic" if magic else "hp"), "pos": m.pos})
	if m.hp <= 0:
		_kill(m, false)
	elif surprise and not m.get("boss", false):
		knockback(m, m.pos - hero.pos)

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
		_log("%s is knocked into the chasm!" % m.name)
		_kill(m, true)
	elif t == T.WALL or unit_at(dest) != null:
		m.hp -= 1
		_log("%s slams into an obstacle (1)." % m.name)
		_ev({"t": "hit", "uid": m.uid, "amount": 1, "kind": "hp", "pos": m.pos})
		if m.hp <= 0: _kill(m, false)
	else:
		_ev({"t": "move", "uid": m.uid, "from": m.pos, "to": dest})
		m.pos = dest

func _kill(m: Dictionary, chasm: bool) -> void:
	m.hp = 0
	var l := int(m.loot)
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
	if m.get("boss", false): boss_killed = true
	if enemies().is_empty():
		over = true; won = true
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
		hit_mob(u, int(hero.dmg), sur)
		_end_hero_turn(float(hero.delay))
		return true
	if passable(p) and u == null:
		_ev({"t": "move", "uid": hero.uid, "from": hero.pos, "to": p})
		hero.pos = p
		_end_hero_turn(1.0)
		return true
	return false

func hero_bolt(p: Vector2i) -> bool:
	if not can_bolt(p): return false
	var u = unit_at(p)
	var magic: bool = hero.bolt.get("magic", true)
	if not hero.bolt.get("infinite", false): hero.charges -= 1
	_log("%s fires %s." % [hero.name, hero.bolt.name])
	_ev({"t": "bolt", "from": hero.pos, "to": p, "magic": magic})
	var sur := surprise_ready() and not magic
	_break_cloak()
	hit_mob(u, int(hero.bolt.dmg), sur, magic)
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
	run_until_hero()

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
			if hero.pos == d.pos: hit_hero(d.dmg, d.src)
			if over: return
	# a mob that finished charging stops charging
	for m in enemies():
		if m.charging and danger.filter(func(d): return d.uid == m.uid).is_empty(): m.charging = false

func _mob_act(m: Dictionary) -> void:
	m.acts += 1
	if m.charging: return  # waits for its telegraph to resolve
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
		"pump":
			if m.acts % int(m.pump_every) == 0:
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
		hit_hero(int(m.dmg), m.name)
		return
	var step = path_step(m.pos, hero.pos)
	if step != null:
		_ev({"t": "move", "uid": m.uid, "from": m.pos, "to": step})
		m.pos = step

## First step of a shortest 8-way path from `from` to a tile adjacent to `to`. null if none.
func path_step(from: Vector2i, to: Vector2i, avoid_danger := false):
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
			prev[n] = c; q.append(n)
	return null

func _free_tile_near(p: Vector2i) -> Vector2i:
	for r in range(0, SIZE):
		for y in range(p.y - r, p.y + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				var c := Vector2i(x, y)
				if passable(c) and unit_at(c) == null: return c
	return p
