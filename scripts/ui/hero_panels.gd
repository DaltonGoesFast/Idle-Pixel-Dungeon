## HeroPanels: shared Talents and Backpack panels (Camp Heroes page, Delve screen, Combat "Bag").
## Built with the SPD chrome theme (UIKit.card / buttons). `refresh` is called after every change.
class_name HeroPanels
extends RefCounted

## Talent tiers for hero `c`. Learned talents are gold, available ones are buttons, locked ones show why.
static var sel_talent := ""   # talent whose details are shown under its tier

## SPD TalentsPane look (DECISIONS #83): per tier a header with points used, then a row of 20x20
## talent_button.png squares holding the talent_icons.png icon (dim until learned) and the name below.
## Tapping one shows its description and a Learn button under that tier, so there are no text walls.
static func talents(parent: Control, c: String, refresh: Callable) -> void:
	var card := UIKit.card(); parent.add_child(card)
	var v := UIKit.vbox(card)
	var free := GameState.talent_points_total_free(c)
	v.add_child(UIKit.label("Talents" + ("  (%d point%s to spend)" % [free, "" if free == 1 else "s"] if free > 0 else ""), 1.1, Color("ffd27a")))
	var bg_tex: Texture2D = load("res://assets/ui/talent_button.png"); var ic_tex: Texture2D = load("res://assets/ui/talent_icons.png")
	var k := maxf(2.0, floorf(UIKit.font_size / 7.0))
	for tier in ["1", "2"]:
		var td: Dictionary = DB.talents._tiers[tier]
		var used := GameState.talent_points(c, tier) - GameState.talent_points_free(c, tier)
		var hdr := UIKit.hbox(v)
		var hl := UIKit.label("Tier %s" % tier, 0.95, Color("ffd27a")); hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hdr.add_child(hl)
		var pl := UIKit.label("%d/%d  (Lv %s)" % [used, td.points_at.size(), ", ".join(td.points_at.map(func(l): return str(int(l))))], 0.8, Color("c9a96e"))
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF; hdr.add_child(pl)
		var row := GridContainer.new(); row.columns = 4; v.add_child(row)
		row.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.3))
		var defs: Dictionary = DB.talents.get(c, {}).get(tier, {})
		var detail_for := ""
		for tid in defs:
			var t: Dictionary = defs[tid]
			var learned: bool = tid in GameState.heroes[c].get("talents", [])
			var why := GameState.can_pick_talent(c, tid)
			if sel_talent == tid: detail_for = tid
			var cell := UIKit.vbox(); cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(cell)
			var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.flat = true
			b.custom_minimum_size = Vector2(20, 20) * k; b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var at := AtlasTexture.new(); at.atlas = bg_tex; at.region = Rect2(0, 0, 20, 20)
			var bgr := UIKit.pixel(at, int(k)); bgr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); b.add_child(bgr)
			var ai := AtlasTexture.new(); ai.atlas = ic_tex
			var idx := int(t.get("icon", 0)); ai.region = Rect2((idx % 32) * 16, (idx / 32) * 16, 16, 16)
			var ir := UIKit.pixel(ai, int(k)); ir.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ir.modulate = Color.WHITE if learned else (Color(1, 1, 1, 0.75) if why == "" else Color(1, 1, 1, 0.3))
			b.add_child(ir)
			if sel_talent == tid:
				var hi := ColorRect.new(); hi.color = Color(1, 1, 0.5, 0.25); hi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hi.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(hi)
			if why == "" and not learned:   # SPD-style "can upgrade" pip
				var pip := ColorRect.new(); pip.color = Color("6bff6b"); pip.size = Vector2(3, 3) * k; pip.position = Vector2(16, 1) * k; pip.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(pip)
			b.tooltip_text = "%s: %s" % [t.name, t.desc]
			b.pressed.connect(func(): Sfx.play("click"); sel_talent = "" if sel_talent == tid else tid; refresh.call())
			cell.add_child(b)
			var nl := UIKit.label(t.name, 0.75, Color("ffd27a") if learned else Color("d8d0c0"))
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cell.add_child(nl)
		if detail_for != "":
			var t2: Dictionary = defs[detail_for]
			var learned2: bool = detail_for in GameState.heroes[c].get("talents", [])
			var dc := UIKit.card(); v.add_child(dc); var dv := UIKit.vbox(dc)
			dv.add_child(UIKit.label(t2.name + ("  (learned)" if learned2 else ""), 1.0, Color("ffd27a")))
			dv.add_child(UIKit.label(t2.desc, 0.9))
			if not learned2:
				var why2 := GameState.can_pick_talent(c, detail_for)
				var tid2 := detail_for
				dv.add_child(UIKit.action("Learn", func():
					if GameState.pick_talent(c, tid2): Sfx.play("levelup"); sel_talent = ""; refresh.call(), why2))

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
	# equipped: the same paperdoll as the Camp Heroes window, swapping from the pack (DECISIONS #84)
	var vs: Vector2 = (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size
	Paperdoll.build(v, c, vs.x > vs.y * 0.7, "delve", refresh, Callable(), on_equip_in_combat)
	# unknown / found potions and scrolls (use identifies them, DECISIONS #80)
	if not in_combat:
		var cons: Array = GameState.unknown_mats().filter(func(k): return int(run.pack.get(k, 0)) > 0)
		if not cons.is_empty():
			v.add_child(UIKit.label("Potions & scrolls", 0.9, Color("c9a96e")))
			var cf := HFlowContainer.new()
			cf.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			cf.add_theme_constant_override("h_separation", int(UIKit.font_size * 0.5))
			cf.add_theme_constant_override("v_separation", int(UIKit.font_size * 0.3))
			v.add_child(cf)
			for k in cons:
				# A wrapping button with no width of its own reports a few pixels wide and hundreds tall
				# (the red columns in the backpack). Keep the label on one line beside the icon.
				var pr := UIKit.hbox(); cf.add_child(pr)
				pr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				var ic := UIKit.icon(k)   # integer-scaled PixelIcon, not a 1x Button icon (DECISIONS #98)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				pr.add_child(ic)
				var cb := UIKit.button("%s x%d" % [DB.mat_name(k), int(run.pack[k])], func(): GameState.delve_use_pack(k); refresh.call())
				cb.autowrap_mode = TextServer.AUTOWRAP_OFF
				cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				cb.tooltip_text = DB.materials[k].desc if GameState.is_mat_known(k) else "Unidentified - use it to find out."
				pr.add_child(cb)
	# carried
	v.add_child(UIKit.label("Carried" if not run.pack_gear.is_empty() else "Carried: nothing yet", 0.9, Color("c9a96e")))
	for g in run.pack_gear:
		var row := UIKit.hbox(v)
		var bdg := UIKit.gear_badge(g)
		row.add_child(UIKit.icon(g.id, -1, bdg if bdg != "" else "NONE"))
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
