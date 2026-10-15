## GameState: the persistent account (Camp, Stash, heroes, facilities, timers) and the active run.
## Pure data + rules; UI screens call these methods and listen to `changed`.
## Everything here is serialisable through to_dict()/from_dict() (see SaveSystem).
extends Node

signal changed
signal toast(text: String)
signal settings_changed

const PACK_MATS := ["gold","dew","iron_ore","dark_gold","seeds","arcane_resin","iron_key","potion_strength","scroll_upgrade"]
const BACKPACK_SLOTS := 8          # found gear + unequipped owned gear carried on a delve (DECISIONS #67)
const SUPPLY_KEYS := ["ration","torch","potion_healing","scroll_passage","elixir_starter"]

var mats: Dictionary = {}          # stash materials & consumables
var gear: Array = []               # [{uid,id,lvl,cracked,known}]
var next_uid := 1
var heroes: Dictionary = {}        # class -> hero dict
var facilities: Dictionary = {}    # id -> {level, cap}
var id_queue: Array = []           # [{uid, ready_at}]
var boss_kills: Dictionary = {}    # class -> [biome ids]  (first kill per class drops a Scroll of Upgrade)
## text_scale multiplies the UI font size; haptics = vibrate on hits/traps (Android); dev_tools shows the Developer section.
var settings := {"sfx": 0.8, "music": 0.5, "haptics": true, "text_scale": 1.0, "dev_tools": false, "tutorial": true,
	"delve_speed": 1.0, "lighting": true}
const STATS_DEFAULT := {"potions_brewed": 0, "deepest_floor": 0, "runs": 0, "deaths": 0, "extractions": 0, "kills": 0,
	"traps_found": 0, "hidden_doors": 0, "goo_kills": 0, "tengu_kills": 0}
var stats := STATS_DEFAULT.duplicate()
var milestones_claimed: Array = []  # milestone ids already rewarded
var seen: Dictionary = {}          # codex discoveries: "mob:rat", "trap:worn_dart", "item:dagger" -> true
var tutorial_done: Array = []      # onboarding steps already shown
var last_result := ""              # "extract" / "death" / "abandon" of the run that just ended (not saved)
var run: Dictionary = {}           # empty when no expedition is active
var time_offset := 0.0             # tests / debug can fast-forward wall-clock time
var messages: PackedStringArray = []

func _ready() -> void:
	if heroes.is_empty(): new_game()

func now() -> float:
	return Time.get_unix_time_from_system() + time_offset

func say(t: String) -> void:
	messages.append(t)
	if messages.size() > 80: messages.remove_at(0)
	toast.emit(t)

func touch() -> void:
	if not heroes.is_empty(): check_milestones()
	changed.emit()

# ---------------------------------------------------------------- setup
func new_game() -> void:
	mats = {"gold": 30, "ration": 2, "torch": 2, "potion_healing": 1, "iron_key": 1, "seeds": 2}
	gear = []; next_uid = 1; id_queue = []; boss_kills = {}; run = {}; time_offset = 0.0
	stats = STATS_DEFAULT.duplicate(); milestones_claimed = []; seen = {}; tutorial_done = []
	_roll_appearances()
	facilities = {}
	for f in DB.facilities: facilities[f] = {"level": 1, "cap": 1}
	heroes = {}
	for c in DB.heroes:
		var h: Dictionary = DB.heroes[c]
		heroes[c] = {"class": c, "unlocked": h.unlocked_by_default, "level": 1, "xp": 0, "str": 10,
			"weapon": add_gear(h.start_weapon), "armor": add_gear(h.start_armor), "ring": 0, "artifact": 0,
			"wand": "wand_magic_missile" if c == "mage" else "", "cleared": [], "patrol": {}, "mask": false, "subclass": "", "talents": []}

func add_gear(id: String, known := true, lvl := 0) -> int:
	var g := {"uid": next_uid, "id": id, "lvl": lvl, "cracked": false, "known": known}
	if known: seen["item:" + id] = true
	next_uid += 1
	gear.append(g)
	return g.uid

func gear_by_uid(uid: int) -> Dictionary:
	for g in gear:
		if g.uid == uid: return g
	return {}

func gear_name(g: Dictionary) -> String:
	if g.is_empty(): return "-"
	var d := DB.item(g.id)
	var n: String = d.name if g.known else d.get("unknown_name", "Unknown " + d.type)
	if g.lvl > 0 and g.known: n += " +%d" % g.lvl
	if g.cracked: n += " (cracked)"
	return n

func equipped_by(uid: int) -> String:
	for c in heroes:
		var h: Dictionary = heroes[c]
		if h.weapon == uid or h.armor == uid or h.ring == uid or int(h.get("artifact", 0)) == uid: return c
	return ""

func mat(id: String) -> int:
	return int(mats.get(id, 0))

func add_mat(id: String, n: int) -> void:
	mats[id] = mat(id) + n

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if mat(k) < int(cost[k]): return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_afford(cost): return false
	for k in cost: mats[k] = mat(k) - int(cost[k])
	return true

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost: parts.append("%d %s" % [cost[k], DB.mat_name(k)])
	return ", ".join(parts)

# ---------------------------------------------------------------- hero stats
func xp_to_next(level: int) -> int:
	return 5 + level * 5   # SPD Hero.maxExp()

