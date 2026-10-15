## Deterministic tactical combat model (no RNG). Pure logic, no nodes, so it can be simulated headless.
class_name Combat
extends RefCounted

enum T { FLOOR, WALL, GRASS, DOOR, CHASM }
const SIZE := 8
const DIRS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]

# Stats taken from SPD Java classes; damage/DR ranges collapsed to floor(avg).
# Rat: HT 8, dmg 1-4, DR 0-1 | Snake: HT 4, dmg 1-4 | Gnoll scout: HT 12, dmg 1-6, DR 0-2 | Sewer crab: HT 15, dmg 1-7, DR 0-4, speed 2x
const MOBS := {
	"rat":   {"name":"Marsupial Rat","ht":8,"dmg":2,"dr":0,"delay":1.0,"sprite":"rat","fw":16,"fh":15,"loot":2},
	"snake": {"name":"Sewer Snake","ht":4,"dmg":2,"dr":0,"delay":1.0,"sprite":"snake","fw":12,"fh":11,"loot":2},
	"gnoll": {"name":"Gnoll Scout","ht":12,"dmg":3,"dr":1,"delay":1.0,"sprite":"gnoll","fw":12,"fh":15,"loot":3,"thrower":true},
	"crab":  {"name":"Sewer Crab","ht":15,"dmg":4,"dr":2,"delay":0.5,"sprite":"crab","fw":16,"fh":16,"loot":4},
}

# Handcrafted 8x8 templates: # wall, . floor, " grass, + door, _ chasm, H hero, r/s/g/c mobs
const ROOMS := [
	["########","#H..\"..#","#..__..#","+..__.r#","#......#","#.\".\"..#","#....r.#","########"],
	["###+####","#H.\"...#","#..#.g.#","#..#...#","#..+..__","#.\"\"..__","#...c..#","########"],
	["########","#H.....#","#.\"..s.#","##+##..#","#....__#","#.g..__#","#..\"..c#","########"],
]

var terrain := []          # [y][x] of T
var units: Array = []      # index 0 = hero
var hero: Dictionary
var time := 0.0
var log_lines: PackedStringArray = []
var danger: Array = []     # [{pos, dmg, at, src}]
var loot := 0
var over := false
var won := false

func setup(room_idx: int, hero_stats: Dictionary) -> void:
	var rows: Array = ROOMS[room_idx % ROOMS.size()]
	terrain.clear(); units.clear(); danger.clear(); log_lines.clear()
	time = 0.0; loot = 0; over = false; won = false
	hero = {"id":"hero","name":"Warrior","hp":hero_stats.hp,"ht":hero_stats.ht,"dmg":hero_stats.dmg,"dr":hero_stats.dr,
		"barrier":hero_stats.barrier_max,"delay":1.0,"next":0.0,"pos":Vector2i.ZERO,"sprite":"warrior","fw":12,"fh":15}
	units.append(hero)
	for y in SIZE:
		var row := []
		for x in SIZE:
			var ch: String = rows[y][x]
			var t := T.FLOOR
			match ch:
				"#": t = T.WALL
				"\"": t = T.GRASS
				"+": t = T.DOOR
				"_": t = T.CHASM
				"H": hero.pos = Vector2i(x,y)
				"r","s","g","c":
					var key: String = {"r":"rat","s":"snake","g":"gnoll","c":"crab"}[ch]
					var m: Dictionary = MOBS[key].duplicate()
					m.id = key; m.hp = m.ht; m.pos = Vector2i(x,y); m.next = m.delay; m.cooldown = 0
					units.append(m)
			row.append(t)
		terrain.append(row)
	_log("A fight! Barrier %d, HP %d/%d." % [hero.barrier, hero.hp, hero.ht])

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60: log_lines.remove_at(0)

func tile(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= SIZE or p.y >= SIZE: return T.WALL
	return terrain[p.y][p.x]

func unit_at(p: Vector2i):
	for u in units:
		if u.hp > 0 and u.pos == p: return u
	return null

func enemies() -> Array:
	return units.filter(func(u): return u != hero and u.hp > 0)

func passable(p: Vector2i) -> bool:
	var t := tile(p)
	return t != T.WALL and t != T.CHASM

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x), absi(a.y-b.y))

