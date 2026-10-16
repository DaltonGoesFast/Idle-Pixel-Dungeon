## CombatBot: a "sensible tactics" player used by tests, balance sims and the in-game Hint button.
## Priorities: dodge telegraphs > heal when low > chasm shove > surprise setups (door/grass) >
## bolt > attack weakest adjacent > approach.
class_name CombatBot
extends RefCounted

## Returns {"act": "tap"|"wait"|"heal", "pos": Vector2i, "mode": String, "why": String}
static func suggest(c: Combat, potions := 0, heal_amount := 10) -> Dictionary:
	var h: Dictionary = c.hero
	var es := c.enemies()
	if es.is_empty(): return {"act": "wait", "why": "nothing to do"}
	var live := es.filter(func(e): return not e.get("shielded", false))   # Yog behind a fist: hit the fist (DECISIONS #87)
	if not live.is_empty(): es = live
	# 1. standing on a red tile: step to a safe free tile, preferring tiles not adjacent to many enemies
	if c.is_danger(h.pos):
		# Yog's fists: gaze paints whole rows, so swing if a fist is already in melee
		var fist_adj := es.filter(func(e): return Combat.cheb(e.pos, h.pos) == 1 and e.get("fist", false))
		if not fist_adj.is_empty():
			return {"act": "tap", "pos": fist_adj[0].pos, "mode": "", "why": "hit the fist through the gaze"}
		var best = null; var best_score := -999
		for d in Combat.DIRS:
			var p: Vector2i = h.pos + d
			if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p): continue
			var score := 0
			for e in es:
				score -= 2 if Combat.cheb(e.pos, p) == 1 else 0
				if e.get("ability", "") == "pump": score += mini(3, _escapes(c, p, e.pos)) * 2  # never dodge into a corner
			if score > best_score: best_score = score; best = p
		if best != null: return {"act": "tap", "pos": best, "mode": "", "why": "dodge the red tiles"}
		# big areas (3x3 shadow blast): no safe tile one step away - head for the nearest safe one
		var safe := []
		for y in c.h:
			for x in c.w:
				var q := Vector2i(x, y)
				if c.passable(q) and c.unit_at(q) == null and not c.is_danger(q) and not c.visible_trap(q): safe.append(q)
		var best_d := 99
		for d in Combat.DIRS:
			var p: Vector2i = h.pos + d
			if not c.passable(p) or c.unit_at(p) != null or c.visible_trap(p): continue
			for q in safe:
				var dq := Combat.cheb(p, q)
				if dq < best_d: best_d = dq; best = p
		if best != null: return {"act": "tap", "pos": best, "mode": "", "why": "run out of the red area"}
	# 1b. vs slammers (Goo): never get cornered - keep a tile 2+ away from it reachable in one step
	for e in es:
		if e.get("ability", "") == "pump" and Combat.cheb(e.pos, h.pos) <= 2 and _escapes(c, h.pos, e.pos) == 0:
			var best = null; var best_n := 0
			for d in Combat.DIRS:
				var p: Vector2i = h.pos + d
				if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p): continue
				var n := _escapes(c, p, e.pos)
				if n > best_n: best_n = n; best = p
			if best != null: return {"act": "tap", "pos": best, "mode": "", "why": "don't get cornered by " + e.name}
		# before it arrives, step off walls/corners into open floor
		if e.get("ability", "") == "pump" and not e.get("charging", false) and Combat.cheb(e.pos, h.pos) >= 2 and _open(c, h.pos) < 6:
			var best2 = null; var best_o := _open(c, h.pos)
			for d in Combat.DIRS:
				var p: Vector2i = h.pos + d
				if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p) or Combat.cheb(p, e.pos) < 2: continue
				var o := _open(c, p)
				if o > best_o: best_o = o; best2 = p
			if best2 != null: return {"act": "tap", "pos": best2, "mode": "", "why": "fight %s in the open" % e.name}
	# 2. heal when low
	var threat := 0
	for e in es:
		if Combat.cheb(e.pos, h.pos) <= 2: threat += maxi(0, int(e.dmg) - int(h.dr))
	# Count telegraphed blasts on our tile (Yog gaze ignores DR)
	var blast := 0
	for d in c.danger:
		if d.pos == h.pos: blast += int(d.dmg)
	if potions > 0 and h.hp <= maxi(7, maxi(threat * 2, blast)) and h.hp + heal_amount <= h.ht + 4:
		return {"act": "heal", "why": "low HP - drink a potion"}
	var adj := es.filter(func(e): return Combat.cheb(e.pos, h.pos) == 1)
	# 3. shove adjacent enemy into a chasm (or onto a known trap)
	if "shove" in h.abilities:
		for e in adj:
			var dir: Vector2i = e.pos - h.pos
			if (c.tile(e.pos + dir) == Combat.T.CHASM or (c.visible_trap(e.pos + dir) and c.unit_at(e.pos + dir) == null)) and not e.get("boss", false):
				return {"act": "tap", "pos": e.pos, "mode": "shove", "why": "shove it into the chasm"}
	# 3a. warrior slam: 2+ adjacent, or one would fall into a chasm (skip if only snakes would be hit without surprise)
	if "slam" in h.abilities and int(h.get("slams", 0)) > 0:
		var into_chasm := adj.any(func(e): return c.tile(e.pos + (e.pos - h.pos)) == Combat.T.CHASM and not e.get("boss", false))
		var slamable := adj.filter(func(e): return not e.get("evade_unless_surprise", false) or c.surprise_against(e))
		if slamable.size() >= 3 or into_chasm:
			return {"act": "slam", "why": "slam the crowd"}
	# 3b. rogue: cloak when swarmed or hurt, then strike from the shadows
	if "cloak" in h.abilities and int(h.cloak_charges) > 0 and not c.hidden() and (adj.size() >= 2 or (adj.size() == 1 and _hits_to_kill(c, adj[0]) >= 2)):
		return {"act": "cloak", "why": "cloak, then strike with a Surprise"}
	# 3c. Clear non-snake threats in melee first, then SPD surprise setups for snakes / DR
	var hittable_now := adj.filter(func(e): return not e.get("evade_unless_surprise", false) or c.surprise_against(e))
	var non_snake_adj := hittable_now.filter(func(e): return not e.get("evade_unless_surprise", false))
	if not non_snake_adj.is_empty():
		var tgt0 = non_snake_adj[0]
		for e in non_snake_adj:
			if _hits_to_kill(c, e) < _hits_to_kill(c, tgt0): tgt0 = e
		return {"act": "tap", "pos": tgt0.pos, "mode": "", "why": "attack " + tgt0.name}
	var sur_hit := _surprise_strike(c, adj)
	if not sur_hit.is_empty(): return sur_hit
	var snakes := es.filter(func(e): return e.get("evade_unless_surprise", false))
	var non_snakes := es.filter(func(e): return not e.get("evade_unless_surprise", false))
	# Clear non-snakes with bolts before committing to a snake door dance
	if not snakes.is_empty() and not non_snakes.is_empty() and c.has_ranged():
		var bolt_tgt = null
		for e in non_snakes:
			if _can_shoot(c, e) and (bolt_tgt == null or e.hp < bolt_tgt.hp): bolt_tgt = e
		if bolt_tgt != null:
			return {"act": "tap", "pos": bolt_tgt.pos, "mode": "bolt", "why": "bolt " + bolt_tgt.name + " before the snake"}
	if not snakes.is_empty():
		var snake_act := _snake_plan(c, snakes)
		# Don't idle on a snake bait while other foes are free to throw / close in
		if not snake_act.is_empty() and not (snake_act.act == "wait" and not non_snakes.is_empty()):
			return snake_act
	var sur_setup := _surprise_setup(c, es)
	if not sur_setup.is_empty(): return sur_setup
	# 4. ranged: bolts (limited) prefer kills; spirit bow never fires point-blank (can_bolt enforces)
	if c.has_ranged():
		var tgt = null
		for e in es:
			if e.get("evade_unless_surprise", false) and not c.surprise_against(e): continue
			if _can_shoot(c, e) and (tgt == null or e.hp < tgt.hp): tgt = e
		# use the ranged attack when nothing is adjacent, when it kills, or when it out-damages melee
		var ranged_net := int(h.bolt.dmg) if h.bolt.get("magic", true) else maxi(0, int(h.bolt.dmg) - (int(tgt.dr) if tgt != null else 0))
		var melee_rate := float(maxi(0, int(h.dmg) - (int(tgt.dr) if tgt != null else 0))) / float(h.delay)
		if tgt != null and (adj.is_empty() or tgt.hp <= ranged_net or float(ranged_net) > melee_rate):
			return {"act": "tap", "pos": tgt.pos, "mode": "bolt", "why": "bolt " + tgt.name}
	# 4a. blind shot (DECISIONS #149): nothing in sight to shoot and nothing adjacent -> shoot where an unseen foe
	# was last seen (it is often still in that grass). At most 2 arrows per sighting; wands spend 1 charge only
	# while keeping one in reserve.
	if c.has_ranged() and adj.is_empty() and not es.any(func(e): return c.hero_sees(e)):
		var cap := 2 if h.bolt.get("infinite", false) else (1 if int(h.charges) >= 2 else 0)
		for e in es:
			if e.has("last_seen") and int(e.get("blind_shots", 0)) < cap:
				var ls := Vector2i(int(e.last_seen[0]), int(e.last_seen[1]))
				if c.can_bolt(ls): return {"act": "tap", "pos": ls, "mode": "bolt", "why": "blind shot where %s was last seen" % e.name}
	# 4b. search once for hidden traps only when every foe is far and slow to close (never vs bosses)
	if adj.is_empty() and not h.get("searched", false) and es.size() == 1 \
			and not es[0].get("boss", false) and not es[0].get("fist", false) \
			and es.all(func(e): return Combat.cheb(e.pos, h.pos) >= 6 and not e.has("throw_range") and not e.has("zap_dmg") and float(e.delay) >= 1.0):
		return {"act": "search", "why": "search for hidden traps before closing in"}
	# 5. attack the adjacent enemy that dies fastest (never a plain swing at a snake)
	if not hittable_now.is_empty():
		var tgt = hittable_now[0]
		for e in hittable_now:
			if _hits_to_kill(c, e) < _hits_to_kill(c, tgt): tgt = e
		return {"act": "tap", "pos": tgt.pos, "mode": "", "why": "attack " + tgt.name}
	# 6. approach the nearest enemy, avoiding red tiles; if a telegraph is coming, wait out of reach
	# Prefer Yog's fist over larva so phases actually advance
	var near = es[0]
	for e in es:
		if e.get("fist", false): near = e; break
		if Combat.cheb(e.pos, h.pos) < Combat.cheb(near.pos, h.pos): near = e
	if near.get("charging", false) and Combat.cheb(near.pos, h.pos) <= 2:
		return {"act": "wait", "why": "let it waste the slam"}
	if near.has("stolen") and int(near.stolen) > 0 and c.has_ranged() and _can_shoot(c, near):
		return {"act": "tap", "pos": near.pos, "mode": "bolt", "why": "shoot the fleeing thief"}
	var step = c.path_step(h.pos, near.pos, true, true, true)
	if step == null: step = c.path_step(h.pos, near.pos, true, true, true)
	# Yog gaze / big telegraphs paint whole lines: still close in rather than stall forever
	if step == null: step = c.path_step(h.pos, near.pos, false, true, true)
	if step == null: step = c.path_step(h.pos, near.pos)
	if step != null: return {"act": "tap", "pos": step, "mode": "", "why": "close in on " + near.name}
	return {"act": "wait", "why": "hold position"}

