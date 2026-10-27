## GameState: the persistent account (Camp, Stash, heroes, facilities, timers) and the active run.
## Pure data + rules; UI screens call these methods and listen to `changed`.
## Everything here is serialisable through to_dict()/from_dict() (see SaveSystem).
extends Node

signal changed
signal toast(text: String)
signal settings_changed

const PACK_MATS := ["gold","dew","iron_ore","dark_gold","seeds","arcane_resin","iron_key","potion_strength","scroll_upgrade"]
const BIG_HAUL_GOLD := 300        # "Heavy Pockets": extract with this much gold in the pack (DECISIONS #195)
const BACKPACK_SLOTS := 8          # found gear + unequipped owned gear carried on a delve (DECISIONS #67)
const SUPPLY_KEYS := ["ration","torch","potion_healing","scroll_passage","elixir_starter"]

var mats: Dictionary = {}          # stash materials & consumables
var gear: Array = []               # [{uid,id,lvl,cracked,known}]
var next_uid := 1
## Shared forge weapon/armor for the whole party (DECISIONS #234). New games start with free
## Worn Shortsword + Cloth Armor; empty only after a wipe/migration edge, then refill.
## {id, lvl}; never cracked. Found weapons stay per-hero overrides; Mage/Huntress keep heirloom melee.
var camp_weapon: Dictionary = {}
var camp_armor: Dictionary = {}
const CAMP_WEAPON_UID := -1
const CAMP_ARMOR_UID := -2
const DEFAULT_CAMP_WEAPON := "worn_shortsword"
const DEFAULT_CAMP_ARMOR := "cloth_armor"
var heroes: Dictionary = {}        # class -> hero dict
var facilities: Dictionary = {}    # id -> {level, cap}
var id_queue: Array = []           # [{uid, ready_at}]
var boss_kills: Dictionary = {}    # class -> [biome ids]  (first kill per class drops a Scroll of Upgrade)
## text_scale multiplies the UI font size; haptics = vibrate on hits/traps (Android); dev_tools shows the Developer section.
## patrol_notify (default off) asks Android to ping when a patrol is ready; PC and web ignore it (DECISIONS #229).
## interface: auto|mobile|desktop - Auto picks Desktop off phones (DECISIONS #232). keybinds: combat InputMap overrides.
var settings := {"sfx": 0.8, "music": 0.5, "haptics": true, "text_scale": 1.0, "dev_tools": false, "tutorial": true,
	"delve_speed": 1.0, "lighting": true, "full_auto": false, "patrol_notify": false,
	"interface": "auto", "keybinds": {}}
const FREE_PASSAGE_USES := 3   # free Scroll of Passage each run until Goo or this many uses (DECISIONS #226)
const STATS_DEFAULT := {"potions_brewed": 0, "deepest_floor": 0, "runs": 0, "deaths": 0, "extractions": 0, "kills": 0,
	"traps_found": 0, "hidden_doors": 0, "goo_kills": 0, "tengu_kills": 0, "goo_losses": 0,
	"free_passage_uses": 0,
	# milestone counters (DECISIONS #195); per-mob kills are "kill_<mob>" keys added as they happen
	"dm300_kills": 0, "dking_kills": 0, "yog_kills": 0, "gold_banked": 0, "gold_spent": 0, "items_upgraded": 0, "items_forged": 0,
	"items_found": 0, "items_identified": 0, "potions_drunk": 0, "scrolls_read": 0, "rations_eaten": 0, "surprises": 0,
	"patrols": 0, "patrol_hours": 0, "patrol_curios": 0, "chests": 0, "rooms": 0, "feat_flawless_boss": 0, "feat_manual_boss": 0,
	"feat_dry_boss": 0, "feat_close_call": 0, "feat_crowd": 0, "feat_big_haul": 0}
var stats := STATS_DEFAULT.duplicate()
var milestones_claimed: Array = []  # milestone ids already rewarded (paid)
var milestones_reached: Array = []  # milestone ids whose goal was met; claimable until also in milestones_claimed (DECISIONS #195)
var seen: Dictionary = {}          # codex discoveries: "mob:rat", "trap:worn_dart", "item:dagger" -> true
var tutorial_done: Array = []      # onboarding steps already shown
var last_result := ""              # "extract" / "death" / "abandon" of the run that just ended (not saved)
var run: Dictionary = {}           # empty when no expedition is active
var time_offset := 0.0             # debug fast-forward; saved so patrol and identify timers survive a relaunch
var _suspend_patrol_sync := false  # from_dict's new_game must not publish an empty widget snapshot
var messages: PackedStringArray = []

func _ready() -> void:
	# Vita defers content until the loading scene has called DB.reload(). Other platforms start here.
	if VitaBoot.on_device():
		return
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

## Message for the log *and* a toast. While capture_says runs, the line is collected for its caller instead
## of toasting (the Backpack shows a used item's lines in a pop-up, DECISIONS #214).
func say(t: String, kind := "") -> void:
	log_line(t, kind)
	if _captured is Array: _captured.append(t); return
	toast.emit(t)

var _captured = null   # Array while capture_says runs, else null

## Run `f` (returns bool) and hand back {ok, lines}: every say() it made, milestones from its touch() included.
func capture_says(f: Callable) -> Dictionary:
	var outer = _captured
	_captured = []
	var ok := bool(f.call())
	var lines: Array = _captured
	_captured = outer
	if outer is Array: outer.append_array(lines)
	return {"ok": ok, "lines": lines}

## Why a belt supply can't be used right now ("" if it can). delve_use refuses these silently.
func delve_use_block_reason(k: String) -> String:
	if run.is_empty() or int(run.supplies.get(k, 0)) <= 0: return "You have none left."
	match k:
		"potion_healing": if int(run.hp) >= int(hero_stats(run.hero).ht): return "You're already at full health."
		"ration": if float(run.satiety) >= 90.0: return "You're not hungry yet."
		"torch": if float(run.torch) >= 90.0: return "Your torch is still burning bright."
	return ""

## Log only (chatty lines: warnings, auto decisions). Small pickups update the haul line instead.
func log_line(t: String, kind := "") -> void:
	messages.append(t); message_kinds.append(kind if kind != "" else classify(t)); log_serial += 1
	if messages.size() > 80: messages.remove_at(0); message_kinds.remove_at(0)

func touch() -> void:
	if not heroes.is_empty(): check_milestones()
	changed.emit()

## Publish patrol countdowns to the Android widget. No-op until PatrolBridge is in the tree, and no-op without the plugin.
func sync_patrol_widget() -> void:
	var bridge := get_node_or_null("/root/PatrolBridge")
	if bridge and bridge.has_method("push"):
		bridge.push(self)

## Developer fast-forward. Moves patrol return timestamps, not just the identify queue.
func skip_time(seconds: float) -> void:
	time_offset += seconds
	tick_identify()
	sync_patrol_widget()
	touch()

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

## Gold for a full first-delve buy at Lv1 facilities: 3 rations (30) + 3 torches (24) +
## 2 healing potions (60) + 1 Scroll of Passage at the Enchanter (20). No starting resin -
## early runs use the free Passage until Goo falls; the Passage gold is spare until resin drops.
const STARTING_GOLD := 134

func new_game() -> void:
	# Empty supply stash on purpose: buy rations, torches and potions at the Guild before the first delve.
	mats = {"gold": STARTING_GOLD, "ration": 0, "torch": 0, "potion_healing": 0, "iron_key": 1, "seeds": 2}
	gear = []; next_uid = 1; id_queue = []; boss_kills = {}; run = {}; time_offset = 0.0
	camp_weapon = {"id": DEFAULT_CAMP_WEAPON, "lvl": 0}
	camp_armor = {"id": DEFAULT_CAMP_ARMOR, "lvl": 0}
	stats = STATS_DEFAULT.duplicate(); milestones_claimed = []; milestones_reached = []; seen = {}; tutorial_done = []; owed_sou = 0
	seen["item:" + DEFAULT_CAMP_WEAPON] = true
	seen["item:" + DEFAULT_CAMP_ARMOR] = true
	_roll_appearances()
	facilities = {}
	for f in DB.facilities: facilities[f] = {"level": 1, "cap": 1}
	heroes = {}
	for c in DB.heroes:
		var h: Dictionary = DB.heroes[c]
		# Shared camp gear (DECISIONS #234): party starts in free Worn Shortsword + Cloth Armor.
		# Mage and Huntress keep heirloom melee instances; armor is always the camp piece.
		var wuid := 0
		if c == "mage" or c == "huntress":
			wuid = add_gear(h.start_weapon)
		heroes[c] = {"class": c, "unlocked": h.unlocked_by_default, "level": 1, "xp": 0, "str": 10, "str_found": [],
			"weapon": wuid, "armor": 0, "ring": 0, "artifact": 0,
			"wand": "wand_magic_missile" if c == "mage" else "", "cleared": [], "patrol": {}, "mask": false, "subclass": "", "talents": []}
	if not _suspend_patrol_sync:
		sync_patrol_widget()

func add_gear(id: String, known := true, lvl := 0) -> int:
	var g := {"uid": next_uid, "id": id, "lvl": lvl, "cracked": false, "known": known}
	if known: seen["item:" + id] = true
	next_uid += 1
	gear.append(g)
	return g.uid

func gear_by_uid(uid: int) -> Dictionary:
	if uid == CAMP_WEAPON_UID:
		if camp_weapon.is_empty(): return {}
		return {"uid": CAMP_WEAPON_UID, "id": String(camp_weapon.id), "lvl": int(camp_weapon.get("lvl", 0)),
			"cracked": false, "known": true, "camp": true}
	if uid == CAMP_ARMOR_UID:
		if camp_armor.is_empty(): return {}
		return {"uid": CAMP_ARMOR_UID, "id": String(camp_armor.id), "lvl": int(camp_armor.get("lvl", 0)),
			"cracked": false, "known": true, "camp": true}
	for g in gear:
		if g.uid == uid: return g
	return {}

## Display name for a camp piece (or "-").
func camp_gear_name(slot: String) -> String:
	var g := gear_by_uid(CAMP_WEAPON_UID if slot == "weapon" else CAMP_ARMOR_UID)
	return gear_name(g) if not g.is_empty() else "-"

## Effective Strength including Ring of Might (gates camp gear and Force).
func effective_str(c: String) -> int:
	var h: Dictionary = heroes[c]
	var ring_str := 0
	var r := gear_by_uid(int(h.get("ring", 0)))
	if not r.is_empty() and r.known and not r.cracked:
		var rd0 := DB.item(r.id)
		ring_str = int(rd0.get("str_bonus", 0)) + trinket_bonus(r, "str_bonus")
	return int(h.str) + ring_str

## True when this hero can wear the item at full effect (camp gear skips under-Str heroes).
func meets_str_req(c: String, item_id: String, lvl: int = 0) -> bool:
	var d := DB.item(item_id)
	var req := Weapons.str_req(d, lvl)
	return req <= 0 or req <= effective_str(c)

## Weapon the hero fights with: found override, else Mage/Huntress heirloom, else camp forge sword
## (only if they meet Str), else starter. Found weapons may still be under-Str with #220 penalties.
func resolved_weapon(c: String) -> Dictionary:
	var h: Dictionary = heroes[c]
	var def: Dictionary = DB.heroes[c]
	var w := gear_by_uid(int(h.get("weapon", 0)))
	if not w.is_empty() and not w.get("cracked", false) and not w.get("camp", false):
		# Personal override (found weapon) or class heirloom instance
		if not is_forge_weapon(String(w.id)):
			return {"id": String(w.id), "lvl": int(w.get("lvl", 0)), "source": "personal", "uid": int(w.uid)}
	if not camp_weapon.is_empty() and c != "mage" and c != "huntress":
		var cid := String(camp_weapon.id); var cl := int(camp_weapon.get("lvl", 0))
		if meets_str_req(c, cid, cl):
			return {"id": cid, "lvl": cl, "source": "camp", "uid": CAMP_WEAPON_UID}
	# Mage / Huntress with empty override: heirloom melee. Warrior / Rogue with no usable camp: starter.
	return {"id": String(def.start_weapon), "lvl": 0, "source": "starter", "uid": 0}

## Armor: camp forge piece when the hero meets Str, else Cloth starter.
func resolved_armor(c: String) -> Dictionary:
	if not camp_armor.is_empty():
		var cid := String(camp_armor.id); var cl := int(camp_armor.get("lvl", 0))
		if meets_str_req(c, cid, cl):
			return {"id": cid, "lvl": cl, "source": "camp", "uid": CAMP_ARMOR_UID}
	var def: Dictionary = DB.heroes[c]
	return {"id": String(def.get("start_armor", "cloth_armor")), "lvl": 0, "source": "starter", "uid": 0}

func gear_name(g: Dictionary) -> String:
	if g.is_empty(): return "-"
	var d := DB.item(g.id)
	# SPD: once a ring or wand type is known, every one of that type reads as it (its level stays hidden)
	var n: String = d.name if g.known or type_known(String(g.id)) else d.get("unknown_name", "Unknown " + d.type)
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

## sink names where the gold went, for telemetry (DECISIONS #197).
func pay(cost: Dictionary, sink := "other") -> bool:
	if not can_afford(cost): return false
	for k in cost: mats[k] = mat(k) - int(cost[k])
	if int(cost.get("gold", 0)) > 0:
		add_stat("gold_spent", int(cost.gold)); Telemetry.spend(sink, int(cost.gold))
	return true

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		if k == "hp" or k == "hp_pct": continue   # HP shown on the option label via Delve.event_hp_cost
		parts.append("%d %s" % [cost[k], DB.mat_name(k)])
	return ", ".join(parts)

# ---------------------------------------------------------------- hero stats
## SPD Hero.MAX_LEVEL: heroes stop gaining levels (and HP/accuracy/talent points) at 30 (DECISIONS #118).
const MAX_LEVEL := 30
func xp_to_next(level: int) -> int:
	return 5 + level * 5   # SPD Hero.maxExp()

## Derived combat stats for a hero with current equipment.
static func armor_dr(ad: Dictionary, al: int) -> int:
	return int(ad.get("dr", 0)) + int(floor(float(ad.get("dr_per_lvl", 1.0)) * maxi(0, al)))

static func armor_barrier(ad: Dictionary, al: int) -> int:
	return int(ad.get("barrier", 0)) + int(floor(float(ad.get("barrier_per_lvl", 0.0)) * maxi(0, al)))

