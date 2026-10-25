## CombatBot: a "sensible tactics" player used by tests, balance sims, Auto Battle, and the Hint keybind.
## Priorities: dodge telegraphs > heal when low > chasm shove > slam a crowd >
## a Surprise that can land this turn (a melee swing in reach, or a Spirit Bow shot) >
## cloak (only when cloak_reason() says the charge is worth it) > attack the weakest foe in reach > bolt > approach. Reach weapons (Spear, Glaive, Whip) swing from 2-3 tiles.
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
	# foes the weapon reaches this turn: adjacent, or 2-3 tiles for a Spear, Glaive or Whip (DECISIONS #207)
	var reach_l := es.filter(func(e): return c.can_melee(e))
	# 3. shove adjacent enemy into a chasm (or onto a known trap)
	if "shove" in h.abilities:
		for e in adj:
			var dir: Vector2i = e.pos - h.pos
			if (c.tile(e.pos + dir) == Combat.T.CHASM or (c.visible_trap(e.pos + dir) and c.unit_at(e.pos + dir) == null)) and not e.get("boss", false):
				return {"act": "tap", "pos": e.pos, "mode": "shove", "why": "shove it into the chasm"}
	# 3a. warrior slam: 3+ foes the slam can actually hurt, or one would fall into a chasm.
	# Snakes slip a slam (it is not a Surprise), so they do not count toward the crowd.
	if "slam" in h.abilities and int(h.get("slams", 0)) > 0:
		var into_chasm := adj.any(func(e): return c.tile(e.pos + (e.pos - h.pos)) == Combat.T.CHASM and not e.get("boss", false))
		var slamable := adj.filter(func(e): return not e.get("evade_unless_surprise", false))
		if slamable.size() >= 3 or into_chasm:
			return {"act": "slam", "why": "slam the crowd"}
	# 3a2. A Surprise that can land this turn beats a normal swing: x surprise_mult then DR.
	# Cash it before cloaking or clearing someone else — the window closes once they see you.
	var sur_hit := _surprise_strike(c, reach_l)
	if not sur_hit.is_empty(): return sur_hit
	if reach_l.is_empty():
		var sur_shot := _surprise_shot(c, es)
		if not sur_shot.is_empty(): return sur_shot
	# 3b. rogue: cloak when swarmed or hurt, then strike from the shadows - but only when the charge is worth it (#211)
	if "cloak" in h.abilities and int(h.cloak_charges) > 0 and not c.hidden() and not h.get("no_surprise", false) and (adj.size() >= 2 or (adj.size() == 1 and _hits_to_kill(c, adj[0]) >= 2)):
		var why := cloak_reason(c, es)
		if why != "": return {"act": "cloak", "why": "cloak (%s), then strike with a Surprise" % why}
	# 3c. No Surprise ready: clear non-snake threats, then SPD door/grass setups for snakes
	var hittable_now := reach_l.filter(func(e): return not e.get("evade_unless_surprise", false) or c.surprise_against(e))
	var non_snake_adj := hittable_now.filter(func(e): return not e.get("evade_unless_surprise", false))
	if not non_snake_adj.is_empty():
		var tgt0 = non_snake_adj[0]
		for e in non_snake_adj:
			if _hits_to_kill(c, e) < _hits_to_kill(c, tgt0): tgt0 = e
		return {"act": "tap", "pos": tgt0.pos, "mode": "", "why": "attack " + tgt0.name}
	# 3d. SPD ambush (DECISIONS #177): break sight, let them walk to where they last saw us, strike with a Surprise
	if adj.is_empty():
		var amb := _ambush(c, es)
		if not amb.is_empty(): return amb
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
	# 4a0. reach weapons: hold still while a foe walks into reach instead of stepping next to it (a free swing, #207)
	if int(h.get("reach", 1)) > 1 and adj.is_empty() and not c.is_danger(h.pos) and int(h.get("bot_reach_wait", 0)) < REACH_WAIT_CAP:
		for e in es:
			var d := Combat.cheb(e.pos, h.pos)
			if d == int(h.reach) + 1 and c.hero_sees(e) and not e.get("stationary", false) and not e.has("throw_range") \
					and not e.has("zap_dmg") and not e.has("holds_range") and not e.get("boss", false) and e.get("state", "hunting") == "hunting":
				h.bot_reach_wait = int(h.get("bot_reach_wait", 0)) + 1
				return {"act": "wait", "why": "let %s walk into reach" % e.name}
	# 4a. blind shot (DECISIONS #149): nothing in sight to shoot and nothing adjacent -> shoot where an unseen foe
	# was last seen (it is often still in that grass). At most 2 arrows per sighting; wands spend 1 charge only
	# while keeping one in reserve.
	if adj.is_empty():
		var blind := _blind_shot(c, es)
		if not blind.is_empty(): return blind
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
	# Magic always hits a snake and bows hit after one slip (DECISIONS #172): shoot when we can
	if c.has_ranged() and (h.bolt.get("infinite", false) or int(h.charges) > 0):
		for e in snakes:
			if c.can_bolt(e.pos) and c.bolt_victim(e.pos) == e:
				return {"act": "tap", "pos": e.pos, "mode": "bolt", "why": "shoot the snake"}
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
		# (at most AMBUSH_CAP turns: a snake that stopped short never arrives, so then walk up and surprise it, #211)
		if not c.sees(sn.pos, h.pos) and Combat.cheb(sn.pos, h.pos) <= 3 and int(h.get("bot_bait", 0)) < AMBUSH_CAP:
			h.bot_bait = int(h.get("bot_bait", 0)) + 1
			return {"act": "wait", "why": "bait the snake after breaking sight"}
		if not c.sees(sn.pos, h.pos):
			var st = c.path_step(h.pos, sn.pos, true, true, true)
			if st != null: return {"act": "tap", "pos": st, "mode": "", "why": "creep up on the unaware snake"}
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
	# No usable door: duck out of sight behind a wall / tall grass. The snake
	# walks to where it last saw us (SPD Hunting target cell) and arrives unaware -> surprise.
	var hide := _hide_step(c, sn)
	if hide.x >= 0:
		return {"act": "tap", "pos": hide, "mode": "", "why": "break sight on the snake"}
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

