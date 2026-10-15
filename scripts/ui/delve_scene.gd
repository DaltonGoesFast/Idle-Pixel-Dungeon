class_name DelveScene
extends Control
## Animated corridor shown above the Delve Bar (DECISIONS #90). Top-down SPD tiles of the current biome scroll
## right-to-left as floor progress rises; the hero plays its SPD run animation in its armor-tier row, a torch
## light pool follows it, dust motes drift at two parallax speeds, and wall doors, bones, grass and idle biome
## mobs pass by (seeded per tile column, so they are stable). Gold/dew gathered pops above the hero. When an
## encounter card opens the scroll stops and the door or enemies appear ahead.

const TILES_PER_FLOOR := 160.0
const ROWS := 5                  # wall top, wall face, floor, floor, wall top
## SPD DungeonTileSheet raised doors: closed, open, locked, crystal.
const DOOR_CLOSED := 112; const DOOR_OPEN := 113; const DOOR_LOCKED := 114; const DOOR_CRYSTAL := 115
const DOOR_STATES := [DOOR_CLOSED, DOOR_CLOSED, DOOR_OPEN, DOOR_LOCKED, DOOR_CRYSTAL]
const PROPS := ["BONES", "BONES", "SOMETHING", "ORE", "SEED_SUNGRASS", "SEED_ROTBERRY", "SEED_FIREBLOOM", "CHEST", "SCROLL_HOLDER"]
const SPRITE_K := 1.5            # characters drawn 1.5x the tile scale so they read on the inner screen
var host                         # DelveScreen (for `pending`, `running`)
var scroll := 0.0                # in tiles
var target := 0.0
var t := 0.0
var moving := false
var pops := []                   # [{id, age}]
var _last := {}
var _anims := {}
var _tex := {}
var _redraw_t := 0.0
var glow := 0.0
var _snd_t := {}

func _pickup(idx: int, n: int, snd: String) -> void:
	pops.append({"idx": idx, "age": 0.0, "n": n})
	if pops.size() > 6: pops.pop_front()
	glow = 1.0
	var now := Time.get_ticks_msec()
	if now - int(_snd_t.get(snd, 0)) > 180: _snd_t[snd] = now; Sfx.play(snd)   # no machine-gun clicks at x3
var _hs := {}
var _hs_t := 0.0
var _light: GradientTexture2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true; mouse_filter = MOUSE_FILTER_IGNORE
	_anims = JSON.parse_string(FileAccess.get_file_as_string("res://data/anims.json"))

func _t(n: String) -> Texture2D:
	if not _tex.has(n): _tex[n] = load(n)
	return _tex[n]

func _run() -> Dictionary: return GameState.run

func encounter() -> Dictionary:
	if host == null: return {}
	var p: Dictionary = host.pending
	return p if p.get("kind", "") in ["combat", "door", "special", "campfire", "floor_done"] else {}

func _process(delta: float) -> void:
	if not is_visible_in_tree() or _run().is_empty(): return
	t += delta; _hs_t -= delta
	var r := _run()
	target = (float(r.get("floor", 1)) - 1.0) * TILES_PER_FLOOR + float(r.get("progress", 0.0)) / 100.0 * TILES_PER_FLOOR
	# critically-damped chase: smooth at any Delve speed (x3 used to outrun a fixed cap and snap) (DECISIONS #99)
	if scroll == 0.0 or absf(target - scroll) > 80.0 or target < scroll - 1.0: scroll = target - 0.001
	var gap := target - scroll
	moving = gap > 0.02 and encounter().is_empty()
	if moving: scroll += gap * (1.0 - exp(-6.0 * delta))
	# pickups: anything gold/dew grew since last frame pops above the hero
	var pack: Dictionary = r.get("pack", {})
	# pickup feedback (DECISIONS #101): SPD gold/dewdrop/item sounds, a rising icon + "+N", a brief glow
	for id in pack:
		var n := int(pack.get(id, 0))
		if _last.has(id) and n > int(_last[id]): _pickup(DB.icon_index(id), n - int(_last[id]), "gold" if id == "gold" else ("dewdrop" if id == "dew" else "item"))
		_last[id] = n
	var ng: int = r.get("pack_gear", []).size()
	if _last.has("_gear") and ng > int(_last._gear): _pickup(DB.icon_index(r.pack_gear[-1].id), 1, "item")
	_last._gear = ng
	for p in pops: p.age += delta
	pops = pops.filter(func(p): return p.age < 1.1)
	glow = maxf(0.0, glow - delta * 2.5)
	queue_redraw()   # 60 fps: the draw is now ~40 quads (DECISIONS #99)

