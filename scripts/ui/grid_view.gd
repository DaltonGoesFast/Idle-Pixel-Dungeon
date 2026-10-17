## GridView: draws the arena (8/10/12) with SPD tiles/sprites (nearest filter, integer scale) and juice:
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
var water: Texture2D        # SPD environment/waterN.png, scrolled (DECISIONS #68)
var water_name := "water0"
var parts := []         # particles [{p: Vector2 cell space, v, t, life, c: Color, s: px}]
var lighting := true    # SPD-style light radius / fog; tests can turn it off
var _rng := RandomNumberGenerator.new()
var anims := {}          # sprite -> {idle/run/attack/die: {fps, loop, frames}} from data/anims.json (tools/gen_anims.py)
var ustate := {}         # uid -> {anim, t, flip}
var dying := []          # [{sprite, fw, fh, pos, flip, t}] SPD die animation then fade
var last_units := {}     # uid -> unit snapshot (for die anims after removal)
var buff_icons: Texture2D
var variance := {}       # Vector2i -> 0..99 (SPD tileVariance)
var door_tween := {}     # Vector2i -> {open: bool, t: float} open/close flash
var _door_was := {}      # last-frame occupancy for door tween

# SPD DungeonTileSheet indices (xy(x,y) = (x-1) + 16*(y-1))
const S_FLOOR := 0; const S_FLOOR_ALT1 := 6; const S_FLOOR_ALT2 := 12
const S_CHASM := 24; const S_WATER := 32
const S_RAISED_WALL := 80; const S_RAISED_WALL_DOOR := 88; const S_RAISED_WALL_ALT := 96
const S_RAISED_DOOR := 112; const S_RAISED_DOOR_OPEN := 113; const S_RAISED_DOOR_SIDE := 116
const S_SHORT_GRASS := 2; const S_SHORT_GRASS_ALT := 8
const S_DOOR_OVERHANG_OPEN := 225; const S_DOOR_SIDE_OVERHANG_OPEN := 208; const S_DOOR_SIDE_OVERHANG_CLOSED := 212
const S_RAISED_GRASS := 122; const S_RAISED_GRASS_ALT := 125
const S_WALL_INTERNAL := 144; const S_WALL_OVERHANG := 192
const S_DOOR_OVERHANG := 224; const S_DOOR_SIDEWAYS := 227
const S_GRASS_OVERHANG := 234; const S_GRASS_OVERHANG_ALT := 237

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tiles = load("res://assets/tiles/%s.png" % tileset)
	features = load("res://assets/tiles/terrain_features.png")
	water = load("res://assets/tiles/%s.png" % water_name)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)
	clip_contents = true
	buff_icons = load("res://assets/ui/buffs.png")

func sprite(name: String) -> Texture2D:
	if not tex.has(name): tex[name] = load("res://assets/sprites/%s.png" % name)
	return tex[name]

func set_combat(c: Combat) -> void:
	combat = c
	disp.clear()
	for u in c.units: disp[u.uid] = Vector2(u.pos)
	if anims.is_empty():
		var f := FileAccess.open("res://data/anims.json", FileAccess.READ)
		if f: anims = JSON.parse_string(f.get_as_text())
	ustate.clear(); dying.clear(); variance.clear(); door_tween.clear(); _door_was.clear()
	var rng := RandomNumberGenerator.new(); rng.seed = hash(str(c.terrain))
	for y in range(-2, c.h + 2):
		for x in range(-2, c.w + 2): variance[Vector2i(x, y)] = rng.randi() % 100

func _aw() -> int: return combat.w if combat != null else Combat.SIZE
func _ah() -> int: return combat.h if combat != null else Combat.SIZE

## SPD anim control: play(uid, "attack"|"run"|"idle"), with facing from a horizontal delta.
func _play(uid: int, a: String, dx := 0.0) -> void:
	var st: Dictionary = ustate.get(uid, {"anim": "idle", "t": 0.0, "flip": false})
	if st.anim != a: st.anim = a; st.t = 0.0
	if dx < -0.01: st.flip = true
	elif dx > 0.01: st.flip = false
	ustate[uid] = st