## Blind shot (DECISIONS #149) where an unseen foe was last seen; {} when none applies.
static func _blind_shot(c: Combat, es: Array) -> Dictionary:
	var h: Dictionary = c.hero
	if not c.has_ranged() or es.any(func(e): return c.hero_sees(e)): return {}
	var cap := 2 if h.bolt.get("infinite", false) else (1 if int(h.charges) >= 2 else 0)
	for e in es:
		if e.has("last_seen") and int(e.get("blind_shots", 0)) < cap:
			var ls := Vector2i(int(e.last_seen[0]), int(e.last_seen[1]))
			if c.can_bolt(ls): return {"act": "tap", "pos": ls, "mode": "bolt", "why": "blind shot where %s was last seen" % e.name}
	return {}

const AMBUSH_CAP := 3
const REACH_WAIT_CAP := 6   # bot turns per fight spent letting foes walk into a Spear/Glaive/Whip's reach (#207)

## SPD ambush for every class (DECISIONS #177, #223): step into nearby cover for a Surprise. Cap 3 turns, cover
## search depth 2, skip when the weapon cannot surprise.
static func _ambush(c: Combat, es: Array) -> Dictionary:
	var h: Dictionary = c.hero
	if h.get("no_surprise", false): return {}
	if int(h.get("bot_ambush", 0)) >= AMBUSH_CAP: return {}
	if es.any(func(e): return e.get("boss", false) or e.get("fist", false) or e.get("stationary", false)): return {}
	if es.size() > 2: return {}   # vs a crowd, hiding just lets them arrive together (sim: more deaths)
	if int(h.hp) * 2 < int(h.ht) or c.is_danger(h.pos): return {}
	# Magic never surprises: a wand with a clear shot just shoots
	if c.has_ranged() and h.bolt.get("magic", true) and es.any(func(e): return _can_shoot(c, e)): return {}
	if not _blind_shot(c, es).is_empty(): return {}
	var unseen := es.filter(func(e): return not c.sees(e.pos, h.pos))
	if unseen.size() == es.size():
		# Hidden from all: wait while someone is still coming to our last-seen cell
		if es.any(func(e): return e.get("state", "hunting") == "hunting" and Combat.cheb(e.pos, h.pos) <= 3):
			h.bot_ambush = int(h.get("bot_ambush", 0)) + 1
			return {"act": "wait", "why": "wait in cover for a Surprise"}
		return {}
	# Only start an ambush when a Surprise could pay off: some foe within reach of the setup
	if not es.any(func(e): return Combat.cheb(e.pos, h.pos) <= 3): return {}
	var hide := _cover_step(c, es)
	if hide.x < 0: return {}
	h.bot_ambush = int(h.get("bot_ambush", 0)) + 1
	return {"act": "tap", "pos": hide, "mode": "", "why": "break sight for a Surprise"}

