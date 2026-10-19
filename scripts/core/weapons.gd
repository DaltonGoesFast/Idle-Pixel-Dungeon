## Weapons (DECISIONS #207): SPD v4 melee weapon numbers mapped onto the deterministic combat model.
## Every rule reads the item's data (data/items.json): `tier`, `max` [base, per level], `delay`, `str`, `reach`, `acc`,
## `block` [base, per level], `surprise_pct`, `no_surprise`. Pure static helpers so Combat, GameState and the UI agree.
class_name Weapons
extends RefCounted

## SPD Generator.floorSetTierProbs: weapon tier odds by floor set (floor / 5), tiers 1-5. SPD never drops tier 1
## (starting weapons only); here 20 of floor set 0's 75 tier-2 share goes to tier 1 so the Cudgel and Rapier can be found
## (DECISIONS #208).
const FLOOR_SET_TIER_PROBS := [[20, 55, 20, 4, 1], [0, 25, 50, 20, 5], [0, 0, 40, 50, 10], [0, 0, 20, 40, 40], [0, 0, 0, 20, 80]]

static func is_weapon(d: Dictionary) -> bool:
	return String(d.get("type", "")) == "weapon"

## SPD MeleeWeapon.min(lvl) = tier + lvl.
static func min_dmg(d: Dictionary, lvl: int) -> int:
	return int(d.get("tier", 1)) + maxi(0, lvl)

## SPD max(lvl): each weapon's own base and per-level scaling (`max`); default 5*(tier+1) + lvl*(tier+1).
static func max_dmg(d: Dictionary, lvl: int) -> int:
	var t := int(d.get("tier", 1))
	var m: Array = d.get("max", [5 * (t + 1), t + 1])
	return int(m[0]) + maxi(0, lvl) * int(m[1])

## A deterministic hit: the average of SPD's roll, floor((min + max) / 2).
static func dmg(d: Dictionary, lvl: int) -> int:
	if not d.has("tier"): return int(d.get("dmg", 1))
	return (min_dmg(d, lvl) + max_dmg(d, lvl)) / 2

## SPD Weapon.STRReq(tier, lvl): the +0 requirement drops by one at +1, +3, +6, +10...
static func str_req(d: Dictionary, lvl: int) -> int:
	var base := int(d.get("str", 10))
	if not is_weapon(d): return base
	lvl = maxi(0, lvl)
	return base - int((sqrt(8.0 * lvl + 1.0) - 1.0) / 2.0)

static func reach(d: Dictionary) -> int:
	return maxi(1, int(d.get("reach", 1)))

static func acc(d: Dictionary) -> float:
	return float(d.get("acc", 1.0))

## SPD defenseFactor: the weapon blocks 0-N of every hit (Rapier 1, Quarterstaff 2, Katana 3, shields scale).
static func block_max(d: Dictionary, lvl: int) -> int:
	var b: Array = d.get("block", [0, 0])
	return int(b[0]) + maxi(0, lvl) * int(b[1])

## The block as flat DR: ceil(N / 2), the rounded-up average of SPD's 0-N roll.
static func block_dr(d: Dictionary, lvl: int) -> int:
	return (block_max(d, lvl) + 1) / 2

## Dagger, Dirk, Assassin's Blade (SPD damageRoll on a surprise): the roll starts `surprise_pct` of the way to max.
## Returns the extra average damage a surprise swing gets over a normal one (0 for other weapons).
static func surprise_bonus(d: Dictionary, lvl: int) -> int:
	if not d.has("surprise_pct"): return 0
	var lo := min_dmg(d, lvl); var hi := max_dmg(d, lvl)
	var sur_lo := lo + int(round((hi - lo) * float(d.surprise_pct)))
	return (sur_lo + hi) / 2 - dmg(d, lvl)

