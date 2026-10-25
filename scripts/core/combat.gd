## Combat: deterministic tactical combat model (no RNG, no nodes) so it can be simulated headless.
##
## Rules (see docs/BALANCE.md):
##  - SPD turn clock: each actor has `next` (time of next action). Hero acts on ties.
##    Moving/attacking costs the actor's delay (1.0 normal, 0.5 fast, 1.5 heavy weapons).
##  - Every attack hits for fixed damage. Physical damage - flat DR. Barrier absorbs before HP.
##    Chip rule: a hit fully blocked by DR still removes 1 Barrier.
##  - Surprise: hit while the foe cannot see you (after a door closes or circling tall grass) =
##    x surprise_mult (1.5 / 2.5 Assassin), then subtract DR (stealth weapons & Assassin pierce 50%). No knockback
##    (DECISIONS #220). Dagger-family sur_bonus still applies; Flail / under-Str can't surprise (#207).
##  - Weapons (DECISIONS #207): reach (Spear/Glaive 2, Whip 3, SPD canReach), accuracy (acc < 1: a fixed share of
##    swings at alert foes miss; acc > 1: that share of swings lands on a dodging snake), block as DR.
##  - Telegraphs: red danger tiles resolve at a known time; step off them.
##  - Knockback into a chasm kills instantly (loot halved, recovered next floor).
##  - Traps (data/traps.json): '^' visible, '?' hidden until searched. Anyone stepping on one triggers it
##    (one-shot). Mobs know trap locations and path around them, but knockback can push them in.
class_name Combat
extends RefCounted

enum T { FLOOR, WALL, GRASS, DOOR, CHASM, WATER }
const SIZE := 8   # default / legacy; each fight uses w x h from its room
const DIRS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
const BOLT_RANGE := 6

var w := SIZE
var h := SIZE
var terrain: Array = []
var units: Array = []
var remains := {}     # door cells where something died and nobody has passed through since: held open (DECISIONS #176)
var trampled := {}   # cells whose tall grass was trodden flat (SPD HIGH_GRASS -> GRASS, DECISIONS #81)
var hero: Dictionary
var time := 0.0
var log_lines: PackedStringArray = []
var events: Array = []          # visual/audio events since last drain_events()
var danger: Array = []          # [{pos, dmg, at, src, uid}]
var loot := 0
var fallen_loot := 0            # loot halved by chasm kills (recovered next floor)
var gold_debt := 0              # gold escaped thieves took from the pack (applied after the fight)
var purse := 0                  # pack gold at fight start (Crazy Thief steals a % of this)
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
var dmg_in := 0                 # post-DR damage + chip taken by the hero (for balance telemetry)
var absorbed_total := 0         # how much of dmg_in was absorbed by Barrier
var dmg_out := 0                # damage the hero's hits dealt to enemies (telemetry, DECISIONS #197)
var hero_turns := 0             # hero actions taken this fight (telemetry)
var hp_lost := 0                # HP (not Barrier) the hero lost this fight, poison included ("Untouchable")
var surprises := 0              # surprise hits landed by the hero (milestones, DECISIONS #195)
var kill_ids := {}              # mob id -> kills this fight (milestones)
var potions_drunk := 0          # healing potions drunk this fight, kept through a mid-fight save (Teetotaller)
var floor := 1                  # delve floor for trap damage scaling (DECISIONS #220)
var auto_used := false          # set by the combat screen once Auto Battle acts (the "By Hand" feat)
var last_target := 0            # uid of last attacker / last foe the hero hit (SPD QuickSlot auto-aim, DECISIONS #231)

## room_rows: Array[String] of equal length (8/10/12); hs: GameState.hero_stats(); mob_ids fill slots 1..8 (B = boss).
func setup(room_rows: Array, hs: Dictionary, hp: int, mob_ids: Array, darkness := false, pool := []) -> void:
	terrain.clear(); units.clear(); danger.clear(); log_lines.clear(); events.clear(); traps.clear()
	kills = 0; traps_found = 0; trap_ids_seen = []; dmg_in = 0; absorbed_total = 0; dmg_out = 0; hero_turns = 0
	surprises = 0; kill_ids = {}; auto_used = false; hp_lost = 0; potions_drunk = 0; last_target = 0
	remains = {}
	if not pool.is_empty(): trap_pool = pool
	time = 0.0; loot = 0; fallen_loot = 0; gold_debt = 0; purse = 0; xp = 0; over = false; won = false; boss_killed = false; _uid = 0
	h = room_rows.size(); w = String(room_rows[0]).length() if h > 0 else SIZE
	hero = {"uid": _next_uid(), "id": "hero", "name": hs.name, "hp": hp, "ht": hs.ht, "dmg": hs.dmg, "dr": hs.dr,
		"barrier": 0 if darkness else hs.barrier_max, "barrier_max": hs.barrier_max, "delay": hs.delay, "next": 0.0,
		"pos": Vector2i.ZERO, "sprite": hs.sprite, "fw": hs.fw, "fh": hs.fh, "row": int(hs.get("row", 0)), "surprise_mult": hs.get("surprise_mult", 1.5),
		"abilities": hs.get("abilities", []), "bolt": hs.get("bolt", {}), "charges": 0, "recharge_t": 0.0, "hero": true,
		"cloak": hs.get("cloak", {}), "cloak_charges": int(hs.get("cloak", {}).get("charges", 0)), "cloak_cap": int(hs.get("cloak", {}).get("cap", 0)), "hidden_until": -1.0,
		"slams": 1 if "slam" in hs.get("abilities", []) else 0, "search_radius": int(hs.get("search_radius", 1)),
		"poison": 0, "keen_eyes": hs.get("keen_eyes", false), "perk": hs.get("perk", ""), "sub": String(hs.get("sub", "")),
		"level": int(hs.get("level", 1)), "combo": 0,
		"move_cost": float(hs.get("move_cost", 1.0)), "elem_resist": float(hs.get("elem_resist", 1.0)),
		"thorns": int(float(hs.get("thorns", 0.0))), "grass_root": float(hs.get("grass_root", 0.0))}
	if not hero.bolt.is_empty(): hero.charges = hero.bolt.charges
	_weapon_stats(hs)
	units.append(hero)
	var slots := {}
	for y in h:
		var row := []
		for x in w:
			var ch: String = room_rows[y][x]
			var t := T.FLOOR
			match ch:
				"#": t = T.WALL
				"\"": t = T.GRASS
				"+": t = T.DOOR
				"_": t = T.CHASM
				"~": t = T.WATER
				"H": hero.pos = Vector2i(x, y)
				"1","2","3","4","5","6","7","8": slots[int(ch) - 1] = Vector2i(x, y)
				"B": slots[0] = Vector2i(x, y)
				"^", "?":
					# trap type: deterministic from position so the same room always has the same traps
					traps[Vector2i(x, y)] = {"id": trap_pool[(x * 7 + y * 3) % trap_pool.size()], "hidden": ch == "?"}
					if ch == "^" and not (traps[Vector2i(x, y)].id in trap_ids_seen): trap_ids_seen.append(traps[Vector2i(x, y)].id)
			row.append(t)
		terrain.append(row)
	for i in mob_ids.size():
		var p: Vector2i = slots.get(i, _free_tile_near(Vector2i(w - 2, h - 2)))
		spawn(mob_ids[i], p)
	_artifact_openers(hs)
	_log("A fight! Barrier %d, HP %d/%d%s." % [hero.barrier, hero.hp, hero.ht, " (darkness: no Barrier)" if darkness else ""])
	_note_sightings()