## Forged sword / armor lines: shared camp pieces (DECISIONS #234). Cloth is the free T1 default.
## Ring of Force uses sword tiers (#223); Force armor reference starts at Leather.
const FORCE_SWORDS := ["worn_shortsword", "shortsword", "sword", "longsword", "greatsword"]
const FORCE_ARMOR := ["cloth_armor", "leather_armor", "mail_armor", "scale_armor", "plate_armor"]

static func is_forge_weapon(id: String) -> bool:
	return id in FORCE_SWORDS

static func is_forge_armor(id: String) -> bool:
	return id in FORCE_ARMOR

static func forged_sword_dmg(tier: int, lvl: int) -> int:
	var id: String = FORCE_SWORDS[clampi(tier, 1, 5) - 1]
	return Weapons.dmg(DB.item(id), lvl)

func hero_stats(c: String) -> Dictionary:
	var h: Dictionary = heroes[c]
	var def: Dictionary = DB.heroes[c]
	var rw := resolved_weapon(c); var ra := resolved_armor(c)
	var r := gear_by_uid(h.ring)
	var art := gear_by_uid(int(h.get("artifact", 0)))
	# cracked/missing personal weapon, or empty camp: class starters (DECISIONS #104 / #234)
	var w_ok: bool = String(rw.get("source", "")) != "starter"
	var a_ok: bool = String(ra.get("source", "")) != "starter"
	var wd := DB.item(String(rw.id))
	var ad := DB.item(String(ra.id))
	var wl := int(rw.get("lvl", 0)); var al := int(ra.get("lvl", 0))
	# Ring of Might: Strength + max HP; effective Str gates camp gear and Force (DECISIONS #223 / #234)
	var ring_str := 0
	if not r.is_empty() and r.known and not r.cracked:
		var rd0 := DB.item(r.id)
		ring_str = int(rd0.get("str_bonus", 0)) + trinket_bonus(r, "str_bonus")
	var eff_str := int(h.str) + ring_str   # same as effective_str(c); inlined to reuse ring lookup
	var dmg := Weapons.dmg(wd, wl)          # SPD min/max at this level, averaged (DECISIONS #207)
	if wd.has("dmg_per_levels"): dmg += int(h.level) / int(wd.dmg_per_levels)
	var wnl := 0 if h.get("wand_cracked", false) else int(h.get("wand_lvl", 0))
	var wid := String(rw.id)
	if wid == "mages_staff":
		dmg += 2 * wnl   # staff melee scales with imbued wand level
		if String(h.get("subclass", "")) == "battlemage": dmg += wnl
	# Strength gate: under-strength weapon divides damage by (1 + missing Str) and zeroes block; under-strength armor divides DR and zeroes Barrier (DECISIONS #218, #220)
	var str_short := maxi(0, Weapons.str_req(wd, wl) - eff_str)
	if str_short > 0: dmg = maxi(1, int(dmg / (1 + str_short)))
	var adr := armor_dr(ad, al)
	var abar := armor_barrier(ad, al)
	var armor_str_short := maxi(0, int(ad.get("str", 10)) - eff_str)
	if armor_str_short > 0:
		adr = adr / (1 + armor_str_short)
		abar = 0
	var w_block := 0 if str_short > 0 else Weapons.block_dr(wd, wl)
	var dr := adr + w_block   # Rapier, Quarterstaff, Katana, shields block (#207)
	var barrier := int(def.base_barrier) + int(def.heirloom_barrier) + abar
	if not r.is_empty() and r.known and not r.cracked:
		var rd := DB.item(r.id)
		dmg += int(rd.get("dmg_bonus", 0)) + trinket_bonus(r, "dmg_bonus"); barrier += int(rd.get("barrier_bonus", 0)) + trinket_bonus(r, "barrier_bonus")
		dr += int(rd.get("dr_bonus", 0)) + trinket_bonus(r, "dr_bonus")
		# Ring of Force: Tier 1 weapons only, never heirlooms; DPS toward forged sword for Strength tier (DECISIONS #223)
		if int(wd.get("tier", 1)) <= 1 and not wd.get("heirloom", false) and rd.has("force_bonus"):
			var ftier := clampi((eff_str - 8) / 2, 1, 5)
			var flvl := mini(6, wl + int(r.get("lvl", 0)))
			var ref := forged_sword_dmg(ftier, flvl)
			var target := ref + maxi(2, int(round(float(ref) * 0.10)))
			var delay := maxf(0.5, float(wd.get("delay", 1.0)))
			var base_dps := float(Weapons.dmg(wd, wl)) / delay
			var add_dps := maxf(0.0, float(target) - base_dps)
			dmg += int(round(add_dps * delay))
	var s := {"starter_weapon": not w_ok, "starter_armor": not a_ok, "class": c, "name": def.name, "sprite": def.sprite, "fw": def.fw, "fh": def.fh, "row": armor_tier(c),
		"ht": int(def.base_ht) + int(def.ht_per_level) * (int(h.level) - 1), "level": int(h.level), "str": eff_str,
		"dmg": dmg, "dr": dr, "barrier_max": barrier, "delay": float(wd.get("delay", 1.0)),
		"surprise_mult": float(wd.get("surprise_mult", 1.5)), "abilities": def.abilities,
		# SPD weapon properties (DECISIONS #207): reach in tiles, accuracy, dagger-family surprise roll, Flail / too heavy = no surprise
		"reach": Weapons.reach(wd), "acc": Weapons.acc(wd), "sur_bonus": Weapons.surprise_bonus(wd, wl),
		"no_surprise": wd.get("no_surprise", false) or str_short > 0,
		"search_radius": int(def.get("search_radius", 1)), "keen_eyes": def.get("keen_eyes", false)}
	# ring / artifact extras (DECISIONS #80)
	for eq in [r, art]:
		if eq.is_empty() or eq.cracked or not eq.known: continue
		var ed := DB.item(eq.id)
		s.ht += int(ed.get("ht_bonus", 0)) + trinket_bonus(eq, "ht_bonus"); s.search_radius += int(ed.get("search_add", 0)) + trinket_bonus(eq, "search_add")
		if ed.get("keen_eyes", false): s.keen_eyes = true
		# vanilla artifacts (DECISIONS #159)
		for fk in ["thorns", "freeze_start", "grass_root", "chain_root"]:
			if ed.has(fk) or ed.get("per_level", {}).has(fk): s[fk] = float(ed.get(fk, 0.0)) + trinket_bonus_f(eq, fk)
		if ed.has("chain_pull"): s.chain_pull = true
		if ed.has("loot_mult"): s.loot_mult = float(ed.loot_mult) + trinket_bonus_f(eq, "loot_mult")
		if ed.has("gold_mult"): s.gold_mult = float(ed.gold_mult) + trinket_bonus_f(eq, "gold_mult")
		if ed.has("hunger_mult"): s.hunger_mult = maxf(0.3, float(ed.hunger_mult) + trinket_bonus_f(eq, "hunger_mult"))
		s.charges_bonus = int(s.get("charges_bonus", 0)) + int(ed.get("charges_bonus", 0))
		# vanilla rings (DECISIONS #157)
		# per-level values (DECISIONS #160); speed/resist floors keep a maxed ring from breaking the tick economy
		if ed.has("delay_mult"): s.delay *= maxf(0.6, float(ed.delay_mult) + trinket_bonus_f(eq, "delay_mult"))
		if ed.has("move_cost"): s.move_cost = maxf(0.6, float(ed.move_cost) + trinket_bonus_f(eq, "move_cost"))
		if ed.has("elem_resist"): s.elem_resist = maxf(0.4, float(ed.elem_resist) + trinket_bonus_f(eq, "elem_resist"))
		s.bolt_bonus = int(s.get("bolt_bonus", 0)) + int(ed.get("bolt_bonus", 0)) + trinket_bonus(eq, "bolt_bonus")
	if "bolt" in def.abilities and h.wand != "":
		var wn := DB.item(h.wand)
		s.bolt = {"dmg": int(wn.bolt_dmg) + int(h.level) / 2 + wnl, "charges": int(wn.charges) + int(h.level) / int(def.get("charge_per_levels", 99)) + wnl / 2, "recharge": int(wn.recharge),
			"burns_grass": wn.get("burns_grass", false), "chains_water": wn.get("chains_water", false), "name": wn.name, "magic": true}
		# vanilla wand effects (DECISIONS #156); scale with hero level like the bolt damage
		var lv := int(h.level)
		if wn.has("chill"): s.bolt.chill = float(wn.chill) + (0.5 if lv >= 15 else 0.0)
		if wn.has("corrode"): s.bolt.corrode = int(wn.corrode) + lv / 6
		if wn.has("blast"): s.bolt.blast = int(wn.blast) + (1 if lv >= 15 else 0)
		if wn.get("pierce_line", false): s.bolt.pierce_line = true
		if wn.has("transfuse"): s.bolt.transfuse = int(wn.transfuse) + lv / 10
		if wn.has("reveal"): s.bolt.reveal = int(wn.reveal)
		if wn.has("root"): s.bolt.root = float(wn.root); s.bolt.grow = wn.get("grow", false)
	if "shoot" in def.abilities:
		var lv := int(h.level)
		s.bolt = {"dmg": 3 + lv / 2, "charges": 0, "infinite": true, "recharge": 0,
			"name": "the Spirit Bow", "magic": false}
	if "cloak" in def.abilities:
		# charges carry across the expedition (DECISIONS #206): a fight starts with what the run has left
		s.cloak = {"charges": cloak_charges(c), "cap": cloak_cap(c), "ticks": float(def.cloak_ticks)}
	# Talents (DECISIONS #66): flat modifiers, picked by level
	for tid in h.get("talents", []):
		var td := talent_def(c, tid)
		s.ht += int(td.get("ht_add", 0)); s.dmg += int(td.get("dmg_add", 0)); s.dr += int(td.get("dr_add", 0))
		s.barrier_max += int(td.get("barrier_add", 0)); s.search_radius += int(td.get("search_add", 0))
		s.surprise_mult += float(td.get("surprise_add", 0.0)); s.potion_add = float(s.get("potion_add", 0.0)) + float(td.get("potion_add", 0.0))
		if s.has("bolt"):
			s.bolt.dmg += int(td.get("bolt_add", 0))
			if not s.bolt.get("infinite", false): s.bolt.charges += int(td.get("charges_add", 0))
	if s.has("bolt") and not s.bolt.get("infinite", false): s.bolt.charges += int(s.get("charges_bonus", 0))   # Ring of Energy
	if s.has("bolt"): s.bolt.dmg += int(s.get("bolt_bonus", 0))   # Ring of Sharpshooting
	# Subclass (Tengu's Mask, DECISIONS #61): flat modifiers here, "perk" hooks in Combat.
	var sub: Dictionary = def.get("subclasses", {}).get(String(h.get("subclass", "")), {})
	if not sub.is_empty():
		s.sub = String(h.subclass); s.perk = sub.get("perk", ""); s.sub_name = sub.name
		s.dr += int(sub.get("dr_add", 0)); s.barrier_max += int(sub.get("barrier_add", 0))
		s.surprise_mult += float(sub.get("surprise_add", 0.0)); s.delay *= float(sub.get("delay_mult", 1.0))
		if s.has("bolt"):
			s.bolt.dmg += int(sub.get("bolt_add", 0))
			if sub.get("bolt_pierce", false): s.bolt.pierce = true
	# SPD-like cap (DECISIONS #147): encounter Barrier never exceeds half of max HP
	s.barrier_max = mini(int(s.barrier_max), int(s.ht) / 2)
	return s

# ---------------------------------------------------------------- Cloak of Shadows (DECISIONS #206)
## SPD CloakOfShadows at +0: chargeCap 3 for the whole dungeon, about 45 turns per charge back. Here the charges
## live on the run, a cleared fight gives 1 back (the closest unit to SPD's ~45 turns between encounters), and
## a new expedition starts full. Mystical Meal (SPD Rogue T2) gives 1 more when a ration is eaten.
const CLOAK_RECHARGE_PER_FIGHT := 1
const CLOAK_MEAL_CHARGE := 1

func cloak_cap(c: String) -> int:
	return int(DB.heroes.get(c, {}).get("cloak_charges", 0))

## Charges left: the run's pool while this hero is delving, otherwise a full cloak.
func cloak_charges(c: String) -> int:
	var cap := cloak_cap(c)
	if run.is_empty() or String(run.get("hero", "")) != c: return cap
	return clampi(int(run.get("cloak_charges", cap)), 0, cap)

## After a won fight: keep what is left (capped; a Scroll of Recharging's extra charge is only for that fight),
## then recharge. Returns the charges gained.
func cloak_after_fight(left: int) -> int:
	if run.is_empty(): return 0
	var c := String(run.hero); var cap := cloak_cap(c)
	if cap <= 0: return 0
	var kept := clampi(left, 0, cap)
	run.cloak_charges = mini(cap, kept + CLOAK_RECHARGE_PER_FIGHT)
	return int(run.cloak_charges) - kept

## Mystical Meal: eating a ration restores a cloak charge.
func _mystical_meal() -> void:
	if run.is_empty(): return
	var c := String(run.hero)
	if not ("mystical_meal" in heroes[c].get("talents", [])): return
	var have := cloak_charges(c)
	if have >= cloak_cap(c): return
	run.cloak_charges = mini(cloak_cap(c), have + CLOAK_MEAL_CHARGE)
	say("Mystical Meal: the Cloak of Shadows recharges (%d/%d)." % [run.cloak_charges, cloak_cap(c)], "positive")

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
	if d.type == "armor" or is_forge_armor(String(g.id)): return "armor is shared at Camp"
	if is_forge_weapon(String(g.id)): return "forge weapons outfit the party at Camp"
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
		var old_lvl := int(h.get("wand_lvl", 0)); var old_cr: bool = h.get("wand_cracked", false)
		h.wand = g.id; h.wand_lvl = int(g.get("lvl", 0)); h.wand_cracked = g.get("cracked", false)
		if old != "": run.pack_gear.append({"uid": _take_uid(), "id": old, "lvl": old_lvl, "cracked": old_cr, "known": true, "owned": true})
		say("Imbued %s into the staff." % d.name)
	else:
		var slot := _slot_for(d.type)
		var old := gear_by_uid(int(h[slot]))
		# Don't put camp synthetic pieces in the pack; heirloom/found only
		if not old.is_empty() and not old.get("camp", false):
			gear.erase(old); old.owned = true; run.pack_gear.append(old)
		g.erase("owned"); gear.append(g); h[slot] = int(g.uid)
		say("Equipped %s." % gear_name(g))
	run.hp = clampi(int(run.hp) + int(hero_stats(c).ht) - before, 1, int(hero_stats(c).ht))
	touch(); return true

