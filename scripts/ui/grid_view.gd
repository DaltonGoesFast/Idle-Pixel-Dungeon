## GridView: draws the 8x8 arena with SPD tiles/sprites (nearest filter, integer scale) and juice:
## tweened movement, hit flash, floating damage numbers, bolt streaks, pulsing red danger tiles.
## Emits `tapped(cell)`. Visual state is driven by Combat.drain_events().
extends Control

signal tapped(cell: Vector2i)

const TILE_IDX := {Combat.T.FLOOR: 0, Combat.T.GRASS: 66, Combat.T.WALL: 48, Combat.T.DOOR: 56, Combat.T.CHASM: 24, Combat.T.WATER: 0}
const MOVE_TIME := 0.12

var combat: Combat
var tex := {}
var tiles: Texture2D
var features: Texture2D     # SPD terrain_features.png (trap sprites)
var tileset := "tiles_sewers"
var rings := []             # search pulses [{pos, r, t}]
var anim_t := 0.0
var disp := {}          # uid -> Vector2 (cell-space display position)
var flash := {}         # uid -> seconds remaining
var floaters := []      # [{pos: Vector2 (cell space), text, color, t}]
var streaks := []       # [{from, to, t}]
var blasts := []        # [{pos, t}]
var hint_cell := Vector2i(-1, -1)
var mode := ""
var lunge := {}         # uid -> {dir: Vector2, t}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tiles = load("res://assets/tiles/%s.png" % tileset)
	features = load("res://assets/tiles/terrain_features.png")
	resized.connect(queue_redraw)

func sprite(name: String) -> Texture2D:
	if not tex.has(name): tex[name] = load("res://assets/sprites/%s.png" % name)
	return tex[name]

func set_combat(c: Combat) -> void:
	combat = c
	disp.clear()
	for u in c.units: disp[u.uid] = Vector2(u.pos)

## Feed model events into visual effects.
func play_events(evs: Array) -> void:
	for e in evs:
		match e.t:
			"hit":
				flash[e.uid] = 0.18
				var col := Color("ff5050")
				var txt := str(e.amount)
				match e.kind:
					"barrier": col = Color("7fd3ff")
					"chip": col = Color("7fd3ff"); txt = "chip"
					"block": col = Color("bbbbbb"); txt = "block"
					"surprise": col = Color("ffd27a"); txt += "!"
					"magic": col = Color("c08bff")
					"poison": col = Color("8be04e")
				floaters.append({"pos": Vector2(e.pos), "text": txt, "color": col, "t": 0.0})
				Sfx.play("hit_strong" if e.kind == "surprise" else ("hit_magic" if e.kind == "magic" else "hit"), 1.0)
				if e.uid == combat.hero.uid and int(e.amount) > 0: Sfx.buzz(60 if e.kind == "hp" else 25)
			"heal":
				floaters.append({"pos": Vector2(e.pos), "text": "+%d" % e.amount, "color": Color("6bff6b"), "t": 0.0}); Sfx.play("drink")
			"die": Sfx.play("death" if e.uid == combat.hero.uid else "bones")
			"fall": Sfx.play("falling")
			"bolt":
				streaks.append({"from": Vector2(e.from), "to": Vector2(e.to), "t": 0.0, "magic": e.get("magic", true)})
				Sfx.play("zap" if e.get("magic", true) else "atk_spiritbow")
			"blast": blasts.append({"pos": Vector2(e.pos), "t": 0.0}); Sfx.play("hit_crush")
			"telegraph": Sfx.play("alert"); Sfx.buzz(20)
			"shock": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "shock": true})
			"burn": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "fire": true}); Sfx.play("burning")
			"move":
				if e.get("blink", false): disp[e.uid] = Vector2(e.to)  # teleports snap, no slide
				elif e.uid == combat.hero.uid: Sfx.play("step", 1.1)
			"trap": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "trap": true}); Sfx.buzz(80)
			"reveal": floaters.append({"pos": Vector2(e.pos), "text": "!", "color": Color("ffd27a"), "t": 0.0})
			"search": rings.append({"pos": Vector2(e.pos), "r": float(e.r), "t": 0.0})
			"sfx": Sfx.play(e.name)
			"attack":
				for u in combat.units:
					if u.uid == e.uid: lunge[e.uid] = {"dir": (Vector2(e.to) - Vector2(u.pos)).normalized(), "t": 0.0}
				Sfx.play("hit_slash", 1.0)

