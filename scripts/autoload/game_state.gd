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
	"delve_speed": 1.0, "lighting": true, "full_auto": false}
const STATS_DEFAULT := {"potions_brewed": 0, "deepest_floor": 0, "runs": 0, "deaths": 0, "extractions": 0, "kills": 0,
	"traps_found": 0, "hidden_doors": 0, "goo_kills": 0, "tengu_kills": 0, "goo_losses": 0}
var stats := STATS_DEFAULT.duplicate()
var milestones_claimed: Array = []  # milestone ids already rewarded
var seen: Dictionary = {}          # codex discoveries: "mob:rat", "trap:worn_dart", "item:dagger" -> true
var tutorial_done: Array = []      # onboarding steps already shown
var last_result := ""              # "extract" / "death" / "abandon" of the run that just ended (not saved)
var run: Dictionary = {}           # empty when no expedition is active
var time_offset := 0.0             # debug fast-forward; saved so patrol and identify timers survive a relaunch
var messages: PackedStringArray = []

func _ready() -> void:
	if heroes.is_empty(): new_game()

func now() -> float:
	return Time.get_unix_time_from_system() + time_offset

## SPD GLog-style colours (DECISIONS #101).
const LOG_COLORS := {"positive": Color("5cff5c"), "negative": Color("ff5a4a"), "warning": Color("ff9a3c"),
	"highlight": Color("ffff66"), "info": Color("e8e0d0"), "auto": Color("9fd3ff")}
var message_kinds: PackedStringArray = []
var log_serial := 0

static func classify(t: String) -> String:
	var l := t.to_lower()
	if l.begins_with("auto:"): return "auto"
	if l.contains("level up") or l.contains("descend") or l.contains("milestone") or l.contains("first "): return "highlight"
	if l.contains("starv") or l.contains("defeat") or l.contains("lost") or l.contains("died") or l.contains("took "): return "negative"
	if l.contains("low") or l.contains("hungry") or l.contains("warning") or l.contains("dark"): return "warning"
	if l.contains("found") or l.contains("reward") or l.contains("+") or l.contains("gold") or l.contains("repaired") or l.contains("victory"): return "positive"
	return "info"

## Message for the log *and* a toast.
func say(t: String, kind := "") -> void:
	log_line(t, kind)
	toast.emit(t)

## Log only (chatty lines: warnings, auto decisions). Small pickups update the haul line instead.
func log_line(t: String, kind := "") -> void:
	messages.append(t); message_kinds.append(kind if kind != "" else classify(t)); log_serial += 1
	if messages.size() > 80: messages.remove_at(0); message_kinds.remove_at(0)

func touch() -> void:
	if not heroes.is_empty(): check_milestones()
	changed.emit()

# ---------------------------------------------------------------- setup
## Scrolls of Upgrade lost in a death come back on the next boss kill, any hero (DECISIONS #103).
var owed_sou := 0

## Called on a boss kill: returns how many owed Scrolls of Upgrade were put back in the pack (0 if none).
func grant_owed_sou() -> int:
	if owed_sou <= 0 or run.is_empty(): return 0
	var n := owed_sou; owed_sou = 0
	# straight to the Camp stash, so they can't be lost again on this run (DECISIONS #119)
	add_mat("scroll_upgrade", n)
	say("A lost Scroll of Upgrade returns to Camp!" if n == 1 else "%d lost Scrolls of Upgrade return to Camp!" % n, "highlight")
	return n

