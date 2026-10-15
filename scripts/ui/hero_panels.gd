## HeroPanels: shared Talents and Backpack panels (Camp Heroes page, Delve screen, Combat "Bag").
## Built with the SPD chrome theme (UIKit.card / buttons). `refresh` is called after every change.
class_name HeroPanels
extends RefCounted

## Talent tiers for hero `c`. Learned talents are gold, available ones are buttons, locked ones show why.
static func talents(parent: Control, c: String, refresh: Callable) -> void:
	var card := UIKit.card(); parent.add_child(card)
	var v := UIKit.vbox(card)
	var free := GameState.talent_points_total_free(c)
	v.add_child(UIKit.label("Talents" + ("  (%d point%s to spend)" % [free, "" if free == 1 else "s"] if free > 0 else ""), 1.1, Color("ffd27a")))
	for tier in ["1", "2"]:
		var td: Dictionary = DB.talents._tiers[tier]
		v.add_child(UIKit.label("Tier %s - points at Lv %s  (%d/%d used)" % [tier, ", ".join(td.points_at.map(func(l): return str(int(l)))),
			GameState.talent_points(c, tier) - GameState.talent_points_free(c, tier), td.points_at.size()], 0.85, Color("c9a96e")))
		var flow := HFlowContainer.new(); v.add_child(flow)
		var defs: Dictionary = DB.talents.get(c, {}).get(tier, {})
		for tid in defs:
			var t: Dictionary = defs[tid]
			var learned: bool = tid in GameState.heroes[c].get("talents", [])
			var why := GameState.can_pick_talent(c, tid)
			var b := UIKit.button(("* " if learned else "") + "%s\n%s" % [t.name, t.desc], func():
				if GameState.pick_talent(c, tid): Sfx.play("levelup"); refresh.call(), why == "", why)
			b.custom_minimum_size.x = UIKit.font_size * 9
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if learned: b.add_theme_color_override("font_disabled_color", Color("ffd27a"))
			flow.add_child(b)

## In-delve backpack: belt supplies (use), equipped slots (unequip), carried gear (equip / compare / drop),
## full-pack loot decisions. in_combat: only equip actions, each costs a turn (on_equip_in_combat is called).
static func backpack(parent: Control, refresh: Callable, in_combat := false, on_equip_in_combat := Callable()) -> void:
	var run: Dictionary = GameState.run
	if run.is_empty(): return
	var c: String = run.hero
	var h: Dictionary = GameState.heroes[c]
	var card := UIKit.card(); parent.add_child(card)
	var v := UIKit.vbox(card)
	v.add_child(UIKit.label("Backpack  %d/%d slots" % [GameState.backpack_used(), GameState.BACKPACK_SLOTS], 1.1, Color("ffd27a")))
	if in_combat: v.add_child(UIKit.label("Swapping gear in a fight costs your turn.", 0.8, Color("c9a96e")))
	# overflow first: it blocks nothing but needs a decision
	var ov: Array = run.get("overflow", [])
	if not ov.is_empty() and not in_combat:
		var g: Dictionary = ov[0]
		v.add_child(UIKit.label("Backpack full! Found: %s. Drop something to take it, or leave it." % GameState.gear_name(g), 0.9, Color("ff9a70")))
		v.add_child(UIKit.button("Leave %s" % GameState.gear_name(g), func(): GameState.resolve_overflow(-1); refresh.call()))
		for pg in run.pack_gear:
			if pg.get("owned", false): continue
			v.add_child(UIKit.button("Drop %s, take it" % GameState.gear_name(pg), func(): GameState.resolve_overflow(int(pg.uid)); refresh.call()))
		return
	if not in_combat:
		var flow := HFlowContainer.new(); v.add_child(flow)
		for k in ["potion_healing", "ration", "torch"]:
			var n := int(run.supplies.get(k, 0))
			var b := UIKit.button("Use %s (%d)" % [DB.mat_name(k), n], func(): GameState.delve_use(k); refresh.call(), n > 0)
			b.custom_minimum_size.x = UIKit.font_size * 7; flow.add_child(b)
	# equipped
	v.add_child(UIKit.label("Equipped", 0.9, Color("c9a96e")))
	for slot in ["weapon", "armor", "ring"]:
		var g := GameState.gear_by_uid(int(h[slot]))
		var row := UIKit.hbox(v)
		if not g.is_empty(): row.add_child(UIKit.icon(g.id))
		var l := UIKit.label("%s: %s" % [slot.capitalize(), GameState.gear_name(g)], 0.9); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not in_combat and not g.is_empty() and not DB.item(g.id).get("heirloom", false):
			var ub := UIKit.button("Unequip", func(): GameState.delve_unequip(slot); refresh.call(), not GameState.backpack_full(), "backpack full")
			ub.size_flags_horizontal = Control.SIZE_SHRINK_END; ub.custom_minimum_size.x = UIKit.font_size * 5; row.add_child(ub)
	if c == "mage" and h.wand != "": v.add_child(UIKit.label("Staff: %s" % DB.item(h.wand).name, 0.9))
	# carried
	v.add_child(UIKit.label("Carried" if not run.pack_gear.is_empty() else "Carried: nothing yet", 0.9, Color("c9a96e")))
	for g in run.pack_gear:
		var row := UIKit.hbox(v)
		row.add_child(UIKit.icon(g.id))
		var info := UIKit.vbox(row); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UIKit.label(GameState.gear_name(g) + ("  (yours)" if g.get("owned", false) else ""), 0.9))
		var why := GameState.can_delve_equip(int(g.uid))
		if why == "":
			info.add_child(UIKit.label(GameState.compare_text(GameState.compare_equip(int(g.uid))), 0.75, Color("9fd3ff")))
		else:
			info.add_child(UIKit.label(why, 0.75, Color("9a8f7c")))
		var bs := UIKit.vbox(row); bs.size_flags_horizontal = Control.SIZE_SHRINK_END
		var label := "Imbue" if DB.item(g.id).type == "wand" else "Equip"
		var eb := UIKit.button(label, func():
			if GameState.delve_equip(int(g.uid)):
				if in_combat and on_equip_in_combat.is_valid(): on_equip_in_combat.call()
				refresh.call(), why == "", why)
		eb.custom_minimum_size.x = UIKit.font_size * 5; bs.add_child(eb)
		if not in_combat and not g.get("owned", false):
			var db := UIKit.button("Drop", func(): GameState.delve_drop(int(g.uid)); refresh.call())
			db.custom_minimum_size.x = UIKit.font_size * 5; bs.add_child(db)