## Derived combat stats for a hero with current equipment.
func hero_stats(c: String) -> Dictionary:
	var h: Dictionary = heroes[c]
	var def: Dictionary = DB.heroes[c]
	var w := gear_by_uid(h.weapon); var a := gear_by_uid(h.armor); var r := gear_by_uid(h.ring)
	var art := gear_by_uid(int(h.get("artifact", 0)))
	# cracked/missing weapon: fight with the class's starting weapon stats (bare minimum)
	var wd := DB.item(w.id) if not w.is_empty() and not w.cracked else DB.item(def.start_weapon)
	var ad := DB.item(a.id) if not a.is_empty() and not a.cracked else {}
	var wl := int(w.get("lvl", 0)); var al := int(a.get("lvl", 0))
	var dmg := int(wd.dmg) + wl * (int(wd.tier) + 1) / 2          # upgrades: +((tier+1)/2) per level
	if wd.has("dmg_per_levels"): dmg += int(h.level) / int(wd.dmg_per_levels)
	var dr := int(ad.get("dr", 0)) + al
	var barrier := int(def.base_barrier) + int(def.heirloom_barrier) + int(ad.get("barrier", 0)) + al
	# Strength gate: each missing point costs 2 damage / 1 DR (SPD-like penalty, deterministic)
	var str_short := maxi(0, int(wd.get("str", 10)) - int(h.str))
	dmg = maxi(1, dmg - 2 * str_short)
	dr = maxi(0, dr - maxi(0, int(ad.get("str", 10)) - int(h.str)))
	if not r.is_empty() and r.known and not r.cracked:
		var rd := DB.item(r.id)
		dmg += int(rd.get("dmg_bonus", 0)); barrier += int(rd.get("barrier_bonus", 0)); dr += int(rd.get("dr_bonus", 0))
	var s := {"class": c, "name": def.name, "sprite": def.sprite, "fw": def.fw, "fh": def.fh,
		"ht": int(def.base_ht) + int(def.ht_per_level) * (int(h.level) - 1),
		"dmg": dmg, "dr": dr, "barrier_max": barrier, "delay": float(wd.get("delay", 1.0)),
		"surprise_mult": float(wd.get("surprise_mult", 1.5)), "abilities": def.abilities,
		"search_radius": int(def.get("search_radius", 1)), "keen_eyes": def.get("keen_eyes", false)}
	# ring / artifact extras (DECISIONS #80)
	for eq in [r, art]:
		if eq.is_empty() or eq.cracked or not eq.known: continue
		var ed := DB.item(eq.id)
		s.ht += int(ed.get("ht_bonus", 0)); s.search_radius += int(ed.get("search_add", 0))
		if ed.get("keen_eyes", false): s.keen_eyes = true
		if ed.has("gold_mult"): s.gold_mult = float(ed.gold_mult)
		if ed.has("hunger_mult"): s.hunger_mult = float(ed.hunger_mult)
		s.charges_bonus = int(s.get("charges_bonus", 0)) + int(ed.get("charges_bonus", 0))
	if "bolt" in def.abilities and h.wand != "":
		var wn := DB.item(h.wand)
		s.bolt = {"dmg": int(wn.bolt_dmg) + int(h.level) / 2, "charges": int(wn.charges) + int(h.level) / int(def.get("charge_per_levels", 99)), "recharge": int(wn.recharge),
			"burns_grass": wn.get("burns_grass", false), "chains_water": wn.get("chains_water", false), "name": wn.name, "magic": true}
	if "shoot" in def.abilities:
		# SPD Spirit Bow: (1 + lvl/5) - (6 + lvl/2.5), collapsed to the average
		var lv := int(h.level)
		s.bolt = {"dmg": (1 + lv / 5 + 6 + int(lv / 2.5)) / 2, "charges": 0, "infinite": true, "recharge": 0,
			"name": "the Spirit Bow", "magic": false}
	if "cloak" in def.abilities:
		s.cloak = {"charges": int(def.cloak_charges), "ticks": float(def.cloak_ticks)}
	# Talents (DECISIONS #66): flat modifiers, picked by level
	for tid in h.get("talents", []):
		var td := talent_def(c, tid)
		s.ht += int(td.get("ht_add", 0)); s.dmg += int(td.get("dmg_add", 0)); s.dr += int(td.get("dr_add", 0))
		s.barrier_max += int(td.get("barrier_add", 0)); s.search_radius += int(td.get("search_add", 0))
		s.surprise_mult += float(td.get("surprise_add", 0.0)); s.potion_add = float(s.get("potion_add", 0.0)) + float(td.get("potion_add", 0.0))
		if s.has("cloak"): s.cloak.charges += int(td.get("cloak_add", 0))
		if s.has("bolt"):
			s.bolt.dmg += int(td.get("bolt_add", 0))
			if not s.bolt.get("infinite", false): s.bolt.charges += int(td.get("charges_add", 0))
	if s.has("bolt") and not s.bolt.get("infinite", false): s.bolt.charges += int(s.get("charges_bonus", 0))   # Ring of Energy
	# Subclass (Tengu's Mask, DECISIONS #61): flat modifiers here, "perk" hooks in Combat.
	var sub: Dictionary = def.get("subclasses", {}).get(String(h.get("subclass", "")), {})
	if not sub.is_empty():
		s.sub = String(h.subclass); s.perk = sub.get("perk", ""); s.sub_name = sub.name
		s.dr += int(sub.get("dr_add", 0)); s.barrier_max += int(sub.get("barrier_add", 0))
		s.surprise_mult += float(sub.get("surprise_add", 0.0)); s.delay *= float(sub.get("delay_mult", 1.0))
		if s.has("cloak"): s.cloak.charges += int(sub.get("cloak_add", 0))
		if s.has("bolt"):
			s.bolt.dmg += int(sub.get("bolt_add", 0))
			if sub.get("bolt_pierce", false): s.bolt.pierce = true
	return s