func _process(d: float) -> void:
	anim_t += d
	if combat:
		for u in combat.units:
			var target := Vector2(u.pos)
			var cur: Vector2 = disp.get(u.uid, target)
			disp[u.uid] = cur.move_toward(target, d / MOVE_TIME * maxf(1.0, cur.distance_to(target)))
	for k in flash.keys():
		flash[k] -= d
		if flash[k] <= 0: flash.erase(k)
	for k in lunge.keys():
		lunge[k].t += d
		if lunge[k].t > 0.16: lunge.erase(k)
	for f in floaters: f.t += d
	floaters = floaters.filter(func(f): return f.t < 0.9)
	for s in streaks: s.t += d
	streaks = streaks.filter(func(s): return s.t < 0.25)
	for b in blasts: b.t += d
	blasts = blasts.filter(func(b): return b.t < 0.35)
	for r in rings: r.t += d
	rings = rings.filter(func(r): return r.t < 0.5)
	queue_redraw()

func cell_size() -> float:
	var raw := floorf(minf(size.x, size.y) / Combat.SIZE)
	if raw >= 16.0: return floorf(raw / 16.0) * 16.0
	return raw

func origin() -> Vector2:
	var cs := cell_size() * Combat.SIZE
	return ((size - Vector2(cs, cs)) / 2.0).floor()

func cell_rect(p: Vector2) -> Rect2:
	var cs := cell_size()
	return Rect2((origin() + p * cs).floor(), Vector2(cs, cs))