## Dedicated snake plan: SPD doorway bait, then surprise. Never swing while they can see you.
static func _snake_plan(c: Combat, snakes: Array) -> Dictionary:
	var h: Dictionary = c.hero
	var sn = snakes[0]
	for e in snakes:
		if Combat.cheb(e.pos, h.pos) < Combat.cheb(sn.pos, h.pos): sn = e
	if Combat.cheb(sn.pos, h.pos) == 1 and c.surprise_against(sn):
		return {"act": "tap", "pos": sn.pos, "mode": "", "why": "surprise the snake"}
	# On a door: always step through so it closes — never wait on the threshold
	if c.tile(h.pos) == Combat.T.DOOR:
		var step_off = _step_off_door(c, h.pos, sn.pos)
		if step_off.x >= 0:
			return {"act": "tap", "pos": step_off, "mode": "", "why": "close the door on the snake"}
	# Foe lost track (SPD seen_hero): wait for it to walk into range, then surprise
	if not sn.get("seen_hero", true):
		if Combat.cheb(sn.pos, h.pos) == 1:
			return {"act": "tap", "pos": sn.pos, "mode": "", "why": "surprise the snake"}
		# Hold only while it's nearby and can't see us; if it's stuck far away, re-path
		if not c.sees(sn.pos, h.pos) and Combat.cheb(sn.pos, h.pos) <= 3:
			return {"act": "wait", "why": "bait the snake after breaking sight"}
	# Circle tall grass / a pillar: end adjacent with a blocker between you
	if Combat.cheb(sn.pos, h.pos) <= 3:
		for d in Combat.DIRS:
			var p: Vector2i = h.pos + d
			if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p): continue
			if Combat.cheb(p, sn.pos) == 1 and not c.sees(sn.pos, p):
				return {"act": "tap", "pos": p, "mode": "", "why": "circle grass vs snake"}
	# Walk onto a door, then next turn step off (handled above)
	var door := _nearest_door(c, h.pos)
	if door.x >= 0:
		if Combat.cheb(h.pos, door) == 1 and c.unit_at(door) == null:
			return {"act": "tap", "pos": door, "mode": "", "why": "take the doorway vs snake"}
		var step = c.path_step(h.pos, door, true, true, true)
		if step != null:
			return {"act": "tap", "pos": step, "mode": "", "why": "reach doorway vs snake"}
	# Keep a tile of space until a setup appears
	if Combat.cheb(sn.pos, h.pos) > 2:
		var step2 = c.path_step(h.pos, sn.pos, true, true, true)
		if step2 != null and Combat.cheb(step2, sn.pos) > 1:
			return {"act": "tap", "pos": step2, "mode": "", "why": "approach snake carefully"}
	# Adjacent and visible with no setup: step away rather than eat hits
	if Combat.cheb(sn.pos, h.pos) == 1:
		for d in Combat.DIRS:
			var p: Vector2i = h.pos + d
			if p == sn.pos: continue
			if c.passable(p) and c.unit_at(p) == null and not c.is_danger(p):
				return {"act": "tap", "pos": p, "mode": "", "why": "kite the snake"}
	return {"act": "wait", "why": "wait for a snake surprise"}