func new_game() -> void:
	mats = {"gold": 30, "ration": 2, "torch": 2, "potion_healing": 1, "iron_key": 1, "seeds": 2}
	gear = []; next_uid = 1; id_queue = []; boss_kills = {}; run = {}; time_offset = 0.0
	stats = STATS_DEFAULT.duplicate(); milestones_claimed = []; seen = {}; tutorial_done = []; owed_sou = 0
	_roll_appearances()
	facilities = {}
	for f in DB.facilities: facilities[f] = {"level": 1, "cap": 1}
	heroes = {}
	for c in DB.heroes:
		var h: Dictionary = DB.heroes[c]
		heroes[c] = {"class": c, "unlocked": h.unlocked_by_default, "level": 1, "xp": 0, "str": 10, "str_found": [],
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
## SPD Hero.MAX_LEVEL: heroes stop gaining levels (and HP/accuracy/talent points) at 30 (DECISIONS #118).
const MAX_LEVEL := 30
func xp_to_next(level: int) -> int:
	return 5 + level * 5   # SPD Hero.maxExp()

## Derived combat stats for a hero with current equipment.
func hero_stats(c: String) -> Dictionary:
	var h: Dictionary = heroes[c]
	var def: Dictionary = DB.heroes[c]
	var w := gear_by_uid(h.weapon); var a := gear_by_uid(h.armor); var r := gear_by_uid(h.ring)
	var art := gear_by_uid(int(h.get("artifact", 0)))
	# cracked/missing weapon or armor: the class's starter gear (SPD starting items: free, never cracks) (DECISIONS #104)
	var w_ok: bool = not w.is_empty() and not w.cracked; var a_ok: bool = not a.is_empty() and not a.cracked
	var wd := DB.item(w.id) if w_ok else DB.item(def.start_weapon)
	var ad := DB.item(a.id) if a_ok else DB.item(def.get("start_armor", "cloth_armor"))
	var wl := int(w.get("lvl", 0)) if w_ok else 0; var al := int(a.get("lvl", 0)) if a_ok else 0
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
	var s := {"starter_weapon": not w_ok, "starter_armor": not a_ok, "class": c, "name": def.name, "sprite": def.sprite, "fw": def.fw, "fh": def.fh, "row": armor_tier(c),
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
	# The rolled colour or rune is the sprite for the whole save. Identifying changes the name
	# only; falling back to POTION_HOLDER / SCROLL_HOLDER draws the empty black outline.
	if not looks.has(k) and DB.materials.get(k, {}).get("unknown", false): _ensure_look(k)
	if looks.has(k): return String(looks[k][1])
	return ""

## One stable appearance for an unknown potion/scroll that a save never rolled (added in a later version).
func _ensure_look(k: String) -> void:
	var md: Dictionary = DB.materials.get(k, {})
	if looks.has(k) or not md.get("unknown", false): return
	var pool: Array = POTION_LOOKS if md.get("kind", "") == "potion" else SCROLL_LOOKS
	var used := {}
	for id in looks: used[String(looks[id][1])] = true
	var choices: Array = pool.filter(func(p): return not used.has(String(p[1])))
	if choices.is_empty(): choices = pool
	var r := RandomNumberGenerator.new(); r.seed = hash(k) + looks.size()
	looks[k] = choices[r.randi() % choices.size()]

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
	while h.level < MAX_LEVEL and h.xp >= xp_to_next(h.level):
		h.xp -= xp_to_next(h.level); h.level += 1; up = true
	if h.level >= MAX_LEVEL: h.level = MAX_LEVEL; h.xp = 0
	return up

## Guild training (DECISIONS #130): a late-game gold sink. A hero who fell can buy back levels with gold, one at
## a time, up to 2 below the best level it ever reached; never past what it earned, so it can't skip early bosses.
const TRAIN_GAP := 2
func train_cap(c: String) -> int:
	return maxi(1, int(heroes[c].get("best_level", 1)) - TRAIN_GAP)

func train_cost(c: String) -> Dictionary:
	var l := int(heroes[c].level)
	return {"gold": 20 * l * l}

func can_train(c: String) -> String:
	if not run.is_empty() and run.hero == c: return "on an expedition"
	if not heroes[c].patrol.is_empty(): return "patrolling"
	if int(heroes[c].level) >= train_cap(c): return "no lost levels to retrain"
	if not can_afford(train_cost(c)): return "need " + cost_text(train_cost(c))
	return ""

func train(c: String) -> bool:
	if can_train(c) != "": return false
	pay(train_cost(c))
	var h: Dictionary = heroes[c]
	grant_xp(c, xp_to_next(int(h.level)) - int(h.xp))
	say("%s trains at the Guild: Lv %d." % [DB.heroes[c].name, h.level]); touch(); return true

# ---------------------------------------------------------------- facilities & crafting
func facility_level(id: String) -> int:
	return int(facilities[id].level)

func facility_upgrade_cost(id: String) -> Dictionary:
	var base: Dictionary = DB.facilities[id].upgrade_cost
	var o := {}
	for k in base: o[k] = int(base[k]) * facility_level(id)
	return o

## Level cap raised by Scrolls of Upgrade. A level above the stored cap (old saves, debug/test edits) counts as
## the cap, so the cap is never below the level and never above the facility max (DECISIONS #114).
func facility_cap(id: String) -> int:
	var f: Dictionary = facilities[id]
	return clampi(maxi(int(f.cap), int(f.level)), 1, int(DB.facilities[id].max))

## Header text: "Name   Lv level / max", plus "(cap N)" only while the Scroll cap blocks the next level.
static func facility_title(fname: String, level: int, cap: int, mx: int) -> String:
	var t := "%s   Lv %d / %d" % [fname, level, mx]
	if level >= cap and cap < mx: t += "  (cap %d)" % cap
	return t

func can_upgrade_facility(id: String) -> String:
	var f: Dictionary = facilities[id]
	if f.level >= int(DB.facilities[id].max): return "max level"
	if f.level >= facility_cap(id): return "capped - apply a Scroll of Upgrade"
	if not can_afford(facility_upgrade_cost(id)): return "need " + cost_text(facility_upgrade_cost(id))
	return ""

func upgrade_facility(id: String) -> bool:
	if can_upgrade_facility(id) != "": return false
	pay(facility_upgrade_cost(id)); facilities[id].level += 1
	say("%s upgraded to level %d." % [DB.facilities[id].name, facilities[id].level]); touch(); return true

func apply_sou(id: String) -> bool:
	var f: Dictionary = facilities[id]
	if mat("scroll_upgrade") < 1 or facility_cap(id) >= int(DB.facilities[id].max): return false
	add_mat("scroll_upgrade", -1); f.cap = facility_cap(id) + 1
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

## Gold sink (DECISIONS #130): each level also costs 10 x (next level)^2 gold. With a max-level Blacksmith,
## "masterwork" levels past its cap (up to +MASTERWORK_MAX) cost 200 x (next level)^2 gold: +4 3.2k, +5 5k, +6 7.2k.
const MASTERWORK_MAX := 6
static func upgrade_step_cost(next_lvl: int) -> Dictionary:
	var per := 200 if next_lvl > int(DB.facilities.blacksmith.max) else 10
	return {"iron_ore": 4 * next_lvl, "gold": per * next_lvl * next_lvl}

## Highest level the Forge can take gear to right now.
func forge_cap() -> int:
	var l := facility_level("blacksmith")
	return MASTERWORK_MAX if l >= int(DB.facilities.blacksmith.max) else l

func item_upgrade_cost(uid: int) -> Dictionary:
	return upgrade_step_cost(int(gear_by_uid(uid).lvl) + 1)

func can_upgrade_item(uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty() or not (DB.item(g.id).type in ["weapon", "armor"]): return "not upgradable"
	if g.cracked: return "repair first"
	if g.lvl >= forge_cap(): return "Blacksmith cap +%d" % forge_cap()
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

# ---------------------------------------------------------------- bulk Forge/Guild actions (DECISIONS #97)
const BULK_CAP := 99

static func cost_mul(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k in cost: out[k] = int(cost[k]) * n
	return out

static func cost_add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b: out[k] = int(out.get(k, 0)) + int(b[k])
	return out

## How many times recipe `rid` can be made right now (0 when locked/unaffordable), capped at BULK_CAP.
func craft_max(fac: String, rid: String) -> int:
	var r := recipe(fac, rid)
	if r.is_empty() or facility_level(fac) < int(r.min_level): return 0
	var n := BULK_CAP
	for k in r.cost:
		if int(r.cost[k]) > 0: n = mini(n, mat(k) / int(r.cost[k]))
	return n

## Make `n` copies; all or nothing. Returns true when all were made.
func craft_n(fac: String, rid: String, n: int) -> bool:
	if n < 1 or n > craft_max(fac, rid): return false
	for i in n: craft(fac, rid)
	return true

## Total iron ore for `n` successive upgrades of one item (costs rise per level).
func upgrade_cost_n(uid: int, n: int) -> Dictionary:
	var g := gear_by_uid(uid); var total := {}
	for i in n: total = cost_add(total, upgrade_step_cost(int(g.lvl) + i + 1))
	return total

## Most levels the item can gain now: limited by the Blacksmith cap and by what is affordable.
func upgrade_max(uid: int) -> int:
	var g := gear_by_uid(uid)
	if g.is_empty() or g.get("cracked", false) or not (DB.item(g.id).type in ["weapon", "armor"]): return 0
	var room := maxi(0, forge_cap() - int(g.lvl))
	var n := 0
	while n < room and can_afford(upgrade_cost_n(uid, n + 1)): n += 1
	return n

func upgrade_item_n(uid: int, n: int) -> bool:
	if n < 1 or n > upgrade_max(uid): return false
	for i in n: upgrade_item(uid)
	return true

## "Patch up" (DECISIONS #104): when no cracked item's repair is affordable, the Blacksmith repairs the cheapest
## cracked weapon/armor for free, so a total wipe can never lock the player out.
func can_patch_up() -> String:
	var cr := cracked_gear()
	if cr.is_empty(): return "nothing to repair"
	for g in cr:
		if can_afford(repair_cost(g.uid)): return "you can afford a repair"
	return ""

func patch_up() -> bool:
	if can_patch_up() != "": return false
	var cr := cracked_gear()
	cr.sort_custom(func(a, b):
		var wa := 0 if DB.item(a.id).type in ["weapon", "armor"] else 1; var wb := 0 if DB.item(b.id).type in ["weapon", "armor"] else 1
		if wa != wb: return wa < wb
		return int(repair_cost(a.uid).iron_ore) < int(repair_cost(b.uid).iron_ore))
	var g: Dictionary = cr[0]; g.cracked = false
	say("The Blacksmith patches up your %s for free." % gear_name(g), "positive"); touch(); return true

## Relief supplies: a broke Camp (no rations or torches, can't buy one) gets 1 of each when a run starts.
const RELIEF_GOLD := 10
## Gold safety net (DECISIONS #109): a death never leaves the stash below enough gold for one Guild potion.
const SAFETY_GOLD := 30
func needs_relief() -> bool:
	return mat("ration") == 0 and mat("torch") == 0 and mat("gold") < RELIEF_GOLD

func cracked_gear() -> Array:
	return gear.filter(func(g): return g.get("cracked", false))

func repair_all_cost() -> Dictionary:
	var total := {}
	for g in cracked_gear(): total = cost_add(total, repair_cost(g.uid))
	return total

func can_repair_all() -> String:
	if cracked_gear().is_empty(): return "nothing to repair"
	if not can_afford(repair_all_cost()): return "need " + cost_text(repair_all_cost())
	return ""

func repair_all() -> bool:
	if can_repair_all() != "": return false
	var n := 0
	for g in cracked_gear():
		if repair(g.uid): n += 1
	say("Repaired %d item%s." % [n, "" if n == 1 else "s"]); touch(); return true

# ---------------------------------------------------------------- breaking down spare rings (DECISIONS #107)
## A ring melts into a little gold (the band) and resin (the gem). Small on purpose: patrols hand rings out.
func ring_break_yield() -> Dictionary:
	return {"gold": 5, "arcane_resin": 1}

func _is_ring(g: Dictionary) -> bool:
	return not g.is_empty() and DB.item(g.id).type == "ring"

## Higher means keep it. Worn rings always stay; then intact, then identified, then upgrade level.
func _ring_keep_score(g: Dictionary) -> int:
	var s := int(g.lvl)
	if g.known: s += 10
	if not g.get("cracked", false): s += 100
	if equipped_by(int(g.uid)) != "": s += 1000
	return s

func rings_of(id: String) -> Array:
	var out: Array = []
	for g in gear:
		if g.id == id and _is_ring(g): out.append(g)
	return out

## Unequipped copies past one spare of each ring. Worn rings are never extras.
func ring_extras() -> Array:
	var groups := {}
	for g in gear:
		if not _is_ring(g): continue
		if not groups.has(g.id): groups[g.id] = []
		groups[g.id].append(g)
	var extras: Array = []
	for id in groups:
		var list: Array = groups[id]
		list.sort_custom(func(a, b): return _ring_keep_score(a) > _ring_keep_score(b))
		var spare := false
		for g in list:
			if equipped_by(int(g.uid)) != "": continue
			if not spare:
				spare = true
				continue
			extras.append(g)
	return extras

func ring_extras_of(id: String) -> Array:
	var out: Array = []
	for g in ring_extras():
		if g.id == id: out.append(g)
	return out

func can_break_ring(uid: int) -> String:
	var g := gear_by_uid(uid)
	if not _is_ring(g): return "not a ring"
	var who := equipped_by(uid)
	if who != "": return "equipped by " + DB.heroes[who].name
	return ""

## The unequipped copy of this ring to melt first: the most worn-out one, so the spare stays.
func breakable_ring(id: String) -> int:
	var worst: Dictionary = {}
	for g in rings_of(id):
		if can_break_ring(int(g.uid)) != "": continue
		if worst.is_empty() or _ring_keep_score(g) < _ring_keep_score(worst): worst = g
	return int(worst.uid) if not worst.is_empty() else 0

func _forget_gear(uid: int) -> void:
	var g := gear_by_uid(uid)
	if g.is_empty(): return
	gear.erase(g)
	for i in range(id_queue.size() - 1, -1, -1):
		if int(id_queue[i].uid) == uid: id_queue.remove_at(i)

## Melt these rings. Skips anything worn or not a ring. One toast for the whole batch.
func break_rings(list: Array) -> bool:
	var picking: Array = []
	for g in list:
		if can_break_ring(int(g.uid)) == "": picking.append(g)
	if picking.is_empty(): return false
	var n := picking.size()
	var single := gear_name(picking[0]) if n == 1 else ""
	for g in picking: _forget_gear(int(g.uid))
	var y := cost_mul(ring_break_yield(), n)
	for k in y: add_mat(k, int(y[k]))
	if n == 1: say("Broke down %s: %s." % [single, cost_text(y)], "positive")
	else: say("Broke down %d rings: %s." % [n, cost_text(y)], "positive")
	touch(); return true

func break_ring(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty(): return false
	return break_rings([g])

func break_ring_extras() -> bool:
	return break_rings(ring_extras())

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
	if not can_afford(patrol_fee(biome)): return "need " + cost_text(patrol_fee(biome))
	return ""

## Gold sink (DECISIONS #130): provisioning a patrol costs half the gold a full-length patrol of that biome yields.
func patrol_fee(biome: String) -> Dictionary:
	return {"gold": int(float(DB.biomes[biome].patrol_yield_per_hour.get("gold", 0)) * patrol_max_hours() / 2.0)}

func start_patrol(c: String, biome: String) -> bool:
	if can_patrol(c, biome) != "": return false
	pay(patrol_fee(biome))
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
## Most rations / torches an expedition may pack: the Guild's `pack_cap` for its level (DECISIONS #144).
func guild_pack_cap(lvl := -1) -> int:
	var caps: Array = DB.facilities.guild.get("pack_cap", [10])
	if lvl < 0: lvl = facility_level("guild")
	return int(caps[clampi(lvl - 1, 0, caps.size() - 1)])

## Pack limit for one supply, before the stash count: belt size for potions, 1 Passage, the Guild cap for
## rations/torches, 10 for anything else.
func supply_cap(k: String) -> int:
	match k:
		"potion_healing": return belt_size()
		"scroll_passage": return 1
		"ration", "torch": return guild_pack_cap()
	return 10

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
	if needs_relief():
		add_mat("ration", 1); add_mat("torch", 1)
		loadout = loadout.duplicate(); loadout.ration = maxi(1, int(loadout.get("ration", 0))); loadout.torch = maxi(1, int(loadout.get("torch", 0)))
		say("The Camp cook spares you a ration and a torch.", "positive")
	var sup := {}
	for k in SUPPLY_KEYS:
		var n := mini(mini(int(loadout.get(k, 0)), mat(k)), supply_cap(k))
		sup[k] = n; add_mat(k, -n)
	var s := hero_stats(c)
	var f0 := int(DB.biomes[biome].floors[0])
	run = {"hero": c, "biome": biome, "floor": f0, "progress": 0.0, "torch": 100.0, "satiety": 100.0,
		"hp": s.ht, "pack": {}, "pack_gear": [], "supplies": sup, "seed": seed if seed >= 0 else int(now()) % 100000,
		"events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false,
		"haul": {}}
	stats.runs += 1; note_floor(f0)
	say("%s descends into the %s." % [s.name, DB.biomes[biome].name]); touch(); return true

func pack_add(id: String, n: int) -> void:
	if run.is_empty(): add_mat(id, n); return  # no expedition: straight to the stash
	run.pack[id] = int(run.pack.get(id, 0)) + n
	if n > 0:   # cumulative for the delve; spending later does not reduce it
		if not run.has("haul"): run.haul = {}
		run.haul[id] = int(run.haul.get(id, 0)) + n

## Pinned log line: everything picked up this expedition, gold first. Empty until the first pickup.
func haul_line() -> String:
	if run.is_empty(): return ""
	var haul: Dictionary = run.get("haul", {})
	var parts: PackedStringArray = []
	var used := {}
	for k in PACK_MATS:
		var n := int(haul.get(k, 0))
		if n <= 0: continue
		used[k] = true
		parts.append("%d %s" % [n, DB.mat_name(k)])
	var extra: Array = []
	for k in haul:
		if not used.has(k) and int(haul[k]) > 0: extra.append(String(k))
	extra.sort()
	for k in extra: parts.append("%d %s" % [int(haul[k]), DB.mat_name(k)])
	if parts.is_empty(): return ""
	return "Collected this delve: " + ", ".join(parts)

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
			if run.get("fighting_goo", false):   # DECISIONS #131: Goo is a skill check, not a death spiral
				stats.goo_losses = int(stats.get("goo_losses", 0)) + 1
				if mat("potion_healing") < 2:
					add_mat("potion_healing", 2 - mat("potion_healing")); log_line("The Camp healer sends you back to Goo with 2 Potions of Healing.", "positive")
			for slot in ["weapon", "armor", "ring", "artifact"]:
				var g := gear_by_uid(int(h.get(slot, 0)))
				# heirlooms (Mage's Staff...) are permanent and never crack
				if not g.is_empty() and not DB.item(g.id).get("heirloom", false): g.cracked = true
			for g in run.pack_gear:
				if g.get("owned", false):
					g.erase("owned")
					if not DB.item(g.id).get("heirloom", false) and DB.item(g.id).type != "wand": g.cracked = true
					gear.append(g)
			h.best_level = maxi(int(h.get("best_level", 1)), int(h.level))
			h.level = 1; h.xp = 0; h.str = 10; h.talents = []; h.str_found = []
			var lost_sou := int(run.pack.get("scroll_upgrade", 0))
			if lost_sou > 0:
				owed_sou += lost_sou
				log_line("%d Scroll%s of Upgrade will return on the next boss kill (%d owed)." % [lost_sou, "" if lost_sou == 1 else "s", owed_sou], "highlight")
			say("%s fell. Pack lost, gear cracked, back to Lv1 / 10 Str." % DB.heroes[c].name)
			if mat("gold") < SAFETY_GOLD:
				log_line("The Camp chips in %d gold so you can restock." % (SAFETY_GOLD - mat("gold")), "positive")
				add_mat("gold", SAFETY_GOLD - mat("gold"))
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
		"milestones_claimed": milestones_claimed, "seen": seen, "tutorial_done": tutorial_done, "looks": looks, "ided": ided, "owed_sou": owed_sou,
		"time_offset": time_offset}

func from_dict(d: Dictionary) -> void:
	new_game()
	looks = d.get("looks", {}); ided = d.get("ided", {})
	if looks.is_empty(): _roll_appearances()
	else:
		for k in DB.materials:
			if DB.materials[k].get("unknown", false): _ensure_look(k)
	mats = d.get("mats", mats); gear = d.get("gear", gear); next_uid = int(d.get("next_uid", next_uid))
	for c in d.get("heroes", {}):
		if heroes.has(c): heroes[c].merge(d.heroes[c], true)
	for f in d.get("facilities", {}):
		if facilities.has(f): facilities[f].merge(d.facilities[f], true)
	id_queue = d.get("id_queue", []); boss_kills = d.get("boss_kills", {})
	owed_sou = int(d.get("owed_sou", 0))   # older saves: nothing owed
	settings.merge(d.get("settings", {}), true); run = d.get("run", {})
	stats.merge(d.get("stats", {}), true)
	milestones_claimed = Array(d.get("milestones_claimed", [])); seen = d.get("seen", {}); tutorial_done = Array(d.get("tutorial_done", []))
	settings.text_scale = float(settings.text_scale); settings.delve_speed = float(settings.delve_speed)
	for k in stats: stats[k] = int(stats[k])
	time_offset = float(d.get("time_offset", 0.0))   # older saves: no fast-forward
	_fix_types()
	touch()

## Old saves (DECISIONS #98): gear from before item ID lacks known/cracked, and early ring ids used gem names.
const LEGACY_IDS := {"ring_garnet": "ring_might", "ring_ruby": "ring_tenacity", "ring_topaz": "ring_evasion",
	"ring_emerald": "ring_wealth", "ring_onyx": "ring_energy", "ring_of_might": "ring_might", "ring_of_tenacity": "ring_tenacity"}
func _fix_gear(g: Dictionary) -> void:
	g.uid = int(g.uid); g.lvl = int(g.get("lvl", 0))
	if not g.has("known"): g.known = true
	if not g.has("cracked"): g.cracked = false
	if LEGACY_IDS.has(g.id): g.id = LEGACY_IDS[g.id]

## Every key start_run creates, with its start value (for loading runs saved by older versions).
const RUN_DEFAULTS := {"biome": "sewers", "floor": 1, "progress": 0.0, "torch": 100.0, "satiety": 100.0, "hp": 1, "pack": {}, "pack_gear": [],
	"supplies": {}, "seed": 0, "events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false}

## JSON turns every number into float; normalise ints we compare/use as keys.
func _fix_types() -> void:
	next_uid = int(next_uid)
	for k in mats: mats[k] = int(mats[k])
	for g in gear: _fix_gear(g)
	for c in heroes:
		var h: Dictionary = heroes[c]
		if not h.has("artifact"): h.artifact = 0
		if not h.has("str_found"): h.str_found = []   # saves before #129: past potions unknown, Str kept as is
		h.str_found = Array(h.str_found)
		for k in ["level", "xp", "str", "weapon", "armor", "ring", "artifact"]: h[k] = int(h[k])
		if h.level > MAX_LEVEL: h.level = MAX_LEVEL; h.xp = 0   # saves from before the cap
		# a start ahead of the clock (fast-forward that was not saved) stays at 0% until that gap passes
		var p: Dictionary = h.get("patrol", {})
		if not p.is_empty() and float(p.get("start", 0)) > now(): p.start = now()
	for f in facilities:
		facilities[f].level = int(facilities[f].level); facilities[f].cap = int(facilities[f].cap)
		if DB.facilities.has(f): facilities[f].cap = facility_cap(f)
	for q in id_queue: q.uid = int(q.uid)
	if not run.is_empty():
		# runs saved before a field existed (backpack #67, milestones, boss flag...) get its start value (DECISIONS #117)
		for k in RUN_DEFAULTS:
			if not run.has(k): run[k] = RUN_DEFAULTS[k].duplicate(true) if RUN_DEFAULTS[k] is Array or RUN_DEFAULTS[k] is Dictionary else RUN_DEFAULTS[k]
		for k in ["floor", "next_event", "gather", "starve", "seed", "hp", "pending_loot"]: run[k] = int(run.get(k, 0))
		if DB.biomes.has(run.get("biome", "")):   # a save can never show "Floor 25 / 5": keep floor inside its biome
			var fr: Array = DB.biomes[run.biome].floors; run.floor = clampi(int(run.floor), int(fr[0]), int(fr[1]))
		for k in run.pack: run.pack[k] = int(run.pack[k])
		# older saves have no haul: start from whatever is still in the pack
		if not run.has("haul"):
			run.haul = {}
			for k in run.pack:
				if int(run.pack[k]) > 0: run.haul[k] = int(run.pack[k])
		else:
			for k in run.haul: run.haul[k] = int(run.haul[k])
		for k in run.supplies: run.supplies[k] = int(run.supplies[k])
		for g in run.pack_gear + run.get("overflow", []):
			_fix_gear(g)
		if run.has("pending_card") and run.pending_card.has("room"):
			run.pending_card.room = Array(run.pending_card.room); run.pending_card.mobs = Array(run.pending_card.mobs)
		if run.has("active_fight"):
			# rooms/mob lists come back as plain arrays; Combat.from_dict handles the combat itself
			var ev: Dictionary = run.active_fight.event
			ev.room = Array(ev.room); ev.mobs = Array(ev.mobs)


## SPD Hero.tier() / HeroSprite row: 0 = nothing worn, otherwise the armor's tier
## (cloth = 1 … plate = 5, class armor = 6). Row 0 is the naked sheet.
func armor_tier(c: String) -> int:
	if not heroes.has(c): return 0
	var a := gear_by_uid(int(heroes[c].get("armor", -1)))
	if a.is_empty(): return 0
	return clampi(int(DB.item(a.id).get("tier", 1)), 0, 6)
