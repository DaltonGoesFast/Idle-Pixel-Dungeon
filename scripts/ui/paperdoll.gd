## Paperdoll: Diablo-style character screen (DECISIONS #84), used by the Camp Heroes window and the in-delve backpack.
## A big hero sprite (its row picks the armor tier, as SPD's HeroSprite does) sits between two columns of SPD item slots:
## weapon/ring/staff on the left, armor/artifact/class item on the right, with no spare misc slot (removed in v0.22.0, DECISIONS #85). A derived-stats panel
## goes beside the doll (inner) or under it (cover). Tapping a slot shows its item and a swap list filtered to that
## slot, with stat deltas: from the stash at Camp, from the pack mid-delve.
class_name Paperdoll
extends RefCounted

static var sel_slot := ""
const LEFT := ["weapon", "ring", "staff"]
const RIGHT := ["armor", "artifact", "class"]
const EMPTY_ICON := {"weapon": "WEAPON_HOLDER", "armor": "ARMOR_HOLDER", "ring": "RING_HOLDER", "artifact": "ARTIFACT_HOLDER",
	"staff": "WAND_HOLDER", "class": "SOMETHING", "misc": "SOMETHING"}
const CLASS_ITEM := {"warrior": ["SEAL", "Broken Seal", "The Warrior's seal: his armor's Barrier comes from it."],
	"mage": ["MAGES_STAFF", "Mage's Staff", "The Mage's heirloom staff: melee grows with level, and it casts the imbued wand's bolt."],
	"rogue": ["ARTIFACT_CLOAK", "Cloak of Shadows", "The Rogue's cloak: surprise attacks hit harder."],
	"huntress": ["SPIRIT_BOW", "Spirit Bow", "The Huntress's bow: ranged shots that grow with level."]}