# ------------------------------------------------------------------ persistence
## Serialise to JSON-safe data (Vector2i -> [x, y]) so a fight survives the app being killed.
func to_dict() -> Dictionary:
	var us := []
	for u in units:
		var d: Dictionary = u.duplicate(true); d.pos = [u.pos.x, u.pos.y]
		if d.has("aim") and d.aim is Vector2i: d.aim = [d.aim.x, d.aim.y]
		us.append(d)
	var dz := []
	for d in danger:
		var e: Dictionary = d.duplicate(); e.pos = [d.pos.x, d.pos.y]; dz.append(e)
	var tr := []
	for k in traps: tr.append({"pos": [k.x, k.y], "id": traps[k].id, "hidden": traps[k].hidden})
	return {"terrain": terrain, "w": w, "h": h, "units": us, "danger": dz, "traps": tr, "trap_pool": trap_pool, "kills": kills, "traps_found": traps_found, "trap_ids_seen": trap_ids_seen, "time": time, "log": Array(log_lines), "loot": loot,
		"fallen_loot": fallen_loot, "gold_debt": gold_debt, "purse": purse, "xp": xp, "over": over, "won": won, "boss_killed": boss_killed, "uid": _uid, "floor": floor,
		"surprises": surprises, "kill_ids": kill_ids, "auto_used": auto_used, "hp_lost": hp_lost, "potions_drunk": potions_drunk, "dmg_in": dmg_in, "absorbed_total": absorbed_total, "dmg_out": dmg_out, "hero_turns": hero_turns, "last_target": last_target, "remains": remains.keys().map(func(k): return [k.x, k.y]), "trampled": trampled.keys().map(func(k): return [k.x, k.y])}

func from_dict(d: Dictionary) -> void:
	trampled = {}
	remains = {}
	for p in d.get("remains", []): remains[Vector2i(int(p[0]), int(p[1]))] = true
	for p in d.get("trampled", []): trampled[Vector2i(int(p[0]), int(p[1]))] = true
	terrain = []
	for row in d.terrain: terrain.append(row.map(func(t): return int(t)))
	h = terrain.size(); w = terrain[0].size() if h > 0 else SIZE
	if d.has("w"): w = int(d.w)
	if d.has("h"): h = int(d.h)
	units = []
	for u in d.units:
		var x: Dictionary = u.duplicate(true)
		x.pos = Vector2i(int(u.pos[0]), int(u.pos[1]))
		for k in ["uid", "hp", "ht", "dmg", "dr", "barrier", "barrier_max", "charges", "cloak_charges", "cloak_cap", "cooldown", "acts", "exp", "loot", "pump_count", "poison", "search_radius", "stolen", "escape_left", "escape_turns", "hits", "slams", "bombs", "blinks", "abil", "abil_n", "combo", "level"]:
			if x.has(k): x[k] = int(x[k])
		if x.has("sub"): x.sub = String(x.sub)
		if x.has("aim"): x.aim = Vector2i(int(x.aim[0]), int(x.aim[1])) if x.aim is Array else x.aim
		units.append(x)
		if x.has("hero"): hero = x
	_fix_cloak()
	floor = int(d.get("floor", 1))
	danger = []
	for e in d.danger:
		var y: Dictionary = e.duplicate(); y.pos = Vector2i(int(e.pos[0]), int(e.pos[1])); y.dmg = int(e.dmg); y.uid = int(e.uid); danger.append(y)
	traps = {}
	for t in d.get("traps", []): traps[Vector2i(int(t.pos[0]), int(t.pos[1]))] = {"id": t.id, "hidden": t.hidden}
	trap_pool = Array(d.get("trap_pool", trap_pool))
	kills = int(d.get("kills", 0)); traps_found = int(d.get("traps_found", 0)); trap_ids_seen = Array(d.get("trap_ids_seen", []))
	surprises = int(d.get("surprises", 0)); auto_used = bool(d.get("auto_used", false)); hp_lost = int(d.get("hp_lost", 0)); potions_drunk = int(d.get("potions_drunk", 0))
	dmg_in = int(d.get("dmg_in", 0)); absorbed_total = int(d.get("absorbed_total", 0))
	dmg_out = int(d.get("dmg_out", 0)); hero_turns = int(d.get("hero_turns", 0))
	last_target = int(d.get("last_target", 0))
	kill_ids = {}
	var ki: Dictionary = d.get("kill_ids", {})
	for k in ki: kill_ids[String(k)] = int(ki[k])
	time = float(d.time); log_lines = PackedStringArray(d.log); loot = int(d.loot); fallen_loot = int(d.fallen_loot)
	gold_debt = int(d.get("gold_debt", 0)); purse = int(d.get("purse", 0))
	xp = int(d.xp); over = d.over; won = d.won; boss_killed = d.boss_killed; _uid = int(d.uid); events = []

func _next_uid() -> int:
	_uid += 1
	return _uid

func spawn(id: String, p: Vector2i) -> Dictionary:
	var m: Dictionary = DB.mobs[id].duplicate(true)
	m.id = id; m.uid = _next_uid(); m.hp = int(m.ht); m.pos = p; m.next = float(m.delay); m.cooldown = 0; m.acts = 0
	# Encounters start alerted (SPD justAlerted/beckon on the fight's noise): HUNTING towards where the hero stands now.
	# From then on the target cell only updates while the mob can see the hero (DECISIONS #176).
	m.charging = false; m.poison = 0; m.seen_hero = true; m.aim = hero.pos; m.state = "hunting"
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
func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func tile(p: Vector2i) -> int:
	if not in_bounds(p): return T.WALL
	return terrain[p.y][p.x]

func unit_at(p: Vector2i):
	for u in units:
		if u.hp > 0 and u.pos == p: return u
	return null

func unit_by_uid(uid: int):
	if uid <= 0: return null
	for u in units:
		if int(u.uid) == uid and int(u.hp) > 0: return u
	return null

func enemies() -> Array:
	return units.filter(func(u): return not u.has("hero") and u.hp > 0)

## Remember who last hit the hero / who the hero last hit (SPD Char.lastTarget for QuickSlot auto-aim).
func note_last_target(u: Dictionary) -> void:
	if u.is_empty() or u.has("hero") or int(u.get("hp", 0)) <= 0: return
	last_target = int(u.uid)

## SPD QuickSlotButton.autoAim: last attacker if still a clear shot, else the nearest shootable foe. Vector2i(-1,-1) if none.
func auto_bolt_pos() -> Vector2i:
	if not has_ranged(): return Vector2i(-1, -1)
	var lt = unit_by_uid(last_target)
	if lt != null and can_bolt(lt.pos) and bolt_victim(lt.pos) == lt:
		return lt.pos
	var best = null; var bd := 999
	for e in enemies():
		if not can_bolt(e.pos) or bolt_victim(e.pos) != e: continue
		var d := cheb(hero.pos, e.pos)
		if d < bd: bd = d; best = e
	return best.pos if best != null else Vector2i(-1, -1)

func passable(p: Vector2i) -> bool:
	var t := tile(p)
	return t != T.WALL and t != T.CHASM

## SPD Door.leave: a door shuts when nothing stands in it and no heap lies on it. Remains of anything that died
## in the doorway count as a heap and hold it open until some unit passes through it (enters, then leaves);
## after that it shuts whenever it is empty again (DECISIONS #176).
func door_closed(p: Vector2i) -> bool:
	return tile(p) == T.DOOR and unit_at(p) == null and not remains.has(p)

## Terrain that blocks vision (SPD FOV): walls, tall grass, closed doors. Units do not.
func blocks_sight(p: Vector2i) -> bool:
	var t := tile(p)
	return t == T.WALL or t == T.GRASS or door_closed(p)

func visible_trap(p: Vector2i) -> bool:
	return traps.has(p) and not traps[p].hidden

func is_danger(p: Vector2i) -> bool:
	for d in danger:
		if d.pos == p: return true
	return false

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Clear line for vision: no walls, tall grass, or closed doors between a and b.
func sees(a: Vector2i, b: Vector2i) -> bool:
	var pts := _line(a, b)
	for i in range(1, pts.size() - 1):
		if blocks_sight(pts[i]): return false
	return true

## Clear straight-ish line with no walls/units between a and b (bolt/path blockers that include bodies).
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

## Vanilla debuffs on the hero (DECISIONS #155): weak (Weakness: melee x2/3), vuln (Vulnerable: +1/3 damage taken),
## root (Roots/web: moving spends the turn), cripple (Cripple: steps cost 2 ticks). Stored as hero.debuffs[id] = expiry time.
const WEAK_MULT := 0.67
const VULN_MULT := 1.33
const CRIPPLE_MOVE := 2.0
const DEBUFF_NAMES := {"weak": "weakened", "vuln": "vulnerable", "root": "caught in a web", "cripple": "crippled"}
func has_debuff(id: String) -> bool:
	return float(hero.get("debuffs", {}).get(id, -1.0)) > time