func _frame(spr: String, a: String, t: float) -> int:
	var sa: Dictionary = anims.get(spr, {})
	var an = sa.get(a, sa.get("idle", null))
	if an == null: return 0 if fmod(t, 1.0) < 0.6 else 1
	var fr: Array = an.frames
	var i := int(t * float(an.fps))
	if an.loop: i = i % fr.size()
	else: i = mini(i, fr.size() - 1)
	return int(fr[i])

func _anim_done(spr: String, a: String, t: float) -> bool:
	var an = anims.get(spr, {}).get(a, null)
	if an == null: return t > 0.3
	return t * float(an.fps) >= float(an.frames.size())

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
				match e.kind:
					"hp", "surprise": _burst(Vector2(e.pos), Color("b01818"), 7 if e.kind == "hp" else 11)   # blood
					"chip", "block", "barrier": _burst(Vector2(e.pos), Color("ffe08a"), 5, 2.2)          # sparks
					"magic": _burst(Vector2(e.pos), Color("c08bff"), 6)
					"poison": _burst(Vector2(e.pos), Color("8be04e"), 4, 0.6)
				Sfx.play("hit_strong" if e.kind == "surprise" else ("hit_magic" if e.kind == "magic" else "hit"), 1.0)
				if e.uid == combat.hero.uid and int(e.amount) > 0: Sfx.buzz(60 if e.kind == "hp" else 25)
			"heal":
				floaters.append({"pos": Vector2(e.pos), "text": "+%d" % e.amount, "color": Color("6bff6b"), "t": 0.0}); Sfx.play("drink")
			"die":
				Sfx.play("death" if e.uid == combat.hero.uid else "bones")
				var lu = last_units.get(e.uid, null)
				if lu != null:
					dying.append({"sprite": lu.sprite, "fw": lu.fw, "fh": lu.fh, "row": int(lu.get("row", 0)), "pos": disp.get(e.uid, Vector2(e.pos)), "flip": ustate.get(e.uid, {}).get("flip", false), "t": 0.0})
			"fall": Sfx.play("falling")
			"bolt":
				streaks.append({"from": Vector2(e.from), "to": Vector2(e.to), "t": 0.0, "magic": e.get("magic", true)})
				Sfx.play("zap" if e.get("magic", true) else "atk_spiritbow")
			"blast": blasts.append({"pos": Vector2(e.pos), "t": 0.0}); Sfx.play("hit_crush")
			"telegraph": Sfx.buzz(20)   # no alarm sound (DECISIONS #100)
			"shock": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "shock": true})
			"burn": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "fire": true}); Sfx.play("burning")
			"move":
				if combat.tile(Vector2i(e.to)) == Combat.T.WATER: _burst(Vector2(e.to), Color("7fb8ff"), 6, 1.2, 0.35)  # splash
				if e.get("blink", false): disp[e.uid] = Vector2(e.to)  # teleports snap, no slide
				elif e.uid == combat.hero.uid: Sfx.play("step", 1.1)
				if not e.get("blink", false): _play(e.uid, "run", float(Vector2(e.to).x - Vector2(e.from).x))
			"trap": blasts.append({"pos": Vector2(e.pos), "t": 0.0, "trap": true}); Sfx.buzz(80)
			"reveal": floaters.append({"pos": Vector2(e.pos), "text": "!", "color": Color("ffd27a"), "t": 0.0})
			"search": rings.append({"pos": Vector2(e.pos), "r": float(e.r), "t": 0.0})
			"sfx": Sfx.play(e.name)
			"attack":
				for u in combat.units:
					if u.uid == e.uid:
						lunge[e.uid] = {"dir": (Vector2(e.to) - Vector2(u.pos)).normalized(), "t": 0.0}
						_play(e.uid, "attack", float(Vector2(e.to).x - Vector2(u.pos).x))
				Sfx.play("hit_slash", 1.0)