## mode: "camp" (swap from the stash) or "delve" (swap from the pack; in_combat costs the turn).
static func build(parent: Control, c: String, wide: bool, mode: String, refresh: Callable, on_talents := Callable(), on_equip_in_combat := Callable()) -> void:
	var h: Dictionary = GameState.heroes[c]
	var outer: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(UIKit.font_size * 0.6)); parent.add_child(outer)
	# --- doll
	var doll_card := UIKit.card(); outer.add_child(doll_card)
	doll_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not wide else Control.SIZE_FILL
	var dv := UIKit.vbox(doll_card)
	var name_l := UIKit.label("%s  Lv%d" % [DB.heroes[c].name, h.level] + ("  -  " + DB.heroes[c].subclasses[h.subclass].name if h.get("subclass", "") != "" else ""), 1.0, Color("ffd27a"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dv.add_child(name_l)
	var lock := GameState.gear_lock(c) if mode == "camp" else ""
	if lock != "":   # patrol / expedition: nothing comes off or goes on until they're back (DECISIONS #189)
		var ll := UIKit.label(lock + " - gear locked", 0.75, Color("c9a96e")); ll.name = "GearLock"
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dv.add_child(ll)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; dv.add_child(row)
	row.add_theme_constant_override("separation", int(UIKit.font_size * 0.5))
	var lc := UIKit.vbox(); row.add_child(lc)
	for s in LEFT: lc.add_child(_slot(c, s, mode, refresh))
	var slot_px := UIKit.font_size * 3.0
	var k := maxf(3.0, floorf((slot_px * 3.0 + UIKit.font_size * 0.8) / 15.0 / 1.15))
	var hero := UIKit.pixel(hero_tex(c), int(k)); hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plinth := PanelContainer.new(); plinth.add_theme_stylebox_override("panel", UIKit.chrome("grey_button", Color(0.55, 0.55, 0.55), UIKit.font_size * 0.3))
	plinth.add_child(hero); plinth.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(plinth)
	var rc := UIKit.vbox(); row.add_child(rc)
	for s in RIGHT: rc.add_child(_slot(c, s, mode, refresh))
	# --- stats
	var right := UIKit.vbox(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; outer.add_child(right)
	right.add_child(stats_panel(c, on_talents))
	if sel_slot != "": right.add_child(_detail(c, sel_slot, mode, refresh, on_equip_in_combat))
	else: right.add_child(UIKit.label("Tap a slot to inspect or swap it.", 0.8, Color("9a9488")))

static func hero_tex(c: String) -> Texture2D:
	var tier := GameState.armor_tier(c)
	var at := AtlasTexture.new(); at.atlas = load("res://assets/sprites/%s.png" % c)
	at.region = Rect2(0, tier * 15, 12, 15); return at

## The item in a slot: gear dict (weapon/armor/ring/artifact), or a pseudo-item for staff/class.
static func slot_item(c: String, s: String) -> Dictionary:
	var h: Dictionary = GameState.heroes[c]
	match s:
		"weapon", "armor", "ring", "artifact": return GameState.gear_by_uid(int(h.get(s, 0)))
		"staff":
			if c == "mage" and String(h.get("wand", "")) != "": return {"pseudo": true, "icon": h.wand, "name": DB.item(h.wand).name, "desc": "Imbued into the Mage's Staff: its bolt."}
		"class": return {"pseudo": true, "icon": CLASS_ITEM[c][0], "name": CLASS_ITEM[c][1], "desc": CLASS_ITEM[c][2]}
	return {}

static func _slot(c: String, s: String, mode: String, refresh: Callable) -> Button:
	var it := slot_item(c, s)
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE
	var sz := UIKit.font_size * 3.0; b.custom_minimum_size = Vector2(sz, sz)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.33, 0.34, 0.30, 0.6)
	if sel_slot == s: bg.border_color = Color("ffff66"); bg.set_border_width_all(maxi(2, int(UIKit.font_size * 0.12)))
	elif not it.is_empty() and not it.has("pseudo"): bg.border_color = Color("c9a96e"); bg.set_border_width_all(maxi(1, int(UIKit.font_size * 0.08)))
	for st in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(st, bg)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon_id: String = EMPTY_ICON[s] if it.is_empty() else (it.icon if it.has("pseudo") else it.id)
	var bdg := UIKit.gear_badge(it)
	var ic := UIKit.icon(icon_id, int(sz * 0.7), bdg if bdg != "" else "NONE"); ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if it.is_empty(): ic.modulate = Color(1, 1, 1, 0.3)
	elif it.get("cracked", false):   # red frame, true colours (DECISIONS #98)
		bg.border_color = Color("ff5040"); bg.set_border_width_all(maxi(2, int(UIKit.font_size * 0.12)))
	b.add_child(ic)
	if not it.is_empty() and not it.has("pseudo") and it.known and int(it.lvl) > 0:
		var l := UIKit.label("+%d" % it.lvl, 0.75, Color("66ffff")); l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.position = Vector2(UIKit.font_size * 0.15, 0); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(l)
	if not it.is_empty() and not it.has("pseudo"):
		UIKit.add_str_label(b, it.id, int(GameState.heroes[c].str), it)
	b.tooltip_text = s.capitalize() + ": " + (("empty" if it.is_empty() else (it.name if it.has("pseudo") else GameState.gear_name(it))))
	b.pressed.connect(func(): Sfx.play("click"); sel_slot = "" if sel_slot == s else s; refresh.call())
	return b

static func stats_panel(c: String, on_talents: Callable) -> Control:
	var card := UIKit.card(); var v := UIKit.vbox(card)
	var h: Dictionary = GameState.heroes[c]; var s := GameState.hero_stats(c)
	v.add_child(UIKit.label("Stats", 0.95, Color("ffd27a")))
	var xb := ProgressBar.new(); xb.max_value = GameState.xp_to_next(h.level); xb.value = h.xp; xb.show_percentage = false
	xb.custom_minimum_size.y = UIKit.font_size * 0.5; xb.tooltip_text = "%d / %d xp" % [h.xp, GameState.xp_to_next(h.level)]; v.add_child(xb)
	var g := GridContainer.new(); g.columns = 4; v.add_child(g)
	g.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.6))
	var rows := [["HP", str(s.ht)], ["Dmg", str(s.dmg)], ["DR", str(s.dr)], ["Barrier", str(s.barrier_max)],
		["Speed", "%.1f" % (1.0 / maxf(0.1, float(s.delay))) + "x"], ["Str", str(h.str)], ["XP", "%d/%d" % [h.xp, GameState.xp_to_next(h.level)]], ["Search", str(1 + int(s.get("search_add", 0)))]]
	for r in rows:
		var kl := UIKit.label(r[0], 0.8, Color("bdb3a0")); kl.autowrap_mode = TextServer.AUTOWRAP_OFF; g.add_child(kl)
		var vl := UIKit.label(r[1], 0.9); vl.autowrap_mode = TextServer.AUTOWRAP_OFF; g.add_child(vl)
	if s.has("bolt"): v.add_child(UIKit.label("Bolt: %s %d dmg, %d charges" % [s.bolt.name, s.bolt.dmg, s.bolt.charges], 0.8, Color("c8a0ff")))
	elif GameState.staff_empty(c):   # DECISIONS #192
		var nb := UIKit.label("Bolt: none - no wand in the Staff", 0.8, Color("ffb060")); nb.name = "NoBolt"; v.add_child(nb)
	if s.has("sub_name"): v.add_child(UIKit.label("%s: %s" % [s.sub_name, DB.heroes[c].subclasses[s.sub].desc], 0.8, Color("9fd3ff")))
	elif h.get("mask", false): v.add_child(UIKit.label("Tengu's Mask: choose a subclass.", 0.8, Color("9fd3ff")))
	if on_talents.is_valid():
		var free := GameState.talent_points_total_free(c)
		var tb := UIKit.button("Talents" + (" (%d)" % free if free > 0 else ""), on_talents); UIKit.with_icon(tb, "talent")
		if free == 0: UIKit.secondary(tb)
		v.add_child(tb)
	return card

