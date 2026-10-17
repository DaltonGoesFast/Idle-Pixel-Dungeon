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
## Biome props along the far wall (DECISIONS #181), SPD raised tile + overhang drawn on the wall above:
## RAISED_REGION_DECO 130 / REGION_DECO_OVERHANG 242 (sewers barrel, prison cage, city plinth, halls tombstone)
## and RAISED_STATUE 128 / STATUE_OVERHANG 240. Caves' region deco is a wall chunk, so caves use the statue.
const REGION_DECO := {"sewers": [[130, 242]], "prison": [[130, 242], [128, 240]], "caves": [[128, 240]],
	"city": [[130, 242], [128, 240]], "halls": [[130, 242], [128, 240]]}
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
var _last_combat := {}            # the combat on screen (ids, boss, world column), for its death scene
var _vis_left := 0                # leftmost visible world column (set each draw)
var _dying := {}                  # foes playing their SPD die frames after a won fight; age in seconds
var hit_flash := 0.0              # hero white flash when a foe's lunge lands (0..1)
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
	hit_flash = maxf(0.0, hit_flash - delta * 8.0)
	if not _dying.is_empty():
		_dying.age = float(_dying.age) + delta
		# kept until the fight's columns scroll off the left edge, so its cleared ground never pops props in view
		if float(_dying.age) > 2.5 and (int(_dying.col) + 6 < _vis_left or float(_dying.age) > 30.0): _dying = {}
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
		"special":
			if dx == 0: return DOOR_CLOSED
			for op in ROOM_SCENES.get(String(ev.special.get("id", "")), []):   # room tiles set into the wall (bookshelves)
				if String(op[0]) == "t" and float(op[3]) == 1.0 and int(op[2]) == dx: return int(op[1])
	return idx

## The fight on screen was won (DelveScreen._after_fight): its foes play their SPD die animation and fade.
func foes_fell() -> void:
	if _last_combat.is_empty(): return
	_dying = _last_combat.duplicate(); _dying.age = 0.0; _last_combat = {}

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

func _sprite(spr: String, fw: int, fh: int, frame: int, row: int, feet: Vector2, k: float, flip := false, shadow := true, flash := 0.0, alpha := 1.0) -> void:
	var tx := _t("res://assets/sprites/%s.png" % spr)
	var cols := maxi(1, tx.get_width() / fw)
	var src := Rect2((frame % cols) * fw, (frame / cols + row) * fh, fw, fh)
	var sz := Vector2(fw, fh) * k
	var pos := (feet - Vector2(sz.x / 2.0, sz.y)).floor()
	if shadow: draw_texture_rect_region(_t("res://assets/ui/shadow.png"), Rect2((Vector2(pos.x + sz.x * 0.15, feet.y - k * 2)).floor(), Vector2(sz.x * 0.7, k * 3).floor()), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.5 * alpha))
	var lm := _lm(feet - Vector2(0, sz.y * 0.5)); lm.a = alpha
	# mirror through a negative destination width: a negative source width dropped some frames (e.g. gnoll die 10)
	var dst := Rect2(pos.x + sz.x, pos.y, -sz.x, sz.y) if flip else Rect2(pos, sz)
	draw_texture_rect_region(tx, dst, src, lm)
	if flash > 0.0:   # white flash: the same frame again, overbright (modulate > 1 saturates to white), fading
		var f := 1.0 + 4.0 * flash
		draw_texture_rect_region(tx, dst, src, Color(f, f, f, flash * alpha))

## Tall grass clumps on the near floor row, seeded per column (never where an encounter stands).
## Corridor puddles (DECISIONS #182): at most one per 11-column block, 2-3 columns wide on one or both floor
## rows, a corner dropped on the big ones; never under a prop. Drawn as SPD stitched water (see _water_cell).
func _puddle(cx: int, row: int) -> bool:
	if row < 2 or row > 3: return false
	var b := floori(cx / 11.0)
	if _h(b, 31) % 5 >= 3: return false
	var s0 := b * 11 + 2 + _h(b, 32) % 5; var w := 2 + _h(b, 33) % 2
	if cx < s0 or cx >= s0 + w: return false
	var v := _h(b, 34) % 3
	if (v == 0 and row == 2) or (v == 2 and row == 3): return false
	if v == 1 and w == 3:   # drop one corner so the big ones are not rectangles
		var cn := _h(b, 35) % 4
		if cx == s0 + (0 if cn % 2 == 0 else w - 1) and row == (2 if cn < 2 else 3): return false
	if row == 2 and _deco_at(cx): return false
	return true