## SPD stats_desc lines for the item window. lvl: the shown level (0 for an unidentified item), so a shield's block
## range is the one it has now, like SPD's RoundShield/Greatshield statsInfo (4 + lvl, 6 + 2 * lvl).
static func stat_lines(d: Dictionary, lvl := 0) -> Array:
	var out := []
	var dl := float(d.get("delay", 1.0)); var a := acc(d)
	if dl <= 0.5: out.append("This is a very fast weapon.")
	elif dl < 1.0: out.append("This is a rather fast weapon.")
	elif dl > 1.0: out.append("This is a rather slow weapon.")
	if int(d.get("str", 10)) > 8 + 2 * int(d.get("tier", 1)): out.append("This weapon is incredibly heavy.")
	if a > 1.0: out.append("This is a rather accurate weapon.")
	elif a < 1.0: out.append("This is a rather inaccurate weapon.")
	if d.get("no_surprise", false): out.append("This weapon cannot surprise attack.")
	if reach(d) >= 3: out.append("This weapon has tremendous reach.")
	elif reach(d) == 2: out.append("This weapon has extra reach.")
	if d.has("surprise_pct"): out.append("This weapon is stronger against unaware enemies.")
	if d.has("block"):
		var scales := int(d.block[1]) > 0
		out.append("This weapon blocks 0-%d damage.%s" % [block_max(d, lvl), " This blocking scales with upgrades." if scales else ""])
	return out

## The SPD item window text for a weapon: description, the tier/damage/strength line, the strength note, and the
## stats lines, with the game's deterministic numbers (per hit, ticks per swing, reach in tiles) in brackets.
static func info_lines(id: String, lvl: int, known: bool, hero_str := -1) -> Array:
	var d := DB.item(id)
	var out := []
	if d.has("spd_desc"): out.append(String(d.spd_desc))
	var l := lvl if known else 0
	var req := str_req(d, l)
	out.append("%s tier-%d melee weapon deals %d-%d damage (%d per hit) and requires %d strength to use properly." % [
		"This" if known else "Typically this", int(d.tier), min_dmg(d, l), max_dmg(d, l), dmg(d, l), req])
	if hero_str >= 0 and req > hero_str:
		out.append("Because of your inadequate strength this weapon will hinder your attack, and you can't surprise attack with it.")
	var bits := []
	var dl := float(d.get("delay", 1.0))
	if dl != 1.0: bits.append("%s ticks per swing" % _num(dl))
	if reach(d) > 1: bits.append("reach %d tiles" % reach(d))
	if d.has("block"): bits.append("+%d DR" % block_dr(d, l))
	if d.has("surprise_pct"): bits.append("surprise hits +%d" % surprise_bonus(d, l))
	if acc(d) < 1.0: bits.append("misses %d%% of swings at alert foes" % int(round((1.0 - acc(d)) * 100)))
	elif acc(d) > 1.0: bits.append("hits dodging foes with %d%% of swings" % int(round((acc(d) - 1.0) * 100)))
	var sl := stat_lines(d, l)
	if not sl.is_empty(): out.append(" ".join(sl) + ((" (" + ", ".join(bits) + ")") if not bits.is_empty() else ""))
	if d.has("spd_note"): out.append(String(d.spd_note))
	return out

static func _num(f: float) -> String:
	return num(f)

## A stat number with up to two decimals and no trailing zeros past `min_dec`: 1.25 stays "1.25" (the Scimitar's
## 1/0.8 speed read "1.2" under "%.1f"), 1.5 -> "1.5", 2 -> "2" (or "2.0" with min_dec 1) (DECISIONS #215).
static func num(f: float, min_dec := 0) -> String:
	var s := "%.2f" % f
	while s.contains(".") and s.ends_with("0") and s.length() - s.find(".") - 1 > min_dec: s = s.left(-1)
	return s.trim_suffix(".")

## Ids a delve can drop at each tier (SPD Generator WEP_T1..T5; the Mage's Staff is never found).
static func pool(tier: int) -> Array:
	var out := []
	for k in DB.items:
		var d: Dictionary = DB.items[k]
		if is_weapon(d) and int(d.get("tier", 0)) == tier and not d.get("heirloom", false): out.append(k)
	out.sort()
	return out

## SPD Generator.randomWeapon(floorSet): a tier by the floor set's odds, then any weapon of that tier (equal weights).
## `roll` is a non-negative int from the caller's seeded RNG; the same roll always picks the same weapon.
static func random_for_floor(floor: int, roll: int) -> String:
	var fs := clampi(floor / 5, 0, FLOOR_SET_TIER_PROBS.size() - 1)
	var probs: Array = FLOOR_SET_TIER_PROBS[fs]
	var total := 0
	for p in probs: total += int(p)
	var r := roll % total
	var tier := 1
	for i in probs.size():
		if r < int(probs[i]): tier = i + 1; break
		r -= int(probs[i])
	var ids := pool(tier)
	return String(ids[(roll / total) % ids.size()])