func _take_uid() -> int:
	next_uid += 1
	return next_uid - 1

## Unequip a slot into the backpack (needs a free slot; heirlooms stay put). Armor is party-wide (#234).
func delve_unequip(slot: String) -> bool:
	if run.is_empty() or backpack_full(): return false
	if slot == "armor": return false
	var h: Dictionary = heroes[run.hero]
	var g := gear_by_uid(int(h[slot]))
	if g.is_empty() or g.get("camp", false) or DB.item(g.id).get("heirloom", false): return false
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
	var req := Weapons.str_req(d, int(g.get("lvl", 0))) if Weapons.is_weapon(d) else int(d.get("str", 0))
	if req > 0 and req > int(a.get("str", h.str)): out.need_str = req
	# Armor Barrier can rise on the piece while the hero's ht/2 cap hides it (DECISIONS #221)
	if d.type == "armor" and g.get("known", true):
		var ra := resolved_armor(c)
		var cur_bar := 0 if String(ra.get("source", "")) == "starter" else armor_barrier(DB.item(String(ra.id)), int(ra.get("lvl", 0)))
		var new_bar := armor_barrier(d, int(g.get("lvl", 0)))
		out.armor_barrier = [cur_bar, new_bar]
		out.barrier_cap = int(a.ht) / 2
		var hero_d := int(b.barrier_max) - int(a.barrier_max)
		var armor_d := new_bar - cur_bar
		if armor_d != 0 and hero_d < armor_d:
			out.barrier_capped = true
	return out

static func compare_text(cmp: Dictionary) -> String:
	var parts := []
	for k in ["dmg", "dr", "barrier", "ht", "bolt"]:
		if not cmp.has(k): continue
		if k == "barrier" and cmp.get("barrier_capped", false) and cmp.has("armor_barrier"):
			var ab: Array = cmp.armor_barrier
			parts.append("Armor Barrier %d->%d (capped at half max HP (%d))" % [ab[0], ab[1], int(cmp.barrier_cap)])
			continue
		var v: Array = cmp[k]
		var tag := "" if v[0] == v[1] else (" (+%d)" % (v[1] - v[0]) if v[1] > v[0] else " (%d)" % (v[1] - v[0]))
		parts.append("%s %d->%d%s" % [{"dmg": "Dmg", "dr": "DR", "barrier": "Barrier", "ht": "HP", "bolt": "Bolt"}[k], v[0], v[1], tag])
	if cmp.has("need_str"): parts.append("(need Str %d)" % int(cmp.need_str))
	return "  ".join(parts)

## Use a belt supply outside combat.
## Unknown potions/scrolls (DECISIONS #80): each save rolls SPD appearances; using one identifies its kind.
const POTION_LOOKS := [["Jade", "POTION_JADE"], ["Turquoise", "POTION_TURQUOISE"], ["Azure", "POTION_AZURE"], ["Indigo", "POTION_INDIGO"], ["Magenta", "POTION_MAGENTA"], ["Bistre", "POTION_BISTRE"], ["Charcoal", "POTION_CHARCOAL"], ["Silver", "POTION_SILVER"], ["Ivory", "POTION_IVORY"]]
const SCROLL_LOOKS := [["Sowilo", "SCROLL_SOWILO"], ["Laguz", "SCROLL_LAGUZ"], ["Yngvi", "SCROLL_YNGVI"], ["Gyfu", "SCROLL_GYFU"], ["Raido", "SCROLL_RAIDO"], ["Mannaz", "SCROLL_MANNAZ"], ["Naudiz", "SCROLL_NAUDIZ"], ["Odal", "SCROLL_ODAL"], ["Tiwaz", "SCROLL_TIWAZ"]]
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
	if not ided.has(k): ided[k] = true; add_stat("items_identified", 1); say("It was a %s!" % DB.materials[k].name)

## Use an unknown-kind potion/scroll from the pack mid-delve (identifies it).
func delve_use_pack(k: String) -> bool:
	if run.is_empty() or int(run.pack.get(k, 0)) <= 0: return false
	var c: String = run.hero
	run.pack[k] = int(run.pack[k]) - 1
	identify_mat(k)
	add_stat("potions_drunk" if k.begins_with("potion_") else "scrolls_read", 1)
	match k:
		"potion_experience":
			var need := xp_to_next(int(heroes[c].level))
			if grant_xp(c, need): say("Level up! %s is now Lv%d." % [DB.heroes[c].name, heroes[c].level])
		"potion_toxic":
			var ht := int(hero_stats(c).ht)
			run.hp = maxi(1, int(run.hp) - ht / 4); say("Choking gas! -%d HP." % (ht / 4))
		"potion_shielding":
			var sh := potion_shield(c)
			run.shield_next = int(run.get("shield_next", 0)) + sh
			say("A shimmering shield: +%d Barrier in your next fight." % sh)
		"scroll_identify":
			var n := 0
			for g in run.pack_gear:
				if not g.known: g.known = true; seen["item:" + g.id] = true; n += 1
			add_stat("items_identified", n)
			say("Identified %d item(s)." % n if n > 0 else "Nothing to identify.")
		"scroll_mapping":
			run.progress = minf(99.0, float(run.get("progress", 0.0)) + 40.0); say("The floor's layout floods your mind (+40%).")
		"scroll_teleport":
			run.skip_card = true; say("You blink past whatever lies ahead.")
		# vanilla potions & scrolls (DECISIONS #161): most set a next-fight effect, read by Delve.new_combat
		"potion_invisibility": _next_fx("invis", 3.0); say("You fade from sight. Your next fight starts unseen.")
		"potion_haste": _next_fx("haste", 1.5); say("Your limbs buzz. Next fight, you act first.")
		"potion_levitation": _next_fx("levitate", 1.0); say("You float. Next fight, traps can't touch you.")
		"potion_frost": _next_fx("frozen", 1.5); say("Ice spreads through you! You'll start your next fight frozen.")
		"potion_paralytic": _next_fx("frozen", 2.5); say("Paralytic gas! You'll start your next fight unable to move.")
		"potion_liquid_flame":
			var ht2 := int(hero_stats(c).ht)
			run.hp = maxi(1, int(run.hp) - ht2 * 3 / 20); say("Liquid flame! -%d HP." % (ht2 * 3 / 20))
		"scroll_recharging": _next_fx("recharge", 1.0); say("Energy hums. +1 charge next fight.")
		"scroll_lullaby": _next_fx("sleep", 2.0); say("A soothing tune lingers. Your next foes will start asleep.")
		"scroll_retribution": _next_fx("retrib", 1.0); say("Your pain gathers. It will burst out at your next foes.")
		"scroll_terror": _next_fx("terror", 1.0); say("A dreadful aura clings to you.")
		"scroll_transmutation":
			var done := false
			for gg in run.pack_gear:
				var t: String = DB.item(gg.id).type
				if not (t in ["ring", "wand"]) or DB.item(gg.id).get("heirloom", false): continue
				var pool: Array = DB.items.keys().filter(func(x): return DB.items[x] is Dictionary and DB.items[x].get("type", "") == t and x != gg.id and not DB.items[x].get("heirloom", false))
				if pool.is_empty(): continue
				gg.id = pool[(int(gg.uid) + int(run.get("floor", 0))) % pool.size()]
				say("Your %s twists into something else." % t); done = true; break
			if not done: say("Nothing to transmute.")
		_: run.pack[k] = int(run.pack[k]) + 1; add_stat("potions_drunk" if k.begins_with("potion_") else "scrolls_read", -1); return false
	touch(); return true

func _next_fx(k: String, v: float) -> void:
	if not run.has("next_fx"): run.next_fx = {}
	run.next_fx[k] = float(run.next_fx.get(k, 0.0)) + v

func delve_use(k: String) -> bool:
	if run.is_empty() or int(run.supplies.get(k, 0)) <= 0: return false
	match k:
		"potion_healing":
			var ht := int(hero_stats(run.hero).ht)
			if int(run.hp) >= ht: return false
			var hp0 := int(run.hp)
			run.hp = mini(ht, int(run.hp) + potion_heal(run.hero)); say("Drank a Potion of Healing. +%d HP." % (int(run.hp) - hp0)); add_stat("potions_drunk", 1)
		"ration":
			if float(run.satiety) >= 90.0: return false
			run.satiety = minf(100.0, float(run.satiety) + 60.0); say("Ate a ration."); add_stat("rations_eaten", 1); _mystical_meal()
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

## Potion of Shielding: same shape as healing; Delve.new_combat still clamps to ht/2 (DECISIONS #221).
func potion_shield(c: String) -> int:
	var p: Dictionary = DB.materials.potion_shielding
	var hs := hero_stats(c)
	return maxi(int(p.get("shield", 10)), int(float(hs.ht) * float(p.get("shield_pct", 0.3))))

## Class starters and heirlooms never crack on death (DECISIONS #221).
func _never_cracks(id: String) -> bool:
	if DB.item(id).get("heirloom", false): return true
	for hc in DB.heroes.values():
		if String(hc.get("start_weapon", "")) == id or String(hc.get("start_armor", "")) == id: return true
	return false

func power_rating(c: String) -> int:
	var s := hero_stats(c)
	return int(s.get("str", heroes[c].str)) + int(s.dmg / 3) + s.dr