func add_debuff(id: String, turns: float) -> void:
	if not hero.has("debuffs"): hero.debuffs = {}
	hero.debuffs[id] = maxf(float(hero.debuffs.get(id, -1.0)), time + turns)
	_log("%s is %s! (%d turns)" % [hero.name, DEBUFF_NAMES.get(id, id), int(turns)]); _ev({"t": "sfx", "name": "debuff"})

## Enemy projectiles (SPD Ballistica PROJECTILE): need sight (walls, closed doors and tall grass block it, #149) and
## stop at the first body, so another mob in the way shields the hero.
func mob_can_shoot(m: Dictionary) -> bool:
	return sees(m.pos, hero.pos) and line_clear(m.pos, hero.pos)

## Evil Eye beam (SPD DisintegrationRay): every tile from the eye through the hero out to BOLT_RANGE, until a wall.
func beam_tiles(from: Vector2i, to: Vector2i) -> Array:
	var d := maxi(1, cheb(from, to)); var k := int(ceil(float(BOLT_RANGE) / d))
	var out := []
	var pts := _line(from, from + (to - from) * k)
	for i in range(1, pts.size()):
		var p: Vector2i = pts[i]
		if cheb(from, p) > BOLT_RANGE or _solid(p): break
		out.append(p)
	return out

func hidden() -> bool:
	return float(hero.hidden_until) > time

## Blind targeting (DECISIONS #149): bows and wands aim at a tile, not a unit, like SPD Ballistica. Any tile in range
## (not a wall) is a valid aim, seen or not. The shot follows the line and hits the first unit on it (STOP_CHARS);
## walls and closed doors stop it (STOP_SOLID); tall grass blocks sight but not shots. Arrows stop at the aimed tile
## (PROJECTILE); wand bolts fly on past it to BOLT_RANGE (MAGIC_BOLT). An empty path wastes the shot.
func can_bolt(target: Vector2i) -> bool:
	if not has_ranged() or not in_bounds(target) or target == hero.pos: return false
	var d := cheb(hero.pos, target)
	if d > BOLT_RANGE or d < 1 or tile(target) == T.WALL: return false
	# Spirit Bow: no point-blank shot (SPD); wands may zap adjacent
	if hero.bolt.get("infinite", false):
		if d <= 1: return false
		var v = bolt_victim(target)
		if v != null and cheb(v.pos, hero.pos) <= 1: return false   # the arrow would be a point-blank shot
	return true

func _solid(p: Vector2i) -> bool:
	return not in_bounds(p) or tile(p) == T.WALL or door_closed(p)

## Where a shot aimed at target lands: the first unit on the line, else the last open tile before a wall/closed
## door, else the aimed tile (arrows) or the end of range (wand bolts).
func bolt_impact(target: Vector2i) -> Vector2i:
	var a: Vector2i = hero.pos
	var far := target
	var magic: bool = not hero.bolt.get("infinite", false)
	if magic:
		var d := maxi(1, cheb(a, target)); var k := int(ceil(float(BOLT_RANGE) / d))
		far = a + (target - a) * k
	var pts := _line(a, far)
	var last := a
	for i in range(1, pts.size()):
		var p: Vector2i = pts[i]
		if cheb(a, p) > BOLT_RANGE or _solid(p): return last
		var u = unit_at(p)
		if u != null and u != hero: return p
		last = p
		if not magic and p == target: return p
	return last

## The unit a shot aimed at target would hit (or null).
func bolt_victim(target: Vector2i):
	var u = unit_at(bolt_impact(target))
	return u if u != hero else null

## Hero sight (for the bot and the UI): an enemy the hero can see right now.
func hero_sees(m: Dictionary) -> bool:
	return sees(hero.pos, m.pos)

## Remember where the hero last saw each enemy (m.last_seen = [x, y]); called whenever it is the hero's turn.
func _note_sightings() -> void:
	for e in enemies():
		if hero_sees(e): e.last_seen = [e.pos.x, e.pos.y]; e.blind_shots = 0

## SPD surprisedBy: cloaked, or the foe lost sight (seen_hero), or they cannot see you right now.
func surprise_against(m: Dictionary) -> bool:
	if hidden(): return true
	if not m.get("seen_hero", true): return true
	return not sees(m.pos, hero.pos)

## True when any living enemy would take a surprise from the next swing.
func surprise_ready() -> bool:
	if hidden(): return true
	for e in enemies():
		if surprise_against(e): return true
	return false

## Status-line check (DECISIONS #163): the hero's next attack really is a Surprise on a foe it can hit right now:
## an adjacent foe for melee, or (Spirit Bow; wand bolts are magic and never surprise) the first body on a clear shot.
func surprise_now() -> bool:
	if over or hero.is_empty(): return false
	var bow: bool = not hero.bolt.is_empty() and hero.bolt.get("infinite", false)
	for e in enemies():
		if e.hp <= 0 or not surprise_against(e): continue
		if can_melee(e) and not hero.get("no_surprise", false): return true
		if bow and can_bolt(e.pos) and bolt_victim(e.pos) == e: return true
	return false

## True when the hero is at critical HP (<= 30% max HP) or adjacent enemies / poison could kill them next turn.
func close_to_dying() -> bool:
	if over or hero.is_empty(): return false
	if int(hero.hp) <= int(ceil(float(hero.ht) * Delve.AUTO_STOP_HP)): return true
	var threat := 1 if int(hero.get("poison", 0)) > 0 else 0
	if not hidden():
		for e in enemies():
			if cheb(e.pos, hero.pos) == 1 and not e.get("charging", false):
				threat += maxi(0, int(e.dmg) - int(hero.dr))
	return threat > 0 and int(hero.hp) + int(hero.barrier) <= threat

# ------------------------------------------------------------------ damage
## Damage to the hero: flat DR -> Barrier -> HP. Chip rule on fully blocked hits.
func hit_hero(raw: int, src: String, pierce := false) -> void:
	if has_debuff("vuln"): raw = int(ceil(raw * VULN_MULT))
	var dmg := raw if pierce else maxi(0, raw - int(hero.dr))
	if pierce and float(hero.get("elem_resist", 1.0)) < 1.0 and dmg > 0: dmg = maxi(1, int(round(dmg * float(hero.elem_resist))))   # Ring of Elements
	if dmg == 0:
		if hero.barrier > 0:
			hero.barrier -= 1; dmg_in += 1; absorbed_total += 1
			_log("%s's hit is blocked (chip: -1 Barrier)." % src)
			_ev({"t": "hit", "uid": hero.uid, "amount": 1, "kind": "chip", "pos": hero.pos})
		else:
			_log("%s's hit is fully blocked." % src)
			_ev({"t": "hit", "uid": hero.uid, "amount": 0, "kind": "block", "pos": hero.pos})
		return
	var absorbed := mini(dmg, int(hero.barrier))
	hero.barrier -= absorbed; dmg_in += dmg; absorbed_total += absorbed
	hero.hp -= dmg - absorbed; hp_lost += dmg - absorbed
	_log("%s hits for %d (%d Barrier, %d HP)." % [src, dmg, absorbed, dmg - absorbed])
	_ev({"t": "hit", "uid": hero.uid, "amount": dmg, "kind": "hp" if dmg > absorbed else "barrier", "pos": hero.pos})
	if hero.hp <= 0:
		hero.hp = 0; over = true; won = false
		_log("%s falls..." % hero.name)
		_ev({"t": "die", "uid": hero.uid, "pos": hero.pos})

