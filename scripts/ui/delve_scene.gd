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
## SPD DungeonTileSheet floor features (DECISIONS #179): exit stairs, tall grass (raised overlay), grass.
const EXIT := 17
## SPD raised high grass: base tile in its cell, overhang in the cell above (DungeonTileSheet RAISED_HIGH_GRASS(_ALT)
## 122/125, HIGH_GRASS_OVERHANG(_ALT) 234/237).
const HIGH_GRASS := [122, 125]; const HIGH_GRASS_TOP := [234, 237]
const SPRITE_K := 1.5            # characters ~1.5x the tile scale (rounded to a whole multiple: pixel-perfect)
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
var _ev_key := ""                # identity of the encounter on screen, to replay its arrival
var _ev_t := 9.0                 # seconds since that encounter appeared
var _floor_seen := -1
var _fade := 0.0                 # black fade-in after descending a floor

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
	var ev := encounter()
	var key := "" if ev.is_empty() else "%s|%s|%s" % [ev.kind, str(ev.get("mobs", "")), str(r.get("floor", 1))]
	if key != _ev_key:
		if key == "" and _ev_key != "": _fade = maxf(_fade, 0.45)   # leaving a room: a short dip to dark
		_ev_key = key; _ev_t = 0.0
	_ev_t += delta
	var fl := int(r.get("floor", 1))
	if _floor_seen >= 0 and fl > _floor_seen: _fade = 1.0
	_floor_seen = fl
	_fade = maxf(0.0, _fade - delta * 1.6)
	for p in pops: p.age += delta
	pops = pops.filter(func(p): return p.age < 1.1)
	glow = maxf(0.0, glow - delta * 2.5)
	queue_redraw()   # 60 fps: the draw is now ~40 quads (DECISIONS #99)

## The wall face at the encounter (DECISIONS #179): a door card shows its two doors, closed or locked if that door
## needs a key; a special room shows its closed door with the room's icon above it. Doors are always shut unless
## something stands in them, matching the combat rule, so no open or crystal doors pass by.
func _encounter_wall(ev: Dictionary, dx: int, idx: int) -> int:
	match ev.kind:
		"door":
			var d: Dictionary = ev.get("door", {})
			if dx == 0: return DOOR_LOCKED if d.get("a", {}).has("cost") else DOOR_CLOSED
			if dx == 2: return DOOR_LOCKED if d.get("b", {}).has("cost") else DOOR_CLOSED
			if dx == 1: return 80
		"special": if dx == 0: return DOOR_CLOSED
	return idx

## Whole-pixel scale: tiles are 16 px at an integer multiple.
func pk() -> float:
	return maxf(1.0, floorf(size.y / ROWS / 16.0))

func cell() -> float:
	return 16.0 * pk()

## Sprite scale: ~1.5x the tile scale, rounded to a whole number so sprite pixels stay square.
func sk(boss := false) -> float:
	return maxf(1.0, roundf(pk() * SPRITE_K * (1.35 if boss else 1.0)))

func _h(x: int, salt: int) -> int:
	return absi(hash(Vector3i(x, salt, int(_run().get("floor", 1)))))

func _frame(anim_owner: String, anim: String, off := 0.0) -> int:
	var a: Dictionary = _anims.get(anim_owner, {}).get(anim, _anims.get(anim_owner, {}).get("idle", {"fps": 1, "frames": [0]}))
	var fl: Array = a.frames
	return int(fl[int((t + off) * float(a.fps)) % fl.size()])

## Torch light at a point, as a modulate colour: matches SceneFX.darkness (clear inside 30% of the radius, full
## `_la` darkness at 95%). Sprites and grass are drawn after the darkness pass with this modulate, so they are lit
## like the floor once, never darkened twice (DECISIONS #179). `strength` < 1 keeps grass blades brighter.
var _lc := Vector2.ZERO; var _lr := 1.0; var _la := 0.0
func _lm(p: Vector2, strength := 1.0) -> Color:
	var d := clampf((p.distance_to(_lc) / _lr - 0.3) / 0.65, 0.0, 1.0)
	var v := 1.0 - _la * d * strength
	return Color(v, v, v)