## Hero stats with `uid` put into `slot` (Camp swap preview).
static func _stats_with(c: String, slot: String, uid: int) -> Dictionary:
	var h: Dictionary = GameState.heroes[c]; var old = h.get(slot, 0)
	h[slot] = uid; var s := GameState.hero_stats(c); h[slot] = old
	return s

## Staff charges a hero's stats give in a fight (0 without a charged staff; the Spirit Bow is unlimited).
static func _staff_charges(s: Dictionary) -> int:
	var bolt: Dictionary = s.get("bolt", {})
	return 0 if bolt.is_empty() or bolt.get("infinite", false) else int(bolt.get("charges", 0))

static func _delta_text(a: Dictionary, b: Dictionary) -> Array:   # [text, better?]
	var parts := []; var score := 0
	for k in [["ht", "HP"], ["dmg", "Dmg"], ["dr", "DR"], ["barrier_max", "Barrier"]]:
		var d := int(b.get(k[0], 0)) - int(a.get(k[0], 0))
		if d != 0: parts.append("%s %s%d" % [k[1], "+" if d > 0 else "", d]); score += d
	# Ring of Energy: count staff charges actually gained, not the raw bonus (no staff, no charges: DECISIONS #126)
	var dc := _staff_charges(b) - _staff_charges(a)
	if dc != 0: parts.append("Charges %s%d" % ["+" if dc > 0 else "", dc]); score += dc
	var dg := int(round((float(b.get("gold_mult", 1.0)) - float(a.get("gold_mult", 1.0))) * 100))
	if dg != 0: parts.append("Gold %s%d%%" % ["+" if dg > 0 else "", dg]); score += dg
	var ds := int(b.get("search_radius", 1)) - int(a.get("search_radius", 1))
	if ds != 0: parts.append("Search %s%d" % ["+" if ds > 0 else "", ds]); score += ds
	var dh := int(round((1.0 - float(b.get("hunger_mult", 1.0))) * 100)) - int(round((1.0 - float(a.get("hunger_mult", 1.0))) * 100))
	if dh != 0: parts.append("Satiety %s%d%%" % ["+" if dh > 0 else "", dh]); score += dh
	return ["no stat change" if parts.is_empty() else "  ".join(parts), score]