## sure: the blow can't be slipped (an unaware snake, or an accurate weapon's catch, DECISIONS #207).
func hit_mob(m: Dictionary, raw: int, surprise := false, magic := false, ranged := false, sure := false) -> void:
	var dmg: int
	if surprise:
		dmg = int(raw * float(hero.surprise_mult))
		if not magic:
			var eff_dr := int(m.dr)
			if (not ranged and int(hero.get("sur_bonus", 0)) > 0) or String(hero.get("sub", "")) == "assassin":
				eff_dr /= 2
			# Warden bow: 50% pierce on surprise (or grass — handled below for non-surprise)
			elif ranged and String(hero.get("sub", "")) == "warden":
				eff_dr /= 2
			dmg = maxi(1, dmg - eff_dr)
	elif magic: dmg = raw
	else:
		var eff_dr2 := int(m.dr)
		if ranged and String(hero.get("sub", "")) == "warden" and (tile(hero.pos) == T.GRASS or trampled.has(hero.pos)):
			eff_dr2 /= 2
		dmg = maxi(0, raw - eff_dr2)
	# Snakes (SPD evasion): melee only connects on a surprise; magic never misses (SPD);
	# a bow shot is slipped once per fight, then connects (DECISIONS #172)
	var snake_slips: bool = m.get("evade_unless_surprise", false) and not surprise and not magic and not sure
	if snake_slips and ranged and m.get("slipped_shot", false): snake_slips = false
	if snake_slips and ranged: m.slipped_shot = true
	if snake_slips:
		_log("%s slips aside!" % m.name)
		_ev({"t": "hit", "uid": m.uid, "amount": 0, "kind": "block", "pos": m.pos})
		return
	# King of Dwarves lifelink (SPD): while his risen dwarves live, he takes 2/3 damage (DECISIONS #79)
	if m.get("ability", "") == "dking" and dmg > 0 and _king_linked():
		dmg = int(ceil(dmg * 2.0 / 3.0))
		_log("The lifelink absorbs a third of the blow!")
	if m.get("ability", "") == "yog":   # Yog-Dzewa phases (DECISIONS #87)
		_yog_phase(m)
		if _yog_shielded():
			if dmg > 0: _log("Yog-Dzewa is shielded by its fist! Destroy the fist first.")
			dmg = 0
	dmg_out += mini(maxi(0, dmg), maxi(0, int(m.hp)))
	m.hp -= dmg
	if m.get("ability", "") == "yog":   # can't skip a phase: damage stops at the next fist's threshold
		var p := int(m.get("phase", 0))
		var floor_hp := int(ceil(int(m.ht) * (3 - p) / 3.0)) if p < 3 else 0
		if p in [1, 2] and m.hp < floor_hp:
			m.hp = floor_hp
		_yog_phase(m)
	if surprise: surprises += 1
	_log("%s%s takes %d." % ["SURPRISE! " if surprise else "", m.name, dmg])
	_ev({"t": "hit", "uid": m.uid, "amount": dmg, "kind": "surprise" if surprise else ("magic" if magic else "hp"), "pos": m.pos})
	# Hitting a fleeing thief resets its escape countdown (DECISIONS: steal-and-flee).
	if int(m.get("stolen", 0)) > 0 and m.hp > 0:
		m.escape_left = int(m.get("escape_turns", 4))
	if m.hp <= 0:
		_kill(m, false)
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
		_left(m.pos); m.pos = dest
		_ev({"t": "move", "uid": m.uid, "from": from, "to": dest})
		_ev({"t": "sfx", "name": "falling"})
		_log("%s is knocked into the chasm!" % m.name)
		_kill(m, true)
	elif t == T.WALL or unit_at(dest) != null:
		if m.get("evade_unless_surprise", false):
			_log("%s slips past the obstacle." % m.name)
		else:
			m.hp -= 1
			_log("%s slams into an obstacle (1)." % m.name)
			_ev({"t": "hit", "uid": m.uid, "amount": 1, "kind": "hp", "pos": m.pos})
			if m.hp <= 0: _kill(m, false)
	else:
		_place(m, dest)

## Fight-start artifact effects (DECISIONS #159): Hourglass freezes, Ethereal Chains drag one far foe close.
func _artifact_openers(hs: Dictionary) -> void:
	var fz := float(hs.get("freeze_start", 0.0))
	if fz > 0.0:
		for e in enemies():
			if not e.get("boss", false): e.next = float(e.next) + fz
		_log("Time slows around you.")
	if hs.get("chain_pull", false):
		var best = null
		for e in enemies():
			if e.get("boss", false) or cheb(e.pos, hero.pos) < 3: continue
			if best == null or cheb(e.pos, hero.pos) < cheb(best.pos, hero.pos): best = e
		if best != null:
			for d in DIRS:
				var q: Vector2i = hero.pos + d
				if passable(q) and unit_at(q) == null and not traps.has(q):
					_ev({"t": "move", "uid": best.uid, "from": best.pos, "to": q}); _left(best.pos); best.pos = q
					best.next = float(best.next) + float(hs.get("chain_root", 0.0))
					_log("Ethereal chains drag %s to you." % best.name); break

## Next-fight effects from vanilla potions and scrolls (DECISIONS #161).
func apply_fx(fx: Dictionary) -> void:
	var foes: Array = enemies().filter(func(e): return not e.get("boss", false))
	if fx.has("invis"): hero.hidden_until = float(fx.invis); _log("You start the fight unseen.")
	if fx.has("haste"):
		for e in enemies(): e.next = float(e.next) + float(fx.haste)
		_log("You move in a blur.")
	if fx.has("levitate"): hero.levitate = true; _log("You float above the floor.")
	if fx.has("frozen"): hero.next = float(hero.next) + float(fx.frozen); _log("You can't move yet!")
	if fx.has("recharge"):
		if not hero.bolt.is_empty() and not hero.bolt.get("infinite", false): hero.charges = int(hero.charges) + int(fx.recharge)
		# a cloak charge like any other: never above the cap, kept until spent (DECISIONS #211)
		if not hero.cloak.is_empty(): hero.cloak_charges = mini(int(hero.cloak_charges) + int(fx.recharge), maxi(int(hero.cloak_charges), int(hero.get("cloak_cap", 0))))
	if fx.has("sleep"):
		for e in foes: e.next = float(e.next) + float(fx.sleep)
		_log("Your foes are drowsy.")
	if fx.has("terror"):
		for e in foes:
			knockback(e, e.pos - hero.pos)
			if e.hp > 0: e.next = float(e.next) + 1.0
		_log("Your foes recoil in terror!")
	if fx.has("retrib"):
		var dmg := maxi(2, (int(hero.ht) - int(hero.hp)) / 2)
		for e in foes:
			if e.hp > 0: hit_mob(e, dmg, false, true)
		_log("Retribution!")

## Move a unit (hero or mob) and fire any trap on the destination tile.
## A unit leaves cell p. Passing through a door that remains were holding open clears them: it shuts normally
## from then on (DECISIONS #176). The dead unit never leaves, so remains alone keep the door open.
func _left(p: Vector2i) -> void:
	if remains.has(p): remains.erase(p)

func _place(u: Dictionary, dest: Vector2i) -> void:
	_ev({"t": "move", "uid": u.uid, "from": u.pos, "to": dest})
	_left(u.pos); u.pos = dest
	if u == hero and tile(dest) == T.GRASS and float(hero.get("grass_root", 0.0)) > 0.0:   # Sandals of Nature (DECISIONS #159)
		for e in enemies():
			if cheb(e.pos, dest) == 1: e.next = float(e.next) + float(hero.grass_root); _log("Roots grip %s." % e.name)
	if tile(dest) == T.GRASS:
		terrain[dest.y][dest.x] = T.FLOOR; trampled[dest] = true
		_ev({"t": "trample", "pos": dest})
	if u == hero and hero.get("keen_eyes", false): _reveal(dest, 1, false)
	if traps.has(dest): _trigger(dest, u)

func _trigger(p: Vector2i, u: Dictionary) -> void:
	if u == hero and hero.get("levitate", false): return   # Potion of Levitation (DECISIONS #161)
	var tid: String = String(traps[p].id)
	var tr: Dictionary = DB.traps[tid]
	if not (tid in trap_ids_seen): trap_ids_seen.append(tid)
	traps.erase(p)
	_log("%s triggers a %s!" % [u.name, tr.name])
	_ev({"t": "trap", "pos": p}); _ev({"t": "sfx", "name": "trap"})
	var is_hero := u == hero
	if tr.has("dmg"):
		# Worn Dart scales with floor; gripping / poison keep their flat hit (DECISIONS #220)
		var tdmg := int(tr.dmg) + (int(floor) / 2 if tid == "worn_dart" else 0)
		if is_hero: hit_hero(tdmg, tr.name)
		else: _trap_hit(u, tdmg)
	if u.hp <= 0: return
	if tr.has("root"):
		u.next = float(u.next) + float(tr.root); _log("%s is held fast." % u.name)
	if tr.has("poison"):
		u.poison = int(u.get("poison", 0)) + int(tr.poison); _ev({"t": "sfx", "name": "debuff"})
	if tr.get("teleport", false):
		var far := _farthest_free(hero.pos if not is_hero else _nearest_enemy_pos())
		_ev({"t": "sfx", "name": "teleport"})
		_ev({"t": "move", "uid": u.uid, "from": u.pos, "to": far, "blink": true})
		_left(u.pos); u.pos = far

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
		hero.hp -= 1; hp_lost += 1
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
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if not passable(c) or unit_at(c) != null or traps.has(c) or is_danger(c): continue
			if cheb(c, from) > bd: bd = cheb(c, from); best = c
	return best