func can_equip(c: String, uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty(): return "missing"
	if g.get("camp", false): return "party gear - forge to change it"
	var d := DB.item(g.id)
	if d.type == "armor" or is_forge_armor(String(g.id)): return "armor is shared at Camp"
	if is_forge_weapon(String(g.id)): return "forge weapons outfit the party at Camp"
	if _slot_for(d.type) == "": return "can't be equipped"
	var lock := gear_lock(c)
	if lock != "": return lock
	if g.cracked: return "cracked - " + repair_where(g)
	if not g.known and d.type == "ring": return "unidentified - use the Enchanter's Desk"
	if d.get("heirloom", false) and DB.heroes[c].heirloom != g.id: return "heirloom of another class"
	# worn by someone else: it moves over (a swap), unless that hero's gear is locked (DECISIONS #189)
	var other := equipped_by(uid)
	if other != "" and other != c:
		var olock := gear_lock(other)
		if olock != "": return olock
	return ""

## Equip from the Camp stash. An item another hero wears moves over; when this hero had something in that slot
## and the other hero can wear it, the two trade (a swap), otherwise their slot is left empty (DECISIONS #189).
## Armor and forge swords are party-wide (DECISIONS #234) - only found weapons, rings, artifacts equip per hero.
func equip(c: String, uid: int) -> bool:
	if can_equip(c, uid) != "": return false
	var g := gear_by_uid(uid)
	var slot := _slot_for(DB.item(g.id).type)
	var other := equipped_by(uid)
	if other == c and int(heroes[c][slot]) == uid: return true
	var given := 0
	if other != "" and other != c:
		given = equip_swap_back(c, uid)
		heroes[other][slot] = given
	heroes[c][slot] = uid
	if other != "" and other != c:
		if given != 0: say("%s and %s swap: %s / %s." % [DB.heroes[c].name, DB.heroes[other].name, gear_name(g), gear_name(gear_by_uid(given))])
		else: say("%s takes %s from %s." % [DB.heroes[c].name, gear_name(g), DB.heroes[other].name])
	touch(); return true

# ---------------------------------------------------------------- gear ownership (DECISIONS #189)
const GEAR_SLOTS := ["weapon", "armor", "ring", "artifact"]

## Why this hero's equipment can't change at Camp right now ("" = free): out on a patrol (its yield is worked out
## from the gear they left with) or on the current expedition (the backpack handles that).
func gear_lock(c: String) -> String:
	if not heroes.has(c): return "unknown hero"
	if not heroes[c].get("patrol", {}).is_empty(): return "%s is on patrol" % DB.heroes[c].name
	if not run.is_empty() and run.hero == c: return "%s is on an expedition" % DB.heroes[c].name
	return ""

## The slot holding uid on hero c ("" when they don't wear it).
func slot_of(c: String, uid: int) -> String:
	for s in GEAR_SLOTS:
		if int(heroes[c].get(s, 0)) == uid: return s
	return ""

## What would go back to the current wearer if c takes uid: c's item in that slot, when the wearer can use it
## (intact, identified, not another class's heirloom); 0 = the wearer's slot is left empty.
func equip_swap_back(c: String, uid: int) -> int:
	var other := equipped_by(uid)
	if other == "" or other == c: return 0
	var g := gear_by_uid(uid)
	var mine := gear_by_uid(int(heroes[c].get(_slot_for(DB.item(g.id).type), 0)))
	if mine.is_empty() or mine.cracked: return 0
	var md := DB.item(mine.id)
	if not mine.known and md.type == "ring": return 0
	if md.get("heirloom", false) and DB.heroes[other].heirloom != mine.id: return 0
	return int(mine.uid)

## Button text for putting uid on hero c: "Equip", "Take from Mage", "Swap with Mage".
func equip_verb(c: String, uid: int) -> String:
	var other := equipped_by(uid)
	if other == "" or other == c: return "Equip"
	return ("Swap with " if equip_swap_back(c, uid) != 0 else "Take from ") + String(DB.heroes[other].name)

## slot: weapon/armor/ring/artifact, or "staff" for the Mage's imbued wand.
func can_unequip(c: String, slot: String) -> String:
	var h: Dictionary = heroes[c]
	if slot == "staff":
		if String(h.get("wand", "")) == "": return "no wand imbued"
	elif slot == "armor":
		return "armor is shared at Camp"
	else:
		if not (slot in GEAR_SLOTS): return "not a gear slot"
		var g := gear_by_uid(int(h.get(slot, 0)))
		if g.is_empty(): return "empty slot"
		if DB.item(g.id).get("heirloom", false): return "heirloom - it stays with the %s" % DB.heroes[c].name
	return gear_lock(c)

## Take a piece off at Camp: it goes back to the stash (still owned, just not worn). The Mage's wand leaves the
## staff as a stash wand with its level and crack kept. Unequipping a found weapon returns to camp / heirloom.
func unequip(c: String, slot: String) -> bool:
	if can_unequip(c, slot) != "": return false
	var h: Dictionary = heroes[c]
	if slot == "staff":
		var ou := add_gear(String(h.wand), true, int(h.get("wand_lvl", 0))); gear_by_uid(ou).cracked = bool(h.get("wand_cracked", false))
		say("Took %s out of the staff." % DB.item(h.wand).name)
		h.wand = ""; h.wand_lvl = 0; h.wand_cracked = false
	else:
		var g := gear_by_uid(int(h[slot]))
		h[slot] = 0
		say("%s unequips %s." % [DB.heroes[c].name, gear_name(g)])
	touch(); return true

## Holder of a stash item, for item lists: {"hero": id, "slot": s, "locked": reason}; empty when nobody wears it.
func gear_owner(uid: int) -> Dictionary:
	var c := equipped_by(uid)
	if c == "": return {}
	return {"hero": c, "slot": slot_of(c, uid), "locked": gear_lock(c)}

## Old saves (DECISIONS #189): one uid per gear entry, one wearer per item, slots only point at real gear of their
## type, and next_uid stays above every uid in use. Returns the number of fixes made.
func _fix_ownership() -> int:
	var fixes := 0
	var seen_uid := {}
	var max_uid := 0
	for g in gear: max_uid = maxi(max_uid, int(g.uid))
	if not run.is_empty():
		for g in run.get("pack_gear", []) + run.get("overflow", []): max_uid = maxi(max_uid, int(g.get("uid", 0)))
	next_uid = maxi(next_uid, max_uid + 1)
	var kept: Array = []
	for g in gear:
		var u := int(g.uid)
		if seen_uid.has(u):
			var first: Dictionary = seen_uid[u]
			if String(first.id) == String(g.id): fixes += 1; continue   # the same item listed twice: keep one
			g.uid = next_uid; next_uid += 1; fixes += 1                    # two items sharing a uid: both stay
		seen_uid[int(g.uid)] = g
		kept.append(g)
	gear = kept
	if not run.is_empty():   # a backpack copy may not reuse a stash uid either, or extracting would duplicate it
		for g in run.get("pack_gear", []) + run.get("overflow", []):
			if seen_uid.has(int(g.get("uid", 0))): g.uid = next_uid; next_uid += 1; fixes += 1
	var worn := {}
	for c in DB.heroes:
		if not heroes.has(c): continue
		var h: Dictionary = heroes[c]
		for s in GEAR_SLOTS:
			var u := int(h.get(s, 0))
			if u == 0: continue
			var g: Dictionary = seen_uid.get(u, {})
			if g.is_empty() or _slot_for(DB.item(g.id).type) != s or worn.has(u):
				h[s] = 0; fixes += 1   # missing, wrong kind, or already worn by an earlier hero: back to the stash
				continue
			worn[u] = c
		if c != "mage" and String(h.get("wand", "")) != "":   # only the Mage's Staff holds a wand
			var wu := add_gear(String(h.wand), true, int(h.get("wand_lvl", 0))); gear_by_uid(wu).cracked = bool(h.get("wand_cracked", false))
			h.wand = ""; h.wand_lvl = 0; h.wand_cracked = false; fixes += 1
	return fixes

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
	pay(train_cost(c), "train")
	var h: Dictionary = heroes[c]
	grant_xp(c, xp_to_next(int(h.level)) - int(h.xp))
	say("%s trains at the Guild: Lv %d." % [DB.heroes[c].name, h.level]); touch(); return true

# ---------------------------------------------------------------- facilities & crafting
func facility_level(id: String) -> int:
	return int(facilities[id].level)

func facility_upgrade_cost(id: String) -> Dictionary:
	# Blacksmith: hardcoded steps; dark gold from Lv2?Lv3 onward
	if id == "blacksmith":
		match facility_level(id):
			1: return {"iron_ore": 35, "gold": 150}
			2: return {"iron_ore": 70, "dark_gold": 16, "gold": 400}
			3: return {"iron_ore": 120, "dark_gold": 30, "gold": 800}
			4: return {"iron_ore": 180, "dark_gold": 45, "gold": 1200}
			_: return {}
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
	if f.level >= facility_cap(id): return "unlock a slot first"
	if not can_afford(facility_upgrade_cost(id)): return "need " + cost_text(facility_upgrade_cost(id))
	return ""

func upgrade_facility(id: String) -> bool:
	if can_upgrade_facility(id) != "": return false
	var id_old := identify_seconds()
	var fcost := facility_upgrade_cost(id)
	pay(fcost, "facility_upgrade"); facilities[id].level += 1
	Telemetry.track("facility_upgrade", {"facility": id, "level": int(facilities[id].level), "cost": fcost})
	if id == "enchanter": rescale_identify(id_old, identify_seconds())
	say("%s upgraded to level %d." % [DB.facilities[id].name, facilities[id].level]); touch(); return true

## Scrolls of Upgrade needed to raise this facility's cap by one (0 at max). Cheap first raise, steep last raise,
## so maxing the whole camp takes every Scroll the game hands out: each hero's first kill of each boss plus the
## Scroll milestones (DECISIONS #150).
func sou_cap_cost(id: String) -> int:
	var d: Dictionary = DB.facilities[id]
	var cap := facility_cap(id)
	if cap >= int(d.max): return 0
	var cs: Array = d.get("cap_scrolls", [])
	return int(cs[cap - 1]) if cap - 1 < cs.size() else 1

## Every Scroll of Upgrade the game can ever grant: one per hero per boss (first kill only, record_boss_kill) plus
## milestone rewards. Owed Scrolls (lost on death, returned on the next boss kill) are the same Scrolls, not new ones.
static func total_sou_supply() -> int:
	var n: int = DB.heroes.size() * DB.biomes.values().filter(func(b): return b is Dictionary and str(b.get("boss", "")) != "").size()
	for m in DB.milestones: n += int(m.get("reward", {}).get("scroll_upgrade", 0))
	return n

## Total Scrolls of Upgrade to raise every facility from cap 1 to max.
static func total_sou_to_max() -> int:
	var n := 0
	for id in DB.facilities:
		var d = DB.facilities[id]
		if not (d is Dictionary): continue
		var cs: Array = d.get("cap_scrolls", [])
		for c in range(1, int(d.max)): n += int(cs[c - 1]) if c - 1 < cs.size() else 1
	return n

func apply_sou(id: String) -> bool:
	var f: Dictionary = facilities[id]
	var need := sou_cap_cost(id)
	if need <= 0 or mat("scroll_upgrade") < need: return false
	add_mat("scroll_upgrade", -need); f.cap = facility_cap(id) + 1
	say("Spent %d Scroll%s of Upgrade. %s slot unlocked." % [need, "" if need == 1 else "s", DB.facilities[id].name]); touch(); return true

func recipe(fac: String, rid: String) -> Dictionary:
	for r in DB.recipes.get(fac, []):
		if r.id == rid: return r
	return {}

## Why a forge recipe can't outfit the party ("" = ok): already have that tier or better.
func can_forge_camp(out_id: String) -> String:
	if is_forge_weapon(out_id):
		if camp_weapon.is_empty(): return ""
		var have := int(DB.item(String(camp_weapon.id)).get("tier", 1))
		var want := int(DB.item(out_id).get("tier", 1))
		if want < have: return "party already has better"
		if want == have: return "party already has %s" % DB.display_name(out_id)
		return ""
	if is_forge_armor(out_id):
		if camp_armor.is_empty(): return ""
		var have_a := int(DB.item(String(camp_armor.id)).get("tier", 1))
		var want_a := int(DB.item(out_id).get("tier", 1))
		if want_a < have_a: return "party already has better"
		if want_a == have_a: return "party already has %s" % DB.display_name(out_id)
		return ""
	return ""

func can_craft(fac: String, rid: String) -> String:
	var r := recipe(fac, rid)
	if r.is_empty(): return "unknown recipe"
	if facility_level(fac) < int(r.min_level): return "needs %s Lv%d" % [DB.facilities[fac].name, r.min_level]
	if r.has("out"):
		var camp_block := can_forge_camp(String(r.out))
		if camp_block != "": return camp_block
	if not can_afford(r.cost): return "need " + cost_text(r.cost)
	return ""

func craft(fac: String, rid: String) -> bool:
	if can_craft(fac, rid) != "": return false
	var r := recipe(fac, rid)
	pay(r.cost, "craft_" + fac)
	# brewing with an unidentified potion/scroll reveals what it was (SPD alchemy, DECISIONS #85)
	for k in r.cost:
		if DB.materials.get(k, {}).get("unknown", false) and not is_mat_known(k): identify_mat(k)
	var n := int(r.get("out_n", 1))
	if r.has("out"):
		var oid: String = String(r.out)
		if is_forge_weapon(oid):
			camp_weapon = {"id": oid, "lvl": 0}; seen["item:" + oid] = true
			add_stat("items_forged", 1); say("Party forged " + DB.display_name(oid) + ".")
		elif is_forge_armor(oid):
			camp_armor = {"id": oid, "lvl": 0}; seen["item:" + oid] = true
			add_stat("items_forged", 1); say("Party forged " + DB.display_name(oid) + ".")
		else:
			add_gear(oid); add_stat("items_forged", 1); say("Forged " + DB.display_name(oid) + ".")
	else: add_mat(r.out_mat, n); say("Made %s%s." % [DB.mat_name(r.out_mat), " x%d" % n if n > 1 else ""])
	if fac == "alchemy": stats.potions_brewed += 1
	check_unlocks()
	touch(); return true

## Tier-scaled forge upgrades. Cap is +3 at Blacksmith Lv4+ (no masterwork).
const FORGE_UPGRADE_MAX := 3
## Legacy alias; gear already past +3 keeps its level but cannot be upgraded further.
const MASTERWORK_MAX := FORGE_UPGRADE_MAX
static func upgrade_step_cost(next_lvl: int, tier := 1) -> Dictionary:
	var t := clampi(tier, 1, 5)
	var out := {}
	out.iron_ore = 4 * t * next_lvl
	out.gold = 15 * t * next_lvl * next_lvl
	if t == 4: out.dark_gold = 4 * next_lvl
	elif t >= 5:
		out.dark_gold = 6 * next_lvl
		out.arcane_resin = 3 * next_lvl
	return out

## Highest level the Forge can take gear to right now. L1 repair-only (0); +1/+2/+3 at Lv2/3/4+.
func forge_cap() -> int:
	return [0, 1, 2, 3, 3][clampi(facility_level("blacksmith") - 1, 0, 4)]

func item_upgrade_cost(uid: int) -> Dictionary:
	var g := gear_by_uid(uid)
	if g.is_empty(): return {}
	if is_trinket(g): return trinket_step_cost(int(g.lvl) + 1)
	return upgrade_step_cost(int(g.lvl) + 1, int(DB.item(g.id).get("tier", 1)))

func can_upgrade_item(uid: int) -> String:
	var g := gear_by_uid(uid)
	if is_trinket(g):
		var t: String = DB.item(g.id).type
		if t == "artifact": return "artifacts level up by use"
		if not g.known: return "identify first"
		if g.cracked: return "repair first"
		if g.lvl >= enchant_cap(): return "Enchanter cap +%d" % enchant_cap() if enchant_cap() > 0 else "needs Enchanter's Desk Lv2"
		if not can_afford(item_upgrade_cost(uid)): return "need " + cost_text(item_upgrade_cost(uid))
		return ""
	if g.is_empty() or not (DB.item(g.id).type in ["weapon", "armor"]): return "not upgradable"
	if g.cracked: return "repair first"
	if g.lvl >= forge_cap(): return "Blacksmith cap +%d" % forge_cap()
	if not can_afford(item_upgrade_cost(uid)): return "need " + cost_text(item_upgrade_cost(uid))
	return ""

func upgrade_item(uid: int) -> bool:
	if can_upgrade_item(uid) != "": return false
	pay(item_upgrade_cost(uid), "item_upgrade")
	if uid == CAMP_WEAPON_UID:
		camp_weapon.lvl = int(camp_weapon.get("lvl", 0)) + 1
	elif uid == CAMP_ARMOR_UID:
		camp_armor.lvl = int(camp_armor.get("lvl", 0)) + 1
	else:
		gear_by_uid(uid).lvl += 1
	add_stat("items_upgraded", 1)
	say("Upgraded " + gear_name(gear_by_uid(uid)) + "."); touch(); return true

func repair_cost(uid: int) -> Dictionary:
	var g := gear_by_uid(uid)
	if is_trinket(g): return trinket_repair_cost(DB.item(g.id).type, int(g.lvl))
	var t := int(DB.item(g.id).get("tier", 1)); var lvl := int(g.lvl)
	var out := {"iron_ore": (2 + lvl) * t}
	if t == 4: out.dark_gold = 2 + int(lvl / 2)
	elif t >= 5:
		out.dark_gold = 4 + lvl
		out.arcane_resin = 2 + int(lvl / 2)
	return out

## Why a cracked item can't be repaired now ("" = ok). Rings/wands/artifacts need the Enchanter (DECISIONS #158).
func can_repair(uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty() or not g.cracked: return "not cracked"
	if is_trinket(g):
		var need := trinket_repair_level(DB.item(g.id).type)
		if facility_level("enchanter") < need: return "needs Enchanter's Desk Lv%d" % need
	if not can_afford(repair_cost(uid)): return "need " + cost_text(repair_cost(uid))
	return ""

func repair(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if can_repair(uid) != "" or not pay(repair_cost(uid), "repair"): return false
	g.cracked = false; say("Repaired " + gear_name(g) + "."); touch(); return true

## Short place hint for cracked gear (stash / paperdoll / can_equip). Trinkets never repair at the Forge.
func repair_where(g: Dictionary) -> String:
	if is_trinket(g): return "repair at the Enchanter's Desk (Attune)"
	return "repair at the Forge"

## Cracked weapons/armor only (Forge tab count). Rings/wands/artifacts are Desk work (DECISIONS #158).
func forge_cracked_gear() -> Array:
	return cracked_gear().filter(func(g): return not is_trinket(g))

func desk_cracked_trinkets() -> Array:
	return cracked_gear().filter(func(g): return is_trinket(g))

# ---------------------------------------------------------------- rings, wands, artifacts (DECISIONS #158)
## Rings, wands and artifacts ("trinkets") level and repair at the Enchanter's Desk, not the Forge.
## Cap: Desk Lv1 +0, Lv2 +1, Lv3 +3 (DECISIONS #222). Rings/wands pay resin + dark gold + gold; artifacts level by use.
## Repair: rings, wands and artifacts need Desk Lv2. Patch up (free) never covers them.
func is_trinket(g: Dictionary) -> bool:
	return not g.is_empty() and DB.item(g.id).type in ["ring", "wand", "artifact"] and not DB.item(g.id).get("heirloom", false)

func enchant_cap() -> int:
	return [0, 1, 3, 4, 5][clampi(facility_level("enchanter") - 1, 0, 4)]

static func trinket_step_cost(next_lvl: int) -> Dictionary:
	return {"arcane_resin": 8 * next_lvl, "dark_gold": 4 * next_lvl, "gold": 100 * next_lvl * next_lvl}

static func trinket_repair_level(t: String) -> int:
	return 2   # artifacts too since DECISIONS #170 (was Lv3)

static func trinket_repair_cost(t: String, lvl: int) -> Dictionary:
	if t == "artifact": return {"arcane_resin": 5 + 2 * lvl, "dark_gold": 2 + lvl, "gold": 50 + 25 * lvl}
	return {"arcane_resin": 3 + 2 * lvl, "dark_gold": 1 + lvl}

## Per-level bonus from the item's "per_level" table (ints round down, so +0.5 steps land every other level).
func trinket_bonus(g: Dictionary, key: String) -> int:
	if g.is_empty() or g.get("cracked", false): return 0
	return int(floor(float(DB.item(g.id).get("per_level", {}).get(key, 0)) * int(g.get("lvl", 0))))

func trinket_bonus_f(g: Dictionary, key: String) -> float:
	if g.is_empty() or g.get("cracked", false): return 0.0
	return float(DB.item(g.id).get("per_level", {}).get(key, 0.0)) * int(g.get("lvl", 0))

const ARTIFACT_HOURS_PER_LVL := 24.0
const ARTIFACT_BOSS_HOURS := 8.0
## Legacy constant kept for Codex call sites; use-meter is hours (DECISIONS #223).
const ARTIFACT_XP_PER_LVL := 8

## Add hours to the equipped artifact's use meter; every 24h banks +1 up to the Desk cap.
func add_artifact_use(c: String, hours: float) -> void:
	if hours <= 0.0: return
	var a := gear_by_uid(int(heroes[c].get("artifact", 0)))
	if a.is_empty() or a.cracked or not a.known or DB.item(a.id).get("heirloom", false): return
	a.use_hours = float(a.get("use_hours", 0.0)) + hours
	var gained := 0
	while float(a.use_hours) >= ARTIFACT_HOURS_PER_LVL and int(a.lvl) < enchant_cap():
		a.use_hours = float(a.use_hours) - ARTIFACT_HOURS_PER_LVL
		a.lvl = int(a.lvl) + 1; gained += 1
	if gained > 0: say("%s grows stronger (+%d)." % [DB.item(a.id).name, a.lvl], "positive")

## No longer levels from fight wins (use meter instead). Kept as a no-op for old call sites.
func charge_artifact(_c: String) -> void:
	pass

## The wand imbued in the Mage's Staff (it lives on the hero, not in gear).
func staff_wand_cost() -> Dictionary:
	return trinket_step_cost(int(heroes.mage.get("wand_lvl", 0)) + 1)

func can_upgrade_staff_wand() -> String:
	var h: Dictionary = heroes.mage
	if String(h.get("wand", "")) == "": return "no wand imbued"
	if h.get("wand_cracked", false): return "repair first"
	if enchant_cap() <= 0: return "needs Enchanter's Desk Lv2"
	if int(h.get("wand_lvl", 0)) >= enchant_cap(): return "Enchanter cap +%d" % enchant_cap()
	if not can_afford(staff_wand_cost()): return "need " + cost_text(staff_wand_cost())
	return ""

func upgrade_staff_wand() -> bool:
	if can_upgrade_staff_wand() != "": return false
	pay(staff_wand_cost(), "staff_wand"); heroes.mage.wand_lvl = int(heroes.mage.get("wand_lvl", 0)) + 1; add_stat("items_upgraded", 1)
	say("Upgraded %s to +%d." % [DB.item(heroes.mage.wand).name, heroes.mage.wand_lvl]); touch(); return true

func staff_wand_repair_cost() -> Dictionary:
	return trinket_repair_cost("wand", int(heroes.mage.get("wand_lvl", 0)))

func can_repair_staff_wand() -> String:
	if not heroes.mage.get("wand_cracked", false): return "not cracked"
	if facility_level("enchanter") < 2: return "needs Enchanter's Desk Lv2"
	if not can_afford(staff_wand_repair_cost()): return "need " + cost_text(staff_wand_repair_cost())
	return ""

func repair_staff_wand() -> bool:
	if can_repair_staff_wand() != "": return false
	pay(staff_wand_repair_cost(), "repair"); heroes.mage.wand_cracked = false
	say("Repaired the staff's %s." % DB.item(heroes.mage.wand).name); touch(); return true

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
## Forge weapon/armor recipes outfit the party once (DECISIONS #234) - max 1.
func craft_max(fac: String, rid: String) -> int:
	var r := recipe(fac, rid)
	if r.is_empty() or facility_level(fac) < int(r.min_level): return 0
	if r.has("out") and (is_forge_weapon(String(r.out)) or is_forge_armor(String(r.out))):
		return 1 if can_craft(fac, rid) == "" else 0
	var n := BULK_CAP
	for k in r.cost:
		if int(r.cost[k]) > 0: n = mini(n, mat(k) / int(r.cost[k]))
	return n

## Make `n` copies; all or nothing. Returns true when all were made.
func craft_n(fac: String, rid: String, n: int) -> bool:
	if n < 1 or n > craft_max(fac, rid): return false
	for i in n: craft(fac, rid)
	return true

## Total cost for `n` successive upgrades of one item (costs rise per level).
func upgrade_cost_n(uid: int, n: int) -> Dictionary:
	var g := gear_by_uid(uid); var total := {}; var tier := int(DB.item(g.id).get("tier", 1))
	var base_lvl := int(g.lvl)
	for i in n: total = cost_add(total, trinket_step_cost(base_lvl + i + 1) if is_trinket(g) else upgrade_step_cost(base_lvl + i + 1, tier))
	return total

## Most levels the item can gain now: limited by the Blacksmith cap and by what is affordable.
func upgrade_max(uid: int) -> int:
	var g := gear_by_uid(uid)
	if g.is_empty() or g.get("cracked", false) or not (DB.item(g.id).type in ["weapon", "armor", "ring", "wand"]): return 0
	if is_trinket(g) and not g.known: return 0
	var room := maxi(0, (enchant_cap() if is_trinket(g) else forge_cap()) - int(g.lvl))
	var n := 0
	while n < room and can_afford(upgrade_cost_n(uid, n + 1)): n += 1
	return n

func upgrade_item_n(uid: int, n: int) -> bool:
	if n < 1 or n > upgrade_max(uid): return false
	for i in n: upgrade_item(uid)
	return true

## "Patch up" (DECISIONS #104, #221): free repair of the cheapest cracked tier-1/2 weapon or armor only.
func can_patch_up() -> String:
	var cr := cracked_gear().filter(func(g): return DB.item(g.id).type in ["weapon", "armor"] and int(DB.item(g.id).get("tier", 1)) <= 2)
	if cr.is_empty(): return "no low-tier gear to patch"
	for g in cr:
		if can_afford(repair_cost(g.uid)): return "you can afford a repair"
	return ""

func patch_up() -> bool:
	if can_patch_up() != "": return false
	var cr := cracked_gear().filter(func(g): return DB.item(g.id).type in ["weapon", "armor"] and int(DB.item(g.id).get("tier", 1)) <= 2)
	cr.sort_custom(func(a, b):
		return int(repair_cost(a.uid).get("iron_ore", 0)) < int(repair_cost(b.uid).get("iron_ore", 0)))
	var g: Dictionary = cr[0]; g.cracked = false
	say("The Blacksmith patches up your %s for free." % gear_name(g), "positive"); touch(); return true

## Relief supplies: a broke Camp (no rations or torches, can't buy one) gets 1 of each when a run starts.
const RELIEF_GOLD := 10
## Gold safety net (DECISIONS #109): a death never leaves the stash below enough gold for one Guild potion.
const SAFETY_GOLD := 30
func needs_relief() -> bool:
	return mat("ration") == 0 and mat("torch") == 0 and mat("gold") < RELIEF_GOLD

## First-run soft landing (DECISIONS #226): a free Passage each delve until Goo falls or FREE_PASSAGE_USES are spent.
func free_passage_eligible() -> bool:
	return int(stats.get("goo_kills", 0)) == 0 and int(stats.get("free_passage_uses", 0)) < FREE_PASSAGE_USES

func free_passage_left() -> int:
	if int(stats.get("goo_kills", 0)) > 0: return 0
	return maxi(0, FREE_PASSAGE_USES - int(stats.get("free_passage_uses", 0)))

func note_free_passage_use() -> void:
	stats.free_passage_uses = int(stats.get("free_passage_uses", 0)) + 1

func cracked_gear() -> Array:
	return gear.filter(func(g): return g.get("cracked", false))

func repair_all_cost() -> Dictionary:
	var total := {}
	for g in repairable_gear(): total = cost_add(total, repair_cost(g.uid))
	return total

## Cracked gear whose facility gate is met (cost aside).
func repairable_gear() -> Array:
	return cracked_gear().filter(func(g): return not is_trinket(g) or facility_level("enchanter") >= trinket_repair_level(DB.item(g.id).type))

func can_repair_all() -> String:
	if repairable_gear().is_empty(): return "nothing to repair" if cracked_gear().is_empty() else "needs the Enchanter's Desk"
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
	_schedule_identify()   # a running item that left frees its slot

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

## A bolt-casting hero (the Mage) whose Staff holds no wand: since gear can come off at Camp (DECISIONS #189) she
## can set out with no Bolt at all. The Expedition window and the Stats panel say so (DECISIONS #193).
func staff_empty(c: String) -> bool:
	return heroes.has(c) and "bolt" in DB.heroes[c].get("abilities", []) and String(heroes[c].get("wand", "")) == ""

func can_imbue_wand(uid: int) -> String:
	var g := gear_by_uid(uid)
	if g.is_empty() or DB.item(g.id).type != "wand": return "not a wand"
	if not g.known: return "unidentified"
	return gear_lock("mage")   # the staff's wand is Mage gear: locked while she's out (DECISIONS #189)

func imbue_wand(uid: int) -> bool:
	if can_imbue_wand(uid) != "": return false
	var g := gear_by_uid(uid)
	var old: String = heroes.mage.wand
	var old_lvl := int(heroes.mage.get("wand_lvl", 0)); var old_cr: bool = heroes.mage.get("wand_cracked", false)
	heroes.mage.wand = g.id; heroes.mage.wand_lvl = int(g.lvl); heroes.mage.wand_cracked = g.get("cracked", false)
	gear.erase(g)
	if old != "":
		var ou := add_gear(old, true, old_lvl); gear_by_uid(ou).cracked = old_cr
	say("Imbued %s into the Mage's Staff." % DB.item(g.id).name); touch(); return true

# ---------------------------------------------------------------- Enchanter's Desk
## Identification (DECISIONS #203). SPD learns a ring or wand *type* once, then every item of that type reads as
## that type. So only the first item of an unknown type takes the Desk's timer; the rest of that type finish the
## moment it does, or at once when queued after the type is known. The Desk works on one type per level at the
## same time (Lv1 1, Lv2 2, Lv3 3), and anything still waiting or running can be finished now for gold.
## Queue entries: {uid, queued_at, started, ready_at}. started 0 = waiting for a slot, or riding along with a running
## item of the same type; ready_at is then the projected finish. All times are absolute (now() incl. time_offset).
const IDENTIFY_RUSH_GOLD_PER_MIN := 15.0   # Finish now: 15 gold per minute of Desk work left (45 for a fresh Lv1 item)
const IDENTIFY_RUSH_MIN := 5

func identify_seconds() -> float:
	return [180.0, 120.0, 60.0, 45.0, 30.0][clampi(facility_level("enchanter") - 1, 0, 4)]

## Items the Desk identifies at the same time (one per level).
func identify_slots() -> int:
	return clampi(facility_level("enchanter"), 1, 5)

## The type is known (one was identified, forged, bought or found known), so this one only needs a tap.
func type_known(id: String) -> bool:
	return seen.has("item:" + id)

func _queue_entry(uid: int) -> Dictionary:
	for q in id_queue:
		if int(q.uid) == uid: return q
	return {}

## The running entry that is learning this entry's type (itself if it is running), or {}.
func _identify_lead(q: Dictionary) -> Dictionary:
	if float(q.get("started", 0.0)) > 0.0: return q
	var id: String = String(gear_by_uid(int(q.uid)).get("id", ""))
	for o in id_queue:
		if float(o.get("started", 0.0)) > 0.0 and String(gear_by_uid(int(o.uid)).get("id", "")) == id: return o
	return {}

## 0..1 of the Desk work done on this item. Running items fill from their start to ready_at; one riding along with a
## running item of its type shows that item's bar; one waiting for a slot sits at 0 until a slot frees.
func identify_progress(q: Dictionary) -> float:
	var lead := _identify_lead(q)
	if lead.is_empty(): return 0.0
	var start := float(lead.started); var ready := float(lead.ready_at)
	return clampf((now() - start) / maxf(1.0, ready - start), 0.0, 1.0)

## "running", "same type" (finishes with an item of its type that is running or ahead of it) or "waiting" (for a slot).
func identify_state(q: Dictionary) -> String:
	if float(q.get("started", 0.0)) > 0.0: return "running"
	var id: String = String(gear_by_uid(int(q.uid)).get("id", ""))
	for o in id_queue:
		if o == q: break
		if String(gear_by_uid(int(o.uid)).get("id", "")) == id: return "same type"
	return "same type" if not _identify_lead(q).is_empty() else "waiting"

## Works out who runs and when everyone finishes. Running items keep their times. Free slots (free_at: now, or the
## moment a slot freed during an offline catch-up) take waiting items in queue order; a waiting item whose type is
## already being learned rides along instead of taking a slot. A slot that frees in the past starts its next item
## then, so time away keeps the Desk busy.
func _schedule_identify(free_at := -1.0) -> void:
	var t := now()
	if free_at < 0.0: free_at = t
	var free: Array = []
	var lead_at := {}   # gear id -> finish time of the item learning that type
	for q in id_queue:
		if float(q.get("started", 0.0)) > 0.0:
			free.append(float(q.ready_at))
			var gid := String(gear_by_uid(int(q.uid)).get("id", ""))
			lead_at[gid] = minf(float(lead_at.get(gid, INF)), float(q.ready_at))
	while free.size() < identify_slots(): free.append(free_at)
	for q in id_queue:
		if float(q.get("started", 0.0)) > 0.0: continue
		var gid := String(gear_by_uid(int(q.uid)).get("id", ""))
		if lead_at.has(gid): q.ready_at = float(lead_at[gid]); continue
		free.sort()
		var s := maxf(float(free[0]), float(q.get("queued_at", free_at)))
		var ready := s + identify_seconds()
		if s <= t: q.started = s
		q.ready_at = ready; free[0] = ready; lead_at[gid] = ready

## Queue an unknown item. A type already known identifies at once (no slot, no wait).
func enqueue_identify(uid: int) -> bool:
	var g := gear_by_uid(uid)
	if g.is_empty() or g.known or not _queue_entry(uid).is_empty(): return false
	if type_known(g.id):
		_identify_gear(g); touch(); return true
	id_queue.append({"uid": uid, "queued_at": now(), "started": 0.0, "ready_at": 0.0})
	_schedule_identify()
	touch(); return true

## Every unknown item not already queued, in stash order (Enchanter "Queue all", DECISIONS #145).
func identify_candidates() -> Array:
	return gear.filter(func(g): return not g.known and _queue_entry(int(g.uid)).is_empty())

## Queues every candidate. The queue has no size limit, so this queues them all. Returns how many were queued.
func enqueue_identify_all() -> int:
	var n := 0
	for g in identify_candidates():
		if enqueue_identify(int(g.uid)): n += 1
	return n

## Enchanter upgrade: the new level's shorter time applies to what's left of every running item (an item 50% done
## stays 50% done), and the new slot starts the next waiting item. Items already due are left for tick_identify.
func rescale_identify(old_secs: float, new_secs: float) -> void:
	tick_identify()
	var t := now()
	if old_secs > 0.0 and not is_equal_approx(old_secs, new_secs):
		var k := new_secs / old_secs
		for q in id_queue:
			if float(q.get("started", 0.0)) <= 0.0: continue
			var left := float(q.ready_at) - t
			if left <= 0.0: continue
			var p := identify_progress(q)   # keep the bar where it was: the rest of the wait shrinks, the part done stays
			q.ready_at = t + left * k
			q.started = float(q.ready_at) - (left * k) / maxf(0.0001, 1.0 - p)
	_schedule_identify()
	touch()

## Gold to finish this queued item now: the Desk work left on its type (a waiting item counts its full time).
func identify_rush_cost(uid: int) -> Dictionary:
	var q := _queue_entry(uid)
	if q.is_empty(): return {}
	var lead := _identify_lead(q)
	var left := identify_seconds() if lead.is_empty() else maxf(0.0, float(lead.ready_at) - now())
	return {"gold": maxi(IDENTIFY_RUSH_MIN, int(ceil(left / 60.0 * IDENTIFY_RUSH_GOLD_PER_MIN)))}

func can_rush_identify(uid: int) -> String:
	if _queue_entry(uid).is_empty(): return "not queued"
	if not can_afford(identify_rush_cost(uid)): return "need " + cost_text(identify_rush_cost(uid))
	return ""

## Finish now: pays the gold sink "enchanter_rush" and identifies the item (and its type) at once.
func rush_identify(uid: int) -> bool:
	if can_rush_identify(uid) != "": return false
	pay(identify_rush_cost(uid), "enchanter_rush")
	var g := gear_by_uid(uid)
	id_queue.erase(_queue_entry(uid))
	_identify_gear(g)
	_schedule_identify()
	touch(); return true

## Marks one item identified, then every other queued item of its type (its type is known now). Returns the uids.
func _identify_gear(g: Dictionary) -> Array:
	var done := []
	if g.is_empty(): return done
	var batch := [g]
	for q in id_queue.duplicate():
		var o := gear_by_uid(int(q.uid))
		if o.is_empty() or o.id == g.id:
			id_queue.erase(q)
			if not o.is_empty() and int(o.uid) != int(g.uid): batch.append(o)
	for x in batch:
		if x.known: continue
		x.known = true; done.append(int(x.uid))
	seen["item:" + g.id] = true
	add_stat("items_identified", done.size())
	if done.size() == 1: say("Identified: " + gear_name(g))
	elif done.size() > 1: say("Identified %d x %s." % [done.size(), DB.item(g.id).name])
	return done

## Finishes any identifications whose time has passed, in the order they finished, and starts the next waiting item
## in each freed slot from the moment it freed. Returns identified uids.
func tick_identify() -> Array:
	# known types that hold no slot go first, so the catch-up below never starts them; running ones of a known type
	# stay in the catch-up (one already due finishes at its own time, keeping the offline chain; Bugbot on #98)
	var done := _identify_known_types(false)
	if not done.is_empty(): _schedule_identify()
	var t := now()
	while true:
		var next: Dictionary = {}
		for q in id_queue:
			if float(q.get("started", 0.0)) > 0.0 and (next.is_empty() or float(q.ready_at) < float(next.ready_at)): next = q
		if next.is_empty() or float(next.ready_at) > t: break
		var at := float(next.ready_at)
		id_queue.erase(next)
		done.append_array(_identify_gear(gear_by_uid(int(next.uid))))
		_schedule_identify(at)
	var late := _identify_known_types(true)   # still running and not due: their slots free now
	if not late.is_empty():
		done.append_array(late); _schedule_identify()
	if not done.is_empty(): touch()
	return done

## A type learned away from the Desk while its items wait (forged, a wand out of the Staff, a known find or curio, a pack Scroll
## of Identify): they need no Desk time, the same as queueing them after the type is known. Without this they kept
## their timer and a Finish price under their real name.
## with_running false skips any type that has a running entry (it holds a slot, so the catch-up handles it first).
func _identify_known_types(with_running := true) -> Array:
	var done := []
	for q in id_queue.duplicate():
		var g := gear_by_uid(int(q.uid))
		if g.is_empty() or g.known or not type_known(String(g.id)): continue
		if not with_running and id_queue.any(func(o): return float(o.get("started", 0.0)) > 0.0 and String(gear_by_uid(int(o.uid)).get("id", "")) == String(g.id)): continue
		done.append_array(_identify_gear(g))
	return done

## Queues saved before DECISIONS #203 ran one item after another with no "started": the front item keeps running
## (its bar stays put, its wait capped at today's shorter time) and the rest are scheduled under the new rules.
func _migrate_id_queue() -> void:
	id_queue = id_queue.filter(func(q): return not gear_by_uid(int(q.uid)).is_empty())
	if id_queue.is_empty() or id_queue.all(func(q): return q.has("started")): return
	var t := now()
	var front: Dictionary = id_queue[0]
	for q in id_queue:
		if not q.has("started"):
			q.started = 0.0
			q.queued_at = float(q.get("queued_at", t))
	if float(front.started) <= 0.0:
		var ready := minf(float(front.ready_at), t + identify_seconds())
		front.started = minf(t, minf(float(front.queued_at), ready - 1.0))
		front.ready_at = ready
	_schedule_identify()
	tick_identify()

# ---------------------------------------------------------------- Offline Patrols
## Guild hours cap; a hero's own cap adds their Timekeeper's Hourglass (DECISIONS #188).
func patrol_max_hours(c := "") -> float:
	var base: float = [2.0, 4.0, 8.0, 12.0, 16.0][clampi(facility_level("guild") - 1, 0, 4)]
	if c == "" or not heroes.has(c): return base
	return base + float(patrol_perks(c).fx.get("max_hours", 0.0))

func can_patrol(c: String, biome: String) -> String:
	var h: Dictionary = heroes[c]
	if not h.unlocked: return "locked"
	if not h.patrol.is_empty(): return "already patrolling"
	if not run.is_empty() and run.hero == c: return "on an expedition"
	if not (biome in h.cleared): return "clear %s first" % DB.biomes[biome].name
	if not can_afford(patrol_fee(biome, c)): return "need " + cost_text(patrol_fee(biome, c))
	return ""

## Patrol fee: 1 hour of expected gold (efficiency-scaled), cut by Ring of Elements (DECISIONS #222 / Plan 11).
func patrol_fee(biome: String, c := "") -> Dictionary:
	var g := float(DB.biomes[biome].patrol_yield_per_hour.get("gold", 0))
	if c != "" and heroes.has(c):
		g *= patrol_efficiency(c, biome)
		g *= 1.0 - minf(PATROL_FEE_CUT_MAX, float(patrol_perks(c).fx.get("fee_cut_pct", 0.0))) / 100.0
	return {"gold": maxi(1, int(round(g)))}

## The patrol remembers what the hero set out with (efficiency, gear bonus, perks, hours cap), so the haul can't
## change by swapping or levelling gear while they are away (DECISIONS #188).
func start_patrol(c: String, biome: String) -> bool:
	if can_patrol(c, biome) != "": return false
	var fee := patrol_fee(biome, c)
	pay(fee, "patrol_fee")
	var pk := patrol_perks(c)
	heroes[c].patrol = {"biome": biome, "start": now(), "v": 2, "eff": patrol_efficiency(c, biome), "gear_mult": patrol_gear_mult(c),
		"gear_lvl": patrol_gear_level(c), "fx": pk.fx.duplicate(true), "lines": pk.lines.duplicate(), "max_h": patrol_max_hours(c)}
	Telemetry.track("patrol_start", {"class": c, "biome": biome, "max_hours": float(heroes[c].patrol.max_h), "eff": float(heroes[c].patrol.eff),
		"gear_level": int(heroes[c].patrol.gear_lvl), "gear_mult": float(heroes[c].patrol.gear_mult), "perks": pk.fx.keys(), "fee_gold": int(fee.get("gold", 0)),
		"hero_level": int(heroes[c].level)})
	say("%s sets out to patrol the %s." % [DB.heroes[c].name, DB.biomes[biome].name]); sync_patrol_widget(); touch(); return true

## Efficiency: hero power (plus patrol power perks) vs biome strength gate, clamped 0.25..1.0 (DECISIONS #222).
func patrol_efficiency(c: String, biome: String) -> float:
	var pw := float(power_rating(c)) + float(patrol_perks(c).fx.get("power", 0.0))
	return clampf(pw / (float(DB.biomes[biome].str_gate) + 2.0), 0.25, 1.0)

# --- gear on patrol (DECISIONS #188, #222)
const PATROL_GEAR_K := 0.08          # +8% at Lv1, +18% at 5, +25% at 10, +32% at 16
const PATROL_MULT_CAP := 1.50        # gear + perk bonuses add, then cap
const PATROL_GOLD_GEAR_SHARE := 0.0  # gold gets none of the gear share (only Wealth / Armband raise it)
const PATROL_FEE_CUT_MAX := 50.0

## Sum of upgrade levels the hero actually uses: resolved weapon/armor (camp or override), ring, artifact,
## and the staff's wand. Cracked pieces don't count (DECISIONS #234).
func patrol_gear_level(c: String) -> int:
	var h: Dictionary = heroes[c]
	var n := 0
	var rw := resolved_weapon(c)
	if String(rw.get("source", "")) != "starter": n += int(rw.get("lvl", 0))
	var ra := resolved_armor(c)
	if String(ra.get("source", "")) != "starter": n += int(ra.get("lvl", 0))
	for s in ["ring", "artifact"]:
		var g := gear_by_uid(int(h.get(s, 0)))
		if not g.is_empty() and not g.get("cracked", false): n += int(g.get("lvl", 0))
	if String(h.get("wand", "")) != "" and not h.get("wand_cracked", false): n += int(h.get("wand_lvl", 0))
	return n

## Diminishing returns, no ceiling: each extra level still adds a little.
static func patrol_gear_mult_for(lvl: int) -> float:
	return 1.0 + PATROL_GEAR_K * sqrt(float(maxi(0, lvl)))

func patrol_gear_mult(c: String) -> float:
	return patrol_gear_mult_for(patrol_gear_level(c))

## The worn pieces that carry a patrol perk: [{name, id, lvl}]. Ring, artifact, then the staff's wand.
func _patrol_perk_items(c: String) -> Array:
	var h: Dictionary = heroes[c]
	var out := []
	for s in ["ring", "artifact"]:
		var g := gear_by_uid(int(h.get(s, 0)))
		if g.is_empty() or g.get("cracked", false) or not g.get("known", true): continue
		if DB.item(g.id).has("patrol"): out.append({"id": g.id, "lvl": int(g.get("lvl", 0)), "name": gear_name(g)})
	var w := String(h.get("wand", ""))
	if w != "" and not h.get("wand_cracked", false) and DB.item(w).has("patrol"):
		var wl := int(h.get("wand_lvl", 0))
		out.append({"id": w, "lvl": wl, "name": DB.item(w).name + (" +%d" % wl if wl > 0 else "")})
	return out

## Value of one perk entry at an item level: [base, per_level] or, for "_every", [hours, per_level, min hours].
static func patrol_perk_value(spec, lvl: int) -> float:
	if spec is Array:
		var v := float(spec[0]) + float(spec[1]) * lvl
		return maxf(float(spec[2]), v) if spec.size() > 2 else v
	return 1.0 if spec else 0.0

## Player-facing text for one perk entry, e.g. "+20% gold", "+1 potion per 4h", "curios: any ring".
static func patrol_perk_text(key: String, v) -> String:
	var n := func(x: float) -> String: return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x
	if key.ends_with("_per_hour"): return "+%s %s/h" % [n.call(v), _patrol_mat_word(key.trim_suffix("_per_hour"))]
	if key.ends_with("_every"): return "+1 %s per %sh" % [_patrol_mat_word(key.trim_suffix("_every")), n.call(v)]
	match key:
		"all_pct": return "+%s%% materials" % n.call(v)
		"time_pct": return "+%s%% patrol time" % n.call(v)
		"curio_pct": return "+%s%% curios" % n.call(v)
		"fee_cut_pct": return "-%s%% fee" % n.call(v)
		"power": return "+%s patrol power" % n.call(v)
		"max_hours": return "+%sh max" % n.call(v)
		"curio_plus_pct": return "%s%% of curios come +1" % n.call(v)
		"curio_known": return "curios arrive identified"
		"curio_pool": return "curios: any ring"
	if key.ends_with("_pct"): return "+%s%% %s" % [n.call(v), _patrol_mat_word(key.trim_suffix("_pct"))]
	return key

static func _patrol_mat_word(m: String) -> String:
	match m:
		"dew": return "dew"
		"potion_healing": return "healing potion"
	return DB.mat_name(m).to_lower()

## Active patrol perks for this hero's current gear: {"fx": merged effects, "lines": ["Ring of Wealth +2: +20% gold", ...]}.
## Percent / flat effects add up; for "_every" drops the shortest interval wins; flags just turn on.
## Perk keys are sorted so lines stay stable across JSON key order (gold before curios, etc.).
func patrol_perks(c: String) -> Dictionary:
	var fx := {}
	var lines := []
	for it in _patrol_perk_items(c):
		var spec: Dictionary = DB.item(it.id).patrol
		var parts := []
		# Percents / numbers first, then flags like curio_pool — matches the player-facing copy in tests.
		var keys: Array = spec.keys()
		keys.sort_custom(func(a, b):
			var ap := 0 if String(a).ends_with("_pct") or String(a).ends_with("_every") or String(a).ends_with("_per_hour") or String(a) in ["power", "max_hours", "time_pct", "all_pct", "fee_cut_pct", "curio_pct", "curio_plus_pct", "gold_pct"] else 1
			var bp := 0 if String(b).ends_with("_pct") or String(b).ends_with("_every") or String(b).ends_with("_per_hour") or String(b) in ["power", "max_hours", "time_pct", "all_pct", "fee_cut_pct", "curio_pct", "curio_plus_pct", "gold_pct"] else 1
			if ap != bp: return ap < bp
			return String(a) < String(b))
		for k in keys:
			if k == "curio_pool" or k == "curio_known":
				fx[k] = spec[k]; parts.append(patrol_perk_text(k, spec[k])); continue
			var v := patrol_perk_value(spec[k], int(it.lvl))
			if k.ends_with("_every"): fx[k] = minf(float(fx.get(k, 999.0)), v)
			else: fx[k] = float(fx.get(k, 0.0)) + v
			parts.append(patrol_perk_text(k, v))
		lines.append("%s: %s" % [it.name, ", ".join(parts)])
	return {"fx": fx, "lines": lines}

## What gear does on this hero's patrols, for the Guild card: the gear-level line first, then one line per perk.
## A hero already out shows what they left with.
func patrol_bonus_lines(c: String) -> Array:
	var p: Dictionary = heroes[c].patrol
	var snap := not p.is_empty() and int(p.get("v", 1)) >= 2
	var lvl := int(p.get("gear_lvl", 0)) if snap else patrol_gear_level(c)
	var gm := float(p.get("gear_mult", 1.0)) if snap else patrol_gear_mult(c)
	var out := []
	if lvl > 0:
		var gold := roundi((gm - 1.0) * PATROL_GOLD_GEAR_SHARE * 100.0)
		out.append("Gear Lv %d: +%d%% materials" % [lvl, roundi((gm - 1.0) * 100.0)] + (", +%d%% gold" % gold if gold > 0 else ""))
	out.append_array(p.get("lines", []) if snap else patrol_perks(c).lines)
	return out

## Curio table: Might/Tenacity by default; a Ring of Wealth opens every ring in the game.
func patrol_curio_pool(fx: Dictionary) -> Array:
	if String(fx.get("curio_pool", "")) != "rings": return ["ring_might", "ring_tenacity"]
	var out := []
	for k in DB.items:
		var d = DB.items[k]
		if d is Dictionary and d.get("type", "") == "ring" and not d.get("heirloom", false): out.append(k)
	return out

## What the patrol would bring back if recalled now. Patrols started before #188 (no "v") are worked out from the
## hero's gear today, the way they always were. `at` is a game-clock timestamp (now() by default) so the widget
## can ask for the full haul without moving the clock.
func patrol_preview(c: String, at := -1.0) -> Dictionary:
	var p: Dictionary = heroes[c].patrol
	if p.is_empty(): return {}
	var b: Dictionary = DB.biomes[p.biome]
	var snap := int(p.get("v", 1)) >= 2
	var fx: Dictionary = p.get("fx", {}) if snap else patrol_perks(c).fx
	var max_h := float(p.get("max_h", patrol_max_hours(c))) if snap else patrol_max_hours(c)
	var eff := float(p.get("eff", 1.0)) if snap else patrol_efficiency(c, p.biome)
	var gm := float(p.get("gear_mult", 1.0)) if snap else patrol_gear_mult(c)
	var t := now() if at < 0.0 else at
	var hours := clampf((t - float(p.start)) / 3600.0, 0.0, max_h)
	var worked := hours * (1.0 + float(fx.get("time_pct", 0.0)) / 100.0)   # Ring of Haste: more ground per hour
	var allp := float(fx.get("all_pct", 0.0))
	var out := {}
	for k in b.patrol_yield_per_hour:
		# gear + perk bonuses add, then cap at 1.50; gold keeps its own perk (Wealth) but no gear share (DECISIONS #222)
		var gear_bonus := (gm - 1.0) if k != "gold" else (gm - 1.0) * PATROL_GOLD_GEAR_SHARE
		var perk_bonus := ((allp if k != "gold" else 0.0) + float(fx.get(k + "_pct", 0.0))) / 100.0
		var mult := minf(PATROL_MULT_CAP, 1.0 + gear_bonus + perk_bonus)
		out[k] = float(b.patrol_yield_per_hour[k]) * worked * eff * mult
	for k in fx:   # flat finds (Sandals, Regrowth): per hour, scaled by efficiency and the material's own bonus
		if not String(k).ends_with("_per_hour"): continue
		var m := String(k).trim_suffix("_per_hour")
		var perk_bonus := (allp + float(fx.get(m + "_pct", 0.0))) / 100.0
		out[m] = float(out.get(m, 0.0)) + float(fx[k]) * worked * eff * minf(PATROL_MULT_CAP, 1.0 + perk_bonus)
	for k in out.keys(): out[k] = int(floor(out[k]))
	for k in fx:   # drops on a timer (Chalice: healing potions, Horn: rations)
		if String(k).ends_with("_every"): out[String(k).trim_suffix("_every")] = int(out.get(String(k).trim_suffix("_every"), 0)) + int(floor(worked / maxf(0.5, float(fx[k]))))
	out["_curios"] = int(floor(worked * (1.0 + float(fx.get("curio_pct", 0.0)) / 100.0) / float(b.patrol_curio_every_hours)))
	out["_hours"] = hours
	out["_max_h"] = max_h
	return out

func collect_patrol(c: String) -> Dictionary:
	var y := patrol_preview(c)
	if y.is_empty(): return {}
	var p: Dictionary = heroes[c].patrol
	var fx: Dictionary = p.get("fx", {}) if int(p.get("v", 1)) >= 2 else patrol_perks(c).fx
	for k in y:
		if not String(k).begins_with("_") and int(y[k]) > 0: add_mat(k, y[k])
	var pool := patrol_curio_pool(fx)
	var known: bool = fx.get("curio_known", false)
	var plus := float(fx.get("curio_plus_pct", 0.0)) / 100.0
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s|%s|%d" % [c, p.biome, int(float(p.start))])
	var first_uid := next_uid   # add_gear bumps next_uid, so (next_uid + i) skipped every other ring (DECISIONS #203)
	for i in y._curios:
		var id: String = pool[(first_uid + i) % pool.size()] if pool.size() == 2 else pool[rng.randi() % pool.size()]
		add_gear(id, known, 1 if plus > 0.0 and rng.randf() < plus else 0)
	var yld := {}
	for k in y:
		if not String(k).begins_with("_"): yld[String(k)] = int(y[k])
	Telemetry.track("patrol_end", {"class": c, "biome": String(p.biome), "hours": float(y._hours), "curios": int(y._curios), "yield": yld,
		"perks": fx.keys(), "gear_level": int(p.get("gear_lvl", 0)), "eff": float(p.get("eff", 0.0))})
	# Artifact use meter: hours actually worked while it was equipped (DECISIONS #223)
	var worked := float(y._hours) * (1.0 + float(fx.get("time_pct", 0.0)) / 100.0)
	add_artifact_use(c, worked)
	heroes[c].patrol = {}
	add_stat("patrols", 1); add_stat("patrol_hours", int(float(y._hours))); add_stat("patrol_curios", int(y._curios))
	add_stat("gold_banked", int(y.get("gold", 0)))
	say("%s returns from patrol (%.1fh)." % [DB.heroes[c].name, y._hours]); sync_patrol_widget(); touch()
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
	return [2, 2, 3, 4, 5][clampi(facility_level("alchemy") - 1, 0, 4)]

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
	var free_passage := false
	if free_passage_eligible() and int(sup.get("scroll_passage", 0)) == 0:
		sup.scroll_passage = 1
		free_passage = true
		say("The Camp scribes you a free Scroll of Passage (%d left, or until Goo falls)." % free_passage_left(), "positive")
	var s := hero_stats(c)
	var f0 := int(DB.biomes[biome].floors[0])
	run = {"hero": c, "biome": biome, "floor": f0, "progress": 0.0, "torch": 100.0, "satiety": 100.0,
		"hp": s.ht, "pack": {}, "pack_gear": [], "supplies": sup, "seed": seed if seed >= 0 else int(now()) % 100000,
		"events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false,
		"haul": {}, "free_passage": free_passage, "feeling": "", "feeling_plan": {}}
	if cloak_cap(c) > 0: run.cloak_charges = cloak_cap(c)   # a fresh expedition starts with a full cloak (DECISIONS #206)
	Delve.plan_biome_feelings(run)
	Delve.plan_floor(run)
	stats.runs += 1; note_floor(f0)
	var team := {}
	for hc in heroes:
		if heroes[hc].unlocked: team[hc] = int(heroes[hc].level)
	Telemetry.track("run_start", {"class": c, "biome": biome, "floor": f0, "hero_level": int(heroes[c].level), "gear_level": patrol_gear_level(c),
		"power": power_rating(c), "heroes": team, "supplies": sup, "runs": int(stats.runs)})
	say("%s descends into the %s." % [s.name, DB.biomes[biome].name])
	Delve.log_feeling(self)
	touch(); return true

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
	_track_run_end(result)
	# unused supplies always go back to the stash (they were never "found"); an unused free Passage does not (DECISIONS #226)
	for k in run.supplies:
		var n := int(run.supplies[k])
		if k == "scroll_passage" and run.get("free_passage", false) and n > 0: n -= 1
		if n > 0: add_mat(k, n)
	match result:
		"extract":
			var banked := int(run.pack.get("gold", 0))
			add_stat("gold_banked", banked)
			if banked >= BIG_HAUL_GOLD: add_stat("feat_big_haul", 1)
			for k in run.pack: add_mat(k, int(run.pack[k]))
			for g in run.pack_gear:
				g.erase("owned")
				if _absorb_into_camp(g): continue
				if DB.item(String(g.id)).type == "armor": continue
				gear.append(g)
			stats.extractions += 1
			say("Extracted! The pack is banked at Camp.")
		"death":
			stats.deaths += 1
			if run.get("fighting_goo", false):   # DECISIONS #131: Goo is a skill check, not a death spiral
				stats.goo_losses = int(stats.get("goo_losses", 0)) + 1
				if mat("potion_healing") < 2:
					add_mat("potion_healing", 2 - mat("potion_healing")); log_line("The Camp healer sends you back to Goo with 2 Potions of Healing.", "positive")
			# Camp weapon/armor never crack. Found weapon overrides and rings/artifacts crack; starters/heirlooms don't (#221, #234)
			for slot in ["weapon", "ring", "artifact"]:
				var g := gear_by_uid(int(h.get(slot, 0)))
				if g.is_empty() or g.get("camp", false): continue
				if not _never_cracks(String(g.id)): g.cracked = true
			if String(h.get("wand", "")) != "" and int(h.get("wand_lvl", 0)) > 0: h.wand_cracked = true   # DECISIONS #158
			for g in run.pack_gear:
				if g.get("owned", false):
					g.erase("owned")
					# Fold forge armor/weapons into camp instead of cracking stash copies
					if is_forge_weapon(String(g.id)) or is_forge_armor(String(g.id)):
						_absorb_into_camp(g)
					elif not _never_cracks(String(g.id)) and (DB.item(g.id).type != "wand" or int(g.get("lvl", 0)) > 0):
						g.cracked = true
						gear.append(g)
					else:
						gear.append(g)
			h.best_level = maxi(int(h.get("best_level", 1)), int(h.level))
			h.level = 1; h.xp = 0; h.str = 10; h.talents = []; h.str_found = []; h.cleared = []
			_owe_pack_sou()
			say("%s fell. Pack lost, gear cracked, back to Lv1 / 10 Str. Biomes locked until you clear them again." % DB.heroes[c].name)
			if mat("gold") < SAFETY_GOLD:
				log_line("The Camp chips in %d gold so you can restock." % (SAFETY_GOLD - mat("gold")), "positive")
				add_mat("gold", SAFETY_GOLD - mat("gold"))
		"abandon":
			for g in run.pack_gear:
				if g.get("owned", false): g.erase("owned"); gear.append(g)
			_owe_pack_sou()   # DECISIONS #169: never destroy a once-ever Scroll
			say("Expedition abandoned. Unbanked loot lost.")
	run = {}
	touch()

## Telemetry (DECISIONS #197): extract / death / abandon with the run's numbers, sent before end_run changes them.
func _track_run_end(result: String) -> void:
	var c: String = run.hero
	var base := {"class": c, "biome": String(run.biome), "floor": int(run.floor), "hero_level": int(heroes[c].level),
		"gear_level": patrol_gear_level(c), "fights_won": int(run.get("fights_won", 0))}
	match result:
		"extract":
			var loot := {}
			for k in run.pack:
				if int(run.pack[k]) > 0: loot[String(k)] = int(run.pack[k])
			Telemetry.track("extract", base.merged({"gold": int(run.pack.get("gold", 0)), "loot": loot, "gear_found": run.pack_gear.size()}))
		"death":
			Telemetry.track("death", base.merged({"cause": String(run.get("death_cause", "unknown")), "gold_lost": int(run.pack.get("gold", 0))}))
		_:
			Telemetry.track("abandon", base.merged({"gold_lost": int(run.pack.get("gold", 0))}))

## Scrolls of Upgrade in the pack when a run ends without extracting (death or abandon) are owed and come back
## on the next boss kill. Every Scroll is a one-time drop and maxing the Camp needs all of them (DECISIONS #150, #169).
func _owe_pack_sou() -> void:
	var lost_sou := int(run.pack.get("scroll_upgrade", 0))
	if lost_sou <= 0: return
	owed_sou += lost_sou
	log_line("%d Scroll%s of Upgrade will return on the next boss kill (%d owed)." % [lost_sou, "" if lost_sou == 1 else "s", owed_sou], "highlight")

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
	add_stat(DB.biomes[biome].boss + "_kills", 1)
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
## Progress toward a milestone stat (see data/milestones.json, DECISIONS #195). Plain names read GameState.stats;
## the prefixed and live forms below are worked out from the account, so old saves count what they already have.
func stat_value(stat: String) -> int:
	if stat.begins_with("boss:"):
		var mob := stat.substr(5)
		# saves from before every boss had a counter: each class's first kill of that boss still counts
		var firsts := 0
		for b in DB.biomes:
			if DB.biomes[b] is Dictionary and String(DB.biomes[b].get("boss", "")) == mob:
				for c in boss_kills: firsts += 1 if b in boss_kills[c] else 0
		return maxi(int(stats.get(mob + "_kills", 0)), firsts)
	if stat.begins_with("cleared:"):
		var b := stat.substr(8)
		return heroes.values().filter(func(h): return b in h.cleared).size()
	if stat.begins_with("class_boss:"):
		var parts := stat.split(":")
		var c := parts[1]; var biome := parts[2]
		return 1 if heroes.has(c) and (biome in boss_kills.get(c, []) or biome in heroes[c].cleared) else 0
	if stat.begins_with("kill:"):
		var n := 0
		for mob in stat.substr(5).split(","): n += int(stats.get("kill_" + mob, 0))
		return n
	if stat.begins_with("seen:"):
		var pre := stat.substr(5)
		return seen.keys().filter(func(k): return String(k).begins_with(pre)).size()
	match stat:
		"best_level":
			var best := 0
			for c in heroes: best = maxi(best, maxi(int(heroes[c].level), int(heroes[c].get("best_level", 1))))
			return best
		"heroes_unlocked": return heroes.values().filter(func(h): return h.unlocked).size()
		"talents_max":
			var t := 0
			for c in heroes: t = maxi(t, Array(heroes[c].get("talents", [])).size())
			return t
		"subclasses": return heroes.values().filter(func(h): return String(h.get("subclass", "")) != "").size()
		"facility_ups":
			var u := 0
			for f in facilities: u += maxi(0, int(facilities[f].level) - 1)
			return u
		"facility_caps":
			var cp := 0
			for f in facilities: cp += maxi(0, int(facilities[f].cap) - 1)
			return cp
		"max_gear_lvl":
			var mx := 0
			for g in gear: if g.get("known", true): mx = maxi(mx, int(g.lvl))
			if not camp_weapon.is_empty(): mx = maxi(mx, int(camp_weapon.get("lvl", 0)))
			if not camp_armor.is_empty(): mx = maxi(mx, int(camp_armor.get("lvl", 0)))
			return maxi(mx, int(heroes.get("mage", {}).get("wand_lvl", 0)))
		"patrol_gear_best":
			var pg := 0
			for c in heroes: pg = maxi(pg, patrol_gear_level(c))
			return pg
		"artifacts_owned":
			var ids := {}
			for g in gear: if DB.item(g.id).get("type", "") == "artifact": ids[g.id] = true
			return ids.size()
	return int(stats.get(stat, 0))

func milestone_def(id: String) -> Dictionary:
	for m in DB.milestones:
		if m.id == id: return m
	return {}

## [have, goal] for a milestone's progress bar; a reached one stays full even if a live total later drops
## (a death resets level and talents, gear can be broken down).
func milestone_progress(m: Dictionary) -> Array:
	var goal := int(m.goal)
	if m.id in milestones_reached or m.id in milestones_claimed: return [goal, goal]
	return [mini(stat_value(m.stat), goal), goal]

func milestone_claimable(id: String) -> bool:
	return id in milestones_reached and not (id in milestones_claimed)

## Ids waiting for the player's Claim tap, in data order.
func claimable_milestones() -> Array:
	return DB.milestones.filter(func(m): return milestone_claimable(m.id)).map(func(m): return m.id)

## Latch every newly reached milestone as claimable. Nothing is paid here: the reward waits for claim_milestone
## (DECISIONS #195). Returns the ids that were newly reached.
func check_milestones() -> Array:
	var got := []
	for m in DB.milestones:
		if m.id in milestones_reached or m.id in milestones_claimed: continue
		if stat_value(m.stat) < int(m.goal): continue
		milestones_reached.append(m.id); got.append(m.id)
	if got.size() == 1:
		say("Milestone: %s! Claim it in the Journal." % milestone_def(got[0]).name, "highlight"); Sfx.play("badge")
	elif got.size() > 1:
		say("%d milestones reached! Claim them in the Journal." % got.size(), "highlight"); Sfx.play("badge")
	return got

## Pay one reached milestone into the Camp stash. False if it isn't claimable (not reached, or already paid).
func claim_milestone(id: String) -> bool:
	if not milestone_claimable(id): return false
	var m := milestone_def(id)
	milestones_claimed.append(id)
	Telemetry.track("milestone_claimed", {"milestone": id, "category": String(m.get("cat", "")), "reward": m.reward})
	for k in m.reward: add_mat(k, int(m.reward[k]))
	log_line("Milestone claimed: %s. %s" % [m.name, cost_text(m.reward)], "positive")
	Sfx.play("gold")
	changed.emit()
	return true

## Claim everything waiting. Returns how many were paid.
func claim_all_milestones() -> int:
	var n := 0
	for id in claimable_milestones():
		if claim_milestone(id): n += 1
	return n

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
		"milestones_claimed": milestones_claimed, "milestones_reached": milestones_reached, "seen": seen, "tutorial_done": tutorial_done, "looks": looks, "ided": ided, "owed_sou": owed_sou,
		"time_offset": time_offset, "camp_weapon": camp_weapon, "camp_armor": camp_armor}

func from_dict(d: Dictionary) -> void:
	_suspend_patrol_sync = true
	new_game()
	looks = d.get("looks", {}); ided = d.get("ided", {})
	if looks.is_empty(): _roll_appearances()
	else:
		for k in DB.materials:
			if DB.materials[k].get("unknown", false): _ensure_look(k)
	mats = d.get("mats", mats); gear = d.get("gear", gear); next_uid = int(d.get("next_uid", next_uid))
	camp_weapon = d.get("camp_weapon", {}).duplicate(true) if d.get("camp_weapon", {}) is Dictionary else {}
	camp_armor = d.get("camp_armor", {}).duplicate(true) if d.get("camp_armor", {}) is Dictionary else {}
	for c in d.get("heroes", {}):
		if heroes.has(c): heroes[c].merge(d.heroes[c], true)
	for f in d.get("facilities", {}):
		if facilities.has(f): facilities[f].merge(d.facilities[f], true)
	id_queue = d.get("id_queue", []); boss_kills = d.get("boss_kills", {})
	owed_sou = int(d.get("owed_sou", 0))   # older saves: nothing owed
	settings.merge(d.get("settings", {}), true); run = d.get("run", {})
	stats.merge(d.get("stats", {}), true)
	milestones_claimed = Array(d.get("milestones_claimed", [])); seen = d.get("seen", {}); tutorial_done = Array(d.get("tutorial_done", []))
	# saves from before Claim (DECISIONS #195) paid every reached milestone on the spot: those stay paid, and anything
	# reached under the new list but never paid becomes claimable on the touch() below
	milestones_reached = Array(d.get("milestones_reached", []))
	for id in milestones_claimed:
		if not (id in milestones_reached): milestones_reached.append(id)
	settings.text_scale = float(settings.text_scale); settings.delve_speed = float(settings.delve_speed)
	var iface := String(settings.get("interface", "auto"))
	if iface not in ["auto", "mobile", "desktop"]:
		settings.interface = "auto"
	if typeof(settings.get("keybinds", {})) != TYPE_DICTIONARY:
		settings.keybinds = {}
	for k in stats: stats[k] = int(stats[k])
	time_offset = float(d.get("time_offset", 0.0))   # older saves: no fast-forward
	_fix_types()
	_suspend_patrol_sync = false
	touch()
	sync_patrol_widget()

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
	"supplies": {}, "seed": 0, "events": [], "next_event": 0, "gather": 0, "starve": 0, "milestones_done": [], "pending_loot": 0, "boss_dead": false,
	"feeling": "", "feeling_plan": {}}

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
		# Mystical Upgrade (+1 cloak charge, not in SPD) became SPD's Mystical Meal (DECISIONS #206)
		if h.has("talents"):
			h.talents = Array(h.talents).map(func(t): return "mystical_meal" if String(t) == "mystical_upgrade" else String(t))
		if h.level > MAX_LEVEL: h.level = MAX_LEVEL; h.xp = 0   # saves from before the cap
		# a start ahead of the clock (fast-forward that was not saved) stays at 0% until that gap passes
		var p: Dictionary = h.get("patrol", {})
		if not p.is_empty() and float(p.get("start", 0)) > now(): p.start = now()
	_fix_ownership()
	_migrate_camp_gear()
	for f in facilities:
		facilities[f].level = int(facilities[f].level); facilities[f].cap = int(facilities[f].cap)
		if DB.facilities.has(f): facilities[f].cap = facility_cap(f)
	for q in id_queue: q.uid = int(q.uid)
	_migrate_id_queue()
	if not run.is_empty():
		# runs saved before a field existed (backpack #67, milestones, boss flag...) get its start value (DECISIONS #117)
		for k in RUN_DEFAULTS:
			if not run.has(k): run[k] = RUN_DEFAULTS[k].duplicate(true) if RUN_DEFAULTS[k] is Array or RUN_DEFAULTS[k] is Dictionary else RUN_DEFAULTS[k]
		for k in ["floor", "next_event", "gather", "starve", "seed", "hp", "pending_loot"]: run[k] = int(run.get(k, 0))
		# runs saved before persistent cloak charges (DECISIONS #206) carry a full cloak
		if heroes.has(String(run.get("hero", ""))) and cloak_cap(String(run.hero)) > 0:
			run.cloak_charges = clampi(int(run.get("cloak_charges", cloak_cap(String(run.hero)))), 0, cloak_cap(String(run.hero)))
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
## (cloth = 1 ... plate = 5, class armor = 6). Row 0 is the naked sheet. Uses camp armor (#234).
func armor_tier(c: String) -> int:
	if not heroes.has(c): return 0
	var ra := resolved_armor(c)
	if String(ra.get("source", "")) == "starter":
		# Cloth starter still shows the cloth row (tier 1), not naked
		return clampi(int(DB.item(String(ra.id)).get("tier", 1)), 0, 6)
	return clampi(int(DB.item(String(ra.id)).get("tier", 1)), 0, 6)

## Prefer g over the current camp piece when it is a better forge tier or same tier with higher level.
func _camp_better(cur: Dictionary, g: Dictionary) -> bool:
	if cur.is_empty(): return true
	var ct := int(DB.item(String(cur.id)).get("tier", 1)); var gt := int(DB.item(String(g.id)).get("tier", 1))
	if gt != ct: return gt > ct
	return int(g.get("lvl", 0)) > int(cur.get("lvl", 0))

## Fold one forge gear dict into camp_weapon / camp_armor (no stash entry). Returns true when absorbed.
func _absorb_into_camp(g: Dictionary) -> bool:
	var id := String(g.get("id", ""))
	if is_forge_weapon(id):
		if _camp_better(camp_weapon, g):
			camp_weapon = {"id": id, "lvl": int(g.get("lvl", 0))}
		seen["item:" + id] = true
		return true
	if is_forge_armor(id):
		if _camp_better(camp_armor, g):
			camp_armor = {"id": id, "lvl": int(g.get("lvl", 0))}
		seen["item:" + id] = true
		return true
	return false

## Old saves (DECISIONS #234): collapse forge weapon/armor copies into one camp piece each; clear hero armor
## slots; strip forge swords from hero weapon slots (keep found weapons and Mage/Huntress heirlooms).
## Empty camp after that gets the free Worn Shortsword + Cloth Armor defaults.
func _migrate_camp_gear() -> void:
	if not camp_weapon is Dictionary: camp_weapon = {}
	if not camp_armor is Dictionary: camp_armor = {}
	if not camp_weapon.is_empty():
		camp_weapon = {"id": String(camp_weapon.get("id", "")), "lvl": int(camp_weapon.get("lvl", 0))}
		if not is_forge_weapon(String(camp_weapon.id)): camp_weapon = {}
	if not camp_armor.is_empty():
		camp_armor = {"id": String(camp_armor.get("id", "")), "lvl": int(camp_armor.get("lvl", 0))}
		if not is_forge_armor(String(camp_armor.id)): camp_armor = {}
	# Absorb forge pieces from stash and from an active pack
	var keep: Array = []
	for g in gear:
		if _absorb_into_camp(g): continue
		if String(DB.item(String(g.get("id", ""))).get("type", "")) == "armor": continue   # leftover armor instances: melt (no refund)
		keep.append(g)
	gear = keep
	if not run.is_empty():
		var pack_keep: Array = []
		for g in run.get("pack_gear", []):
			if _absorb_into_camp(g): continue
			if String(DB.item(String(g.get("id", ""))).get("type", "")) == "armor": continue
			pack_keep.append(g)
		run.pack_gear = pack_keep
		var over_keep: Array = []
		for g in run.get("overflow", []):
			if _absorb_into_camp(g): continue
			if String(DB.item(String(g.get("id", ""))).get("type", "")) == "armor": continue
			over_keep.append(g)
		run.overflow = over_keep
	if camp_weapon.is_empty():
		camp_weapon = {"id": DEFAULT_CAMP_WEAPON, "lvl": 0}
		seen["item:" + DEFAULT_CAMP_WEAPON] = true
	if camp_armor.is_empty():
		camp_armor = {"id": DEFAULT_CAMP_ARMOR, "lvl": 0}
		seen["item:" + DEFAULT_CAMP_ARMOR] = true
	for c in heroes:
		var h: Dictionary = heroes[c]
		h.armor = 0
		var w := gear_by_uid(int(h.get("weapon", 0)))
		if w.is_empty():
			h.weapon = 0
		elif is_forge_weapon(String(w.id)):
			h.weapon = 0
		elif c != "mage" and c != "huntress" and String(w.id) == String(DB.heroes[c].get("start_weapon", "")):
			# Warrior worn shortsword / Rogue dagger instances: use camp instead
			gear.erase(w); h.weapon = 0
		# Mage/Huntress keep staff/gloves; found weapons stay