func _process(d: float) -> void:
	anim_t += d
	if combat:
		for y in combat.h:
			for x in combat.w:
				var c := Vector2i(x, y)
				if combat.tile(c) != Combat.T.DOOR: continue
				var now := not combat.door_closed(c)
				if _door_was.get(c, now) != now:
					door_tween[c] = {"open": now, "t": 0.0}
				_door_was[c] = now
		for k in door_tween.keys():
			door_tween[k].t += d
			if door_tween[k].t >= MOVE_TIME: door_tween.erase(k)
		for u in combat.units:
			var target := Vector2(u.pos)
			var cur: Vector2 = disp.get(u.uid, target)
			disp[u.uid] = cur.move_toward(target, d / MOVE_TIME * maxf(1.0, cur.distance_to(target)))
			last_units[u.uid] = u
			var st: Dictionary = ustate.get(u.uid, {"anim": "idle", "t": randf() * 3.0, "flip": false})
			st.t += d
			if st.anim == "run" and disp[u.uid] == target and st.t > 0.1: st.anim = "idle"; st.t = 0.0
			elif st.anim == "attack" and _anim_done(u.sprite, "attack", st.t): st.anim = "idle"; st.t = 0.0
			ustate[u.uid] = st
	for dd in dying: dd.t += d
	dying = dying.filter(func(dd): return dd.t < 1.6)
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
	for q in parts:
		q.t += d; q.p += q.v * d; q.v.y += 3.0 * d   # light gravity (cells/s^2)
	parts = parts.filter(func(q): return q.t < q.life)
	queue_redraw()

## Particles in cell space: n pixels flung from the centre of cell p.
func _burst(p: Vector2, c: Color, n: int, speed := 1.6, up := 0.0) -> void:
	if parts.size() > 160: return   # perf cap
	for i in n:
		var a := _rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * (0.4 + _rng.randf() * 0.6) + Vector2(0, -up - 0.6)
		parts.append({"p": p + Vector2(0.5, 0.5), "v": v, "t": 0.0, "life": 0.35 + _rng.randf() * 0.25, "c": c, "s": 1 + _rng.randi() % 2})

## Light radius in cells: SPD-like torchlight that shrinks as the torch burns down; darkness = tiny radius.
func light_radius() -> float:
	var run: Dictionary = GameState.run
	if run.is_empty(): return 99.0
	if Delve.darkness(run): return 1.8
	return lerpf(3.2, 6.5, clampf(float(run.get("torch", 100.0)) / 100.0, 0.0, 1.0))

## SPD-style camera: the arena plus a half-tile wall border fills the view; cells snap to whole
## multiples of the 16 px art (integer zoom) whenever the screen allows it (DECISIONS #72).
func cell_size() -> float:
	var side := float(maxi(_aw(), _ah()))
	var raw := floorf(minf(size.x, size.y) / (side + 0.3))
	if raw < 16.0: return raw
	var snapped := floorf(raw / 16.0) * 16.0
	# integer zoom unless it would waste >15% of the screen; then 1/4-pixel steps (still nearest-filtered)
	return snapped if snapped >= raw * 0.9 else floorf(raw / 4.0) * 4.0

func origin() -> Vector2:
	var cs := cell_size()
	var arena := Vector2(cs * _aw(), cs * _ah())
	var slack := size - arena
	# most vertical slack goes on top so the raised top wall face is visible (SPD rooms read from their top wall)
	return Vector2(slack.x / 2.0, minf(slack.y * 0.8, cs * 0.75)).floor()

func cell_rect(p: Vector2) -> Rect2:
	var cs := cell_size()
	return Rect2((origin() + p * cs).floor(), Vector2(cs, cs))