func _sprite(spr: String, fw: int, fh: int, frame: int, row: int, feet: Vector2, k: float, flip := false) -> void:
	var tx := _t("res://assets/sprites/%s.png" % spr)
	var cols := maxi(1, tx.get_width() / fw)
	var src := Rect2((frame % cols) * fw, (frame / cols + row) * fh, fw, fh)
	var sz := Vector2(fw, fh) * k
	var pos := (feet - Vector2(sz.x / 2.0, sz.y)).floor()
	if flip: src = Rect2(src.position.x + fw, src.position.y, -fw, fh)
	draw_texture_rect_region(_t("res://assets/ui/shadow.png"), Rect2((Vector2(pos.x + sz.x * 0.15, feet.y - k * 2)).floor(), Vector2(sz.x * 0.7, k * 3).floor()), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.5))
	draw_texture_rect_region(tx, Rect2(pos, sz), src, _lm(feet - Vector2(0, sz.y * 0.5)))

## Tall grass clumps on the near floor row, seeded per column (never where an encounter stands).
func _grass_at(cx: int) -> bool:
	return _h(cx, 11) % 9 == 0 or (_h(cx - 1, 11) % 9 == 0 and _h(cx, 12) % 2 == 0)

func _draw() -> void:
	var r := _run()
	if r.is_empty(): return
	var k := pk(); var cs := cell()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.03))
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
	var busy_from := stop_col - 1; var busy_to := stop_col + 4
	if ev.is_empty(): busy_to = busy_from - 1
	var grass_cells := []
	for i in range(-int(hero_x / cs) - 2, cols):
		var cx := hero_col + i
		var x := floorf(ox + i * cs)
		var busy := cx >= busy_from and cx <= busy_to
		for row in ROWS:
			var rc := Rect2(x, y0 + row * cs, cs, cs)
			var idx := 0
			match row:
				0, 4: idx = 144
				1: idx = 80 if _h(cx, 1) % 7 else 96
				_: idx = 1 if _h(cx * 3 + row, 2) % 11 == 0 else 0
			if row == 1 and _h(cx, 3) % 23 == 0 and not busy: idx = DOOR_CLOSED   # side rooms pass by, shut
			if row == 3 and not busy and _grass_at(cx): idx = 0; grass_cells.append([rc, cx & 1])   # blades drawn after the light
			if row == 1 and not ev.is_empty(): idx = _encounter_wall(ev, cx - stop_col, idx)
			draw_texture_rect_region(tiles, rc, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
		# bones on the far floor row (seeded per column, kept clear of the encounter)
		if not busy and cx > hero_col + 1 and _h(cx, 5) % 17 == 0:
			var ir := UIKit.item_rect(DB.icon_index("BONES"))
			var isz := ir.size * k
			draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((Vector2(x, y0 + 2 * cs) + (Vector2(cs, cs) - isz) / 2.0).floor(), isz), ir, Color(1, 1, 1, 0.85))
	# lighting pass on the ground layer only; everything drawn after takes _lm() instead (no double darkening)
	var dk := Delve.darkness(r)
	var lit := float(r.get("torch", 0)) > 0 and not dk
	var rad := cs * (6.5 if lit else (2.6 if dk else 4.6)) * SceneFX.flicker(t)
	var hc := Vector2(hero_x + cs / 2.0, y0 + 3 * cs)
	_lc = hc; _lr = rad; _la = 0.78
	SceneFX.darkness(self, Rect2(Vector2.ZERO, size), hc, rad, 0.78)
	if lit: SceneFX.glow(self, hc, rad * 0.55, Color(1.0, 0.7, 0.35, 0.10))
	# SPD raised high grass: base tile (122/125) in its cell, overhang (234/237) in the cell above, behind the
	# characters; blades lit at half the floor's darkness so they read over the dark ground
	for g in grass_cells:
		var gr: Rect2 = g[0]; var gb: int = HIGH_GRASS[g[1]]; var gi: int = HIGH_GRASS_TOP[g[1]]
		var m := _lm(gr.get_center(), 0.5)
		draw_texture_rect_region(_grass_tex(tiles, gb), gr, Rect2(0, 0, 16, 16), m)
		draw_texture_rect_region(tiles, Rect2(gr.position - Vector2(0, cs), gr.size), Rect2((gi % 16) * 16, (gi / 16) * 16, 16, 16), m)
	var arrive := clampf(_ev_t / 0.45, 0.0, 1.0); var ease := 1.0 - pow(1.0 - arrive, 3.0)
	if not ev.is_empty():
		var ex := floorf(ox + (stop_col - hero_col) * cs)
		match ev.kind:
			"floor_done":   # the floor's exit: SPD down stairs on the floor
				draw_texture_rect_region(tiles, Rect2(ex, y0 + 2 * cs, cs, cs), Rect2((EXIT % 16) * 16, (EXIT / 16) * 16, 16, 16), _lm(Vector2(ex + cs / 2.0, y0 + 2.5 * cs)))
			"campfire":
				var fp := Vector2(ex + cs / 2.0, y0 + 3.4 * cs).floor()
				SceneFX.glow(self, fp - Vector2(0, 3 * k), cs * 2.2 * SceneFX.flicker(t), Color(1.0, 0.55, 0.2, 0.25))
				draw_texture_rect_region(tiles, Rect2(fp - Vector2(cs / 2.0, cs * 0.7), Vector2(cs, cs)), Rect2(3 * 16, 0, 16, 16), _lm(fp))
				SceneFX.fire(self, fp, k, t, 7.0)
	# encounter ahead: each foe on its own whole column, alternating floor rows, facing the hero; they run in on arrival
	if not ev.is_empty() and ev.kind == "combat":
		var ids: Array = ev.get("mobs", [])
		var boss: bool = ev.get("boss", false)
		for j in ids.size():
			var m: Dictionary = DB.mobs[ids[j]]
			var spr := String(m.sprite)
			var colx := floorf(ox + (stop_col - hero_col + j) * cs + cs / 2.0)
			var fy := y0 + (3.85 if j % 2 == 0 else 2.95) * cs
			var dx := (1.0 - ease) * cs * 3.0
			var anim := "run" if arrive < 1.0 else "idle"
			var fr := _frame(spr, anim, j * 0.37)
			# menace: every ~2.6 s one foe plays its SPD attack frames with a short lunge toward the hero
			var ph := fposmod(_ev_t - 0.6 - j * 0.9, 2.6 + ids.size() * 0.4)
			var lunge := 0.0
			if arrive >= 1.0 and ph < 0.3:
				var a: Dictionary = _anims.get(spr, {}).get("attack", {})
				if not a.is_empty():
					var afl: Array = a.frames; fr = int(afl[mini(int(ph * float(a.fps)), afl.size() - 1)])
				lunge = -sin(ph / 0.3 * PI) * cs * 0.25
			_sprite(spr, int(m.fw), int(m.fh), fr, 0, Vector2(colx + dx + lunge, fy).floor(), sk(boss), true)
	if not ev.is_empty() and ev.kind == "special" and ev.get("special", {}).has("icon"):
		var ir := UIKit.item_rect(DB.icon_index(ev.special.icon)); var isz := ir.size * k
		var dc := Vector2(floorf(ox + (stop_col - hero_col) * cs + cs / 2.0), y0 + 0.5 * cs + roundf(sin(t * 3.0)) * k)
		SceneFX.glow(self, dc, cs * 0.8, Color(1, 0.95, 0.6, 0.18))
		draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((dc - isz / 2.0).floor(), isz), ir)
	# hero
	if _hs_t <= 0.0 or _hs.is_empty(): _hs = GameState.hero_stats(r.hero); _hs_t = 0.5
	var hs: Dictionary = _hs
	var hf := _frame(String(hs.sprite), "run") if moving else _frame(String(hs.sprite), "idle")
	var hfeet := Vector2(hero_x + cs / 2.0, y0 + 3.8 * cs).floor()
	_sprite(hs.sprite, int(hs.fw), int(hs.fh), hf, int(hs.row), hfeet, sk())
	# parallax dust: far layer drifts at 0.3x the scroll, near at 1.4x
	for layer in [[0.3, 0.25, 9], [1.4, 0.5, 6]]:
		for n in int(layer[2]):
			var px := fposmod(n * 137.0 * k - scroll * cs * float(layer[0]) + sin(t + n) * k * 3, size.x)
			var py := fposmod(n * 59.0 * k + t * k * 2.0 * (n % 3 + 1), size.y)
			draw_rect(Rect2(Vector2(px, py).floor(), Vector2(k, k)), Color(1, 0.9, 0.7, float(layer[1])))
	# pickup pops: rising icon, "+N", and an SPD-style spark burst
	if glow > 0.0: SceneFX.glow(self, hc - Vector2(0, cs * 0.6), cs * 1.2, Color(1.0, 0.9, 0.4, 0.3 * glow))
	var font := get_theme_default_font(); var fs := int(UIKit.font_size * 0.8)
	for i in pops.size():
		var p: Dictionary = pops[i]
		var ir := UIKit.item_rect(int(p.get("idx", DB.icon_index(String(p.get("id", "GOLD"))))))
		var isz := ir.size * k
		var a := clampf(1.0 - p.age / 1.1, 0.0, 1.0)
		var c := Vector2(hc.x + (i % 3 - 1) * cs * 0.5, hc.y - cs * 1.4 - p.age * cs * 1.2)
		SceneFX.sparkle(self, Vector2(hc.x + (i % 3 - 1) * cs * 0.5, hc.y - cs * 1.2), k, p.age / 0.5)
		draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((c - isz / 2.0).floor(), isz), ir, Color(1, 1, 1, a))
		var tp := (c + Vector2(isz.x / 2.0 + k, fs * 0.35)).floor()
		draw_string_outline(font, tp, "+%d" % int(p.n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(k)), Color(0, 0, 0, a))
		draw_string(font, tp, "+%d" % int(p.n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.5, a))
	# descending: the new floor fades in from black
	if _fade > 0.0: draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))
	# border
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, maxf(2.0, k))