func _kill(m: Dictionary, chasm: bool) -> void:
	m.hp = 0
	kills += 1
	kill_ids[String(m.id)] = int(kill_ids.get(String(m.id), 0)) + 1
	if not chasm and tile(m.pos) == T.DOOR: remains[m.pos] = true
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
			if e.get("summoned", false) or e.get("fist", false):
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
	# SPD reach weapons (Spear, Glaive, Whip): a seen foe within reach is a melee swing, not a shot (DECISIONS #207)
	if mode != "bolt" and mode != "shove" and u != null and u != hero and cheb(p, hero.pos) > 1 and can_melee(u):
		_hero_melee(u, p)
		return true
	# distant enemy, or (Spirit Bow) any distant tile: shoot; wands need Bolt mode for an empty tile
	if mode == "bolt" or (cheb(p, hero.pos) > 1 and ((u != null and u != hero) or hero.bolt.get("infinite", false))):
		return hero_bolt(p)
	if cheb(p, hero.pos) != 1: return false
	if u != null and u != hero:
		if mode == "shove":
			_log("%s shoves %s." % [hero.name, u.name])
			_ev({"t": "sfx", "name": "hit_crush"})
			knockback(u, p - hero.pos)
			_end_hero_turn(1.0)
			return true
		_hero_melee(u, p)
		return true
	if passable(p) and u == null:
		if has_debuff("root"):
			_log("%s struggles against the web." % hero.name)
			_end_hero_turn(1.0)
			return true
		_place(hero, p)
		_end_hero_turn(CRIPPLE_MOVE if has_debuff("cripple") else float(hero.get("move_cost", 1.0)))   # Ring of Haste; Cripple costs 2
		return true
	return false

## One melee swing at u (adjacent or within reach). Accuracy is deterministic (DECISIONS #207): an alert foe dodges a
## fixed share (1 - acc) of an inaccurate weapon's swings (Sickle, Flail, War Scythe); a dodging snake is caught by a
## fixed share (acc - 1) of an accurate weapon's swings (Cudgel, Hand Axe, Mace, Battle Axe, War Hammer). An unaware
## foe can't dodge at all (SPD: defenseSkill 0 when surprised), so a Flail still lands on it, without the Surprise bonus.
func _hero_melee(u: Dictionary, p: Vector2i) -> void:
	_ev({"t": "attack", "uid": hero.uid, "to": p})
	var unaware := surprise_against(u)
	var sur: bool = unaware and not hero.get("no_surprise", false)
	_break_cloak()
	var a := float(hero.get("acc", 1.0))
	var sure := false
	if not unaware and a < 1.0:
		hero.acc_miss = float(hero.get("acc_miss", 0.0)) + (1.0 - a)
		if hero.acc_miss >= 1.0 - 0.0001:
			hero.acc_miss -= 1.0
			_log("%s dodges %s's attack." % [u.name, hero.name])
			_ev({"t": "hit", "uid": u.uid, "amount": 0, "kind": "miss", "pos": u.pos})
			reveal_to(u); _end_hero_turn(float(hero.delay))
			return
	if not unaware and a > 1.0 and u.get("evade_unless_surprise", false):
		hero.acc_catch = float(hero.get("acc_catch", 0.0)) + (a - 1.0)
		if hero.acc_catch >= 1.0 - 0.0001: hero.acc_catch -= 1.0; sure = true
	hit_mob(u, _melee_dmg(sur), sur, false, false, sure or unaware)
	note_last_target(u)
	reveal_to(u)
	_melee_perks()
	_end_hero_turn(float(hero.delay))

## SPD KindOfWeapon.canReach: within the weapon's reach (Chebyshev), in sight, and a path of at most `reach` steps over
## open, unoccupied tiles (walls and closed doors block, chasms don't). Adjacent foes are always in reach.
func can_melee(m: Dictionary) -> bool:
	if hero.is_empty() or m.is_empty() or m.get("hp", 0) <= 0: return false
	var d := cheb(m.pos, hero.pos)
	if d == 1: return true
	var r := int(hero.get("reach", 1))
	if d < 1 or d > r or not hero_sees(m): return false
	var seen := {hero.pos: 0}; var q := [hero.pos]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var k := int(seen[c])
		if k >= r: continue
		for dd in DIRS:
			var n: Vector2i = c + dd
			if seen.has(n): continue
			if n == m.pos: return true
			if _solid(n) or unit_at(n) != null: continue
			seen[n] = k + 1; q.append(n)
	return false

## Living foes the hero can swing at this turn (adjacent or within the weapon's reach).
func in_reach() -> Array:
	return enemies().filter(func(e): return can_melee(e))

## Copy the SPD weapon properties from hero stats into the fight (setup and mid-fight swaps).
func _weapon_stats(hs: Dictionary) -> void:
	hero.reach = int(hs.get("reach", 1)); hero.acc = float(hs.get("acc", 1.0))
	hero.sur_bonus = int(hs.get("sur_bonus", 0)); hero.no_surprise = bool(hs.get("no_surprise", false))

## Attacking reveals you (SPD: a struck mob is alerted and hunts the attacker): the target sees you again, so the
## next swing is not a Surprise unless you break sight again (DECISIONS #177).
func reveal_to(m: Dictionary) -> void:
	if m.hp <= 0 or hidden(): return
	m.seen_hero = true; m.aim = hero.pos; m.state = "hunting"

## Subclass perks (DECISIONS #61)
func _melee_dmg(sur := false) -> int:
	var d := int(hero.dmg) + (int(hero.get("sur_bonus", 0)) if sur else 0)
	match hero.get("perk", ""):
		"rage":
			if int(hero.hp) * 2 < int(hero.ht): d = int(d * 1.2)
		"combo":
			var stacks := mini(int(hero.combo), 3)
			d += maxi(stacks, int(d * 0.10 * stacks))
	if has_debuff("weak"): d = maxi(1, int(d * WEAK_MULT))
	return d

func _melee_perks() -> void:
	match hero.get("perk", ""):
		"combo": hero.combo = int(hero.combo) + 1
		"battle_recharge":
			hero.combo = int(hero.combo) + 1
			if hero.combo % 3 == 0 and not hero.bolt.is_empty() and int(hero.charges) < int(hero.bolt.charges):
				hero.charges += 1; _log("The staff hums: +1 charge.")

func hero_bolt(p: Vector2i) -> bool:
	if not can_bolt(p): return false
	var magic: bool = hero.bolt.get("magic", true)
	if not hero.bolt.get("infinite", false): hero.charges -= 1
	var at := bolt_impact(p)
	var u = bolt_victim(p)
	_log("%s fires %s." % [hero.name, hero.bolt.name])
	_ev({"t": "bolt", "from": hero.pos, "to": at, "magic": magic})
	var sur: bool = u != null and surprise_against(u) and not magic
	for e in enemies():   # a blind shot at where an unseen foe was last seen (CombatBot caps these)
		if not hero_sees(e) and e.has("last_seen") and Vector2i(int(e.last_seen[0]), int(e.last_seen[1])) == p:
			e.blind_shots = int(e.get("blind_shots", 0)) + 1
	_break_cloak()
	if u == null:
		_log("The shot hits nothing.")
		if hero.bolt.get("burns_grass", false) and tile(at) == T.GRASS: _burn(at)
		if hero.bolt.has("reveal") and _reveal(at, int(hero.bolt.reveal)) > 0: _log("Prismatic light shows hidden traps.")
		if hero.bolt.get("grow", false): _grow(at)
		_end_hero_turn(1.0)
		return true
	p = at
	var hp_before := int(u.hp)
	hit_mob(u, int(hero.bolt.dmg), sur, magic or hero.bolt.get("pierce", false), true)
	note_last_target(u)
	reveal_to(u)
	if hero.get("perk", "") == "soul_heal" and magic and hero.hp > 0 and hero.hp < hero.ht:
		var sh := mini(int(hero.ht) - int(hero.hp), maxi(1, (hp_before - maxi(0, int(u.hp))) / 3))
		hero.hp += sh; _log("Soul siphon: +%d HP." % sh)
	_wand_effects(u, p)
	if hero.bolt.get("chains_water", false) and tile(p) == T.WATER:
		_shock(p, int(hero.bolt.dmg))
	if hero.bolt.get("burns_grass", false):
		for d in [Vector2i.ZERO] + DIRS:
			if tile(p + d) == T.GRASS: _burn(p + d); break
	_end_hero_turn(1.0)
	return true