## Only a near-row puddle spills over the floor's edge into the void. A two-row pool already touches the wall, so it
## keeps a rim at the bottom; otherwise it read as a wall-to-edge channel (DECISIONS #182).
func _puddle_spills(cx: int) -> bool:
	return _puddle(cx, 3) and _h(floori(cx / 11.0), 34) % 3 == 0

func _grass_at(cx: int) -> bool:
	if _deco_at(cx - 1) or _deco_at(cx) or _deco_at(cx + 1): return false   # props keep their columns clear
	if _puddle(cx, 3): return false
	return _h(cx, 11) % 9 == 0 or (_h(cx - 1, 11) % 9 == 0 and _h(cx, 12) % 2 == 0)

## A biome prop on the far floor row: exactly one per 7-column block at a seeded spot, so every screen of
## corridor shows at least one (~15 columns are visible). Props win over grass, side doors and wall deco.
func _deco_at(cx: int) -> bool:
	var b := floori(cx / 7.0)
	return cx == b * 7 + _h(b, 21) % 7

## SPD raised wall (DungeonTileSheet getRaisedWallTile): RAISED_WALL 80 or its 50% alt 96; WALL_DECO uses
## RAISED_WALL_DECO 84 / alt 100 (sewers drain, prison torch, caves ore vein, city recess, halls stained glass).
func _wall_tile(cx: int) -> int:
	var alt := _h(cx, 1) % 2 == 1
	if _h(cx, 4) % 6 == 0 and not _side_door(cx) and not _deco_at(cx): return 100 if alt else 84
	return 96 if alt else 80

## DungeonTileSheet raised-wall stitching for the corridor's wall row (`wall` = column -> row-1 tile):
## a wall face gets +1 when a door is to its right and +2 when one is to its left (getRaisedWallTile).
const DOORS := [112, 113, 114, 115]
func _face_tile(wall: Dictionary, cx: int) -> int:
	var w: int = wall.get(cx, 80)
	if w in DOORS or w < 80 or w >= 112 or w in [92, 108]: return w
	return w + (1 if int(wall.get(cx + 1, 80)) in DOORS else 0) + (2 if int(wall.get(cx - 1, 80)) in DOORS else 0)

## The cell above the wall row is void, so SPD's walls layer draws the wall's top there (DungeonWallsTilemap):
## WALL_OVERHANG 192 (+1 open down-right, +2 open down-left, i.e. a door beside it), WALL_INTERNAL_WOODEN over a
## bookshelf, or over a door its lintel:
## DOOR_OVERHANG 224 (closed and locked), DOOR_OVERHANG_OPEN 225, DOOR_OVERHANG_CRYSTAL 226.
func _top_tile(wall: Dictionary, cx: int) -> int:
	var w: int = wall.get(cx, 80)
	var side := (1 if int(wall.get(cx + 1, 80)) in DOORS else 0) + (2 if int(wall.get(cx - 1, 80)) in DOORS else 0)
	match w:
		92, 108:   # SPD LibraryRoom: shelves stand against the room wall, so the cell above is that wall's top,
			# WALL_INTERNAL_WOODEN 176 (stitchInternalWallTile). Its left/right neighbours are wall tops too (every
			# wall, shelf or plain, is wall-stitchable), so +1 / +8 never apply. The +2 / +4 door-below posts are
			# left off as well: in SPD another wall row sits above, but here the row above is the void, so a post
			# at either end of the shelf run would poke up into it. WALL_OVERHANG_WOODEN is only for a floor cell
			# above a shelf, which the corridor never has.
			return 176
		112, 114: return 224
		113: return 225
		115: return 226
	return 192 + side   # WALL_OVERHANG (208+ is DOOR_SIDEWAYS_OVERHANG: door-frame caps, not a wall top)

const CHASM_FLOOR := 25; const CHASM_WATER := 28   # DungeonTileSheet CHASM + 1 / + 4