## The high-grass base tile with its baked stone floor keyed out (flood from the border over floor tile 0/1
## colours), so the darkened ground shows through between the blades. Cached per biome sheet.
var _grass_cache := {}
func _grass_tex(tiles: Texture2D, idx: int) -> Texture2D:
	var key := "%s|%d" % [tiles.resource_path, idx]
	if _grass_cache.has(key): return _grass_cache[key]
	var src: Image = tiles.get_image()
	if src.is_compressed(): src.decompress()
	var img := src.get_region(Rect2i((idx % 16) * 16, (idx / 16) * 16, 16, 16)); img.convert(Image.FORMAT_RGBA8)
	var cols := {}
	for b in [0, 1]:
		for y in 16:
			for x in 16: cols[src.get_pixel((b % 16) * 16 + x, (b / 16) * 16 + y).to_html()] = true
	var st := []
	for i in 16: st.append_array([Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)])
	var seen := {}
	while not st.is_empty():
		var p: Vector2i = st.pop_back()
		if seen.has(p) or p.x < 0 or p.y < 0 or p.x > 15 or p.y > 15: continue
		seen[p] = true
		var c := img.get_pixel(p.x, p.y)
		if c.a > 0.5 and cols.has(c.to_html()):
			img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
			st.append_array([p + Vector2i.RIGHT, p + Vector2i.LEFT, p + Vector2i.DOWN, p + Vector2i.UP])
	var tx := ImageTexture.create_from_image(img)
	_grass_cache[key] = tx
	return tx