## The wall face at the encounter: door cards show their two doors (locked if one needs a key), special rooms an
## open doorway, a cleared floor the crystal exit.
func _encounter_wall(ev: Dictionary, dx: int, idx: int) -> int:
	match ev.kind:
		"door":
			var d: Dictionary = ev.get("door", {})
			if dx == 0: return DOOR_LOCKED if d.get("a", {}).has("cost") else DOOR_CLOSED
			if dx == 2: return DOOR_LOCKED if d.get("b", {}).has("cost") else DOOR_CLOSED
		"special": if dx == 0: return DOOR_OPEN
		"floor_done": if dx == 0: return DOOR_CRYSTAL
	return idx

func cell() -> float:
	return floorf(size.y / ROWS)

func _h(x: int, salt: int) -> int:
	return absi(hash(Vector3i(x, salt, int(_run().get("floor", 1)))))

func _frame(anim_owner: String, anim: String) -> int:
	var a: Dictionary = _anims.get(anim_owner, {}).get(anim, {"fps": 1, "frames": [0]})
	var fl: Array = a.frames
	return int(fl[int(t * float(a.fps)) % fl.size()])

func _sprite(spr: String, fw: int, fh: int, frame: int, row: int, feet: Vector2, k: float, flip := false) -> void:
	var tx := _t("res://assets/sprites/%s.png" % spr)
	var cols := maxi(1, tx.get_width() / fw)
	var src := Rect2((frame % cols) * fw, (frame / cols + row) * fh, fw, fh)
	var sz := Vector2(fw, fh) * k
	var pos := (feet - Vector2(sz.x / 2.0, sz.y)).floor()
	if flip: src = Rect2(src.position.x + fw, src.position.y, -fw, fh)
	draw_texture_rect_region(_t("res://assets/ui/shadow.png"), Rect2(pos.x + sz.x * 0.15, feet.y - k * 2, sz.x * 0.7, k * 3), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.5))
	draw_texture_rect_region(tx, Rect2(pos, sz), src)