func _tile_at(tiles: Texture2D, rc: Rect2, idx: int) -> void:
	draw_texture_rect_region(tiles, rc, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

func _side_door(cx: int) -> bool:
	return _h(cx, 3) % 23 == 0 and not _deco_at(cx)

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
	var busy_from := stop_col - 1; var busy_to := stop_col + 5
	if ev.is_empty(): busy_to = busy_from - 1
	if ev.is_empty() and not _dying.is_empty():   # the won fight's ground stays clear (no barrel popping up under a corpse)
		busy_from = int(_dying.col) - 1; busy_to = int(_dying.col) + 5
	_vis_left = hero_col - int(ceil(hero_x / cs)) - 1
	var grass_cells := []
	var deco_cells := []
	var wet_cells := []
	var water := _t("res://assets/tiles/%s.png" % biome.get("water", "water0"))
	var wo := Vector2(fposmod(t * 3.0, 32.0), fposmod(t * 2.0, 32.0)).floor()   # SPD water drifts slowly
	var wall_fx := []   # SPD wall-deco cells that carry their region's visual (drip, torch, sparkle, smoke)
	# the wall row first (one extra column each side), so faces and tops can stitch against their neighbours
	var wall := {}
	for i in range(-int(hero_x / cs) - 3, cols + 1):
		var wcx := hero_col + i
		var wb := wcx >= busy_from and wcx <= busy_to
		var wi := _wall_tile(wcx)
		if _side_door(wcx) and not wb: wi = DOOR_CLOSED   # side rooms pass by, shut
		if not ev.is_empty(): wi = _encounter_wall(ev, wcx - stop_col, wi)
		wall[wcx] = wi
	for i in range(-int(hero_x / cs) - 2, cols):
		var cx := hero_col + i
		var x := floorf(ox + i * cs)
		var busy := cx >= busy_from and cx <= busy_to
		var near_grass := _grass_at(cx - 1) or _grass_at(cx) or _grass_at(cx + 1)
		for row in ROWS:
			var rc := Rect2(x, y0 + row * cs, cs, cs)
			var idx := 0
			match row:
				0:   # void above the wall: SPD draws the wall's top (WALL_OVERHANG) or the door's lintel here
					_tile_at(tiles, rc, _top_tile(wall, cx)); continue
				1: idx = _face_tile(wall, cx)
				4:   # the floor's edge dropping into the void below (SPD CHASM_FLOOR / CHASM_WATER)
					if not busy and _puddle_spills(cx):
						_water_cell(water, rc.position, k, wo + Vector2(cx * 16, 64), Color.WHITE); _tile_at(tiles, rc, CHASM_WATER)
					else: _tile_at(tiles, rc, CHASM_FLOOR)
					continue
				_: idx = 1 if _h(cx * 3 + row, 2) % 11 == 0 and not near_grass and not busy else 0   # no moss deco by the grass
			if row == 1 and idx in [84, 100] and not busy: wall_fx.append([rc, idx])
			if row == 2 and _deco_at(cx) and not busy: deco_cells.append([rc, cx])
			# grass clump: SPD short-grass floor (GRASS 2) under the keyed blades, drawn after the light
			if row == 3 and not busy and _grass_at(cx): idx = 2; grass_cells.append([rc, cx & 1, cx])
			if not busy and _puddle(cx, row):   # SPD water: scrolling texture, then the stitch tile over it
				var wet := func(c2: int, r2: int) -> bool: return r2 <= 1 or (r2 >= 4 and _puddle_spills(c2)) or (_puddle(c2, r2) and not (c2 >= busy_from and c2 <= busy_to))
				_water_cell(water, rc.position, k, wo + Vector2(cx * 16, row * 16), Color.WHITE)
				idx = WATER + (0 if wet.call(cx, row - 1) else 1) + (0 if wet.call(cx + 1, row) else 2) + (0 if wet.call(cx, row + 1) else 4) + (0 if wet.call(cx - 1, row) else 8)
				wet_cells.append(rc)
			draw_texture_rect_region(tiles, rc, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
		# bones on the far floor row (seeded per column, kept clear of the encounter)
		if not busy and cx > hero_col + 1 and _h(cx, 5) % 17 == 0 and not _grass_at(cx) and not _deco_at(cx) and not _puddle(cx, 2):   # never under a prop or in water
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
	var decos: Array = REGION_DECO.get(String(r.biome), REGION_DECO.sewers)
	for d in deco_cells:   # props: floor keyed out of the base, overhang on the wall, lit once like the sprites
		var dr: Rect2 = d[0]; var pr: Array = decos[_h(int(d[1]), 22) % decos.size()]
		var lm := _lm(dr.get_center())
		draw_texture_rect_region(_grass_tex(tiles, pr[0]), dr, Rect2(0, 0, 16, 16), lm)
		draw_texture_rect_region(tiles, Rect2(dr.position - Vector2(0, cs), dr.size), Rect2((pr[1] % 16) * 16, (pr[1] / 16) * 16, 16, 16), lm)
	for wr in wall_fx: SceneFX.wall_visual(self, t, String(r.biome), wr[0], int(wr[1]), k)
	if String(r.biome) == "halls":   # SPD HallsLevel.Stream: embers rise from the water and fall back
		for wc in wet_cells: SceneFX.halls_stream(self, t, wc, k)
	if String(r.biome) == "city":   # SPD CityLevel GreenFlame over the region-deco plinths
		for d in deco_cells:
			if decos[_h(int(d[1]), 22) % decos.size()][0] == 130: SceneFX.green_flame(self, t, (d[0] as Rect2).get_center() - Vector2(0, cs * 0.55), k, int(d[1]))
	for g in grass_cells:
		var gr: Rect2 = g[0]; var gb: int = HIGH_GRASS[g[1]]; var gi: int = HIGH_GRASS_TOP[g[1]]
		# one-pixel wind sway applied to base and overhang together; tips lit lighter so they stay crisp green
		var sw := roundf(sin(t * 1.6 + float(g[2]) * 0.9)) * k
		draw_texture_rect_region(_grass_tex(tiles, gb), Rect2(gr.position + Vector2(sw, 0), gr.size), Rect2(0, 0, 16, 16), _lm(gr.get_center(), 0.5))
		draw_texture_rect_region(tiles, Rect2(gr.position + Vector2(sw, -cs), gr.size), Rect2((gi % 16) * 16, (gi / 16) * 16, 16, 16), _lm(gr.get_center(), 0.3))
	var arrive := clampf(_ev_t / 0.45, 0.0, 1.0); var ease := 1.0 - pow(1.0 - arrive, 3.0)
	if not ev.is_empty():
		var ex := floorf(ox + (stop_col - hero_col) * cs)
		match ev.kind:
			"floor_done":   # the floor's exit: SPD down stairs on the floor
				draw_texture_rect_region(tiles, Rect2(ex, y0 + 2 * cs, cs, cs), Rect2((EXIT % 16) * 16, (EXIT / 16) * 16, 16, 16), _lm(Vector2(ex + cs / 2.0, y0 + 2.5 * cs)))
			"campfire":
				var fp := Vector2(ex + cs / 2.0, y0 + 3.4 * cs).floor()
				SceneFX.glow(self, fp - Vector2(0, 3 * k), cs * 2.2 * SceneFX.flicker(t), Color(1.0, 0.55, 0.2, 0.25))
				# SPD EMBERS with its baked floor keyed out: it sits off the tile grid, so the floor square would show (POLISH #56)
				draw_texture_rect_region(_grass_tex(tiles, 3), Rect2(fp - Vector2(cs / 2.0, cs * 0.7), Vector2(cs, cs)), Rect2(0, 0, 16, 16), _lm(fp))
				SceneFX.fire(self, fp, k, t, 7.0)
	# encounter ahead: each foe on its own whole column, alternating floor rows, facing the hero; they run in on arrival.
	# Characters are collected and drawn back to front by their feet (z-order), the hero included.
	var actors := []
	var h_atk := -1.0; var h_win := 0.3; var h_tgt := -1
	if not ev.is_empty() and ev.kind == "combat":
		var ids: Array = ev.get("mobs", [])
		var boss: bool = ev.get("boss", false)
		_last_combat = {"ids": ids, "boss": boss, "col": stop_col}
		var per := 2.6 + ids.size() * 0.4
		# the hero answers between the foes' blows: SPD attack frames, a lunge, and the struck foe flashes and recoils
		var ha: Dictionary = _anims.get(String(_hs.get("sprite", "")), {}).get("attack", {})
		if not ha.is_empty(): h_win = clampf(float(ha.frames.size()) / float(ha.fps), 0.2, 0.8)
		var hoff := 0.7 + ids.size() * 0.9
		if arrive >= 1.0 and ids.size() > 0:
			var hp := fposmod(_ev_t - hoff, per)
			if hp < h_win + 0.3: h_atk = hp; h_tgt = int(floorf((_ev_t - hoff) / per)) % ids.size()
		for j in ids.size():
			var m: Dictionary = DB.mobs[ids[j]]
			var spr := String(m.sprite)
			var colx := floorf(ox + (stop_col - hero_col + j) * cs + cs / 2.0)
			var fy := y0 + (3.85 if j % 2 == 0 else 2.95) * cs
			var dx := (1.0 - ease) * cs * 3.0
			var anim := "run" if arrive < 1.0 else "idle"
			var fr := _frame(spr, anim, j * 0.37)
			# menace: every ~2.6 s one foe plays its SPD attack frames with a short lunge toward the hero
			# the window is the SPD attack animation's own length (frames / fps), so every frame plays once
			var ph := fposmod(_ev_t - 0.6 - j * 0.9, per)
			var lunge := 0.0
			var a: Dictionary = _anims.get(spr, {}).get("attack", {})
			var win := clampf(float(a.frames.size()) / float(a.fps), 0.2, 0.8) if not a.is_empty() else 0.3
			if arrive >= 1.0 and ph < win:
				if not a.is_empty():
					var afl: Array = a.frames; fr = int(afl[mini(int(ph * float(a.fps)), afl.size() - 1)])
				lunge = -sin(ph / win * PI) * cs * 0.25
				# SPD CharSprite.flash(): the hero blinks white for a moment as the blow lands (lunge peak)
				if absf(ph - win * 0.5) < 0.06: hit_flash = 1.0
			var fflash := 0.0
			if j == h_tgt:   # struck by the hero: white flash and a small knockback, easing back
				var kt := h_atk - h_win * 0.5
				if kt >= 0.0 and kt < 0.25: lunge += sin(kt / 0.25 * PI) * cs * 0.12
				if kt >= 0.0 and kt < 0.12: fflash = 1.0 - kt / 0.12
			actors.append({"spr": spr, "fw": int(m.fw), "fh": int(m.fh), "fr": fr, "row": 0, "feet": Vector2(colx + dx + lunge, fy).floor(), "k": sk(boss), "flip": true, "flash": fflash, "alpha": 1.0})
	# foes that fell in the fight just won: SPD die frames where they stood, then a fade (DECISIONS #182)
	if not _dying.is_empty():
		var dids: Array = _dying.ids
		for j in dids.size():
			var m: Dictionary = DB.mobs[dids[j]]
			var spr := String(m.sprite)
			var da: Dictionary = _anims.get(spr, {}).get("die", {})
			var dur := float(da.frames.size()) / float(da.fps) if not da.is_empty() else 0.0
			var fr := int(da.frames[mini(int(float(_dying.age) * float(da.fps)), da.frames.size() - 1)]) if not da.is_empty() else _frame(spr, "idle")
			var al := 1.0 - clampf((float(_dying.age) - dur - 0.4) / 1.0, 0.0, 1.0)   # hold the corpse, then fade
			if al <= 0.0: continue
			var colx := floorf(ox + (int(_dying.col) - hero_col + j) * cs + cs / 2.0)
			actors.append({"spr": spr, "fw": int(m.fw), "fh": int(m.fh), "fr": fr, "row": 0, "feet": Vector2(colx, y0 + (3.85 if j % 2 == 0 else 2.95) * cs).floor(), "k": sk(bool(_dying.boss)), "flip": true, "flash": 0.0, "alpha": al})
	if not ev.is_empty() and ev.kind == "special": _room_scene(String(ev.special.get("id", "")), ox + (stop_col - hero_col) * cs, y0, cs, k, biome)
	if not ev.is_empty() and ev.kind == "special" and ev.get("special", {}).has("icon") and not ROOM_SCENES.has(String(ev.special.get("id", ""))):
		var ir := UIKit.item_rect(DB.icon_index(ev.special.icon)); var isz := ir.size * k
		var dc := Vector2(floorf(ox + (stop_col - hero_col) * cs + cs / 2.0), y0 + 0.5 * cs + roundf(sin(t * 3.0)) * k)
		SceneFX.glow(self, dc, cs * 0.8, Color(1, 0.95, 0.6, 0.18))
		draw_texture_rect_region(_t("res://assets/sprites/items.png"), Rect2((dc - isz / 2.0).floor(), isz), ir)
	# hero
	if _hs_t <= 0.0 or _hs.is_empty(): _hs = GameState.hero_stats(r.hero); _hs_t = 0.5
	var hs: Dictionary = _hs
	var hf := _frame(String(hs.sprite), "run") if moving else _frame(String(hs.sprite), "idle")
	var hlunge := 0.0
	if h_atk >= 0.0 and h_atk < h_win:
		var ha2: Dictionary = _anims.get(String(hs.sprite), {}).get("attack", {})
		if not ha2.is_empty(): hf = int(ha2.frames[mini(int(h_atk * float(ha2.fps)), ha2.frames.size() - 1)])
		hlunge = sin(h_atk / h_win * PI) * cs * 0.25
	var hfeet := Vector2(hero_x + cs / 2.0 + hlunge, y0 + 3.8 * cs).floor()
	actors.append({"spr": String(hs.sprite), "fw": int(hs.fw), "fh": int(hs.fh), "fr": hf, "row": int(hs.row), "feet": hfeet, "k": sk(), "flip": false, "flash": hit_flash, "alpha": 1.0})
	actors.sort_custom(func(p, q): return p.feet.y < q.feet.y)
	for ac in actors: _sprite(ac.spr, ac.fw, ac.fh, ac.fr, ac.row, ac.feet, ac.k, ac.flip, true, ac.flash, ac.alpha)
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

## Special-room scenes (DECISIONS #180): each room is built on the corridor floor ahead of its door from SPD's own
## tiles. Ops are [kind, what, dx, row]: "t" level tile (biome sheet), "f" terrain_features.png, "w" animated water,
## "speck" SPD Speck from effects/specks.png over the cell (0 HEALING, 3 QUESTION).
## "i" item sprite, "m" mob sprite (idle anim, facing the hero), "fire"/"spark" SPD-style particles (what = colour).
## "r" SPD raised terrain (base tile in the cell, overhang tile in the cell above; DungeonTileSheet RAISED_* and
## *_OVERHANG): "grass" 122/234, "grass2" 125/237, "pot" 120/232, "barricade" 121/233. "f" props are bottom-aligned in their cell.
## dx is in tiles from the door column, row 2 = far floor row, 3 = near floor row (fractions allowed for sprites).
const ROOM_SCENES := {
	"piranha": [["w", 0, 0, 2], ["w", 0, 1, 2], ["w", 0, 2, 2], ["w", 0, 0, 3], ["w", 0, 1, 3], ["w", 0, 2, 3], ["m", "piranha", 0.5, 3.6], ["m", "piranha", 2.0, 3.1]],
	"sacrificial_fire": [["t", 20, 1, 2], ["fire", "", 1.5, 2.75], ["f", 216, 0, 3], ["f", 217, 2, 3]],
	"statue": [["t", 20, 1, 2], ["m", "statue", 1.5, 2.85], ["f", 216, 2, 3]],
	"barricade": [["r", "barricade", 0, 3], ["r", "barricade", 1, 3], ["f", 216, 2, 3]],
	"garden": [["t", 2, 0, 2], ["t", 2, 1, 2], ["t", 2, 2, 2], ["t", 2, 0, 3], ["t", 2, 1, 3], ["r", "grass", 0, 3], ["r", "grass2", 1, 3], ["f", 115, 1, 2], ["f", 113, 2, 2], ["f", 112, 2, 3], ["i", "SEED_SUNGRASS", 0, 2]],
	"trapped_hall": [["f", 0, 0, 2], ["f", 18, 1, 3], ["f", 33, 2, 2], ["f", 68, 3, 3]],
	"odd_wall": [["f", 216, 1, 3], ["f", 217, 2, 3], ["spark", "c8c8ff", 1.5, 1.5]],
	"cell_block": [["m", "thief", 0.5, 2.85], ["f", 153, 0, 2], ["f", 154, 1, 2], ["i", "IRON_KEY", 2, 3]],
	"armory": [["f", 137, 0, 2], ["i", "SWORD", 1, 2], ["i", "ARMOR_MAIL", 2, 2], ["i", "MACE", 1, 3], ["f", 138, 3, 2]],
	"crystal_vein": [["f", 210, 0, 2], ["f", 211, 1, 2], ["f", 210, 2, 3], ["spark", "8ad8ff", 1.0, 2.5]],
	"vault": [["t", 4, 0, 2], ["t", 4, 1, 2], ["t", 4, 0, 3], ["t", 4, 1, 3], ["i", "CRYSTAL_CHEST", 0.5, 2.5], ["spark", "a0e8ff", 0.5, 2.4]],
	"library": [["t", 92, 1, 1], ["t", 108, 2, 1], ["t", 92, 3, 1], ["i", "SCROLL_KAUNAN", 1, 2], ["i", "SCROLL_ISAZ", 2, 3]],
	"well_health": [["w", 0, 1, 2], ["t", 18, 1, 2], ["spark", "ff7070", 1.5, 2.4], ["speck", 0, 1, 2]],
	"well_awareness": [["w", 0, 1, 2], ["t", 18, 1, 2], ["spark", "80c8ff", 1.5, 2.4], ["speck", 3, 1, 2]],
	"laboratory": [["r", "pot", 1, 3], ["i", "POTION_CRIMSON", 2, 2], ["i", "POTION_AZURE", 2, 3], ["i", "SEED_ROTBERRY", 0, 3], ["spark", "c0ff80", 1.5, 2.3]],
	"treasury": [["f", 216, 0, 2], ["f", 218, 1, 2], ["i", "GOLD", 1, 3], ["i", "GOLD", 2, 2], ["f", 217, 3, 3]],
	"shrine": [["t", 20, 1, 2], ["i", "ARTIFACT_CHALICE1", 1, 1.85], ["spark", "ffd27a", 1.5, 2.2]],
	"larder": [["f", 137, 0, 2], ["f", 138, 1, 2], ["i", "RATION", 1, 3], ["i", "PASTY", 2, 3]],
	"trap_vault": [["f", 0, 0, 2], ["f", 34, 0, 3], ["f", 65, 2, 3], ["t", 4, 1, 2], ["i", "CRYSTAL_CHEST", 1, 2], ["spark", "a0e8ff", 1.5, 2.4]],
	"prisoner": [["f", 153, 1, 2], ["f", 154, 2, 2], ["m", "guard", 0.5, 3.8], ["i", "IRON_KEY", 3, 3]],
	"abandoned_shop": [["f", 169, 1, 2], ["f", 170, 2, 2], ["i", "RATION", 1, 1.8], ["i", "TORCH", 2, 1.8], ["i", "POTION_GOLDEN", 1.5, 3], ["f", 138, 0, 3]],
	"gnoll_camp": [["t", 3, 1, 3], ["fire", "", 1.5, 3.7], ["m", "gnoll", 0.9, 2.95], ["m", "gnoll", 2.2, 2.95], ["m", "gnoll", 3.5, 3.95], ["i", "TORCH", 0, 3]],
}

const RAISED_KINDS := {"grass": [122, 234, 0.5], "grass2": [125, 237, 0.5], "pot": [120, 232, 1.0], "barricade": [121, 233, 1.0]}
var _feat_drop := {}
## Pixels of empty space under a terrain_features cell, so the prop can stand on the cell's bottom edge.
func _drop(feats: Texture2D, fi: int) -> int:
	if not _feat_drop.has(fi):
		var img: Image = feats.get_image()
		if img.is_compressed(): img.decompress()
		var u := img.get_region(Rect2i((fi % 16) * 16, (fi / 16) * 16, 16, 16)).get_used_rect()
		_feat_drop[fi] = 0 if u.size == Vector2i.ZERO else maxi(0, 15 - u.end.y)
	return int(_feat_drop[fi])

func _room_scene(id: String, x0: float, y0: float, cs: float, k: float, biome: Dictionary) -> void:
	if not ROOM_SCENES.has(id): return
	var tiles := _t("res://assets/tiles/%s.png" % biome.tile)
	var feats := _t("res://assets/tiles/terrain_features.png")
	var water := _t("res://assets/tiles/%s.png" % biome.get("water", "water0"))
	var items := _t("res://assets/sprites/items.png")
	var wo := Vector2(fposmod(t * 3.0, 32.0), fposmod(t * 2.0, 32.0)).floor()   # SPD water drifts slowly; wraps at the 32 px sheet so pools never hitch
	var mi := 0
	var wet := {}   # water cells, for SPD's edge stitching
	for op in ROOM_SCENES[id]:
		if String(op[0]) == "w": wet[Vector2i(int(op[2]), int(op[3]))] = true
	for op in ROOM_SCENES[id]:
		var dx := float(op[2]); var row := float(op[3])
		var tl := Vector2(floorf(x0 + dx * cs), floorf(y0 + row * cs))
		match String(op[0]):
			"t":
				var ti := int(op[1]); draw_texture_rect_region(tiles, Rect2(tl, Vector2(cs, cs)), Rect2((ti % 16) * 16, (ti / 16) * 16, 16, 16), _lm(tl + Vector2(cs, cs) / 2.0))
			"f":
				var fi := int(op[1])
				draw_texture_rect_region(feats, Rect2(tl + Vector2(0, _drop(feats, fi) * k), Vector2(cs, cs)), Rect2((fi % 16) * 16, (fi / 16) * 16, 16, 16), _lm(tl + Vector2(cs, cs) / 2.0))
			"r":
				var rk: Array = RAISED_KINDS[String(op[1])]
				var rm := _lm(tl + Vector2(cs, cs) / 2.0, float(rk[2]))
				draw_texture_rect_region(_grass_tex(tiles, int(rk[0])), Rect2(tl, Vector2(cs, cs)), Rect2(0, 0, 16, 16), rm)
				var oi := int(rk[1]); draw_texture_rect_region(tiles, Rect2(tl - Vector2(0, cs), Vector2(cs, cs)), Rect2((oi % 16) * 16, (oi / 16) * 16, 16, 16), rm)
			"w":   # SPD water: the scrolling water texture, then the stitch tile (ground edges) over it
				var wc := Vector2i(int(op[2]), int(op[3])); var lm := _lm(tl + Vector2(cs, cs) / 2.0)
				_water_cell(water, tl, k, wo + Vector2(wc * 16), lm)
				var wi := WATER + (0 if wet.has(wc + Vector2i.UP) or wc.y <= 2 else 1) + (0 if wet.has(wc + Vector2i.RIGHT) else 2) \
					+ (0 if wet.has(wc + Vector2i.DOWN) else 4) + (0 if wet.has(wc + Vector2i.LEFT) else 8)
				draw_texture_rect_region(tiles, Rect2(tl, Vector2(cs, cs)), Rect2((wi % 16) * 16, (wi / 16) * 16, 16, 16), lm)
			"i":
				var ir := UIKit.item_rect(DB.icon_index(String(op[1]))); var isz := ir.size * k
				var c := tl + Vector2(cs, cs) / 2.0
				draw_texture_rect_region(items, Rect2((c - isz / 2.0).floor(), isz), ir, _lm(c))
			"m":
				var mid := String(op[1])
				var m: Dictionary = DB.mobs.get(mid, {"sprite": mid, "fw": 16, "fh": 16})
				var bob := roundf(sin(t * 3.0 + mi)) * k if mid == "piranha" else 0.0
				# piranhas: SPD's submerged idle, with one leaping out of the water every few seconds
				var fr := _frame(String(m.sprite), "idle", mi * 0.41)
				if mid == "piranha" and fposmod(t + mi * 1.7, 3.4) < 0.45: fr = _frame("piranha", "attack", mi)
				_sprite(String(m.sprite), int(m.fw), int(m.fh), fr, 0, Vector2(floorf(x0 + dx * cs), floorf(y0 + row * cs + bob)), sk(), true, mid != "piranha")
				mi += 1
			"fire":
				var fp := Vector2(floorf(x0 + dx * cs), floorf(y0 + row * cs))
				SceneFX.glow(self, fp - Vector2(0, 3 * k), cs * 1.8 * SceneFX.flicker(t), Color(1.0, 0.55, 0.2, 0.25))
				SceneFX.fire(self, fp, k, t, 7.0)
			"speck":   # SPD well water (WaterOfHealth / WaterOfAwareness use()): the blob pours Specks over the cell
				_specks(int(op[1]), tl, cs, k)
			"spark":
				var sp := Vector2(x0 + dx * cs, y0 + row * cs)
				SceneFX.glow(self, sp, cs * 0.9, Color(op[1], 0.22))
				SceneFX.twinkle(self, sp, k, t, cs * 0.6, Color(op[1]))
## SPD DungeonTileSheet water: WATER = xy(1,3) = 32, then +1 ground above, +2 right, +4 below, +8 left
## (stitchWaterTile). Those tiles are transparent where the water shows.
const WATER := 32

## One 16x16 cell of the 32x32 water texture at source offset `o` (wrapped), so neighbouring cells and the
## drift stay continuous; drawn as up to four pieces instead of relying on texture repeat.
func _water_cell(water: Texture2D, tl: Vector2, k: float, o: Vector2, mod: Color) -> void:
	var ox := int(fposmod(o.x, 32.0)); var oy := int(fposmod(o.y, 32.0))
	var xs := [[ox, mini(16, 32 - ox), 0]]
	if 32 - ox < 16: xs.append([0, 16 - (32 - ox), 32 - ox])
	var ys := [[oy, mini(16, 32 - oy), 0]]
	if 32 - oy < 16: ys.append([0, 16 - (32 - oy), 32 - oy])
	for xp in xs:
		for yp in ys:
			draw_texture_rect_region(water, Rect2(tl + Vector2(xp[2], yp[2]) * k, Vector2(xp[1], yp[1]) * k), Rect2(xp[0], yp[0], xp[1], yp[1]), mod)

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
	for b in [0, 1, 4, 10]:   # stone and plank floors (the pot and barricade sit on planks)
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

## SPD Specks poured over a well (Speck.java): HEALING (0) is a red plus that rises 20 px/s for 1 s and fades in its
## second half, one every 0.5 s; QUESTION (3) is a "?" that grows and shrinks in place over 0.8 s, one every 0.3 s.
## Positions are seeded per speck, scales are whole art pixels, so nothing shimmers between frames.
var _speck_tex: Texture2D
func _specks(kind: int, tl: Vector2, cs: float, k: float) -> void:
	if _speck_tex == null: _speck_tex = load("res://assets/ui/specks.png")
	var every := 0.5 if kind == 0 else 0.3
	var life := 1.0 if kind == 0 else 0.8
	var n := int(ceil(life / every))
	for i in n:
		var age := fposmod(t + i * every, n * every)
		if age > life: continue
		var seq := int(floor((t + i * every) / (n * every))) * n + i
		var p := age / life
		var sc := 1.0
		var a := 1.0
		var pos := tl + Vector2(SceneFX._rnd(seq, 7) * 12.0 + 2.0, SceneFX._rnd(seq, 11) * 10.0 + 3.0) * k
		if kind == 0:
			pos.y -= age * 20.0 * k
			a = 1.0 if p < 0.5 else 2.0 - p * 2.0
		else:
			sc = floorf(sqrt(p if p < 0.5 else 1.0 - p) * 3.0)
			if sc < 1.0: continue
		var sz := Vector2(7, 7) * k * sc
		draw_texture_rect_region(_speck_tex, Rect2((pos - sz / 2.0).floor(), sz), Rect2(kind * 7, 0, 7, 7), Color(1, 1, 1, a))