# ---- SPD terrain stitching (DungeonTileSheet / DungeonTerrainTilemap / DungeonWallsTilemap) ----
# Cells outside the arena are walls (a SPD room border); beyond that NULL_TILE also stitches as wall.
func _t(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= _aw() or c.y >= _ah(): return Combat.T.WALL
	return combat.terrain[c.y][c.x]

func _is_wall(c: Vector2i) -> bool: return _t(c) == Combat.T.WALL
func _is_door(c: Vector2i) -> bool: return _t(c) == Combat.T.DOOR
func _door_open(c: Vector2i) -> bool:
	if combat == null or not _is_door(c): return false
	var occ := not combat.door_closed(c)
	# brief open/close: hold the previous frame for half a move, then settle (tests see settled without _process)
	if door_tween.has(c) and float(door_tween[c].t) < MOVE_TIME * 0.45:
		return not bool(door_tween[c].open)
	return occ
func _water_stitch(c: Vector2i) -> bool:
	var t := _t(c); return t == Combat.T.FLOOR or t == Combat.T.GRASS or t == Combat.T.DOOR

## Ground layer visual for a cell (or -1 = nothing; walls fall to the walls layer).
func terrain_visual(c: Vector2i) -> int:
	var t := _t(c)
	var v: int = variance.get(c, 50)
	match t:
		Combat.T.FLOOR, Combat.T.GRASS:
			if combat != null and combat.trampled.has(c): return S_SHORT_GRASS_ALT if v < 50 else S_SHORT_GRASS
			if v < 5: return S_FLOOR_ALT2
			if v < 52: return S_FLOOR_ALT1
			return S_FLOOR
		Combat.T.WATER:
			var m := 0
			if _water_stitch(c + Vector2i(0, -1)): m += 1
			if _water_stitch(c + Vector2i(1, 0)): m += 2
			if _water_stitch(c + Vector2i(0, 1)): m += 4
			if _water_stitch(c + Vector2i(-1, 0)): m += 8
			return S_WATER + m if m > 0 else -1
		Combat.T.CHASM:
			var a := _t(c + Vector2i(0, -1))
			if a == Combat.T.FLOOR or a == Combat.T.GRASS: return S_CHASM + 1
			if a == Combat.T.WALL or a == Combat.T.DOOR: return S_CHASM + 3
			if a == Combat.T.WATER: return S_CHASM + 4
			return S_CHASM
		Combat.T.DOOR:
			# SPD: a door with wall below is a sideways door; doors show OPEN while someone stands in them
			if _is_wall(c + Vector2i(0, 1)): return S_RAISED_DOOR_SIDE
			return S_RAISED_DOOR_OPEN if _door_open(c) else S_RAISED_DOOR
		Combat.T.WALL:
			var below := c + Vector2i(0, 1)
			if _is_wall(below) or below.y > _ah(): return -1
			var r := S_RAISED_WALL_DOOR if _is_door(below) else (S_RAISED_WALL_ALT if v < 50 else S_RAISED_WALL)
			if not _is_wall(c + Vector2i(1, 0)): r += 1
			if not _is_wall(c + Vector2i(-1, 0)): r += 2
			return r
	return -1

## Raised grass sits on the floor (RAISED_HIGH_GRASS).
func grass_visual(c: Vector2i) -> int:
	return S_RAISED_GRASS_ALT if int(variance.get(c, 50)) < 50 else S_RAISED_GRASS

## Walls layer (drawn OVER characters): wall tops, and overhangs of walls/doors/grass on the cell above.
func wall_visual(c: Vector2i) -> int:
	var below := c + Vector2i(0, 1)
	if _is_wall(c):
		if not _is_wall(below):
			if _is_door(below):
				# Sideways door only when there is wall under the door; otherwise front overhang
				if _is_wall(below + Vector2i(0, 1)):
					return -1 if _door_open(below) else S_DOOR_SIDEWAYS
				return S_DOOR_OVERHANG_OPEN if _door_open(below) else S_DOOR_OVERHANG
			return -1
		var r := S_WALL_INTERNAL
		if not _is_wall(c + Vector2i(1, 0)): r += 1
		if not _is_wall(c + Vector2i(1, 1)): r += 2
		if not _is_wall(c + Vector2i(-1, 1)): r += 4
		if not _is_wall(c + Vector2i(-1, 0)): r += 8
		return r
	if _is_wall(below):
		var o := S_WALL_OVERHANG
		if _is_door(c): o = S_DOOR_SIDE_OVERHANG_OPEN if _door_open(c) else S_DOOR_SIDE_OVERHANG_CLOSED
		if not _is_wall(c + Vector2i(1, 1)): o += 1
		if not _is_wall(c + Vector2i(-1, 1)): o += 2
		return o
	if _is_door(below): return S_DOOR_OVERHANG_OPEN if _door_open(below) else S_DOOR_OVERHANG
	return -1

## Tall-grass overhang on the cell above. Drawn in the ground pass (under units) so it never
## covers the head of a character standing in the grass or the cell above (DECISIONS #81).
func grass_overhang(c: Vector2i) -> int:
	var below := c + Vector2i(0, 1)
	if _is_wall(c) or _t(below) != Combat.T.GRASS or below.y >= _ah(): return -1
	return S_GRASS_OVERHANG_ALT if int(variance.get(below, 50)) < 50 else S_GRASS_OVERHANG

## SPD FogOfWar-like darkness 0..1 at a cell corner (bilinear blend between cells like SPD's fog texture).
## Perf (DECISIONS #88): line-of-sight per cell is cached until the hero moves or the terrain changes,
## instead of ~680 line_clear calls per frame (4 per fog corner).
var _vis := {}
var _vis_key := []
func _visible(c: Vector2i) -> bool:
	var key := [combat.hero.pos, combat.terrain.hash(), combat.units.size()]
	if key != _vis_key:
		_vis_key = key; _vis.clear()
	if not _vis.has(c): _vis[c] = combat.sees(combat.hero.pos, c)
	return _vis[c]

func _corner_dark(cx: int, cy: int, ctr: Vector2, lr: float) -> float:
	var acc := 0.0
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var c: Vector2i = Vector2i(cx, cy) + o
		var dk := 0.0
		if c.x < 0 or c.y < 0 or c.x >= _aw() or c.y >= _ah(): dk = 0.55
		elif not _is_wall(c) and not _visible(c): dk = 0.55   # SPD "visited" (seen, not in view)
		acc += dk
	var fog := acc / 4.0
	var dist := Vector2(cx, cy).distance_to(ctr)
	var torch := clampf((dist - lr * 0.55) / (lr * 0.45), 0.0, 1.0) * 0.85
	return clampf(maxf(fog, torch) + fog * torch * 0.3, 0.0, 0.92)

func _draw() -> void:
	if combat == null: return
	var cs := cell_size()
	var ps := cs / 16.0
	var lo := -2; var hi_x := _aw() + 1; var hi_y := _ah() + 1
	# 1. ground layer
	for y in range(lo, hi_y + 1):
		for x in range(lo, hi_x + 1):
			var c := Vector2i(x, y)
			var t := _t(c)
			var r := cell_rect(Vector2(x, y))
			if t == Combat.T.WATER:
				var off := Vector2(anim_t * 3.0, anim_t * 1.5)   # SPD water texture scroll
				draw_texture_rect_region(water, r, Rect2(Vector2(x * 16, y * 16) + off, Vector2(16, 16)))
			var v := terrain_visual(c)
			if v >= 0: _tile(r, v)
			elif t == Combat.T.WALL and _is_wall(c + Vector2i(0, 1)): _tile(r, S_WALL_INTERNAL + 15)  # solid fill under wall tops
			if t == Combat.T.GRASS:
				# blades + overhang share one offset; floor strip (bottom 6 art px) stays put
				var sway := roundf(sin(anim_t * 1.7 + x * 0.9 + y * 0.5) * 0.6) * ps
				_tile_grass(r, grass_visual(c), sway)
			var go := grass_overhang(c)
			if go >= 0:
				var sway2 := 0.0
				if _t(c + Vector2i(0, 1)) == Combat.T.GRASS:
					sway2 = roundf(sin(anim_t * 1.7 + x * 0.9 + (y + 1) * 0.5) * 0.6) * ps
				_tile(Rect2(r.position + Vector2(sway2, 0), r.size), go)
	# 2. terrain features: revealed traps
	for k in combat.traps:
		if not combat.traps[k].hidden:
			var idx := int(DB.traps[combat.traps[k].id].sprite)
			draw_texture_rect_region(features, cell_rect(Vector2(k)), Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
	# 3. tactical highlights
	var hp: Vector2i = combat.hero.pos
	if not combat.over:
		for d in Combat.DIRS:
			var n: Vector2i = hp + d
			var u = combat.unit_at(n)
			if u != null and u != combat.hero:
				draw_rect(cell_rect(Vector2(n)).grow(-2), Color(1, 0.8, 0.3, 0.7) if mode == "shove" else Color(1, 0.4, 0.3, 0.6), false, maxf(2.0, ps))
			elif combat.passable(n) and u == null:
				var warn := combat.visible_trap(n)
				draw_rect(cell_rect(Vector2(n)).grow(-2), Color(1, 0.6, 0.2, 0.5) if warn else Color(1, 1, 1, 0.16), false, maxf(2.0, ps * 0.5))
		if mode == "bolt" or not combat.hero.bolt.is_empty():
			for e in combat.enemies():
				if combat.hero_sees(e) and combat.can_bolt(e.pos) and combat.bolt_victim(e.pos) == e and Combat.cheb(e.pos, hp) > 1:
					draw_rect(cell_rect(Vector2(e.pos)).grow(-4), Color(0.75, 0.55, 1.0, 0.7), false, 2.0)
	for dz in combat.danger:
		var pulse := 0.3 + 0.2 * sin(anim_t * 9.0)
		draw_rect(cell_rect(Vector2(dz.pos)), Color(1, 0, 0, pulse))
		draw_rect(cell_rect(Vector2(dz.pos)).grow(-1), Color(1, 0.2, 0.2, 0.9), false, 2.0)
	if hint_cell.x >= 0:
		draw_rect(cell_rect(Vector2(hint_cell)).grow(-3), Color(0.4, 1, 0.5, 0.5 + 0.3 * sin(anim_t * 6)), false, 4.0)
	# 4. characters (SPD CharSprite: animated frames, facing flip, tweened walk, lunge, die + fade)
	var hero_disp: Vector2 = disp.get(combat.hero.uid, Vector2(combat.hero.pos))
	var lr := light_radius() if lighting else 99.0
	var scale := floorf(ps) if cs >= 16.0 else ps
	var order := combat.units.duplicate()
	order.sort_custom(func(a, b): return float(disp.get(a.uid, Vector2(a.pos)).y) < float(disp.get(b.uid, Vector2(b.pos)).y))
	for dd in dying:
		var dk: float = 1.0 if dd.t < 0.8 else 1.0 - (dd.t - 0.8) / 0.8
		var dfr := _frame(dd.sprite, "die", dd.t)
		_draw_sprite(dd.sprite, dd.fw, dd.fh, dfr + int(dd.get("row", 0)) * 1000, dd.pos, dd.flip, scale, Color(1, 1, 1, dk))
	for u in order:
		if u.hp <= 0: continue
		var p: Vector2 = disp.get(u.uid, Vector2(u.pos))
		if lunge.has(u.uid): p += lunge[u.uid].dir * 0.25 * sin(lunge[u.uid].t / 0.16 * PI)
		var st: Dictionary = ustate.get(u.uid, {"anim": "idle", "t": 0.0, "flip": false})
		var fr := _frame(u.sprite, st.anim, st.t + (0.0 if st.anim != "idle" else u.uid * 0.37))
		var mod := Color(1, 1, 1)
		if flash.has(u.uid): mod = Color(4, 4, 4)
		if u.get("charging", false): mod = Color(1.6, 0.6, 0.6)
		if u.has("hero") and combat.hidden(): mod.a = 0.45
		if not u.has("hero") and lighting and p.distance_to(hero_disp) > lr: mod = mod * Color(0.55, 0.55, 0.6)
		var top := _draw_sprite(u.sprite, u.fw, u.fh, fr + int(u.get("row", 0)) * 1000, p, st.flip, scale, mod)
		_health_bar(u, top, scale)
		_status_icons(u, top, scale)
	# 5. walls layer over characters (SPD perspective wall tops / overhangs)
	for y in range(lo, hi_y + 1):
		for x in range(lo, hi_x + 1):
			var wv := wall_visual(Vector2i(x, y))
			if wv >= 0: _tile(cell_rect(Vector2(x, y)), wv)
	# 6. fog of war + torchlight: smooth per-corner blend (SPD FogOfWar texture is bilinear)
	if lighting and lr < 50.0:
		var ctr := hero_disp + Vector2(0.5, 0.5)
		var dark := {}
		for y in range(lo, hi_y + 2):
			for x in range(lo, hi_x + 2): dark[Vector2i(x, y)] = _corner_dark(x, y, ctr, lr)
		for y in range(lo, hi_y + 1):
			for x in range(lo, hi_x + 1):
				var a: float = dark[Vector2i(x, y)]; var b: float = dark[Vector2i(x + 1, y)]
				var c2: float = dark[Vector2i(x + 1, y + 1)]; var d2: float = dark[Vector2i(x, y + 1)]
				if a + b + c2 + d2 <= 0.0: continue
				var r := cell_rect(Vector2(x, y))
				draw_polygon(PackedVector2Array([r.position, r.position + Vector2(cs, 0), r.end, r.position + Vector2(0, cs)]),
					PackedColorArray([Color(0, 0, 0, a), Color(0, 0, 0, b), Color(0, 0, 0, c2), Color(0, 0, 0, d2)]))
		draw_circle(cell_rect(hero_disp).get_center(), cs * 0.9, Color(1.0, 0.75, 0.35, 0.07 + 0.02 * sin(anim_t * 5.0)))
	# 7. effects
	for q in parts:
		var qa: float = 1.0 - float(q.t) / float(q.life)
		var px: float = maxf(2.0, ps) * float(q.s)
		draw_rect(Rect2((origin() + q.p * cs).floor(), Vector2(px, px)), Color(q.c.r, q.c.g, q.c.b, qa))
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
	# SPD FloatingText: pixel font, rises and fades, whole-pixel sizes
	var font := get_theme_default_font()
	var fs := UIKit.font_px(maxf(14, cs * 0.34))
	for f in floaters:
		var r := cell_rect(f.pos)
		var w := font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := (r.get_center() + Vector2(-w / 2.0, -cs * 0.25 - f.t * cs * 0.7)).floor()
		var col: Color = f.color; col.a = 1.0 - maxf(0, f.t - 0.5) / 0.4
		draw_string_outline(font, p, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(ps)), Color(0, 0, 0, col.a))
		draw_string(font, p, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Draw one sprite frame bottom-centred in its cell; returns the sprite's top-left (for bars/icons).
func _draw_sprite(spr: String, fw: int, fh: int, frame: int, p: Vector2, flip: bool, scale: float, mod: Color) -> Vector2:
	var t := sprite(spr)
	var cols := maxi(1, t.get_width() / fw)
	var row := frame / 1000; frame = frame % 1000   # armor-tier row packed by the caller (SPD HeroSprite)
	var src := Rect2((frame % cols) * fw, (frame / cols + row) * fh, fw, fh)
	var sz := Vector2(fw, fh) * scale
	var cs := cell_size()
	var r := cell_rect(p)
	var pos := (r.position + Vector2((cs - sz.x) / 2.0, cs - sz.y)).floor()
	if flip:
		draw_set_transform(Vector2(pos.x * 2.0 + sz.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(t, Rect2(pos, sz), src, mod)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(t, Rect2(pos, sz), src, mod)
	return pos

## SPD HealthBar: thin red bg, green hp, pale shield; above the sprite; mobs only when hurt.
func _health_bar(u: Dictionary, top: Vector2, scale: float) -> void:
	var is_hero := u.has("hero")
	if not is_hero and int(u.hp) >= int(u.ht): return
	var cs := cell_size()
	var w := floorf(cs * 0.75); var h := maxf(2.0, scale)
	var x := cell_rect(disp.get(u.uid, Vector2(u.pos))).position.x + floorf((cs - w) / 2.0)
	var y := top.y - h * 2.0
	draw_rect(Rect2(x - scale * 0.5, y - scale * 0.5, w + scale, h + scale), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(x, y, w, h), Color("cc0000"))
	var hpw := floorf(w * clampf(float(u.hp) / float(u.ht), 0, 1))
	if is_hero and int(u.barrier) > 0:
		var bw := floorf(w * clampf(float(u.barrier) / maxf(1.0, float(u.barrier_max)), 0, 1))
		draw_rect(Rect2(x, y, bw, h), Color("bbeebb"))
	draw_rect(Rect2(x, y, hpw, h), Color("00ee00"))

## SPD BuffIndicator small icons (buffs.png, 8 px grid) shown above the bar.
const BUFF_IDX := {"poison": 3, "charging": 10, "enraged": 9, "hidden": 12, "barrier": 20, "shielded": 20}
func _status_icons(u: Dictionary, top: Vector2, scale: float) -> void:
	var list := []
	if int(u.get("poison", 0)) > 0: list.append("poison")
	if u.get("charging", false): list.append("charging")
	if u.get("enraged", false): list.append("enraged")
	if u.has("hero") and combat.hidden(): list.append("hidden")
	if u.get("shielded", false): list.append("shielded")
	if list.is_empty(): return
	var s := 7.0 * maxf(1.0, floorf(scale * 0.75))   # whole-pixel icon scale (DECISIONS #89)
	var x := floorf(top.x)
	for k in list:
		var i: int = BUFF_IDX[k]
		draw_texture_rect_region(buff_icons, Rect2(x, floorf(top.y - maxf(2.0, scale) * 3.0 - s), s, s), Rect2((i % 18) * 7, (i / 18) * 7, 7, 7))
		x += s + scale


func _tile(r: Rect2, idx: int) -> void:
	draw_texture_rect_region(tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

## Tall grass: bottom 6 art pixels stay put (floor), top 10 sway with the overhang.
func _tile_grass(r: Rect2, idx: int, sway: float) -> void:
	var sx := (idx % 16) * 16; var sy := int(idx / 16) * 16
	var ps := r.size.x / 16.0
	var floor_h := 6.0 * ps
	var blade_h := 10.0 * ps
	draw_texture_rect_region(tiles, Rect2(r.position + Vector2(0, blade_h), Vector2(r.size.x, floor_h)), Rect2(sx, sy + 10, 16, 6))
	draw_texture_rect_region(tiles, Rect2(r.position + Vector2(sway, 0), Vector2(r.size.x, blade_h)), Rect2(sx, sy, 16, 10))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var c: Vector2 = ((e.position - origin()) / cell_size()).floor()
		var cell := Vector2i(c)
		if cell.x >= 0 and cell.y >= 0 and cell.x < _aw() and cell.y < _ah():
			tapped.emit(cell)
		accept_event()