## Step off a door cell, preferring a tile the closed door will hide from `foe`.
static func _step_off_door(c: Combat, door: Vector2i, foe: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1); var best_sc := -999
	for d in Combat.DIRS:
		var p: Vector2i = door + d
		if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p): continue
		if p == foe: continue
		var sc := Combat.cheb(p, foe)
		if not _los_with_block(c, foe, p, door): sc += 5
		if sc > best_sc: best_sc = sc; best = p
	return best

## Line of sight treating `block` as a sight blocker (door about to close).
static func _los_with_block(c: Combat, a: Vector2i, b: Vector2i, block: Vector2i) -> bool:
	var pts := Combat._line(a, b)
	for i in range(1, pts.size() - 1):
		if pts[i] == block: return false
		if c.blocks_sight(pts[i]): return false
	return true

static func _nearest_door(c: Combat, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1); var bd := 999
	for y in c.h:
		for x in c.w:
			var p := Vector2i(x, y)
			if c.tile(p) != Combat.T.DOOR: continue
			var d := Combat.cheb(p, from)
			if d < bd: bd = d; best = p
	return best

## Swing now if an adjacent foe is already surprised (especially snakes / DR / chasm setups).
static func _surprise_strike(c: Combat, adj: Array) -> Dictionary:
	for e in adj:
		if not c.surprise_against(e): continue
		var want: bool = bool(e.get("evade_unless_surprise", false)) or int(e.dr) > 0
		var dir: Vector2i = e.pos - c.hero.pos
		if c.tile(e.pos + dir) == Combat.T.CHASM: want = true
		if want:
			return {"act": "tap", "pos": e.pos, "mode": "", "why": "surprise " + e.name}
	return {}