# ---------------------------------------------------------------- talents (SPD-style tiers, DECISIONS #66)
func talent_def(c: String, tid: String) -> Dictionary:
	for tier in ["1", "2"]:
		var t: Dictionary = DB.talents.get(c, {}).get(tier, {})
		if t.has(tid): return t[tid]
	return {}

func talent_tier(c: String, tid: String) -> String:
	for tier in ["1", "2"]:
		if DB.talents.get(c, {}).get(tier, {}).has(tid): return tier
	return ""

## Points earned in a tier at the hero's current level.
func talent_points(c: String, tier: String) -> int:
	var lv := int(heroes[c].level)
	return DB.talents._tiers[tier].points_at.filter(func(l): return lv >= int(l)).size()

func talent_points_free(c: String, tier: String) -> int:
	var used: int = heroes[c].get("talents", []).filter(func(t): return talent_tier(c, t) == tier).size()
	return talent_points(c, tier) - used

func talent_points_total_free(c: String) -> int:
	return talent_points_free(c, "1") + talent_points_free(c, "2")

## Bot / sims: spend free points on the first talents in data order.
func auto_pick_talents(c: String) -> void:
	for tier in ["1", "2"]:
		for tid in DB.talents.get(c, {}).get(tier, {}):
			if can_pick_talent(c, tid) == "": pick_talent(c, tid)

func can_pick_talent(c: String, tid: String) -> String:
	var tier := talent_tier(c, tid)
	if tier == "": return "unknown talent"
	if tid in heroes[c].get("talents", []): return "already learned"
	if talent_points_free(c, tier) <= 0:
		return "reach Lv%d" % int(DB.talents._tiers[tier].from_level) if talent_points(c, tier) == 0 else "no free tier %s points" % tier
	return ""

## Works in Camp and mid-delve (stats refresh immediately; max HP gains are added to current run HP).
func pick_talent(c: String, tid: String) -> bool:
	if can_pick_talent(c, tid) != "": return false
	var before := int(hero_stats(c).ht)
	if not heroes[c].has("talents"): heroes[c].talents = []
	heroes[c].talents.append(tid)
	if not run.is_empty() and run.hero == c: run.hp = int(run.hp) + int(hero_stats(c).ht) - before
	say("Talent learned: %s" % talent_def(c, tid).name); touch()
	return true

# ---------------------------------------------------------------- backpack (in-delve inventory, DECISIONS #67)
func backpack_used() -> int:
	return 0 if run.is_empty() else run.pack_gear.size()

func backpack_full() -> bool:
	return backpack_used() >= BACKPACK_SLOTS

func pack_item(uid: int) -> Dictionary:
	if run.is_empty(): return {}
	for g in run.pack_gear:
		if int(g.uid) == uid: return g
	return {}

func _slot_for(t: String) -> String:
	return t if t in ["weapon", "armor", "ring", "artifact"] else ""

## Why a backpack item can't be equipped right now ("" = ok).
func can_delve_equip(uid: int) -> String:
	var g := pack_item(uid)
	if g.is_empty(): return "not in backpack"
	var d := DB.item(g.id); var c: String = run.hero
	if d.type == "wand":
		if c != "mage": return "only the Mage can imbue wands"
		if not g.known: return "unidentified"
		return ""
	if _slot_for(d.type) == "": return "can't be equipped"
	if g.cracked: return "cracked"
	if not g.known and d.type == "ring": return "unidentified"
	if d.get("heirloom", false) and DB.heroes[c].heirloom != g.id: return "heirloom of another class"
	return ""

## Equip from the backpack mid-delve: the item moves into the hero's slot (and the Camp's gear),
## the old item takes its place in the backpack (flagged owned: comes home even on death, cracked).
func delve_equip(uid: int) -> bool:
	if can_delve_equip(uid) != "": return false
	var g := pack_item(uid); var d := DB.item(g.id); var c: String = run.hero; var h: Dictionary = heroes[c]
	var before := int(hero_stats(c).ht)
	run.pack_gear.erase(g)
	if d.type == "wand":
		var old: String = h.wand
		h.wand = g.id
		if old != "": run.pack_gear.append({"uid": _take_uid(), "id": old, "lvl": 0, "cracked": false, "known": true, "owned": true})
		say("Imbued %s into the staff." % d.name)
	else:
		var slot := _slot_for(d.type)
		var old := gear_by_uid(int(h[slot]))
		if not old.is_empty():
			gear.erase(old); old.owned = true; run.pack_gear.append(old)
		g.erase("owned"); gear.append(g); h[slot] = int(g.uid)
		say("Equipped %s." % gear_name(g))
	run.hp = clampi(int(run.hp) + int(hero_stats(c).ht) - before, 1, int(hero_stats(c).ht))
	touch(); return true

func _take_uid() -> int:
	next_uid += 1
	return next_uid - 1