func _draw() -> void:
	var r := _run()
	if r.is_empty(): return
	var cs := cell(); var k := cs / 16.0
	var y0 := floorf((size.y - cs * ROWS) / 2.0)
	var biome: Dictionary = DB.biomes[r.biome]
	var tiles := _t("res://assets/tiles/%s.png" % biome.tile)
	var cols := int(ceil(size.x / cs)) + 2
	var base := int(floor(scroll)); var frac := scroll - base
	var hero_x := floorf(size.x * 0.32)
	var ox := hero_x - frac * cs
	var hero_col := base
	var ev := encounter()
	var stop_col := hero_col + 2         # where an encounter's door/enemies stand
	for i in range(-int(hero_x / cs) - 2, cols):
		var cx := hero_col + i
		var x := floorf(ox + i * cs)
		for row in ROWS:
			var rc := Rect2(x, y0 + row * cs, cs + 1, cs + 1)
			var idx := 0
			match row:
				0, 4: idx = 144
				1: idx = 80 if _h(cx, 1) % 7 else 96
				_: idx = 2 if _h(cx * 3 + row, 2) % 9 == 0 else (1 if _h(cx, row) % 5 == 0 else 0)
			if row == 1 and _h(cx, 3) % 23 == 0: idx = DOOR_STATES[_h(cx, 8) % DOOR_STATES.size()]   # side doors pass by
			if row == 2 and _h(cx, 9) % 31 == 0: idx = 3                                              # embers
			if row == 1 and not ev.is_empty(): idx = _encounter_wall(ev, cx - stop_col, idx)
			draw_texture_rect_region(tiles, rc, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
		# props on the far floor row (seeded per column)
		if cx > hero_col + 1 and _h(cx, 5) % 13 == 0:
			var pid: String = PROPS[_h(cx, 10) % PROPS.size()]
			var ir := UIKit.item_rect(DB.icon_index(pid))
			var isz := ir.size * k
			draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((Vector2(x, y0 + 2 * cs) + (Vector2(cs, cs) - isz) / 2.0).floor(), isz), ir, Color(1, 1, 1, 0.85))
		# ambient biome mob idling by the wall
		if cx > hero_col + 2 and _h(cx, 6) % 41 == 0:
			var sets: Array = biome.get("encounter_sets", [])
			if not sets.is_empty():
				var mid: String = sets[_h(cx, 7) % sets.size()].mobs[0]
				var m: Dictionary = DB.mobs[mid]
				_sprite(m.sprite, int(m.fw), int(m.fh), _frame(mid, "idle"), 0, Vector2(x + cs / 2.0, y0 + 3 * cs - k * 2), k * SPRITE_K, true)
	# encounter ahead
	if not ev.is_empty() and ev.kind == "combat":
		var ids: Array = ev.get("mobs", [])
		for j in ids.size():
			var m: Dictionary = DB.mobs[ids[j]]
			var mk := k * SPRITE_K * (1.4 if ev.get("boss", false) else 1.0)
			_sprite(m.sprite, int(m.fw), int(m.fh), _frame(ids[j], "idle"), 0, Vector2(floorf(hero_x + (2 + j * 1.1) * cs + cs / 2.0), y0 + (3.6 + (j % 2) * 0.35) * cs), mk, true)
	if not ev.is_empty() and ev.kind == "special" and ev.get("special", {}).has("icon"):
		var ir := UIKit.item_rect(DB.icon_index(ev.special.icon)); var isz := ir.size * k
		var dc := Vector2(hero_x + 2.5 * cs, y0 + 1.5 * cs + sin(t * 3.0) * k)
		draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((dc - isz / 2.0).floor(), isz), ir)
	# hero
	if _hs_t <= 0.0 or _hs.is_empty(): _hs = GameState.hero_stats(r.hero); _hs_t = 0.5
	var hs: Dictionary = _hs
	var hf := _frame(String(hs.sprite), "run") if moving else _frame(String(hs.sprite), "idle")
	_sprite(hs.sprite, int(hs.fw), int(hs.fh), hf, int(hs.row), Vector2(hero_x + cs / 2.0, y0 + 3.8 * cs), k * SPRITE_K)
	# torchlight: darkness falls off with distance from the hero (bigger pool with a lit torch)
	var lit := float(r.get("torch", 0)) > 0 and not Delve.darkness(r)
	var rad := cs * (5.5 if lit else (2.0 if Delve.darkness(r) else 3.8))
	var hc := Vector2(hero_x + cs / 2.0, y0 + 3 * cs)
	# one radial-gradient quad for the light pool + 4 solid rects around it (was ~2400 rects per frame)
	if _light == null:
		var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0.02, 0.01, 0.03, 0.0), Color(0.02, 0.01, 0.03, 0.0), Color(0.02, 0.01, 0.03, 0.6)])
		_light = GradientTexture2D.new(); _light.gradient = g; _light.fill = GradientTexture2D.FILL_RADIAL
		_light.fill_from = Vector2(0.5, 0.5); _light.fill_to = Vector2(1.0, 0.5); _light.width = 128; _light.height = 128
	var flick := 1.0 + 0.04 * sin(t * 9.0) + 0.03 * sin(t * 23.0)
	var lr := Rect2(hc - Vector2.ONE * rad * flick, Vector2.ONE * rad * flick * 2.0)
	var dark := Color(0.02, 0.01, 0.03, 0.6)
	draw_texture_rect(_light, lr, false)
	draw_rect(Rect2(0, 0, size.x, maxf(0.0, lr.position.y)), dark)
	draw_rect(Rect2(0, lr.end.y, size.x, maxf(0.0, size.y - lr.end.y)), dark)
	draw_rect(Rect2(0, lr.position.y, maxf(0.0, lr.position.x), lr.size.y), dark)
	draw_rect(Rect2(lr.end.x, lr.position.y, maxf(0.0, size.x - lr.end.x), lr.size.y), dark)
	if lit: draw_circle(hc, rad * 0.35, Color(1.0, 0.75, 0.35, 0.06))
	# parallax dust: far layer drifts at 0.3x the scroll, near at 1.4x
	for layer in [[0.3, 0.25, 9], [1.4, 0.5, 6]]:
		for n in int(layer[2]):
			var px := fposmod(n * 137.0 * k - scroll * cs * float(layer[0]) + sin(t + n) * k * 3, size.x)
			var py := fposmod(n * 59.0 * k + t * k * 2.0 * (n % 3 + 1), size.y)
			draw_rect(Rect2(Vector2(px, py).floor(), Vector2(k, k)), Color(1, 0.9, 0.7, float(layer[1])))
	# pickup pops
	if glow > 0.0: draw_circle(hc - Vector2(0, cs * 0.6), cs * 0.9, Color(1.0, 0.9, 0.4, 0.18 * glow))
	var font := get_theme_default_font(); var fs := int(UIKit.font_size * 0.8)
	for i in pops.size():
		var p: Dictionary = pops[i]
		var ir := UIKit.item_rect(int(p.get("idx", DB.icon_index(String(p.get("id", "GOLD"))))))
		var isz := ir.size * k
		var a := clampf(1.0 - p.age / 1.1, 0.0, 1.0)
		var c := Vector2(hc.x + (i % 3 - 1) * cs * 0.5, hc.y - cs * 1.4 - p.age * cs * 1.2)
		draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((c - isz / 2.0).floor(), isz), ir, Color(1, 1, 1, a))
		var tp := (c + Vector2(isz.x / 2.0 + k, fs * 0.35)).floor()
		draw_string_outline(font, tp, "+%d" % int(p.n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(k)), Color(0, 0, 0, a))
		draw_string(font, tp, "+%d" % int(p.n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.5, a))
	# border
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, maxf(2.0, k))