## Step off a door or around tall grass/pillar so the foe loses sight (SPD surprise setups).
static func _surprise_setup(c: Combat, es: Array) -> Dictionary:
	var h: Dictionary = c.hero
	# Door/grass dances are for snakes; DR foes still get surprise_strike when already ready
	var targets := es.filter(func(e): return e.get("evade_unless_surprise", false))
	if targets.is_empty(): return {}
	for e in targets:
		if c.surprise_against(e) and Combat.cheb(e.pos, h.pos) == 1: continue
		# Standing on a door with the foe approaching: step off so it closes
		if c.tile(h.pos) == Combat.T.DOOR and c.sees(e.pos, h.pos):
			var off := _step_off_door(c, h.pos, e.pos)
			if off.x >= 0:
				return {"act": "tap", "pos": off, "mode": "", "why": "close the door on " + e.name}
		# Circle tall grass / a pillar: only when the step ends adjacent (setup for next swing)
		if Combat.cheb(e.pos, h.pos) <= 3:
			for d in Combat.DIRS:
				var p: Vector2i = h.pos + d
				if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p): continue
				if Combat.cheb(p, e.pos) != 1 or c.sees(e.pos, p): continue
				if e.get("evade_unless_surprise", false) or int(e.dr) > 0:
					return {"act": "tap", "pos": p, "mode": "", "why": "break sight on " + e.name}
		# Walk toward a door between us and the foe
		if e.get("evade_unless_surprise", false) or int(e.dr) > 0:
			var door = _door_between(c, h.pos, e.pos)
			if door.x >= 0:
				var step = c.path_step(h.pos, door, true, true, true)
				if step != null and step != door:
					return {"act": "tap", "pos": step, "mode": "", "why": "reach the door vs " + e.name}
				# Step onto the door if adjacent, then next turn step off
				if Combat.cheb(h.pos, door) == 1 and c.unit_at(door) == null:
					return {"act": "tap", "pos": door, "mode": "", "why": "enter the doorway vs " + e.name}
	return {}