## Unequip a slot into the backpack (needs a free slot; heirlooms stay put).
func delve_unequip(slot: String) -> bool:
	if run.is_empty() or backpack_full(): return false
	var h: Dictionary = heroes[run.hero]
	var g := gear_by_uid(int(h[slot]))
	if g.is_empty() or DB.item(g.id).get("heirloom", false): return false
	gear.erase(g); g.owned = true; run.pack_gear.append(g); h[slot] = 0
	run.hp = mini(int(run.hp), int(hero_stats(run.hero).ht))
	say("Unequipped %s." % gear_name(g)); touch(); return true

## Drop a backpack item for good (owned items you brought from Camp can't be dropped; they're yours).
func delve_drop(uid: int) -> bool:
	var g := pack_item(uid)
	if g.is_empty() or g.get("owned", false): return false
	run.pack_gear.erase(g)
	say("Dropped %s." % gear_name(g)); touch(); return true

## Stat preview for equipping a backpack item: {"dmg": [now, new], "dr": [...], "barrier": [...], "ht": [...]}
func compare_equip(uid: int) -> Dictionary:
	var g := pack_item(uid)
	if g.is_empty(): return {}
	var c: String = run.hero; var h: Dictionary = heroes[c]; var d := DB.item(g.id)
	var a := hero_stats(c)
	var b: Dictionary
	if d.type == "wand":
		var ow: String = h.wand; h.wand = g.id; b = hero_stats(c); h.wand = ow
	else:
		var slot := _slot_for(d.type)
		if slot == "": return {}
		var old: int = int(h[slot]); gear.append(g); h[slot] = int(g.uid)
		b = hero_stats(c)
		h[slot] = old; gear.erase(g)
	var out := {"dmg": [a.dmg, b.dmg], "dr": [a.dr, b.dr], "barrier": [a.barrier_max, b.barrier_max], "ht": [a.ht, b.ht]}
	if a.has("bolt") or b.has("bolt"): out.bolt = [a.get("bolt", {}).get("dmg", 0), b.get("bolt", {}).get("dmg", 0)]
	return out

static func compare_text(cmp: Dictionary) -> String:
	var parts := []
	for k in ["dmg", "dr", "barrier", "ht", "bolt"]:
		if not cmp.has(k): continue
		var v: Array = cmp[k]
		var tag := "" if v[0] == v[1] else (" (+%d)" % (v[1] - v[0]) if v[1] > v[0] else " (%d)" % (v[1] - v[0]))
		parts.append("%s %d->%d%s" % [{"dmg": "Dmg", "dr": "DR", "barrier": "Barrier", "ht": "HP", "bolt": "Bolt"}[k], v[0], v[1], tag])
	return "  ".join(parts)

## Use a belt supply outside combat.
## Unknown potions/scrolls (DECISIONS #80): each save rolls SPD appearances; using one identifies its kind.
const POTION_LOOKS := [["Jade", "POTION_JADE"], ["Turquoise", "POTION_TURQUOISE"], ["Azure", "POTION_AZURE"], ["Indigo", "POTION_INDIGO"], ["Magenta", "POTION_MAGENTA"], ["Bistre", "POTION_BISTRE"]]
const SCROLL_LOOKS := [["Sowilo", "SCROLL_SOWILO"], ["Laguz", "SCROLL_LAGUZ"], ["Yngvi", "SCROLL_YNGVI"], ["Gyfu", "SCROLL_GYFU"], ["Raido", "SCROLL_RAIDO"], ["Mannaz", "SCROLL_MANNAZ"]]
var looks := {}     # mat id -> [appearance name, icon key]
var ided := {}      # mat id -> true once identified

func _roll_appearances() -> void:
	looks = {}; ided = {}
	var r := RandomNumberGenerator.new(); r.randomize()
	var pl := POTION_LOOKS.duplicate(); var sl := SCROLL_LOOKS.duplicate()
	for k in DB.materials:
		var md: Dictionary = DB.materials[k]
		if not md.get("unknown", false): continue
		var pool: Array = pl if md.kind == "potion" else sl
		looks[k] = pool.pop_at(r.randi() % pool.size())

func unknown_mats() -> Array:
	return DB.materials.keys().filter(func(k): return DB.materials[k].get("unknown", false))

func is_mat_known(k: String) -> bool:
	return not DB.materials.get(k, {}).get("unknown", false) or ided.has(k)

func mat_label(k: String) -> String:
	if is_mat_known(k) or not looks.has(k): return DB.materials.get(k, {}).get("name", k.capitalize())
	return "%s %s" % [looks[k][0], "Potion" if DB.materials[k].kind == "potion" else "Scroll"]

func mat_icon_key(k: String) -> String:
	if is_mat_known(k) or not looks.has(k): return ""
	return looks[k][1]

func identify_mat(k: String) -> void:
	if not ided.has(k): ided[k] = true; say("It was a %s!" % DB.materials[k].name)

