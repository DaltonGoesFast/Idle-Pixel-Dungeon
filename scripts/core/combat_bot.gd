## CombatBot: a "sensible tactics" player used by tests, balance sims and the in-game Hint button.
## Priorities: dodge telegraphs > heal when low > chasm shove > bolt > attack weakest adjacent > approach.
class_name CombatBot
extends RefCounted

## Returns {"act": "tap"|"wait"|"heal", "pos": Vector2i, "mode": String, "why": String}
static func suggest(c: Combat, potions := 0, heal_amount := 10) -> Dictionary:
	var h: Dictionary = c.hero
	var es := c.enemies()
	if es.is_empty(): return {"act": "wait", "why": "nothing to do"}
	# 1. standing on a red tile: step to a safe free tile, preferring tiles not adjacent to many enemies
	if c.is_danger(h.pos):
		var best = null; var best_score := -999
		for d in Combat.DIRS:
			var p: Vector2i = h.pos + d
			if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p) or c.visible_trap(p): continue
			var score := 0
			for e in es:
				score -= 2 if Combat.cheb(e.pos, p) == 1 else 0
				if e.get("ability", "") == "pump": score += mini(3, _escapes(c, p, e.pos)) * 2  # never dodge into a corner
			if c.surprise_ready() == false and (c.tile(p) == Combat.T.GRASS or c.tile(p) == Combat.T.DOOR): score += 1
			if score > best_score: best_score = score; best = p
		if best != null: return {"act": "tap", "pos": best, "mode": "", "why": "dodge the red tiles"}
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
	if potions > 0 and h.hp <= maxi(7, threat * 2) and h.hp + heal_amount <= h.ht + 4:
		return {"act": "heal", "why": "low HP - drink a potion"}
	var adj := es.filter(func(e): return Combat.cheb(e.pos, h.pos) == 1)
	# 3. shove adjacent enemy into a chasm (or onto a known trap)
	if "shove" in h.abilities:
		for e in adj:
			var dir: Vector2i = e.pos - h.pos
			if (c.tile(e.pos + dir) == Combat.T.CHASM or (c.visible_trap(e.pos + dir) and c.unit_at(e.pos + dir) == null)) and not e.get("boss", false):
				return {"act": "tap", "pos": e.pos, "mode": "shove", "why": "shove it into the chasm"}
	# 3a. warrior slam: 2+ adjacent, or one would fall into a chasm
	if "slam" in h.abilities and int(h.get("slams", 0)) > 0:
		var into_chasm := adj.any(func(e): return c.tile(e.pos + (e.pos - h.pos)) == Combat.T.CHASM and not e.get("boss", false))
		if adj.size() >= 3 or into_chasm:
			return {"act": "slam", "why": "slam the crowd"}
	# 3b. rogue: cloak when swarmed or hurt, then strike from the shadows
	if "cloak" in h.abilities and int(h.cloak_charges) > 0 and not c.hidden() and (adj.size() >= 2 or (adj.size() == 1 and _hits_to_kill(c, adj[0]) >= 2)):
		return {"act": "cloak", "why": "cloak, then strike with a Surprise"}
	# 4. ranged: bolts (limited) prefer kills; infinite arrows shoot whenever nothing is adjacent
	if c.has_ranged():
		var tgt = null
		for e in es:
			if c.can_bolt(e.pos) and (tgt == null or e.hp < tgt.hp): tgt = e
		# use the ranged attack when nothing is adjacent, when it kills, or when it out-damages melee
		var ranged_net := int(h.bolt.dmg) if h.bolt.get("magic", true) else maxi(0, int(h.bolt.dmg) - (int(tgt.dr) if tgt != null else 0))
		var melee_rate := float(maxi(0, int(h.dmg) - (int(tgt.dr) if tgt != null else 0))) / float(h.delay)
		if tgt != null and (adj.is_empty() or tgt.hp <= ranged_net or float(ranged_net) > melee_rate):
			return {"act": "tap", "pos": tgt.pos, "mode": "bolt", "why": "bolt " + tgt.name}
	# 4b. nothing close yet: search once for hidden traps (a fight is a minefield in the Prison)
	if adj.is_empty() and not h.get("searched", false) and es.all(func(e): return Combat.cheb(e.pos, h.pos) >= 4 and not e.has("throw_range") and not e.has("zap_dmg")):
		return {"act": "search", "why": "search for hidden traps before closing in"}
	# 5. attack the adjacent enemy that dies fastest
	if not adj.is_empty():
		var tgt = adj[0]
		for e in adj:
			if _hits_to_kill(c, e) < _hits_to_kill(c, tgt): tgt = e
		return {"act": "tap", "pos": tgt.pos, "mode": "", "why": "attack " + tgt.name}
	# 6. approach the nearest enemy, avoiding red tiles; if a telegraph is coming, wait out of reach
	var near = es[0]
	for e in es:
		if Combat.cheb(e.pos, h.pos) < Combat.cheb(near.pos, h.pos): near = e
	if near.get("charging", false) and Combat.cheb(near.pos, h.pos) <= 2:
		return {"act": "wait", "why": "let it waste the slam"}
	if near.has("stolen") and int(near.stolen) > 0 and c.has_ranged() and c.can_bolt(near.pos):
		return {"act": "tap", "pos": near.pos, "mode": "bolt", "why": "shoot the fleeing thief"}
	var step = c.path_step(h.pos, near.pos, true, true, true)
	if step == null: step = c.path_step(h.pos, near.pos, true)
	if step != null: return {"act": "tap", "pos": step, "mode": "", "why": "close in on " + near.name}
	return {"act": "wait", "why": "hold position"}

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