## Vanilla wand effects (DECISIONS #156), applied after the bolt's damage to the unit it hit (u) at p.
func _wand_effects(u: Dictionary, p: Vector2i) -> void:
	var b: Dictionary = hero.bolt
	if b.get("pierce_line", false):   # Disintegration: every other enemy on the line beyond the first body
		var d := maxi(1, cheb(hero.pos, p)); var far: Vector2i = hero.pos + (p - hero.pos) * int(ceil(float(BOLT_RANGE) / d))
		var pts := _line(hero.pos, far)
		for i in range(1, pts.size()):
			var q: Vector2i = pts[i]
			if cheb(hero.pos, q) > BOLT_RANGE or _solid(q): break
			var o = unit_at(q)
			if q != p and o != null and o != hero and o.hp > 0: hit_mob(o, int(b.dmg), false, true)
	if b.has("transfuse") and hero.hp < hero.ht:
		var hl := mini(int(hero.ht) - int(hero.hp), int(b.transfuse))
		hero.hp += hl; _log("Transfusion: +%d HP." % hl)
	if b.has("reveal") and _reveal(p, int(b.reveal)) > 0: _log("Prismatic light shows hidden traps.")
	if b.get("grow", false): _grow(p)
	if u.hp <= 0: return
	if b.has("chill"):
		u.next = float(u.next) + float(b.chill); _log("%s is chilled." % u.name); _ev({"t": "sfx", "name": "debuff"})
	if b.has("corrode"):
		u.poison = int(u.get("poison", 0)) + int(b.corrode); _log("%s is corroded." % u.name); _ev({"t": "sfx", "name": "debuff"})
	if b.has("root"):
		u.next = float(u.next) + float(b.root); _log("%s is rooted." % u.name)
	if b.has("blast") and not u.get("boss", false):
		for i in int(b.blast):
			if u.hp <= 0: break
			var before: Vector2i = u.pos
			knockback(u, u.pos - hero.pos)
			if u.pos == before: break
	elif b.has("blast"): _log("%s is too heavy to move." % u.name)

## Regrowth: tall grass springs up on open floor around p (blocks sight, not shots).
func _grow(p: Vector2i) -> void:
	for d in [Vector2i.ZERO] + DIRS:
		var q: Vector2i = p + d
		if in_bounds(q) and tile(q) == T.FLOOR and not traps.has(q):
			terrain[q.y][q.x] = T.GRASS; _ev({"t": "grow", "pos": q})

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

## A fight saved before DECISIONS #206 has no cloak_cap and may hold the old bonus charges (an Assassin's 4/3):
## give it the class cap and clamp the charges to it (#211).
func _fix_cloak() -> void:
	if hero.get("cloak", {}).is_empty(): return
	if int(hero.get("cloak_cap", 0)) <= 0:
		var cap := 0
		for k in DB.heroes:
			cap = maxi(cap, int(DB.heroes[k].get("cloak_charges", 0)))
		hero.cloak_cap = cap
	hero.cloak_charges = clampi(int(hero.get("cloak_charges", 0)), 0, int(hero.cloak_cap))

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
	hero.sub = String(hs.get("sub", "")); hero.level = int(hs.get("level", 1))
	hero.perk = String(hs.get("perk", hero.get("perk", "")))
	_weapon_stats(hs)
	hero.acc_miss = 0.0; hero.acc_catch = 0.0   # the miss / catch rhythm belongs to the weapon in hand (#207)
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

## Barrier segments on the HP bars (DECISIONS #210): how much Barrier one enemy hit takes right now.
## hit_hero spends the post-DR damage from Barrier, or 1 (the chip rule) when DR blocks the whole hit, so a
## hit costs max(1, dmg - DR) (x VULN_MULT while vulnerable). We use the hardest-hitting living enemy, so the
## segment count is the number of hits the Barrier is sure to stop. No enemies left = the chip size 1.
func barrier_hit_size() -> int:
	if hero.is_empty(): return 1
	var best := 1
	for e in enemies():
		if int(e.hp) <= 0: continue
		var raw := int(e.get("dmg", 0))
		if has_debuff("vuln"): raw = int(ceil(raw * VULN_MULT))
		best = maxi(best, raw - int(hero.dr))
	return best

const BARRIER_SEG_CAP := 10
## Segments for `barrier` Barrier against hits of `hit`: ceil(barrier / hit), capped at BARRIER_SEG_CAP; 0 = no blue.
static func barrier_segments(barrier: int, hit: int) -> int:
	if barrier <= 0: return 0
	return mini(BARRIER_SEG_CAP, int(ceil(float(barrier) / float(maxi(1, hit)))))

func barrier_hits() -> int:
	return barrier_segments(int(hero.get("barrier", 0)), barrier_hit_size())

## SPD Barrier decay (Barrier.act): each turn loses min(1, shield/20) of a point (DECISIONS #134).
const BARRIER_DECAY_DIV := 20.0
func _decay_barrier(cost: float) -> void:
	if int(hero.barrier) <= 0: hero.bar_partial = 0.0; return
	var p := float(hero.get("bar_partial", 0.0)) + minf(1.0, float(hero.barrier) / BARRIER_DECAY_DIV) * cost
	while p >= 1.0 and int(hero.barrier) > 0:
		hero.barrier -= 1; p -= 1.0
	hero.bar_partial = p