## Use an unknown-kind potion/scroll from the pack mid-delve (identifies it).
func delve_use_pack(k: String) -> bool:
	if run.is_empty() or int(run.pack.get(k, 0)) <= 0: return false
	var c: String = run.hero
	run.pack[k] = int(run.pack[k]) - 1
	identify_mat(k)
	match k:
		"potion_experience":
			var need := xp_to_next(int(heroes[c].level))
			if grant_xp(c, need): say("Level up! %s is now Lv%d." % [DB.heroes[c].name, heroes[c].level])
		"potion_toxic":
			var ht := int(hero_stats(c).ht)
			run.hp = maxi(1, int(run.hp) - ht / 4); say("Choking gas! -%d HP." % (ht / 4))
		"potion_shielding":
			run.shield_next = int(run.get("shield_next", 0)) + 10; say("A shimmering shield: +10 Barrier in your next fight.")
		"scroll_identify":
			var n := 0
			for g in run.pack_gear:
				if not g.known: g.known = true; seen["item:" + g.id] = true; n += 1
			say("Identified %d item(s)." % n if n > 0 else "Nothing to identify.")
		"scroll_mapping":
			run.progress = minf(99.0, float(run.get("progress", 0.0)) + 40.0); say("The floor's layout floods your mind (+40%).")
		"scroll_teleport":
			run.skip_card = true; say("You blink past whatever lies ahead.")
		_: run.pack[k] = int(run.pack[k]) + 1; return false
	touch(); return true

func delve_use(k: String) -> bool:
	if run.is_empty() or int(run.supplies.get(k, 0)) <= 0: return false
	match k:
		"potion_healing":
			var ht := int(hero_stats(run.hero).ht)
			if int(run.hp) >= ht: return false
			run.hp = mini(ht, int(run.hp) + potion_heal(run.hero)); say("Drank a Potion of Healing.")
		"ration":
			if float(run.satiety) >= 90.0: return false
			run.satiety = minf(100.0, float(run.satiety) + 60.0); say("Ate a ration.")
		"torch":
			if float(run.torch) >= 90.0: return false
			run.torch = minf(100.0, float(run.torch) + 60.0); say("Lit a fresh torch.")
		_: return false
	run.supplies[k] = int(run.supplies[k]) - 1
	touch(); return true

## Full-pack loot waiting for a decision (run.overflow). take = drop `drop_uid` and keep the new item.
func resolve_overflow(drop_uid: int) -> bool:
	if run.is_empty() or run.get("overflow", []).is_empty(): return false
	var newg: Dictionary = run.overflow.pop_front()
	if drop_uid < 0:
		say("Left %s behind." % gear_name(newg)); touch(); return true
	if not delve_drop(drop_uid): run.overflow.push_front(newg); return false
	run.pack_gear.append(newg); say("Took %s." % gear_name(newg)); touch(); return true

## Tengu's Mask: earned by beating Tengu with this class; lets the hero pick one of two subclasses (permanent).
func can_choose_subclass(c: String) -> bool:
	return bool(heroes[c].get("mask", false)) and String(heroes[c].get("subclass", "")) == ""

func choose_subclass(c: String, sub: String) -> bool:
	if not can_choose_subclass(c) or not DB.heroes[c].get("subclasses", {}).has(sub): return false
	heroes[c].subclass = sub
	say("The %s becomes a %s!" % [DB.heroes[c].name, DB.heroes[c].subclasses[sub].name])
	touch()
	return true

## Potion of Healing: flat 10 early, 30% of max HP later so potions stay relevant in deep biomes.
func potion_heal(c: String) -> int:
	var p: Dictionary = DB.materials.potion_healing
	var hs := hero_stats(c)
	return maxi(int(p.heal), int(float(hs.ht) * (float(p.get("heal_pct", 0.0)) + float(hs.get("potion_add", 0.0)))))

func power_rating(c: String) -> int:
	var s := hero_stats(c)
	return int(heroes[c].str) + int(s.dmg / 3) + s.dr