## First step toward the nearest cell (<= 2 steps) no living foe can see and no foe is next to.
static func _cover_step(c: Combat, es: Array) -> Vector2i:
	var h: Dictionary = c.hero
	var prev := {h.pos: h.pos}; var q := [h.pos]; var depth := {h.pos: 0}
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur != h.pos and es.all(func(e): return not c.sees(e.pos, cur) and Combat.cheb(e.pos, cur) > 1):
			while prev[cur] != h.pos: cur = prev[cur]
			return cur
		if int(depth[cur]) >= 2: continue
		for d in Combat.DIRS:
			var n: Vector2i = cur + d
			if prev.has(n) or not c.passable(n) or c.unit_at(n) != null or c.is_danger(n) or c.visible_trap(n): continue
			if es.any(func(e): return Combat.cheb(e.pos, n) <= 1): continue
			prev[n] = cur; depth[n] = int(depth[cur]) + 1; q.append(n)
	return Vector2i(-1, -1)

## First step toward the nearest tile (BFS, up to 6 steps) the snake cannot see. Vector2i(-1,-1) if none.
static func _hide_step(c: Combat, sn: Dictionary) -> Vector2i:
	var h: Dictionary = c.hero
	var prev := {h.pos: h.pos}; var q := [h.pos]; var depth := {h.pos: 0}
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur != h.pos and not c.sees(sn.pos, cur) and Combat.cheb(cur, sn.pos) > 1:
			while prev[cur] != h.pos: cur = prev[cur]
			return cur
		if int(depth[cur]) >= 6: continue
		for d in Combat.DIRS:
			var n: Vector2i = cur + d
			if prev.has(n) or not c.passable(n) or c.unit_at(n) != null or c.is_danger(n) or c.visible_trap(n): continue
			if Combat.cheb(n, sn.pos) <= 1: continue
			prev[n] = cur; depth[n] = int(depth[cur]) + 1; q.append(n)
	return Vector2i(-1, -1)

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
			if c.tile(p) != Combat.T.DOOR: continue   # a door held open by remains shuts once we pass through (DECISIONS #176)
			var d := Combat.cheb(p, from)
			if d < bd: bd = d; best = p
	return best

## Swing now at the adjacent foe a Surprise would hit hardest (x surprise_mult, then DR; no knockback, DECISIONS #220).
static func _surprise_strike(c: Combat, adj: Array) -> Dictionary:
	var best = null
	var best_hits := 99
	var best_bonus := -1
	for e in adj:
		if not c.surprise_against(e): continue
		var hits := _hits_to_kill(c, e)
		var bonus := (2 if e.get("evade_unless_surprise", false) else 0) + int(e.dr)
		if best == null or hits < best_hits or (hits == best_hits and bonus > best_bonus):
			best = e
			best_hits = hits
			best_bonus = bonus
	if best == null: return {}
	return {"act": "tap", "pos": best.pos, "mode": "", "why": "surprise " + best.name}

## Spirit Bow only: a clear shot on a foe who would be surprised. Wands are magic and never surprise.
## Called when nobody is adjacent, so the shot is not traded for a free hit.
static func _surprise_shot(c: Combat, es: Array) -> Dictionary:
	var h: Dictionary = c.hero
	if not c.has_ranged() or h.bolt.get("magic", true): return {}
	var best = null
	var best_hits := 99
	var best_bonus := -1
	for e in es:
		if not c.surprise_against(e) or not _can_shoot(c, e): continue
		var hits := _hits_to_kill_ranged(c, e, true)
		var bonus := (2 if e.get("evade_unless_surprise", false) else 0) + int(e.dr)
		if best == null or hits < best_hits or (hits == best_hits and bonus > best_bonus):
			best = e
			best_hits = hits
			best_bonus = bonus
	if best == null: return {}
	return {"act": "tap", "pos": best.pos, "mode": "bolt", "why": "surprise shot on " + best.name}

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

# ---- Cloak of Shadows budget (DECISIONS #211). The charges last the whole expedition (#206): 3, +1 per cleared fight.
const CLOAK_THREAT_FRAC := 0.5   # projected HP loss without the cloak >= this share of HP (+ barrier) = a real threat
const CLOAK_LOW_HP := 0.4        # at or below this share of max HP, any charge may go (emergency)
const CLOAK_CROWD := 3           # this many living foes is a threat on its own
const CLOAK_STALL_T := 15.0      # a snake next to us after this many ticks: the door/grass dance failed, cloak it