func _end_hero_turn(cost: float) -> void:
	hero_turns += 1
	hero.next += cost
	_decay_barrier(cost)
	if hero.get("perk", "") == "grass_heal" and (tile(hero.pos) == T.GRASS or trampled.has(hero.pos)) and hero.hp < hero.ht:
		hero.hp = mini(int(hero.ht), int(hero.hp) + 1 + int(hero.get("level", 1)) / 8)
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
	_note_sightings()

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
			_ev({"t": "blast", "pos": d.pos, "uid": int(d.get("uid", 0)), "src": String(d.get("src", "")), "debuff": String(d.get("debuff", ""))})   # caster + source only feed the zap visual
			if d.has("leap"):   # Ripper Demon lands (on the tile, or next to it if taken)
				var lm = null
				for e in enemies():
					if e.uid == int(d.uid): lm = e
				if lm != null:
					var lp: Vector2i = d.pos if unit_at(d.pos) == null else _adjacent_free(d.pos, lm.pos)
					if lp.x >= 0: _place(lm, lp)
			if hero.pos == d.pos:
				var dd := int(d.dmg)
				if float(d.get("water_mult", 0.0)) > 0.0 and tile(hero.pos) == T.WATER:
					dd = int(dd * float(d.water_mult)); _log("The water conducts the shock!")
				if dd > 0:
					var atk = unit_by_uid(int(d.get("uid", 0)))
					if atk != null: note_last_target(atk)
					hit_hero(dd, d.src, d.get("pierce", false))
				if d.has("debuff") and not over: add_debuff(String(d.debuff), float(d.get("debuff_t", 3)))
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
	# SPD: enemySeen / FOV at the start of the turn (door closes behind hero → surprise next swing)
	var in_view := not hidden() and sees(m.pos, hero.pos)
	m.seen_hero = in_view
	# SPD Hunting/Wandering: the target cell tracks the hero only while in FOV; a wandering mob that sees the hero
	# starts hunting again. Out of sight it keeps the last cell it saw the hero on (DECISIONS #176).
	if in_view: m.aim = hero.pos; m.state = "hunting"
	elif not m.has("aim"): m.aim = m.pos; m.state = "wandering"
	# SPD Goo: regenerates while standing in water (DECISIONS #131)
	if int(m.get("water_heal", 0)) > 0 and tile(m.pos) == T.WATER and int(m.hp) < int(m.ht):
		var wh := mini(int(m.water_heal), int(m.ht) - int(m.hp)); m.hp += wh
		_ev({"t": "heal", "uid": m.uid, "amount": wh, "pos": m.pos}); _log("%s soaks up the water (+%d)." % [m.name, wh])
	if m.has("enraged_dmg") and int(m.hp) * 2 <= int(m.ht) and int(m.dmg) != int(m.enraged_dmg):
		m.dmg = int(m.enraged_dmg); _log("%s is enraged! (dmg %d)" % [m.name, m.dmg])
	if m.has("hp_flee") and int(m.get("stolen", 0)) > 0:
		_flee(m); return
	match m.get("ability", ""):
		"throw":
			var rng: Array = m.throw_range
			if in_view and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= int(rng[0]) and cheb(m.pos, hero.pos) <= int(rng[1]) and mob_can_shoot(m):
				danger.append({"pos": hero.pos, "dmg": int(m.dmg) + int(m.throw_bonus), "at": m.next + 1.0, "src": m.name + "'s spear", "uid": m.uid})
				m.cooldown = int(m.throw_cooldown)
				_log("%s winds up a throw! (red tile)" % m.name)
				_ev({"t": "telegraph", "uid": m.uid})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"zap":
			# DM-100: telegraphed lightning bolt (ignores DR); conducts through water to the hero
			if in_view and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 2 and cheb(m.pos, hero.pos) <= 4 and (m.get("zap_beam", false) or mob_can_shoot(m)):
				var zd := {"pos": hero.pos, "dmg": int(m.zap_dmg), "at": m.next + 1.0, "src": m.name + "'s lightning", "uid": m.uid, "pierce": m.get("zap_magic", false)}
				if m.has("zap_water"): zd.water_mult = float(m.zap_water)
				var dbs: Array = m.get("zap_debuffs", [])
				if not dbs.is_empty(): zd.debuff = dbs[int(m.uid) % dbs.size()]; zd.debuff_t = 3   # shaman colour by uid (red weak / blue vuln)
				if m.get("zap_beam", false):   # Evil Eye: the whole line lights up; step off it
					for bp in beam_tiles(m.pos, hero.pos):
						var bd: Dictionary = zd.duplicate(); bd.pos = bp; bd.src = m.name + "'s beam"; danger.append(bd)
					m.charging = true
				else:
					danger.append(zd)
				m.cooldown = int(m.zap_cooldown)
				_log("%s crackles with energy! (red tile)" % m.name)
				_ev({"t": "telegraph", "uid": m.uid}); _ev({"t": "sfx", "name": "chargeup"})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"web":
			# SPD Spinner: shoots a web; the hero is rooted for web_root turns (still able to attack)
			var wr: Array = m.web_range; var wdist := cheb(m.pos, hero.pos)
			if in_view and m.cooldown <= 0 and wdist >= int(wr[0]) and wdist <= int(wr[1]) and mob_can_shoot(m):
				danger.append({"pos": hero.pos, "dmg": 0, "at": m.next + 1.0, "src": m.name + "'s web", "uid": m.uid, "debuff": "root", "debuff_t": int(m.web_root)})
				m.cooldown = int(m.web_cooldown)
				_log("%s spits a web! (red tile)" % m.name); _ev({"t": "telegraph", "uid": m.uid})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"blink":
			# SPD Succubus: blinks next to a hero it sees at range 3+
			# only into an open duel: never when another enemy is already next to the hero (no double-blink ganks)
			if in_view and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 3 and enemies().filter(func(e): return cheb(e.pos, hero.pos) == 1).is_empty():
				var bp := _adjacent_free(hero.pos, m.pos)
				if bp.x >= 0:
					m.cooldown = int(m.blink_cooldown)
					_log("%s blinks to your side!" % m.name); _ev({"t": "sfx", "name": "teleport"})
					_ev({"t": "move", "uid": m.uid, "from": m.pos, "to": bp}); _left(m.pos); m.pos = bp
					return
			m.cooldown = maxi(0, m.cooldown - 1)
		"leap":
			# SPD Ripper Demon: telegraphed leap onto the hero's tile from range 2-4 (hits, then lands there)
			var lr: Array = m.leap_range; var ld := cheb(m.pos, hero.pos)
			if in_view and m.cooldown <= 0 and ld >= int(lr[0]) and ld <= int(lr[1]) and line_clear(m.pos, hero.pos):
				danger.append({"pos": hero.pos, "dmg": int(m.dmg), "at": m.next + 1.0, "src": m.name + "'s leap", "uid": m.uid, "leap": true})
				m.cooldown = int(m.leap_cooldown); m.charging = true
				_log("%s crouches to leap! (red tile)" % m.name); _ev({"t": "telegraph", "uid": m.uid})
				return
			m.cooldown = maxi(0, m.cooldown - 1)
		"teleport":
			# SPD Golem: pulls a hero it sees at range 3+ to its side (teleport), so slowness isn't a free kite
			if in_view and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 3:
				var tp := _adjacent_free(m.pos, hero.pos)
				if tp.x >= 0:
					m.cooldown = int(m.tele_cooldown)
					_log("%s's runes flare - you are pulled to it!" % m.name); _ev({"t": "sfx", "name": "teleport"})
					_place(hero, tp)
					return
			m.cooldown = maxi(0, m.cooldown - 1)
		"chain":
			# Prison Guard: once per fight, yanks the hero next to it
			if in_view and m.cooldown <= 0 and cheb(m.pos, hero.pos) >= 2 and cheb(m.pos, hero.pos) <= 3:
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
	# (cloaked hero: in_view is false, so the mob walks to where it last saw the hero, like SPD invisibility)
	if in_view and cheb(m.pos, hero.pos) == 1:
		_ev({"t": "attack", "uid": m.uid, "to": hero.pos})
		var hp_before: int = hero.hp + hero.barrier
		note_last_target(m)
		hit_hero(int(m.dmg), m.name)
		if int(hero.get("thorns", 0)) > 0 and m.hp > 0 and hero.hp > 0:   # Cape of Thorns (DECISIONS #159)
			_log("Thorns!"); hit_mob(m, int(hero.thorns), false, true)
		var dealt: int = hp_before - (hero.hp + hero.barrier)
		# SPD Bat.attackProc: heals (damage dealt - 4); our bat hits at half damage twice as often, so -2 (DECISIONS #148)
		var heal := dealt - int(m.drain_over) if m.has("drain_over") else (int(m.get("drain", 0)) if dealt > 0 else 0)
		if heal > 0 and m.hp < m.ht:
			var h := mini(heal, int(m.ht) - int(m.hp)); m.hp += h
			_ev({"t": "heal", "uid": m.uid, "amount": h, "pos": m.pos}); _log("%s drinks your blood (+%d)." % [m.name, h])
		if m.has("bite_poison") and dealt > 0 and not over:
			hero.poison = int(hero.get("poison", 0)) + int(m.bite_poison); _log("The bite is venomous!"); _ev({"t": "sfx", "name": "debuff"})
		if m.has("bite_cripple") and dealt > 0 and not over: add_debuff("cripple", float(m.bite_cripple))
		if m.has("disarm_every") and not over:   # SPD Monk: knocks your weapon aside (melee weakened)
			m.hits = int(m.get("hits", 0)) + 1
			if m.hits % int(m.disarm_every) == 0:
				_log("%s knocks your weapon aside!" % m.name); add_debuff("weak", float(m.disarm_t))
		if m.get("ability", "") == "steal" and int(m.get("stolen", 0)) == 0 and not over:
			var amt := _steal_amount(m)
			if amt > 0:
				m.stolen = amt
				m.escape_left = int(m.get("escape_turns", 4))
				_log("%s snatches %d gold and runs! Hit it within %d turns or it escapes with the gold." % [m.name, m.stolen, int(m.escape_left)])
				_ev({"t": "sfx", "name": "gold"})
		return
	if m.get("stationary", false): return   # Yog-Dzewa never moves
	# SPD casters (shaman, warlock, Bright Fist): with a clear shot in range they hold position instead
	# of closing to melee, and reload there (DECISIONS #155)
	if m.get("holds_range", false) and in_view and _in_shot_range(m) and (m.get("zap_beam", false) or mob_can_shoot(m)):
		return
	if not in_view and m.get("state", "hunting") == "wandering":
		return   # lost the hero: searches where it gave up (SPD wanders to a random cell; we have no RNG)
	var target: Vector2i = hero.pos if in_view else m.aim
	var step = mob_step(m, target)
	if step != null:
		_place(m, step)
	elif not in_view:
		# SPD handleUnreachableTarget: reached the target cell (or can't get closer) without seeing the hero
		m.state = "wandering"
		_log("%s has lost track of you." % m.name); _ev({"t": "lost", "uid": m.uid})