func _draw() -> void:
	if combat == null: return
	var cs := cell_size()
	for y in Combat.SIZE:
		for x in Combat.SIZE:
			var t: int = combat.terrain[y][x]
			var r := cell_rect(Vector2(x, y))
			if t == Combat.T.GRASS or t == Combat.T.DOOR: _tile(r, 0)
			_tile(r, TILE_IDX[t])
			if t == Combat.T.CHASM: draw_rect(r, Color(0, 0, 0, 0.6))
			if t == Combat.T.WATER: draw_rect(r, Color(0.25, 0.45, 0.8, 0.45 + 0.05 * sin(anim_t * 2.0 + x + y)))
	# revealed traps (SPD sprite); hidden ones are drawn as plain floor
	for k in combat.traps:
		if not combat.traps[k].hidden:
			var idx := int(DB.traps[combat.traps[k].id].sprite)
			draw_texture_rect_region(features, cell_rect(Vector2(k)), Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
	# reachable / targetable highlights
	var hp: Vector2i = combat.hero.pos
	if not combat.over:
		for d in Combat.DIRS:
			var n: Vector2i = hp + d
			var u = combat.unit_at(n)
			if u != null and u != combat.hero:
				draw_rect(cell_rect(Vector2(n)).grow(-2), Color(1, 0.8, 0.3, 0.7) if mode == "shove" else Color(1, 0.4, 0.3, 0.6), false, 3.0)
			elif combat.passable(n) and u == null:
				var warn := combat.visible_trap(n)
				draw_rect(cell_rect(Vector2(n)).grow(-2), Color(1, 0.6, 0.2, 0.5) if warn else Color(1, 1, 1, 0.16), false, 2.0)
		if mode == "bolt" or not combat.hero.bolt.is_empty():
			for e in combat.enemies():
				if combat.can_bolt(e.pos) and Combat.cheb(e.pos, hp) > 1:
					draw_rect(cell_rect(Vector2(e.pos)).grow(-4), Color(0.75, 0.55, 1.0, 0.7), false, 2.0)
	for dz in combat.danger:
		var pulse := 0.3 + 0.2 * sin(anim_t * 9.0)
		draw_rect(cell_rect(Vector2(dz.pos)), Color(1, 0, 0, pulse))
		draw_rect(cell_rect(Vector2(dz.pos)).grow(-1), Color(1, 0.2, 0.2, 0.9), false, 2.0)
	if hint_cell.x >= 0:
		draw_rect(cell_rect(Vector2(hint_cell)).grow(-3), Color(0.4, 1, 0.5, 0.5 + 0.3 * sin(anim_t * 6)), false, 4.0)
	# units
	var scale := floorf(cs / 16.0) if cs >= 16.0 else cs / 16.0
	for u in combat.units:
		if u.hp <= 0: continue
		var p: Vector2 = disp.get(u.uid, Vector2(u.pos))
		if lunge.has(u.uid): p += lunge[u.uid].dir * 0.3 * sin(lunge[u.uid].t / 0.16 * PI)
		var frame := 0 if fmod(anim_t + u.uid * 0.37, 1.0) < 0.6 else 1
		var src := Rect2(frame * int(u.fw), 0, int(u.fw), int(u.fh))
		var sz := Vector2(u.fw, u.fh) * scale
		var r := cell_rect(p)
		var pos := (r.position + Vector2((cs - sz.x) / 2.0, cs - sz.y)).floor()
		var mod := Color(1, 1, 1)
		if flash.has(u.uid): mod = Color(4, 4, 4)
		if u.get("charging", false): mod = Color(1.6, 0.6, 0.6)
		if u.has("hero") and combat.hidden(): mod.a = 0.45
		draw_texture_rect_region(sprite(u.sprite), Rect2(pos, sz), src, mod)
		var bw := (cs - 4) * clampf(float(u.hp) / float(u.ht), 0, 1)
		var bh := maxf(3, floorf(cs * 0.06))
		draw_rect(Rect2(r.position + Vector2(2, 1), Vector2(cs - 4, bh)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position + Vector2(2, 1), Vector2(bw, bh)), Color("5fd35f") if u.has("hero") else Color("e04040"))
		if u.has("hero") and int(u.barrier) > 0:
			var bb := (cs - 4) * clampf(float(u.barrier) / maxf(1.0, float(u.barrier_max)), 0, 1)
			draw_rect(Rect2(r.position + Vector2(2, 1 + bh), Vector2(bb, bh)), Color("7fd3ff"))
	for s in streaks:
		var a := cell_rect(s.from).get_center(); var b := cell_rect(s.to).get_center()
		var sc := Color(0.8, 0.6, 1.0) if s.get("magic", true) else Color(0.9, 0.9, 0.7)
		draw_line(a, a.lerp(b, clampf(s.t / 0.12, 0, 1)), sc, maxf(3, cs * 0.08))
	for b in blasts:
		var c := Color(1, 0.6, 0.1, 1.0 - b.t / 0.35) if b.get("fire", false) else Color(1, 0.3, 0.2, 1.0 - b.t / 0.35)
		if b.get("trap", false): c = Color(1, 0.9, 0.3, 1.0 - b.t / 0.35)
		if b.get("shock", false): c = Color(0.7, 0.9, 1.0, 1.0 - b.t / 0.35)
		draw_rect(cell_rect(b.pos).grow(b.t * cs * 0.3), c, false, 3.0)
	for r in rings:
		var c := cell_rect(r.pos).get_center()
		draw_arc(c, (0.5 + r.r) * cs * clampf(r.t / 0.4, 0, 1), 0, TAU, 48, Color(1, 0.85, 0.4, 1.0 - r.t / 0.5), 3.0)
	var font := get_theme_default_font()
	var fs := int(maxf(14, cs * 0.38))
	for f in floaters:
		var r := cell_rect(f.pos)
		var p := r.get_center() + Vector2(-cs * 0.2, -cs * 0.2 - f.t * cs * 0.8)
		var col: Color = f.color; col.a = 1.0 - maxf(0, f.t - 0.5) / 0.4
		draw_string_outline(font, p, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 6), Color(0, 0, 0, col.a))
		draw_string(font, p, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _tile(r: Rect2, idx: int) -> void:
	draw_texture_rect_region(tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var c: Vector2 = ((e.position - origin()) / cell_size()).floor()
		var cell := Vector2i(c)
		if cell.x >= 0 and cell.y >= 0 and cell.x < Combat.SIZE and cell.y < Combat.SIZE:
			tapped.emit(cell)
		accept_event()