func can_equip(c: String, uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty(): return "missing"
	if g.cracked: return "cracked - repair at the Blacksmith"
	if not g.known and DB.item(g.id).type == "ring": return "unidentified - use the Enchanter's Desk"
	var d := DB.item(g.id)
	if d.get("heirloom", false) and DB.heroes[c].heirloom != g.id: return "heirloom of another class"
	var other := equipped_by(uid)
	if other != "" and other != c: return "equipped by " + DB.heroes[other].name
	if not run.is_empty() and run.hero == c: return "hero is on an expedition"
	return ""

func equip(c: String, uid: int) -> bool:
	if can_equip(c, uid) != "": return false
	var t: String = DB.item(gear_by_uid(uid).id).type
	match t:
		"weapon": heroes[c].weapon = uid
		"armor": heroes[c].armor = uid
		"ring": heroes[c].ring = uid
		"artifact": heroes[c].artifact = uid
		_: return false
	touch(); return true

func grant_xp(c: String, n: int) -> bool:
	var h: Dictionary = heroes[c]
	h.xp += n
	var up := false
	while h.xp >= xp_to_next(h.level):
		h.xp -= xp_to_next(h.level); h.level += 1; up = true
	return up

# ---------------------------------------------------------------- facilities & crafting
func facility_level(id: String) -> int:
	return int(facilities[id].level)

func facility_upgrade_cost(id: String) -> Dictionary:
	var base: Dictionary = DB.facilities[id].upgrade_cost
	var o := {}
	for k in base: o[k] = int(base[k]) * facility_level(id)
	return o

func can_upgrade_facility(id: String) -> String:
	var f: Dictionary = facilities[id]
	if f.level >= int(DB.facilities[id].max): return "max level"
	if f.level >= f.cap: return "capped - apply a Scroll of Upgrade"
	if not can_afford(facility_upgrade_cost(id)): return "need " + cost_text(facility_upgrade_cost(id))
	return ""

func upgrade_facility(id: String) -> bool:
	if can_upgrade_facility(id) != "": return false
	pay(facility_upgrade_cost(id)); facilities[id].level += 1
	say("%s upgraded to level %d." % [DB.facilities[id].name, facilities[id].level]); touch(); return true

func apply_sou(id: String) -> bool:
	var f: Dictionary = facilities[id]
	if mat("scroll_upgrade") < 1 or f.cap >= int(DB.facilities[id].max): return false
	add_mat("scroll_upgrade", -1); f.cap += 1
	say("Scroll of Upgrade: %s cap raised to %d." % [DB.facilities[id].name, f.cap]); touch(); return true

func recipe(fac: String, rid: String) -> Dictionary:
	for r in DB.recipes.get(fac, []):
		if r.id == rid: return r
	return {}

func can_craft(fac: String, rid: String) -> String:
	var r := recipe(fac, rid)
	if r.is_empty(): return "unknown recipe"
	if facility_level(fac) < int(r.min_level): return "needs %s Lv%d" % [DB.facilities[fac].name, r.min_level]
	if not can_afford(r.cost): return "need " + cost_text(r.cost)
	return ""

func craft(fac: String, rid: String) -> bool:
	if can_craft(fac, rid) != "": return false
	var r := recipe(fac, rid)
	pay(r.cost)
	# brewing with an unidentified potion/scroll reveals what it was (SPD alchemy, DECISIONS #85)
	for k in r.cost:
		if DB.materials.get(k, {}).get("unknown", false) and not is_mat_known(k): identify_mat(k)
	var n := int(r.get("out_n", 1))
	if r.has("out"): add_gear(r.out); say("Forged " + DB.display_name(r.out) + ".")
	else: add_mat(r.out_mat, n); say("Made %s%s." % [DB.mat_name(r.out_mat), " x%d" % n if n > 1 else ""])
	if fac == "alchemy": stats.potions_brewed += 1
	check_unlocks()
	touch(); return true

func item_upgrade_cost(uid: int) -> Dictionary:
	return {"iron_ore": 4 * (int(gear_by_uid(uid).lvl) + 1)}

func can_upgrade_item(uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty() or not (DB.item(g.id).type in ["weapon", "armor"]): return "not upgradable"
	if g.cracked: return "repair first"
	if g.lvl >= facility_level("blacksmith"): return "Blacksmith cap +%d" % facility_level("blacksmith")
	if not can_afford(item_upgrade_cost(uid)): return "need " + cost_text(item_upgrade_cost(uid))
	return ""

func upgrade_item(uid: int) -> bool:
	if can_upgrade_item(uid) != "": return false
	pay(item_upgrade_cost(uid)); gear_by_uid(uid).lvl += 1
	say("Upgraded " + gear_name(gear_by_uid(uid)) + "."); touch(); return true

func repair_cost(uid: int) -> Dictionary:
	var g := gear_by_uid(uid)
	return {"iron_ore": 2 + int(DB.item(g.id).get("tier", 1)) + int(g.lvl)}

func repair(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or not g.cracked or not pay(repair_cost(uid)): return false
	g.cracked = false; say("Repaired " + gear_name(g) + "."); touch(); return true

## Drink a Starter Elixir at the elevator: raises a level-1 hero to the Sewers baseline (Lv3).
func use_elixir(c: String) -> bool:
	var h: Dictionary = heroes[c]
	if mat("elixir_starter") < 1 or h.level >= 3: return false
	add_mat("elixir_starter", -1); h.level = 3; h.xp = 0
	say(DB.heroes[c].name + " drinks a Starter Elixir (Lv3)."); touch(); return true

func imbue_wand(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or DB.item(g.id).type != "wand" or not g.known: return false
	var old: String = heroes.mage.wand
	heroes.mage.wand = g.id
	gear.erase(g)
	if old != "": add_gear(old)
	say("Imbued %s into the Mage's Staff." % DB.item(g.id).name); touch(); return true

# ---------------------------------------------------------------- Enchanter's Desk
func identify_seconds() -> float:
	return maxf(60.0, 600.0 - 180.0 * (facility_level("enchanter") - 1))   # 10 / 7 / 4 minutes

func enqueue_identify(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or g.known: return false
	for q in id_queue:
		if q.uid == uid: return false
	var start := now()
	if not id_queue.is_empty(): start = maxf(start, float(id_queue.back().ready_at))
	id_queue.append({"uid": uid, "ready_at": start + identify_seconds()})
	touch(); return true

## Finishes any identifications whose time has passed. Returns identified uids.
func tick_identify() -> Array:
	var done := []
	for q in id_queue.duplicate():
		if float(q.ready_at) <= now():
			var g := gear_by_uid(q.uid)
			if not g.is_empty():
				g.known = true; seen["item:" + g.id] = true; done.append(q.uid); say("Identified: " + gear_name(g))
			id_queue.erase(q)
	if not done.is_empty(): touch()
	return done

# ---------------------------------------------------------------- Offline Patrols
func patrol_max_hours() -> float:
	return [2.0, 4.0, 8.0][clampi(facility_level("guild") - 1, 0, 2)]

func can_patrol(c: String, biome: String) -> String:
	var h: Dictionary = heroes[c]
	if not h.unlocked: return "locked"
	if not h.patrol.is_empty(): return "already patrolling"
	if not run.is_empty() and run.hero == c: return "on an expedition"
	if not (biome in h.cleared): return "clear %s first" % DB.biomes[biome].name
	return ""

func start_patrol(c: String, biome: String) -> bool:
	if can_patrol(c, biome) != "": return false
	heroes[c].patrol = {"biome": biome, "start": now()}
	say("%s sets out to patrol the %s." % [DB.heroes[c].name, DB.biomes[biome].name]); touch(); return true

## Efficiency: hero power vs biome strength gate, clamped 0.25..1.25.
func patrol_efficiency(c: String, biome: String) -> float:
	return clampf(float(power_rating(c)) / (float(DB.biomes[biome].str_gate) + 2.0), 0.25, 1.25)

func patrol_preview(c: String) -> Dictionary:
	var p: Dictionary = heroes[c].patrol
	if p.is_empty(): return {}
	var b: Dictionary = DB.biomes[p.biome]
	var hours := clampf((now() - float(p.start)) / 3600.0, 0.0, patrol_max_hours())
	var eff := patrol_efficiency(c, p.biome)
	var out := {}
	for k in b.patrol_yield_per_hour: out[k] = int(floor(float(b.patrol_yield_per_hour[k]) * hours * eff))
	out["_curios"] = int(floor(hours / float(b.patrol_curio_every_hours)))
	out["_hours"] = hours
	return out

func collect_patrol(c: String) -> Dictionary:
	var y := patrol_preview(c)
	if y.is_empty(): return {}
	for k in y:
		if not String(k).begins_with("_"): add_mat(k, y[k])
	for i in y._curios: add_gear(["ring_might", "ring_tenacity"][(next_uid + i) % 2], false)
	heroes[c].patrol = {}
	say("%s returns from patrol (%.1fh)." % [DB.heroes[c].name, y._hours]); touch()
	return y

# ---------------------------------------------------------------- expeditions
func belt_size() -> int:
	return facility_level("alchemy") + 1

func can_start_run(c: String) -> String:
	var h: Dictionary = heroes[c]
	if not h.unlocked: return "locked: " + DB.heroes[c].get("unlock", "")
	if not run.is_empty(): return "an expedition is already active"
	if not h.patrol.is_empty(): return "hero is on patrol"
	return ""

## loadout: {ration:n, torch:n, potion_healing:n, scroll_passage:n}; taken out of the stash.
func start_run(c: String, loadout: Dictionary, biome := "sewers", seed := -1) -> bool:
	if can_start_run(c) != "": return false
	var sup := {}
	for k in SUPPLY_KEYS:
		var n := mini(int(loadout.get(k, 0)), mat(k))
		if k == "potion_healing": n = mini(n, belt_size())
		sup[k] = n; add_mat(k, -n)
	var s := hero_stats(c)
	var f0 := int(DB.biomes[biome].floors[0])
	run = {"hero": c, "biome": biome, "floor": f0, "progress": 0.0, "torch": 100.0, "satiety": 100.0,
		"hp": s.ht, "pack": {}, "pack_gear": [], "supplies": sup, "seed": seed if seed >= 0 else int(now()) % 100000,
		"events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false}
	stats.runs += 1; note_floor(f0)
	say("%s descends into the %s." % [s.name, DB.biomes[biome].name]); touch(); return true

func pack_add(id: String, n: int) -> void:
	if run.is_empty(): add_mat(id, n); return  # no expedition: straight to the stash
	run.pack[id] = int(run.pack.get(id, 0)) + n

## result: "extract" keeps everything; "death" loses pack, cracks gear, resets hero; "abandon" loses pack.
func end_run(result: String) -> void:
	if run.is_empty(): return
	last_result = result
	var c: String = run.hero
	var h: Dictionary = heroes[c]
	# unused supplies always go back to the stash (they were never "found")
	for k in run.supplies: add_mat(k, int(run.supplies[k]))
	match result:
		"extract":
			for k in run.pack: add_mat(k, int(run.pack[k]))
			for g in run.pack_gear:
				g.erase("owned"); gear.append(g)
			stats.extractions += 1
			say("Extracted! The pack is banked at Camp.")
		"death":
			stats.deaths += 1
			for slot in ["weapon", "armor", "ring", "artifact"]:
				var g := gear_by_uid(int(h.get(slot, 0)))
				# heirlooms (Mage's Staff...) are permanent and never crack
				if not g.is_empty() and not DB.item(g.id).get("heirloom", false): g.cracked = true
			for g in run.pack_gear:
				if g.get("owned", false):
					g.erase("owned")
					if not DB.item(g.id).get("heirloom", false) and DB.item(g.id).type != "wand": g.cracked = true
					gear.append(g)
			h.level = 1; h.xp = 0; h.str = 10; h.talents = []
			say("%s fell. Pack lost, gear cracked, back to Lv1 / 10 Str." % DB.heroes[c].name)
		"abandon":
			for g in run.pack_gear:
				if g.get("owned", false): g.erase("owned"); gear.append(g)
			say("Expedition abandoned. Unbanked loot lost.")
	run = {}
	touch()

func record_boss_kill(c: String, biome: String) -> bool:
	var kills: Array = boss_kills.get(c, [])
	var first := not (biome in kills)
	if first:
		kills.append(biome); boss_kills[c] = kills
		pack_add("scroll_upgrade", 1)
	if not (biome in heroes[c].cleared): heroes[c].cleared.append(biome)
	if DB.biomes[biome].boss == "tengu" and not heroes[c].get("mask", false):
		heroes[c].mask = true
		say("Tengu's Mask! Choose a subclass for the %s in Camp -> Heroes." % DB.heroes[c].name)
	var key: String = DB.biomes[biome].boss + "_kills"
	if stats.has(key): stats[key] += 1
	check_unlocks()
	return first

## Class unlock milestones (DECISIONS.md #11, #31)
func check_unlocks() -> void:
	for c in heroes:
		var rule: Dictionary = DB.heroes[c].get("unlock_rule", {})
		if rule.is_empty() or heroes[c].unlocked: continue
		if stat_value(rule.stat) >= int(rule.goal):
			heroes[c].unlocked = true
			say("The %s has joined the Camp!" % DB.heroes[c].name)

# ---------------------------------------------------------------- meta-progression
## Progress toward a milestone stat (see data/milestones.json).
func stat_value(stat: String) -> int:
	if stat.begins_with("boss:"): return int(stats.get(stat.substr(5) + "_kills", 0))
	if stat.begins_with("cleared:"):
		var b := stat.substr(8)
		return heroes.values().filter(func(h): return b in h.cleared).size()
	return int(stats.get(stat, 0))

## Grant every newly reached milestone (once). Returns the ids granted.
func check_milestones() -> Array:
	var got := []
	for m in DB.milestones:
		if m.id in milestones_claimed or stat_value(m.stat) < int(m.goal): continue
		milestones_claimed.append(m.id); got.append(m.id)
		for k in m.reward: add_mat(k, int(m.reward[k]))
		say("Milestone: %s! Reward: %s" % [m.name, cost_text(m.reward)])
		Sfx.play("badge")
	return got

func add_stat(k: String, n: int) -> void:
	stats[k] = int(stats.get(k, 0)) + n

## Tutorial: should tip `id` be shown now?
func wants_tip(id: String) -> bool:
	return bool(settings.get("tutorial", true)) and DB.tips.has(id) and not (id in tutorial_done)

## Codex: remember that the player has encountered something.
func discover(key: String) -> void:
	if not seen.has(key): seen[key] = true

func set_setting(k: String, v) -> void:
	settings[k] = v
	settings_changed.emit()

func note_floor(f: int) -> void:
	if f > int(stats.deepest_floor):
		stats.deepest_floor = f; check_unlocks()

# ---------------------------------------------------------------- persistence
func to_dict() -> Dictionary:
	return {"mats": mats, "gear": gear, "next_uid": next_uid, "heroes": heroes, "facilities": facilities,
		"id_queue": id_queue, "boss_kills": boss_kills, "settings": settings, "run": run, "stats": stats,
		"milestones_claimed": milestones_claimed, "seen": seen, "tutorial_done": tutorial_done, "looks": looks, "ided": ided}

func from_dict(d: Dictionary) -> void:
	new_game()
	looks = d.get("looks", {}); ided = d.get("ided", {})
	if looks.is_empty(): _roll_appearances()
	mats = d.get("mats", mats); gear = d.get("gear", gear); next_uid = int(d.get("next_uid", next_uid))
	for c in d.get("heroes", {}):
		if heroes.has(c): heroes[c].merge(d.heroes[c], true)
	for f in d.get("facilities", {}):
		if facilities.has(f): facilities[f].merge(d.facilities[f], true)
	id_queue = d.get("id_queue", []); boss_kills = d.get("boss_kills", {})
	settings.merge(d.get("settings", {}), true); run = d.get("run", {})
	stats.merge(d.get("stats", {}), true)
	milestones_claimed = Array(d.get("milestones_claimed", [])); seen = d.get("seen", {}); tutorial_done = Array(d.get("tutorial_done", []))
	settings.text_scale = float(settings.text_scale); settings.delve_speed = float(settings.delve_speed)
	for k in stats: stats[k] = int(stats[k])
	_fix_types()
	touch()

## JSON turns every number into float; normalise ints we compare/use as keys.
func _fix_types() -> void:
	next_uid = int(next_uid)
	for k in mats: mats[k] = int(mats[k])
	for g in gear:
		g.uid = int(g.uid); g.lvl = int(g.lvl)
	for c in heroes:
		var h: Dictionary = heroes[c]
		if not h.has("artifact"): h.artifact = 0
		for k in ["level", "xp", "str", "weapon", "armor", "ring", "artifact"]: h[k] = int(h[k])
	for f in facilities:
		facilities[f].level = int(facilities[f].level); facilities[f].cap = int(facilities[f].cap)
	for q in id_queue: q.uid = int(q.uid)
	if not run.is_empty():
		for k in ["floor", "next_event", "gather", "starve", "seed", "hp", "pending_loot"]: run[k] = int(run.get(k, 0))
		for k in run.pack: run.pack[k] = int(run.pack[k])
		for k in run.supplies: run.supplies[k] = int(run.supplies[k])
		for g in run.pack_gear + run.get("overflow", []):
			g.uid = int(g.uid); g.lvl = int(g.lvl)
		if run.has("pending_card") and run.pending_card.has("room"):
			run.pending_card.room = Array(run.pending_card.room); run.pending_card.mobs = Array(run.pending_card.mobs)
		if run.has("active_fight"):
			# rooms/mob lists come back as plain arrays; Combat.from_dict handles the combat itself
			var ev: Dictionary = run.active_fight.event
			ev.room = Array(ev.room); ev.mobs = Array(ev.mobs)
