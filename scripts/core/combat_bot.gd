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
			if not c.passable(p) or c.unit_at(p) != null or c.is_danger(p): continue
			var score := 0
			for e in es: score -= 2 if Combat.cheb(e.pos, p) == 1 else 0
			if c.surprise_ready() == false and (c.tile(p) == Combat.T.GRASS or c.tile(p) == Combat.T.DOOR): score += 1
			if score > best_score: best_score = score; best = p
		if best != null: return {"act": "tap", "pos": best, "mode": "", "why": "dodge the red tiles"}
	# 2. heal when low
	if potions > 0 and h.hp <= 7 and h.hp + heal_amount <= h.ht + 4:
		return {"act": "heal", "why": "low HP - drink a potion"}
	var adj := es.filter(func(e): return Combat.cheb(e.pos, h.pos) == 1)
	# 3. shove adjacent enemy into a chasm
	if "shove" in h.abilities:
		for e in adj:
			var dir: Vector2i = e.pos - h.pos
			if c.tile(e.pos + dir) == Combat.T.CHASM and not e.get("boss", false):
				return {"act": "tap", "pos": e.pos, "mode": "shove", "why": "shove it into the chasm"}
	# 4. bolt: prefer kills, then highest-threat target
	if not h.bolt.is_empty() and h.charges > 0:
		var tgt = null
		for e in es:
			if c.can_bolt(e.pos) and (tgt == null or e.hp < tgt.hp): tgt = e
		if tgt != null and (adj.is_empty() or tgt.hp <= int(h.bolt.dmg)):
			return {"act": "tap", "pos": tgt.pos, "mode": "bolt", "why": "bolt " + tgt.name}
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
	var step = c.path_step(h.pos, near.pos, true)
	if step != null: return {"act": "tap", "pos": step, "mode": "", "why": "close in on " + near.name}
	return {"act": "wait", "why": "hold position"}

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
			"wait": c.hero_wait()
			"tap":
				if not c.hero_tap(s.pos, s.mode): c.hero_wait()
	return {"won": c.won, "turns": turns, "hp": c.hero.hp, "potions_used": used}