## A closed-or-empty door cell on a straight orthogonal line between a and b.
static func _door_between(c: Combat, a: Vector2i, b: Vector2i) -> Vector2i:
	if a.x != b.x and a.y != b.y: return Vector2i(-1, -1)
	var pts := Combat._line(a, b)
	for i in range(1, pts.size() - 1):
		if c.tile(pts[i]) == Combat.T.DOOR: return pts[i]
	return Vector2i(-1, -1)

## Free tiles next to `p` that are outside the 3x3 slam area around `boss`.
static func _escapes(c: Combat, p: Vector2i, boss: Vector2i) -> int:
	var n := 0
	for d in Combat.DIRS:
		var q: Vector2i = p + d
		if Combat.cheb(q, boss) >= 2 and c.passable(q) and c.unit_at(q) == null: n += 1
	return n

static func _open(c: Combat, p: Vector2i) -> int:
	var n := 0
	for d in Combat.DIRS:
		if c.passable(p + d): n += 1
	return n

static func _hits_to_kill(c: Combat, e: Dictionary) -> int:
	var d := maxi(1, int(c.hero.dmg) - int(e.dr))
	if e.get("evade_unless_surprise", false) and not c.surprise_against(e): return 99
	return int(ceil(float(e.hp) / d))

## Plays a full fight. Returns {won, turns, hp, potions_used}.
static func play(c: Combat, potions := 0, heal := 10, max_turns := 300) -> Dictionary:
	var turns := 0; var used := 0
	while not c.over and turns < max_turns:
		turns += 1
		var s := suggest(c, potions - used, heal)
		match s.act:
			"heal": used += 1; c.hero_heal(heal)
			"cloak": if not c.hero_cloak(): c.hero_wait()
			"slam": if not c.hero_slam(): c.hero_wait()
			"wait": c.hero_wait()
			"search": c.hero_search()
			"tap":
				if not c.hero_tap(s.pos, s.mode): c.hero_wait()
	return {"won": c.won, "turns": turns, "hp": c.hero.hp, "potions_used": used}

## A shot the bot would take: the target is in sight and the arrow/bolt aimed at it hits it (no body or door in front).
static func _can_shoot(c, e: Dictionary) -> bool:
	return c.hero_sees(e) and c.can_bolt(e.pos) and c.bolt_victim(e.pos) == e