## Damage to the hero: flat DR, then Barrier, then HP. Chip rule: fully blocked hit still strips 1 Barrier.
func hit_hero(raw: int, src: String, pierce := false) -> void:
	var dmg := raw if pierce else maxi(0, raw - int(hero.dr))
	if dmg == 0:
		if hero.barrier > 0:
			hero.barrier -= 1
			_log("%s's hit is blocked (chip: -1 Barrier)." % src)
		else:
			_log("%s's hit is fully blocked." % src)
		return
	var absorbed := mini(dmg, int(hero.barrier))
	hero.barrier -= absorbed
	hero.hp -= dmg - absorbed
	_log("%s hits for %d (%d Barrier, %d HP)." % [src, dmg, absorbed, dmg - absorbed])
	if hero.hp <= 0:
		hero.hp = 0; over = true; won = false
		_log("The Warrior falls...")

func hit_mob(m: Dictionary, raw: int, surprise: bool) -> void:
	var dmg := raw
	if surprise:
		dmg = int(raw * 1.5)  # surprise: +50%, ignores DR, knockback
	else:
		dmg = maxi(0, raw - int(m.dr))
	m.hp -= dmg
	_log("%s%s takes %d." % ["SURPRISE! " if surprise else "", m.name, dmg])
	if m.hp <= 0:
		_kill(m, false)
	elif surprise:
		knockback(m, m.pos - hero.pos)

func knockback(m: Dictionary, dir: Vector2i) -> void:
	dir = Vector2i(signi(dir.x), signi(dir.y))
	var dest: Vector2i = m.pos + dir
	var t := tile(dest)
	if t == T.CHASM:
		m.pos = dest
		_log("%s is knocked into the chasm!" % m.name)
		_kill(m, true)
	elif t == T.WALL or unit_at(dest) != null:
		m.hp -= 1
		_log("%s slams into an obstacle (1)." % m.name)
		if m.hp <= 0: _kill(m, false)
	else:
		m.pos = dest

func _kill(m: Dictionary, chasm: bool) -> void:
	m.hp = 0
	var l: int = m.loot
	if chasm: l = int(l / 2.0)  # halved, recovered next floor (stub: banked immediately)
	loot += l
	_log("%s dies. +%d gold%s" % [m.name, l, " (halved, fell)" if chasm else ""])
	if enemies().is_empty():
		over = true; won = true
		_log("Room cleared!")

## Hero actions. Returns true if a tick was spent.
func hero_tap(p: Vector2i, shove := false) -> bool:
	if over: return false
	if cheb(p, hero.pos) != 1: return false
	var u = unit_at(p)
	if u != null and u != hero:
		if shove:
			_log("Warrior shoves %s." % u.name)
			knockback(u, p - hero.pos)
		else:
			var ht := tile(hero.pos)
			hit_mob(u, hero.dmg, ht == T.DOOR or ht == T.GRASS)
	elif passable(p) and u == null:
		hero.pos = p
	else:
		return false
	_end_hero_turn()
	return true

func hero_wait() -> void:
	if over: return
	_log("Warrior waits.")
	_end_hero_turn()

func _end_hero_turn() -> void:
	hero.next += hero.delay
	run_until_hero()

## Advance the deterministic clock: every actor whose next time is strictly before the hero's acts (hero wins ties).
func run_until_hero() -> void:
	var guard := 0
	while not over and guard < 500:
		guard += 1
		var best = null
		for u in enemies():
			if best == null or u.next < best.next: best = u
		if best == null or best.next >= hero.next: break
		time = best.next
		_resolve_danger()
		if over: break
		_mob_act(best)
		best.next += best.delay
	time = hero.next
	_resolve_danger()

func _resolve_danger() -> void:
	for d in danger.duplicate():
		if d.at <= time:
			danger.erase(d)
			if hero.pos == d.pos: hit_hero(d.dmg, d.src + "'s thrown spear")
			else: _log("%s's spear hits the ground." % d.src)
			if over: return

func _mob_act(m: Dictionary) -> void:
	if m.get("thrower", false) and m.cooldown <= 0 and cheb(m.pos, hero.pos) in [2, 3]:
		danger.append({"pos": hero.pos, "dmg": m.dmg + 2, "at": m.next + 1.0, "src": m.name})
		m.cooldown = 3
		_log("%s winds up a throw! (red tile)" % m.name)
		return
	m.cooldown = maxi(0, m.cooldown - 1)
	if cheb(m.pos, hero.pos) == 1:
		hit_hero(m.dmg, m.name)
		return
	var step = _path_step(m.pos, hero.pos)
	if step != null: m.pos = step

func _path_step(from: Vector2i, to: Vector2i):
	var prev := {from: from}
	var q := [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if cheb(c, to) == 1 and c != from:
			while prev[c] != from: c = prev[c]
			return c
		if cheb(c, to) == 1: return null
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not passable(n) or unit_at(n) != null: continue
			prev[n] = c; q.append(n)
	return null