static func _detail(c: String, s: String, mode: String, refresh: Callable, on_equip_in_combat: Callable) -> Control:
	var card := UIKit.card(); var v := UIKit.vbox(card)
	var it := slot_item(c, s)
	var top := UIKit.hbox(v)
	var nm := UIKit.label(s.capitalize() + ": " + ("empty" if it.is_empty() else (it.name if it.has("pseudo") else GameState.gear_name(it))), 0.95, Color("ffd27a"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(nm)
	if it.has("pseudo"): v.add_child(UIKit.label(it.desc, 0.8))
	elif not it.is_empty():
		var d := DB.item(it.id)
		if it.get("known", true) and d.has("desc"): v.add_child(UIKit.label(d.desc, 0.8))
		if it.get("cracked", false): v.add_child(UIKit.label("Cracked - repair at the Forge.", 0.8, Color("ff6a5a")))
		if mode == "delve" and not d.get("heirloom", false):
			v.add_child(UIKit.button("Unequip", func(): GameState.delve_unequip(s); refresh.call(), not GameState.backpack_full(), "backpack full"))
	# Camp: take it off into the stash, unless it's an heirloom or the hero is out (DECISIONS #189)
	if mode == "camp" and not it.is_empty() and s != "class" and not (not it.has("pseudo") and DB.item(it.id).get("heirloom", false)):
		var why_off := GameState.can_unequip(c, s)
		var ub := UIKit.action("Unequip", func(): GameState.unequip(c, s); refresh.call(), why_off); ub.name = "UnequipAction"
		v.add_child(ub)
	if s == "class": return card
	# swap candidates, filtered to this slot
	var want := "wand" if s == "staff" else s
	if s == "staff" and c != "mage": v.add_child(UIKit.label("Only the Mage imbues wands.", 0.8, Color("9a9488"))); return card
	var cands: Array = []
	if mode == "camp":
		if s == "staff": return card   # wands are imbued from the Heroes page button
		var base := GameState.hero_stats(c)
		var worn_list: Array = []
		for g in GameState.gear:
			var who := GameState.equipped_by(g.uid)
			if DB.item(g.id).type != want or who == c: continue
			var why := GameState.can_equip(c, g.uid)
			if why.begins_with("heirloom"): continue
			var dt: Array = _delta_text(base, _stats_with(c, s, g.uid)) if why == "" else [why, 0]
			var cd := [g, dt, why, func(): GameState.equip(c, g.uid), who]
			if who == "": cands.append(cd)
			else: worn_list.append(cd)   # gear other heroes wear comes after the free pieces
		cands.append_array(worn_list)
	else:
		for g in GameState.run.pack_gear:
			if DB.item(g.id).type != want: continue
			var why := GameState.can_delve_equip(int(g.uid))
			var dt := [GameState.compare_text(GameState.compare_equip(int(g.uid))) if why == "" else why, 0]
			cands.append([g, dt, why, func():
				if GameState.delve_equip(int(g.uid)) and on_equip_in_combat.is_valid(): on_equip_in_combat.call()])
	var any_worn := cands.any(func(cd): return cd.size() > 4 and String(cd[4]) != "")
	v.add_child(UIKit.label(("Swap from stash" + (" or another hero" if any_worn else "") if mode == "camp" else "Swap from pack") + (" - nothing fits" if cands.is_empty() else ""), 0.85, Color("c9a96e")))
	for cd in cands:
		var g: Dictionary = cd[0]
		var r := UIKit.hbox(v)
		var bdg := UIKit.gear_badge(g)
		r.add_child(UIKit.icon(g.id, -1, bdg if bdg != "" else "NONE"))
		var cv := UIKit.vbox(r); cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UIKit.label(GameState.gear_name(g), 0.85))
		var who2: String = cd[4] if cd.size() > 4 else ""
		if who2 != "":   # worn by another hero: say who, and what happens to their slot
			var back := GameState.equip_swap_back(c, int(g.uid))
			var wl := UIKit.label("Worn by %s - %s" % [DB.heroes[who2].name, ("they get your " + GameState.gear_name(GameState.gear_by_uid(back))) if back != 0 else "their slot goes empty"], 0.75, Color("c9a96e"))
			wl.name = "WornBy"; cv.add_child(wl)
		var col := Color("9a8f7c") if cd[2] != "" else (Color("6bff6b") if int(cd[1][1]) > 0 else (Color("ff6a5a") if int(cd[1][1]) < 0 else Color("9fd3ff")))
		cv.add_child(UIKit.label(String(cd[1][0]), 0.75, col))
		var cb: Callable = cd[3]
		var verb := "Equip" if who2 == "" else ("Swap" if GameState.equip_swap_back(c, int(g.uid)) != 0 else "Take")
		var eb := UIKit.button(verb, func(): cb.call(); refresh.call(), cd[2] == "", cd[2])
		eb.size_flags_horizontal = Control.SIZE_SHRINK_END; eb.custom_minimum_size.x = UIKit.font_size * 5; r.add_child(eb)
	return card