## SPD Mob.getCloser: the next step towards target (the cell itself; an occupied target is approached to adjacent).
## Full path routes around other characters; if they force a route more than twice as long as the path ignoring
## them, it assumes the blockage is temporary and waits instead (null). Mobs know every trap.
func mob_step(m: Dictionary, target: Vector2i):
	if target == m.pos: return null
	if cheb(m.pos, target) == 1:
		return target if passable(target) and unit_at(target) == null and not traps.has(target) else null
	var full = _mob_path(m.pos, target, true)
	var free = _mob_path(m.pos, target, false)
	var path = full
	if free != null and (full == null or full.size() > 2 * free.size()):
		path = free
		if unit_at(path[0]) != null: return null
	if path == null or path.is_empty(): return null
	return path[0]

## Shortest 8-way path (BFS, DIRS order breaks ties, so it is predictable) from `from` to target, excluding `from`.
## A path may end on, or next to, an occupied target. chars: other characters block cells.
func _mob_path(from: Vector2i, target: Vector2i, chars: bool):
	var prev := {from: from}
	var q := [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == target or (c != from and cheb(c, target) == 1 and unit_at(target) != null):
			var out := []
			while c != from: out.push_front(c); c = prev[c]
			return out
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not passable(n) or traps.has(n): continue
			if chars and n != target and unit_at(n) != null: continue
			prev[n] = c; q.append(n)
	return null

func _in_shot_range(m: Dictionary) -> bool:
	var d := cheb(m.pos, hero.pos)
	if m.has("throw_range"): return d >= int(m.throw_range[0]) and d <= int(m.throw_range[1])
	return d >= 2 and d <= 4

## A free, passable, trap-free tile next to `around`, closest to `toward` (or Vector2i(-1, -1)).
func _adjacent_free(around: Vector2i, toward: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1); var bd := 999
	for d in DIRS:
		var n: Vector2i = around + d
		if passable(n) and unit_at(n) == null and not traps.has(n) and cheb(n, toward) < bd: bd = cheb(n, toward); best = n
	return best

## Pack gold the thief grabs: steal_pct of purse at fight start, at least 1 if you have any.
func _steal_amount(m: Dictionary) -> int:
	if purse <= 0: return 0
	return mini(purse, maxi(1, int(purse * float(m.get("steal_pct", 0.05)))))

## Thief: after stealing, runs to the tile farthest from the hero. Each flee act burns one
## escape_left; if the hero never lands a hit before it hits 0, the thief escapes with the gold.
func _flee(m: Dictionary) -> void:
	m.escape_left = int(m.get("escape_left", 0)) - 1
	if int(m.escape_left) <= 0:
		_escape(m); return
	var best = null; var bd := cheb(m.pos, hero.pos)
	for d in DIRS:
		var n: Vector2i = m.pos + d
		if passable(n) and unit_at(n) == null and not traps.has(n) and cheb(n, hero.pos) > bd: bd = cheb(n, hero.pos); best = n
	if best != null: _place(m, best)
	elif cheb(m.pos, hero.pos) == 1:
		note_last_target(m)
		hit_hero(int(m.dmg), m.name)

## Thief got away: no XP/loot kill, and the stolen gold is charged to the pack after the fight.
func _escape(m: Dictionary) -> void:
	var took := int(m.get("stolen", 0))
	gold_debt += took
	m.stolen = 0
	m.hp = 0
	danger = danger.filter(func(d): return d.uid != m.uid)
	_log("%s escapes with %d gold!" % [m.name, took])
	_ev({"t": "die", "uid": m.uid, "pos": m.pos})
	_ev({"t": "sfx", "name": "miss"})
	if enemies().is_empty():
		over = true; won = true
		danger.clear()
		_log("Room cleared!")

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
	if d >= 2 and m.cooldown <= 0 and sees(m.pos, hero.pos):
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
func _yog_shielded() -> bool:
	return enemies().any(func(e): return e.get("fist", false))

## Phase 0 -> Burning Fist; at 2/3 HP -> Rotting Fist; at 1/3 -> Bright Fist (one at a time, SPD-style).
func _yog_phase(m: Dictionary) -> void:
	var p := int(m.get("phase", 0))
	var fid := ""
	if p == 0: fid = "fist_burning"
	elif p == 1 and int(m.hp) <= int(ceil(int(m.ht) * 2 / 3.0)) and not _yog_shielded(): fid = "fist_rotting"
	elif p == 2 and int(m.hp) <= int(ceil(int(m.ht) / 3.0)) and not _yog_shielded(): fid = "fist_bright"
	if fid == "": m.shielded = _yog_shielded(); return
	m.phase = p + 1
	var spot = null; var best := -1
	for y in h:
		for x in w:
			var q := Vector2i(x, y)
			if not passable(q) or unit_at(q) != null: continue
			var sc := cheb(q, hero.pos) * 2 - cheb(q, m.pos)
			if spot == null or sc > best: best = sc; spot = q
	if spot == null: m.shielded = false; return
	var f := spawn(fid, spot)
	f.next = time + 1.0
	m.shielded = true
	_ev({"t": "spawn", "uid": f.uid, "pos": spot})
	_log("%s rises to shield Yog-Dzewa! (phase %d/3)" % [f.name, m.phase]); _ev({"t": "sfx", "name": "boss"}); _ev({"t": "telegraph", "uid": m.uid})

func _yog_act(m: Dictionary) -> bool:
	if hidden(): return false
	_yog_phase(m)
	var enr := int(m.hp) * 2 <= int(m.ht)
	if enr and not m.get("enraged", false):
		m.enraged = true; m.summon_n = int(m.summon_n) + 1
		_log("Yog-Dzewa's eye burns brighter! (abilities come faster)"); _ev({"t": "sfx", "name": "chargeup"}); _ev({"t": "telegraph", "uid": m.uid})
	m.abil = int(m.get("abil", 0)) + 1
	if m.abil < int(m.ability_every_super if enr else m.ability_every): return false
	m.abil = 0
	m.abil_n = int(m.get("abil_n", 0)) + 1
	if m.abil_n % 2 == 1 and not _yog_shielded() and enemies().filter(func(e): return e.get("summoned", false)).is_empty():
		var spots := []
		for d in DIRS + [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var q: Vector2i = hero.pos + d
			if spots.size() >= int(m.summon_n): break
			if passable(q) and unit_at(q) == null and not is_danger(q): spots.append(q)
		for q in spots:
			danger.append({"pos": q, "dmg": 4, "at": m.next + 2.0, "src": "Larva hatching", "uid": m.uid, "spawn": m.summon, "summoned": true})
		_log("Yog-Dzewa spawns larva! (red tiles, 2 ticks)"); _ev({"t": "sfx", "name": "bones"})
	else:
		for i in maxi(w, h):
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
		_left(m.pos); m.pos = far
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
	for r in range(0, maxi(w, h)):
		for y in range(p.y - r, p.y + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				var c := Vector2i(x, y)
				if passable(c) and unit_at(c) == null: return c
	return p

## Milestone fields for a fight result dict (DECISIONS #195): kills per mob, surprise hits, HP actually lost
## (damage Barrier soaked doesn't count, poison does), and whether Auto Battle ever acted.
func milestone_result() -> Dictionary:
	return {"kill_ids": kill_ids.duplicate(), "surprises": surprises, "cloak_charges": int(hero.get("cloak_charges", 0)), "hp_lost": hp_lost, "auto_used": auto_used, "potions_fight": potions_drunk,
		"dmg_in": dmg_in, "dmg_out": dmg_out, "turns": hero_turns}
