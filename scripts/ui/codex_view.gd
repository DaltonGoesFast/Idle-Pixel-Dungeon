## CodexView: the bestiary / trap / item encyclopedia in the Camp Journal. Entries unlock as you meet
## them (GameState.seen); unknown ones show as "???" so the codex doubles as a discovery checklist.
class_name CodexView
extends RefCounted

static func build(v: VBoxContainer, portrait: bool) -> void:
	var mobs := DB.mobs.keys()
	var known := mobs.filter(func(m): return GameState.seen.has("mob:" + m))
	v.add_child(UIKit.header("Bestiary  %d / %d" % [known.size(), mobs.size()]))
	for id in mobs:
		var m: Dictionary = DB.mobs[id]
		var card := UIKit.card(); v.add_child(card)
		if GameState.seen.has("mob:" + id):
			var row := UIKit.hbox(card)
			row.add_child(_sprite(m))
			var cv := UIKit.vbox(row); cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cv.add_child(UIKit.label(m.name + ("  (boss)" if m.get("boss", false) else ""), 1.0, Color("ffd27a")))
			cv.add_child(UIKit.label(Codex.mob_line(id), 0.85))
			cv.add_child(UIKit.label("Found in: " + ", ".join(Codex.mob_biomes(id)), 0.75, Color("9a8f7c")))
		else:
			card.add_child(UIKit.label("???  - not encountered yet (%s)" % ", ".join(Codex.mob_biomes(id)), 0.9, Color("777064")))
	v.add_child(UIKit.header("Traps"))
	for id in DB.traps:
		var t: Dictionary = DB.traps[id]
		if GameState.seen.has("trap:" + id): v.add_child(UIKit.label("%s - %s" % [t.name, t.desc], 0.85))
		else: v.add_child(UIKit.label("??? - an undiscovered trap", 0.85, Color("777064")))
	v.add_child(UIKit.header("Items"))
	var grid := GridContainer.new(); grid.columns = 1 if portrait else 2; v.add_child(grid)
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if Codex.item_known(id):
			var r := UIKit.icon_row(id, "%s - %s" % [it.name, Codex.item_line(id)], 0.8); r.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_child(r)
		else:
			var l := UIKit.label("??? (%s)" % it.get("unknown_name", it.type), 0.8, Color("777064"))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_child(l)

static func _sprite(m: Dictionary) -> Control:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/%s.png" % m.sprite)
	at.region = Rect2(0, 0, int(m.fw), int(m.fh))
	var s := UIKit.font_size * 3.0
	var tr := UIKit.pixel(at, maxi(1, int(s / maxf(float(m.fw), float(m.fh)))), Vector2(s, s))
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tr