## Why a cloak charge is worth spending now, or "" to keep it. Used by Auto Battle and the Hint button alike.
## - a boss fight (Goo, Tengu, DM-300, the King, Yog) or an emergency (low HP, or the fight would kill us): any charge;
## - a full cloak: spend freely, since the win refills it and the recharge would otherwise go to waste;
## - a snake still beside us after CLOAK_STALL_T ticks (the door/grass dance failed): any charge, or the fight stalls;
## - otherwise keep one charge in reserve and spend the rest only on a threat: an elite (Animated Statue),
##   CLOAK_CROWD+ foes, or a projected HP loss >= CLOAK_THREAT_FRAC of HP.
static func cloak_reason(c: Combat, es: Array) -> String:
	var h: Dictionary = c.hero
	var n := int(h.cloak_charges)
	if n <= 0: return ""
	var cap := maxi(1, int(h.get("cloak_cap", 0)) if int(h.get("cloak_cap", 0)) > 0 else n)
	if es.any(func(e): return e.get("boss", false) or e.get("fist", false)): return "boss"
	var pool := int(h.hp) + int(h.barrier)
	var loss := projected_loss(c, es)
	if int(h.hp) <= int(float(h.ht) * CLOAK_LOW_HP) or loss >= pool: return "emergency"
	if n >= cap: return "full cloak"
	# a foe that slips every normal hit (snake) still beside us after a long dance: only a Surprise ends the fight
	if float(c.time) >= CLOAK_STALL_T and es.any(func(e): return e.get("evade_unless_surprise", false) and Combat.cheb(e.pos, h.pos) == 1):
		return "stalled on a snake"
	if n <= 1: return ""   # the last charge waits for a boss or an emergency
	if es.any(func(e): return e.get("elite", false)): return "elite"
	if es.size() >= CLOAK_CROWD: return "crowd"
	if float(loss) >= CLOAK_THREAT_FRAC * float(pool): return "dangerous fight"
	return ""

## HP the hero would lose finishing this fight with plain swings (no cloak, no Surprise): foes die quickest-first,
## and each one hits back (its damage minus our DR) every `delay` ticks until it dies. Deterministic, like the combat.
static func projected_loss(c: Combat, es: Array) -> int:
	var h: Dictionary = c.hero
	var foes := []
	for e in es:
		if e.get("boss", false) or e.get("fist", false): continue
		var d := float(maxi(0, int(h.dmg) - int(e.dr))) * minf(1.0, float(h.get("acc", 1.0)))
		var hits := 8 if (d <= 0.0 or e.get("evade_unless_surprise", false)) else mini(8, int(ceil(float(e.hp) / d)))
		var per := float(maxi(0, int(e.dmg) - int(h.dr))) / maxf(0.25, float(e.get("delay", 1.0)))
		foes.append([float(hits) * float(h.delay), per])
	foes.sort_custom(func(a, b): return a[0] < b[0])
	var t := 0.0; var loss := 0.0
	for f in foes:
		t += float(f[0]); loss += t * float(f[1])
	return int(loss)

static func _hits_to_kill(c: Combat, e: Dictionary) -> int:
	var sur := c.surprise_against(e)
	if e.get("evade_unless_surprise", false) and not sur: return 99
	if sur and c.hero.get("no_surprise", false): sur = false
	var raw := int(c.hero.dmg) + (int(c.hero.get("sur_bonus", 0)) if sur else 0)
	var d: float
	if sur:
		d = float(int(float(raw) * float(c.hero.surprise_mult)))
		var eff_dr := int(e.dr)
		if int(c.hero.get("sur_bonus", 0)) > 0 or String(c.hero.get("sub", "")) == "assassin":
			eff_dr /= 2
		d = float(maxi(1, int(d) - eff_dr))
	else:
		d = float(maxi(0, raw - int(e.dr)))
		d *= minf(1.0, float(c.hero.get("acc", 1.0)))   # an inaccurate weapon's misses (#207)
	if d <= 0.0: return 99
	return int(ceil(float(e.hp) / d))

## Spirit Bow hits-to-kill (surprise multiplies then subtracts DR unless the bolt pierces, DECISIONS #220).
static func _hits_to_kill_ranged(c: Combat, e: Dictionary, sur: bool) -> int:
	var h: Dictionary = c.hero
	var raw := int(h.bolt.dmg)
	var magic: bool = h.bolt.get("magic", false) or h.bolt.get("pierce", false)
	var d: float
	if sur:
		d = float(int(float(raw) * float(h.surprise_mult)))
		if not magic:
			d = float(maxi(1, int(d) - int(e.dr)))
	elif magic:
		d = float(raw)
	else:
		d = float(maxi(0, raw - int(e.dr)))
	if d <= 0.0: return 99
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
