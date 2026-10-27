## GridView: draws the arena (8/10/12) with SPD tiles/sprites (nearest filter, integer scale) and juice:
## tweened movement, hit flash, floating damage numbers, SPD projectiles and beams, pulsing red danger tiles.
## Emits `tapped(cell)`. Pan always + pinch/wheel zoom (DECISIONS #235). Visual state is driven by Combat.drain_events().
extends Control

signal tapped(cell: Vector2i)

const TILE_IDX := {Combat.T.FLOOR: 0, Combat.T.GRASS: 66, Combat.T.WALL: 48, Combat.T.DOOR: 56, Combat.T.CHASM: 24, Combat.T.WATER: 0}
const MOVE_TIME := 0.12
const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.5
const ZOOM_WHEEL := 1.12
const DRAG_THRESH_FS := 0.55   # same spirit as TouchScroll.THRESHOLD_FS

var combat: Combat
var tex := {}
var tiles: Texture2D
var features: Texture2D     # SPD terrain_features.png (trap sprites)
var tileset := "tiles_sewers"
var rings := []             # search pulses [{pos, r, t}]
var anim_t := 0.0
var disp := {}          # uid -> Vector2 (cell-space display position)
var flash := {}         # uid -> seconds remaining
const FLASH_S := 0.05   # SPD CharSprite.FLASH_INTERVAL: full white for 0.05 s, then back
var floaters := []      # [{pos: Vector2 (cell space), text, color, t}]
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
var shots := []          # SPD projectiles [{kind, from, to, t, dur, col, mid}]: arrows, MagicMissile, Lightning, beams
var _danger_prev := []   # last frame's telegraphed tiles, to know who fired a resolving zap (visual only)
var effects: Texture2D   # SPD effects/effects.png (Lightning, DeathRay, LightRay strips)
var _door_was := {}      # last-frame occupancy for door tween
var _boss := ""          # boss sprite of this arena ("" = none): picks SPD boss-room dressing, visual only (DECISIONS #185)
var _ctex := {}          # SPD custom boss tiles (environment/custom_tiles) and the DM-300 pylon sprite
## Combat camera: 1 = fit whole arena; pan is pixels after fit centering (DECISIONS #235).
var zoom_mult := 1.0
var pan := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false
var _pan_btn := -1            # MOUSE_BUTTON_* while middle/right-dragging; -1 otherwise
var _last_ptr := Vector2.ZERO
var _touches := {}            # finger index -> local position (pinch)
var _pinch_active := false
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0

# SPD DungeonTileSheet indices (xy(x,y) = (x-1) + 16*(y-1))
const S_FLOOR := 0; const S_FLOOR_ALT1 := 6; const S_FLOOR_ALT2 := 12
const S_CHASM := 24; const S_WATER := 32
const S_RAISED_WALL := 80; const S_RAISED_WALL_DECO := 84; const S_RAISED_WALL_DOOR := 88; const S_RAISED_WALL_ALT := 96; const S_RAISED_WALL_DECO_ALT := 100
const S_RAISED_DOOR := 112; const S_RAISED_DOOR_OPEN := 113; const S_RAISED_DOOR_SIDE := 116
const S_SHORT_GRASS := 2; const S_SHORT_GRASS_ALT := 8
const S_DOOR_OVERHANG_OPEN := 225; const S_DOOR_SIDE_OVERHANG_OPEN := 208; const S_DOOR_SIDE_OVERHANG_CLOSED := 212
const S_RAISED_GRASS := 122; const S_RAISED_GRASS_ALT := 125
const S_WALL_INTERNAL := 144; const S_WALL_OVERHANG := 192
const S_DOOR_OVERHANG := 224; const S_DOOR_SIDEWAYS := 227
const S_GRASS_OVERHANG := 234; const S_GRASS_OVERHANG_ALT := 237
var _vita_acc := 0.0
var _last_draw_us := 0
const VITA_FRAME_N := 1
const VITA_BAKE_LO := -2
var _vita_frames: Array = []
var _vita_wall_fx: Array = []
var _vita_walls: Node2D
var _vita_fog: Node2D
var _vita_fx: Node2D
var _vita_stamp := ""
var _vita_bake_key := ""
var _vita_fog_key := ""
var _vita_warm := 0
var _vita_phase := 0
var _vita_dirty := true
var _vita_disp_key := ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tiles = load("res://assets/tiles/%s.png" % tileset)
	features = load("res://assets/tiles/terrain_features.png")
	water = load("res://assets/tiles/%s.png" % water_name)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(_on_resized)
	clip_contents = true
	buff_icons = load("res://assets/ui/buffs.png")
	effects = load("res://assets/ui/effects.png")

func _on_resized() -> void:
	reset_camera()
	queue_redraw()

## Fit the whole arena again (new fight or layout change).
func reset_camera() -> void:
	zoom_mult = 1.0
	pan = Vector2.ZERO
	_pressing = false
	_dragging = false
	_pan_btn = -1
	_touches.clear()
	_pinch_active = false

func sprite(name: String) -> Texture2D:
	if not tex.has(name): tex[name] = load("res://assets/sprites/%s.png" % name)
	return tex[name]

func set_combat(c: Combat) -> void:
	combat = c
	reset_camera()
	disp.clear()
	for u in c.units: disp[u.uid] = Vector2(u.pos)
	if anims.is_empty():
		var f := FileAccess.open("res://data/anims.json", FileAccess.READ)
		if f: anims = JSON.parse_string(f.get_as_text())
	ustate.clear(); dying.clear(); variance.clear(); door_tween.clear(); _door_was.clear(); shots.clear(); _danger_prev = []
	_boss = ""
	for u in c.units:
		if u.get("boss", false): _boss = String(u.get("sprite", ""))
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
	var fired := {}   # uid -> true: one beam per caster per batch (an Evil Eye beam resolves tile by tile)
	_batch_blasts = evs.filter(func(e): return e.t == "blast")   # this batch's resolving tiles, for the beam's far end
	for e in evs:
		match e.t:
			"hit":
				flash[e.uid] = FLASH_S
				var col := Color("ff5050")
				var txt := str(e.amount)
				match e.kind:
					"barrier": col = Color("7fd3ff")
					"chip": col = Color("7fd3ff"); txt = "chip"
					"block": col = Color("bbbbbb"); txt = "block"
					"miss": col = Color("bbbbbb"); txt = "dodged"   # SPD defenseVerb (inaccurate weapons, DECISIONS #207)
					"surprise": col = Color("ffd27a"); txt += "!"
					"magic": col = Color("c08bff")
					"poison": col = Color("8be04e")
				floaters.append({"pos": Vector2(e.pos), "text": txt, "color": col, "t": 0.0})
				match e.kind:
					"hp", "surprise": _burst(Vector2(e.pos), Color("b01818"), 7 if e.kind == "hp" else 11)   # blood
					"chip", "block", "barrier": _burst(Vector2(e.pos), Color("ffe08a"), 5, 2.2)          # sparks
					"magic": _burst(Vector2(e.pos), Color("c08bff"), 6)
					"poison": _burst(Vector2(e.pos), Color("8be04e"), 4, 0.6)
				Sfx.play("miss" if e.kind == "miss" else ("hit_strong" if e.kind == "surprise" else ("hit_magic" if e.kind == "magic" else "hit")), 1.0)
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
				# SPD: the Spirit Bow looses a spirit arrow (MissileSprite); staffs and wands a MagicMissile
				_shot("magic" if e.get("magic", true) else "arrow", Vector2(e.from), Vector2(e.to))
				Sfx.play("zap" if e.get("magic", true) else "atk_spiritbow")
			"blast":
				blasts.append({"pos": Vector2(e.pos), "t": 0.0}); Sfx.play("hit_crush")
				_zap_visual(Vector2i(e.pos), fired, e)
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

## Flight time like SPD's MissileSprite / MagicMissile (~12 tiles a second), never slower than 0.25 s.
func _shot(kind: String, from: Vector2, to: Vector2, col := Color.WHITE) -> void:
	var dur := clampf(from.distance_to(to) / 12.0, 0.08, 0.25)
	if kind in ["lightning", "deathray", "lightray"]: dur = 0.35   # SPD Lightning / Beam linger and fade
	var mid := (from + to) / 2.0 + Vector2(-(to - from).y, (to - from).x).normalized() * (_rng.randf() - 0.5) * 0.6
	shots.append({"kind": kind, "from": from, "to": to, "t": 0.0, "dur": dur, "col": col, "mid": mid})

var _batch_blasts := []   # blast events of the batch play_events is reading

## A telegraphed zap resolving on `p`: draw what fired it, from the caster (SPD DM100 Lightning, Shaman / Warlock
## MagicMissile, Evil Eye DeathRay, Bright Fist LightRay). Combat resolves the damage; this only reads it.
## The blast event names its caster, so a telegraph made and resolved inside one step still draws; older danger
## snapshots are the fallback.
func _zap_visual(p: Vector2i, fired: Dictionary, ev := {}) -> void:
	var cands := ([{"pos": p, "uid": ev.uid, "src": ev.get("src", ""), "debuff": ev.get("debuff", "")}] if int(ev.get("uid", 0)) > 0 else []) + _danger_prev
	for dz in cands:
		if Vector2i(dz.pos) != p or int(dz.get("uid", 0)) <= 0: continue
		var src := String(dz.get("src", ""))
		if not (src.ends_with("lightning") or src.ends_with("beam")): continue
		var m = null
		for u in combat.units:
			if u.uid == int(dz.uid): m = u
		if m == null or fired.has(m.uid): continue   # a second zapper on the same cell still draws
		var from: Vector2 = disp.get(m.uid, Vector2(m.pos))
		fired[m.uid] = true
		_play(m.uid, "zap" if anims.get(String(m.sprite), {}).has("zap") else "attack", float(p.x) - from.x)
		match String(m.sprite):
			"dm100": _shot("lightning", from, Vector2(p))
			"eye":
				var far := Vector2(p)   # the beam runs to the far end of the line it lit up
				for d2 in _danger_prev + _batch_blasts:
					if int(d2.get("uid", 0)) == int(m.uid) and Vector2(d2.pos).distance_to(from) > far.distance_to(from): far = Vector2(d2.pos)
				_shot("deathray", from, far)
			"fist_bright": _shot("lightray", from, Vector2(p))
			"warlock": _shot("shadow", from, Vector2(p), Color("4b2a63"))
			"shaman": _shot("magic", from, Vector2(p), Color("ff4d4d") if String(dz.get("debuff", "")) == "weak" else Color("4d7dff"))
			_: _shot("magic", from, Vector2(p), Color("88ccff"))
		return

var _vita_door_turn := -1

func _process(d: float) -> void:
	var vita := VitaBoot.runs_on_vita()
	var t0 := Time.get_ticks_usec() if vita else 0
	anim_t += d
	if combat:
		# Full board door scan only when the turn counter moves (was every frame on Vita).
		var door_scan := not vita or int(combat.hero_turns) != _vita_door_turn or not door_tween.is_empty()
		if door_scan:
			if vita:
				_vita_door_turn = int(combat.hero_turns)
			for y in combat.h:
				for x in combat.w:
					var c := Vector2i(x, y)
					if combat.tile(c) != Combat.T.DOOR: continue
					var now := not combat.door_closed(c)
					if _door_was.get(c, now) != now:
						door_tween[c] = {"open": now, "t": 0.0}
						if vita:
							_vita_dirty = true
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
			elif (st.anim == "attack" or st.anim == "zap") and _anim_done(u.sprite, st.anim, st.t): st.anim = "idle"; st.t = 0.0
			ustate[u.uid] = st
	for dd in dying: dd.t += d
	dying = dying.filter(func(dd): return dd.t < 1.6)
	for k in flash.keys():
		flash[k] -= minf(d, FLASH_S * 0.5)   # a slow frame still shows the flash at least once
		if flash[k] <= 0: flash.erase(k)
	for k in lunge.keys():
		lunge[k].t += d
		if lunge[k].t > 0.16: lunge.erase(k)
	for f in floaters: f.t += d
	floaters = floaters.filter(func(f): return f.t < 0.9)
	for s in shots: s.t += d
	shots = shots.filter(func(s): return s.t < s.dur)
	if combat: _danger_prev = combat.danger.duplicate()
	for b in blasts: b.t += d
	blasts = blasts.filter(func(b): return b.t < 0.35)
	for r in rings: r.t += d
	rings = rings.filter(func(r): return r.t < 0.5)
	for q in parts:
		q.t += d; q.p += q.v * d; q.v.y += 3.0 * d   # light gravity (cells/s^2)
	parts = parts.filter(func(q): return q.t < q.life)
	if vita:
		_vita_place_bake()
		_vita_mark_dirty()
		_vita_acc += d
		var due := _vita_acc >= 1.0 / 5.0
		if due:
			_vita_acc -= 1.0 / 5.0
		# 5 Hz idle bob; combat flashes/moves redraw on the dirty flag without waiting a full tick.
		if due or _vita_dirty:
			_vita_dirty = false
			queue_redraw()
			if _vita_fx != null:
				_vita_fx.queue_redraw()
		VitaBoot.add_us("grid_proc", int(Time.get_ticks_usec() - t0))
	else:
		queue_redraw()

func _vita_mark_dirty() -> void:
	if _vita_dirty:
		return
	var dk := "%s|%s|%s|%s|%s|%s|%s" % [flash.size(), floaters.size(), shots.size(), dying.size(), door_tween.size(), parts.size(), blasts.size() + rings.size()]
	var disp_bits := ""
	if combat:
		for u in combat.units:
			var p: Vector2 = disp.get(u.uid, Vector2(u.pos))
			disp_bits += "%s:%d,%d|" % [u.uid, int(round(p.x * 4.0)), int(round(p.y * 4.0))]
	if dk != _vita_disp_key or disp_bits != str(get_meta("_vita_disp_bits", "")):
		_vita_disp_key = dk
		set_meta("_vita_disp_bits", disp_bits)
		_vita_dirty = true

## Particles in cell space: n pixels flung from the centre of cell p.
func _burst(p: Vector2, c: Color, n: int, speed := 1.6, up := 0.0) -> void:
	var cap := 40 if VitaBoot.runs_on_vita() else 160
	if parts.size() > cap: return
	var count := mini(n, cap - parts.size())
	for i in count:
		var a := _rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * (0.4 + _rng.randf() * 0.6) + Vector2(0, -up - 0.6)
		parts.append({"p": p + Vector2(0.5, 0.5), "v": v, "t": 0.0, "life": 0.35 + _rng.randf() * 0.25, "c": c, "s": 1 + _rng.randi() % 2})
	if VitaBoot.runs_on_vita() and count > 0:
		_vita_dirty = true

## Light radius in cells: SPD-like torchlight that shrinks as the torch burns down; darkness = tiny radius.
func light_radius() -> float:
	var run: Dictionary = GameState.run
	if run.is_empty(): return 99.0
	if Delve.darkness(run): return 1.8
	return lerpf(3.2, 6.5, clampf(float(run.get("torch", 100.0)) / 100.0, 0.0, 1.0))

## Fit zoom only: arena + half-tile border fills the view (DECISIONS #72).
func _fit_cell_size() -> float:
	var side := float(maxi(_aw(), _ah()))
	var raw := floorf(minf(size.x, size.y) / (side + 0.3))
	return _snap_cell(raw)

## Snap a raw px/cell to SPD integer zoom (16) or 4 px steps when that wastes >15% (DECISIONS #72).
func _snap_cell(raw: float) -> float:
	if raw < 16.0: return raw
	var snapped := floorf(raw / 16.0) * 16.0
	return snapped if snapped >= raw * 0.9 else floorf(raw / 4.0) * 4.0

## Effective cell size including player zoom (DECISIONS #235).
func cell_size() -> float:
	return _snap_cell(_fit_cell_size() * zoom_mult)

## Centered origin for a given cell size (no pan).
func _centered_origin(cs: float) -> Vector2:
	var arena := Vector2(cs * _aw(), cs * _ah())
	var slack := size - arena
	# most vertical slack goes on top so the raised top wall face is visible (SPD rooms read from their top wall)
	return Vector2(slack.x / 2.0, minf(slack.y * 0.8, cs * 0.75)).floor()

## Keep the arena attached to the viewport (slide within slack when fit; fill view when zoomed in).
func clamp_pan() -> void:
	var cs := cell_size()
	var arena := Vector2(cs * _aw(), cs * _ah())
	var fo := _centered_origin(cs)
	var min_o := Vector2(minf(0.0, size.x - arena.x), minf(0.0, size.y - arena.y))
	var max_o := Vector2(maxf(0.0, size.x - arena.x), maxf(0.0, size.y - arena.y))
	pan = pan.clamp(min_o - fo, max_o - fo)

func origin() -> Vector2:
	return (_centered_origin(cell_size()) + pan).floor()

## Cell under a local screen point (fractional).
func screen_to_cell(s: Vector2) -> Vector2:
	var cs := cell_size()
	if cs <= 0.0: return Vector2.ZERO
	return (s - origin()) / cs

## Zoom so `s` (local) stays on the same cell-space point.
func zoom_at(s: Vector2, new_zoom: float) -> void:
	var cell := screen_to_cell(s)
	zoom_mult = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	var cs := cell_size()
	pan = s - cell * cs - _centered_origin(cs)
	clamp_pan()
	queue_redraw()

func cell_rect(p: Vector2) -> Rect2:
	var cs := cell_size()
	return Rect2((origin() + p * cs).floor(), Vector2(cs, cs))

func _drag_threshold() -> float:
	return clampf(UIKit.font_size * DRAG_THRESH_FS, 10.0, 16.0)

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
			# SPD HIGH_GRASS stands on the GRASS ground tile (keyed blades over short grass, not bare floor)
			if t == Combat.T.GRASS or (combat != null and combat.trampled.has(c)): return S_SHORT_GRASS_ALT if v < 50 else S_SHORT_GRASS
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
			if r != S_RAISED_WALL_DOOR and wall_deco(c): r = S_RAISED_WALL_DECO_ALT if v < 50 else S_RAISED_WALL_DECO
			if not _is_wall(c + Vector2i(1, 0)): r += 1
			if not _is_wall(c + Vector2i(-1, 0)): r += 2
			return r
	return -1

## SPD WALL_DECO on a raised wall face (drain, torch sconce, ore vein, recess, stained glass): about one face in
## six, from the room-seeded tile variance. Visual only; the arena's terrain has no deco walls of its own.
func wall_deco(c: Vector2i) -> bool:
	if c.x < 0 or c.x >= _aw() or c.y < -1 or c.y >= _ah(): return false   # only faces the player can see
	# Goo's sewer: a drain (with its drips) on every third top-wall face; Tengu's prison: a torch there instead
	if _boss in ["goo", "tengu"] and c.y == 0: return c.x % 3 == 1
	if _boss == "yog" and c.y == 0: return false    # stained glass instead
	return int(variance.get(c, 50)) % 6 == 1

func biome() -> String: return tileset.trim_prefix("tiles_")

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
	if _is_wall(below) and not _pylon(below):
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
	## Match Combat sight stamp (terrain, remains, door occupancy) so fog tracks door open/close.
	var key := [combat.hero.pos, combat._sight_stamp()]
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
	var vita_draw := VitaBoot.runs_on_vita()
	var vita_t0 := Time.get_ticks_usec() if vita_draw else 0
	if combat == null: return
	var cs := cell_size()
	var ps := cs / 16.0
	var lo := -2; var hi_x := _aw() + 1; var hi_y := _ah() + 1
	if vita_draw:
		_vita_place_bake()
	# 1. ground layer. Vita paints this once into VitaBake and then only the sprites below.
	var deco_faces := []; var wet := []
	if not vita_draw:
		for y in range(lo, hi_y + 1):
			for x in range(lo, hi_x + 1):
				var c := Vector2i(x, y)
				var t := _t(c)
				var r := cell_rect(Vector2(x, y))
				if t == Combat.T.WATER:
					var off := Vector2(anim_t * 3.0, anim_t * 1.5)   # SPD water texture scroll
					draw_texture_rect_region(water, r, Rect2(Vector2(x * 16, y * 16) + off, Vector2(16, 16)))
				var v := terrain_visual(c)
				if _pylon(c): v = S_FLOOR   # DM-300's pylons stand on the floor; the wall under them only blocks
				if v >= 0: _tile(r, v)
				if _boss != "": _boss_ground(c, r, v)
				if v - v % 4 == S_RAISED_WALL_DECO or v - v % 4 == S_RAISED_WALL_DECO_ALT: deco_faces.append([r, v])   # stitched sides (+1/+2) too
				if t == Combat.T.WATER: wet.append(r)
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
		# reach weapons (Spear, Glaive, Whip): foes 2-3 tiles away the next swing can hit (DECISIONS #207)
		if mode != "bolt" and int(combat.hero.get("reach", 1)) > 1:
			for e in combat.enemies():
				if Combat.cheb(e.pos, hp) > 1 and combat.can_melee(e):
					draw_rect(cell_rect(Vector2(e.pos)).grow(-2), Color(1, 0.4, 0.3, 0.6), false, maxf(2.0, ps))
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
	# dying and living characters share one back-to-front pass by their feet (SPD z-order)
	var actors := []
	for dd in dying: actors.append({"y": float(dd.pos.y), "dd": dd})
	if _boss == "dm300":
		for py in range(1, _ah() - 1):
			for px in range(1, _aw() - 1):
				if _pylon(Vector2i(px, py)): actors.append({"y": float(py), "pylon": Vector2i(px, py)})
	for u in order:
		if u.hp > 0: actors.append({"y": float(disp.get(u.uid, Vector2(u.pos)).y), "u": u})
	actors.sort_custom(func(a, b): return a.y < b.y)
	for ac in actors:
		if ac.has("pylon"):   # SPD PylonSprite, inactive frame (10x20), bottom-centred on its cell
			var pr := cell_rect(Vector2(ac.pylon)); var pz := Vector2(10, 20) * scale
			draw_texture_rect_region(_ct("pylon", "sprites"), Rect2(Vector2(pr.get_center().x - pz.x / 2.0, pr.end.y - pz.y - scale).floor(), pz), Rect2(0, 0, 10, 20))
			continue
		if ac.has("dd"):
			var dd: Dictionary = ac.dd
			var dk: float = 1.0 if dd.t < 0.8 else 1.0 - (dd.t - 0.8) / 0.8
			var dfr := _frame(dd.sprite, "die", dd.t)
			_draw_sprite(dd.sprite, dd.fw, dd.fh, dfr + int(dd.get("row", 0)) * 1000, dd.pos, dd.flip, scale, Color(1, 1, 1, dk))
			continue
		var u: Dictionary = ac.u
		var p := unit_draw_pos(u)
		var st: Dictionary = ustate.get(u.uid, {"anim": "idle", "t": 0.0, "flip": false})
		var fr := _frame(u.sprite, st.anim, st.t + (0.0 if st.anim != "idle" else u.uid * 0.37))
		var mod := Color(1, 1, 1)
		if u.get("charging", false): mod = Color(1.6, 0.6, 0.6)
		if u.has("hero") and combat.hidden(): mod.a = 0.45
		if not u.has("hero") and lighting and p.distance_to(hero_disp) > lr: mod = mod * Color(0.55, 0.55, 0.6)
		# SPD CharSprite.flash(): the struck sprite is drawn fully white for FLASH_INTERVAL, with no fade
		var fl := flash_white(u.uid)
		var top := _draw_sprite(u.sprite, u.fw, u.fh, fr + int(u.get("row", 0)) * 1000, p, st.flip, scale, mod, fl)
		_health_bar(u, top, scale)
		_status_icons(u, top, scale)
	# 5. walls layer over characters (SPD perspective wall tops / overhangs).
	# Vita draws walls, fog, and effects on front canvases so tops stay above sprites.
	if vita_draw:
		_last_draw_us = int(Time.get_ticks_usec() - vita_t0)
		VitaBoot.add_us("grid_draw", _last_draw_us)
		return
	if not vita_draw:
		for y in range(lo, hi_y + 1):
			for x in range(lo, hi_x + 1):
				var wv := wall_visual(Vector2i(x, y))
				if wv >= 0: _tile(cell_rect(Vector2(x, y)), wv)
		# a door held open by remains (DECISIONS #176) shows just the open door, like SPD; no bones (DECISIONS #187)
		# 5c. SPD region visuals: drips from drains, Prison wall torches, cave ore sparkles, City smoke, Halls embers.
		# Drawn under the fog, so out-of-sight walls dim like everything else.
		var bio := biome()
		for df in deco_faces:
			var fr: Rect2 = df[0]
			SceneFX.wall_visual(self, anim_t, bio, fr, int(df[1]), ps, Rect2(origin(), Vector2(_aw(), _ah()) * cs))   # halo stays off the black above
		if bio == "halls":
			for wr in wet: SceneFX.halls_stream(self, anim_t, wr, ps)
		_chasm_wind(cs, ps)
	# 6. fog of war + torchlight: smooth per-corner blend (SPD FogOfWar texture is bilinear)
	if not vita_draw and lighting and lr < 50.0:
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
	# 7. effects. Vita draws these on a front canvas, after the fog.
	_paint_effects(self)
	if vita_draw:
		_last_draw_us = int(Time.get_ticks_usec() - vita_t0)
		VitaBoot.add_us("grid_draw", _last_draw_us)

## Ground frames sit behind sprites. Wall tops, fog, and effects are later children, so they draw
## in front. A pan only moves the baked items. Water and grass are four retained frames.
## Node2D so a pan or a 1 px size jitter does not mark the canvas dirty (Control.set_size does).
func _vita_canvas(node_name: String, behind: bool) -> Node2D:
	var c := Node2D.new()
	c.name = node_name
	c.texture_filter = TEXTURE_FILTER_NEAREST
	c.show_behind_parent = behind
	add_child(c)
	return c

func _vita_place_bake() -> void:
	if combat == null or size.x < 2.0:
		return
	var cs := cell_size()
	if cs <= 0.0:
		return
	var stamp := _vita_stamp_now()
	var key := _vita_bake_key
	if _vita_frames.is_empty() or stamp != _vita_stamp:
		_vita_stamp = stamp
		key = _vita_bake_key_now()
	if _vita_frames.is_empty():
		for i in VITA_FRAME_N:
			var frame := _vita_canvas("VitaFrame%d" % i, true)
			frame.draw.connect(_vita_paint_bake.bind(i))
			_vita_frames.append(frame)
		_vita_walls = _vita_canvas("VitaWalls", false)
		_vita_walls.draw.connect(_vita_paint_walls)
		for i in VITA_FRAME_N:
			var fx := _vita_canvas("VitaWallFx%d" % i, false)
			fx.draw.connect(_vita_paint_wall_fx.bind(i))
			_vita_wall_fx.append(fx)
		_vita_fog = _vita_canvas("VitaFog", false)
		_vita_fog.draw.connect(_vita_paint_fog)
		_vita_fx = _vita_canvas("VitaFx", false)
		_vita_fx.draw.connect(_vita_paint_effects)
	var bake_pos := origin() + Vector2(VITA_BAKE_LO, VITA_BAKE_LO) * cs
	var bake_sz := Vector2((_aw() + 4) * cs, (_ah() + 4) * cs)
	for i in VITA_FRAME_N:
		if _vita_frames[i].position != bake_pos:
			_vita_frames[i].position = bake_pos
		if _vita_wall_fx[i].position != bake_pos:
			_vita_wall_fx[i].position = bake_pos
		_vita_frames[i].set_meta("vita_sz", bake_sz)
	if _vita_walls.position != bake_pos:
		_vita_walls.position = bake_pos
	if _vita_fog.position != bake_pos:
		_vita_fog.position = bake_pos
	if _vita_fx.position != Vector2.ZERO:
		_vita_fx.position = Vector2.ZERO
	if key != _vita_bake_key:
		_vita_bake_key = key
		VitaBoot.add_n("grid_bake_key_n")
		_vita_warm = 0
		for i in VITA_FRAME_N:
			_vita_frames[i].set_meta("vita_painted", false)
			_vita_wall_fx[i].set_meta("vita_painted", false)
		_vita_walls.queue_redraw()
	# Flat visibility on Vita — torch fog was rebaking every hero step (grid_fog_key_n churn).
	if _vita_fog != null and bool(_vita_fog.get_meta("vita_on", true)):
		_vita_fog.set_meta("vita_on", false)
		RenderingServer.canvas_item_set_visible(_vita_fog.get_canvas_item(), false)
	_vita_phase = posmod(int(floor(anim_t / 0.22)), VITA_FRAME_N)
	var show_i := _vita_warm if _vita_warm < VITA_FRAME_N else _vita_phase
	# visible=true repaints. The server flag swaps pre-baked water and grass frames without a rebake.
	_vita_show_baked(_vita_frames, show_i)
	_vita_show_baked(_vita_wall_fx, show_i)
	if _vita_warm < VITA_FRAME_N:
		if not _vita_frames[show_i].get_meta("vita_painted", false):
			_vita_frames[show_i].queue_redraw()
		if not _vita_wall_fx[show_i].get_meta("vita_painted", false):
			_vita_wall_fx[show_i].queue_redraw()

func _vita_show_baked(nodes: Array, show_i: int) -> void:
	for i in nodes.size():
		var node: CanvasItem = nodes[i]
		var on := i == show_i
		if node.has_meta("vita_on") and bool(node.get_meta("vita_on")) == on:
			continue
		node.set_meta("vita_on", on)
		RenderingServer.canvas_item_set_visible(node.get_canvas_item(), on)

## Cheap change detector. The full door and trap strings are walked only when this changes.
func _vita_stamp_now() -> String:
	if combat == null:
		return ""
	var tw := 0
	for k in door_tween:
		tw += 1 if float(door_tween[k].t) < MOVE_TIME * 0.45 else 10
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [
		int(round(cell_size())), tileset, _boss, combat.trampled.size(), combat.hero_turns,
		combat.traps.size(), combat.traps_found, tw]

func _vita_advance_warm(phase: int) -> void:
	if phase != _vita_warm or phase < 0 or phase >= VITA_FRAME_N:
		return
	if not _vita_frames[phase].get_meta("vita_painted", false):
		return
	if not _vita_wall_fx[phase].get_meta("vita_painted", false):
		return
	_vita_warm = phase + 1

func _vita_fog_center() -> Vector2:
	var cell := Vector2(combat.hero.pos)
	var hero: Vector2 = disp.get(combat.hero.uid, cell)
	if hero.distance_to(cell) > 0.4:
		return hero
	return cell

func _vita_bake_key_now() -> String:
	var doors := ""
	for y in combat.h:
		for x in combat.w:
			var c := Vector2i(x, y)
			if _t(c) == Combat.T.DOOR:
				doors += "%d,%d:%s|" % [x, y, _door_open(c)]
	var traps := ""
	for k in combat.traps:
		traps += "%s:%s|" % [str(k), combat.traps[k].hidden]
	return "%s|%s|%s|%s|%s|%s" % [int(round(cell_size())), tileset, _boss, combat.trampled.size(), doors, traps]

func _vita_cell(c: Vector2, cs: float) -> Rect2:
	return Rect2(Vector2((c.x - VITA_BAKE_LO) * cs, (c.y - VITA_BAKE_LO) * cs), Vector2(cs, cs))

func _vita_paint_bake(phase: int = 0) -> void:
	var t0 := Time.get_ticks_usec()
	if combat == null or phase < 0 or phase >= _vita_frames.size():
		return
	var ci: Node2D = _vita_frames[phase]
	var frame_sz: Vector2 = ci.get_meta("vita_sz", Vector2.ZERO)
	ci.draw_rect(Rect2(Vector2(-2, -2), frame_sz + Vector2(4, 4)), Color(0, 0, 0))
	var cs := cell_size()
	var ps := cs / 16.0
	var lo := VITA_BAKE_LO
	var hi_x := _aw() + 1
	var hi_y := _ah() + 1
	var off := Vector2(float(phase) * 8.0, float(phase) * 4.0)
	for y in range(lo, hi_y + 1):
		for x in range(lo, hi_x + 1):
			var c := Vector2i(x, y)
			var t := _t(c)
			var r := _vita_cell(Vector2(x, y), cs)
			if t == Combat.T.WATER:
				ci.draw_texture_rect_region(water, r, Rect2(Vector2(x * 16, y * 16) + off, Vector2(16, 16)))
			var v := terrain_visual(c)
			if _pylon(c):
				v = S_FLOOR
			if v >= 0:
				_tile(r, v, ci)
			if _boss != "":
				_boss_ground(c, r, v, ci)
			if t == Combat.T.WALL and _is_wall(c + Vector2i(0, 1)):
				_tile(r, S_WALL_INTERNAL + 15, ci)
			if t == Combat.T.GRASS:
				var sway := roundf(sin(float(phase) * TAU / 4.0 + float(x) * 0.9 + float(y) * 0.5) * 0.6) * ps
				_tile_grass(r, grass_visual(c), sway, ci)
			var go := grass_overhang(c)
			if go >= 0:
				var sway2 := 0.0
				if _t(c + Vector2i(0, 1)) == Combat.T.GRASS:
					sway2 = roundf(sin(float(phase) * TAU / 4.0 + float(x) * 0.9 + float(y + 1) * 0.5) * 0.6) * ps
				_tile(Rect2(r.position + Vector2(sway2, 0), r.size), go, ci)
	for k in combat.traps:
		if not combat.traps[k].hidden:
			var idx := int(DB.traps[combat.traps[k].id].sprite)
			ci.draw_texture_rect_region(features, _vita_cell(Vector2(k), cs), Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))
	if phase == _vita_warm:
		ci.set_meta("vita_painted", true)
		_vita_advance_warm(phase)
	VitaBoot.add_n("grid_bake_n")
	VitaBoot.add_us("grid_bake", int(Time.get_ticks_usec() - t0))

func _vita_paint_walls() -> void:
	if combat == null or _vita_walls == null:
		return
	var ci := _vita_walls
	var cs := cell_size()
	var lo := VITA_BAKE_LO
	var hi_x := _aw() + 1
	var hi_y := _ah() + 1
	for y in range(lo, hi_y + 1):
		for x in range(lo, hi_x + 1):
			var wv := wall_visual(Vector2i(x, y))
			if wv >= 0:
				_tile(_vita_cell(Vector2(x, y), cs), wv, ci)

func _vita_paint_wall_fx(phase: int) -> void:
	# Vita: skip SceneFX wall/stream overlays; static bake already has deco tiles.
	if phase < 0 or phase >= _vita_wall_fx.size():
		return
	if phase == _vita_warm:
		_vita_wall_fx[phase].set_meta("vita_painted", true)
		_vita_advance_warm(phase)

func _vita_paint_fog() -> void:
	# Torch fog disabled on Vita (hidden in _vita_place_bake); node kept for bake wiring.
	pass

func _vita_paint_effects() -> void:
	if _vita_fx == null:
		return
	_paint_effects(_vita_fx)
	if lighting and light_radius() < 50.0 and combat != null:
		var cs := cell_size()
		var hero_disp: Vector2 = disp.get(combat.hero.uid, Vector2(combat.hero.pos))
		_vita_fx.draw_circle(cell_rect(hero_disp).get_center(), cs * 0.9, Color(1.0, 0.75, 0.35, 0.07 + 0.02 * sin(anim_t * 5.0)))

func _paint_effects(dst: CanvasItem) -> void:
	var cs := cell_size()
	var ps := cs / 16.0
	for q in parts:
		var qa: float = 1.0 - float(q.t) / float(q.life)
		var px: float = maxf(2.0, ps) * float(q.s)
		dst.draw_rect(Rect2((origin() + q.p * cs).floor(), Vector2(px, px)), Color(q.c.r, q.c.g, q.c.b, qa))
	for sh in shots:
		_draw_shot(sh, cs, ps, dst)
	for b in blasts:
		var c := Color(1, 0.6, 0.1, 1.0 - b.t / 0.35) if b.get("fire", false) else Color(1, 0.3, 0.2, 1.0 - b.t / 0.35)
		if b.get("trap", false):
			c = Color(1, 0.9, 0.3, 1.0 - b.t / 0.35)
		if b.get("shock", false):
			c = Color(0.7, 0.9, 1.0, 1.0 - b.t / 0.35)
		dst.draw_rect(cell_rect(b.pos).grow(b.t * cs * 0.3), c, false, 3.0)
	for ring in rings:
		var center := cell_rect(ring.pos).get_center()
		dst.draw_arc(center, (0.5 + ring.r) * cs * clampf(ring.t / 0.4, 0, 1), 0, TAU, 48, Color(1, 0.85, 0.4, 1.0 - ring.t / 0.5), 3.0)
	var font := get_theme_default_font()
	var fs := UIKit.font_px(maxf(14, cs * 0.34))
	for floater in floaters:
		var rr := cell_rect(floater.pos)
		var w := font.get_string_size(floater.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := (rr.get_center() + Vector2(-w / 2.0, -cs * 0.25 - floater.t * cs * 0.7)).floor()
		var col: Color = floater.color
		col.a = 1.0 - maxf(0, floater.t - 0.5) / 0.4
		dst.draw_string_outline(font, p, floater.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(ps)), Color(0, 0, 0, col.a))
		dst.draw_string(font, p, floater.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Draw one sprite frame bottom-centred in its cell; returns the sprite's top-left (for bars/icons).
func _draw_sprite(spr: String, fw: int, fh: int, frame: int, p: Vector2, flip: bool, scale: float, mod: Color, white := 0.0) -> Vector2:
	var t := sprite(spr)
	var cols := maxi(1, t.get_width() / fw)
	var row := frame / 1000; frame = frame % 1000   # armor-tier row packed by the caller (SPD HeroSprite)
	var src := Rect2((frame % cols) * fw, (frame / cols + row) * fh, fw, fh)
	var dst := sprite_rect(fw, fh, p, scale)
	# mirrored in place by a canvas transform, never a negative-size rect (DECISIONS #187)
	SceneFX.blit(self, t, dst, src, mod, flip)
	if white > 0.0:   # overbright copy of the same frame: modulate > 1 saturates to white
		var f := 1.0 + 4.0 * white
		SceneFX.blit(self, t, dst, src, Color(f, f, f, white * mod.a), flip)
	return dst.position

## Where a fw x fh sprite at grid position `p` is drawn: bottom-centred on its cell, positive size, whole pixels.
## Flipped sprites use the same rect (DECISIONS #187).
func sprite_rect(fw: int, fh: int, p: Vector2, scale: float) -> Rect2:
	var sz := Vector2(fw, fh) * scale
	var cs := cell_size()
	var r := cell_rect(p)
	return Rect2((r.position + Vector2((cs - sz.x) / 2.0, cs - sz.y)).floor(), sz)

## A unit's drawn grid position: its tweened cell plus any attack lunge (0 once the lunge is over).
func unit_draw_pos(u: Dictionary) -> Vector2:
	var p: Vector2 = disp.get(u.uid, Vector2(u.pos))
	if lunge.has(u.uid): p += lunge[u.uid].dir * 0.25 * sin(lunge[u.uid].t / 0.16 * PI)
	return p

## The white hit-flash strength a unit is drawn with right now: 1 for SPD's FLASH_INTERVAL after a hit, else 0.
func flash_white(uid: int) -> float:
	return 1.0 if float(flash.get(uid, 0.0)) > 0.0 else 0.0

## SPD HealthBar: thin red bg, green hp, then blue segmented Barrier for the hero; above the sprite; mobs only when hurt.
func _health_bar(u: Dictionary, top: Vector2, scale: float) -> void:
	var is_hero := u.has("hero")
	if not is_hero and int(u.hp) >= int(u.ht): return
	var cs := cell_size()
	var w := floorf(cs * 0.75); var h := maxf(2.0, scale)
	var x := cell_rect(disp.get(u.uid, Vector2(u.pos))).position.x + floorf((cs - w) / 2.0)
	var y := top.y - h * 2.0
	draw_rect(Rect2(x - scale * 0.5, y - scale * 0.5, w + scale, h + scale), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(x, y, w, h), Color("cc0000"))
	var bar_n := int(u.barrier) if is_hero else 0
	var tot := maxf(float(u.ht), float(u.hp + bar_n))
	var hpw := floorf(w * clampf(float(u.hp) / tot, 0, 1))
	draw_rect(Rect2(x, y, hpw, h), Color("00ee00"))
	if bar_n > 0:   # blue Barrier after the green, one segment per hit it stops (DECISIONS #210)
		var segs := combat.barrier_hits() if combat != null else 1
		StatusPane.barrier_segs(self, Rect2(x, y, w, h), float(u.hp) / tot, float(u.hp + bar_n) / tot, segs, maxf(1.0, floorf(scale / 2.0)))

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


func _tile(r: Rect2, idx: int, ci: CanvasItem = null) -> void:
	(self if ci == null else ci).draw_texture_rect_region(tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

## Tall grass: bottom 6 art pixels stay put (floor), top 10 sway with the overhang.
func _tile_grass(r: Rect2, idx: int, sway: float, ci: CanvasItem = null) -> void:
	var dst: CanvasItem = self if ci == null else ci
	var sx := (idx % 16) * 16; var sy := int(idx / 16) * 16
	var ps := r.size.x / 16.0
	var floor_h := 6.0 * ps
	var blade_h := 10.0 * ps
	dst.draw_texture_rect_region(tiles, Rect2(r.position + Vector2(0, blade_h), Vector2(r.size.x, floor_h)), Rect2(sx, sy + 10, 16, 6))
	dst.draw_texture_rect_region(tiles, Rect2(r.position + Vector2(sway, 0), Vector2(r.size.x, blade_h)), Rect2(sx, sy, 16, 10))

func _gui_input(e: InputEvent) -> void:
	# Two-finger pinch (raw touches; first finger may also emulate mouse)
	if e is InputEventScreenTouch:
		_on_screen_touch(e)
		return
	if e is InputEventScreenDrag:
		_on_screen_drag(e)
		return
	if _touches.size() >= 2:
		return   # pinch owns the gesture; ignore emulated mouse
	if e is InputEventMouseButton:
		_on_mouse_button(e)
		return
	if e is InputEventMouseMotion:
		_on_mouse_motion(e)

func _on_screen_touch(e: InputEventScreenTouch) -> void:
	# Track fingers for pinch only; single-finger tap/pan goes through emulated mouse (project default).
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 2:
			_pinch_active = true
			_pressing = false
			_dragging = false
			_pan_btn = -1
			var pts: Array = _touches.values()
			var a: Vector2 = pts[0]; var b: Vector2 = pts[1]
			_pinch_start_dist = maxf(1.0, a.distance_to(b))
			_pinch_start_zoom = zoom_mult
			accept_event()
	else:
		_touches.erase(e.index)
		if _pinch_active and _touches.size() < 2:
			_pinch_active = false
			accept_event()

func _on_screen_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index): return
	_touches[e.index] = e.position
	if not _pinch_active or _touches.size() < 2: return
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]; var b: Vector2 = pts[1]
	var dist := maxf(1.0, a.distance_to(b))
	zoom_at((a + b) * 0.5, _pinch_start_zoom * (dist / _pinch_start_dist))
	accept_event()

func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				zoom_at(e.position, zoom_mult * ZOOM_WHEEL)
				accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				zoom_at(e.position, zoom_mult / ZOOM_WHEEL)
				accept_event()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_pan_btn = e.button_index
				_last_ptr = e.position
				_pressing = false
				_dragging = false
				accept_event()
			elif _pan_btn == e.button_index:
				_pan_btn = -1
				accept_event()
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pressing = true
				_dragging = false
				_press_pos = e.position
				_last_ptr = e.position
				accept_event()
			else:
				if _pressing and not _dragging:
					_emit_tap(e.position)
				_pressing = false
				_dragging = false
				accept_event()

func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _pan_btn >= 0 and (e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		pan += e.position - _last_ptr
		_last_ptr = e.position
		clamp_pan()
		queue_redraw()
		accept_event()
		return
	if _pressing and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _dragging and _press_pos.distance_to(e.position) >= _drag_threshold():
			_dragging = true
		if _dragging:
			pan += e.position - _last_ptr
			_last_ptr = e.position
			clamp_pan()
			queue_redraw()
			accept_event()

func _emit_tap(local_pos: Vector2) -> void:
	var c: Vector2 = screen_to_cell(local_pos).floor()
	var cell := Vector2i(c)
	if cell.x >= 0 and cell.y >= 0 and cell.x < _aw() and cell.y < _ah():
		tapped.emit(cell)

## SPD projectiles in flight (cell space -> screen): the spirit arrow item sprite turned along its path
## (MissileSprite; the art points up-right), MagicMissile as a bright core pouring particles, Lightning as the
## effects.png bolt strip bent at a random midpoint, DeathRay / LightRay beams that thin out as they fade.
func _draw_shot(sh: Dictionary, cs: float, ps: float, ci: CanvasItem = null) -> void:
	var dst: CanvasItem = self if ci == null else ci
	var a := cell_rect(sh.from).get_center(); var b := cell_rect(sh.to).get_center()
	var k := clampf(float(sh.t) / float(sh.dur), 0.0, 1.0)
	var px := maxf(1.0, floorf(ps))
	match String(sh.kind):
		"arrow":
			var ir := UIKit.item_rect(24)   # SPD ItemSpriteSheet.SPIRIT_ARROW
			var sz := ir.size * px
			dst.draw_set_transform(a.lerp(b, k).floor(), (b - a).angle() + PI / 4.0)
			dst.draw_texture_rect_region(sprite("items"), Rect2(-sz / 2.0, sz), ir)
			dst.draw_set_transform(Vector2.ZERO)
		"magic", "shadow":
			var col: Color = sh.col
			var c := a.lerp(b, k)
			var seed := int(float(sh.t) * 60.0)
			for i in 8:   # trail: particles left behind along the path, shrinking and fading
				var q := clampf(k - float(i) * 0.05, 0.0, 1.0)
				var j := Vector2(SceneFX._rnd(i, seed) - 0.5, SceneFX._rnd(i + 9, seed) - 0.5) * 3.0 * px
				var tc := col.lerp(Color(0, 0, 0) if sh.kind == "shadow" else Color.WHITE, SceneFX._rnd(i, 3) * 0.6); tc.a = 1.0 - float(i) / 8.0
				var ts := maxf(1.0, roundf(3.0 - float(i) * 0.3)) * px
				dst.draw_rect(Rect2((a.lerp(b, q) + j - Vector2(ts, ts) / 2.0).floor(), Vector2(ts, ts)), tc)
			dst.draw_rect(Rect2((c - Vector2(2, 2) * px).floor(), Vector2(4, 4) * px), col)
			dst.draw_rect(Rect2((c - Vector2(1, 1) * px).floor(), Vector2(2, 2) * px), Color.WHITE if sh.kind == "magic" else Color("22102e"))
		"lightning":
			var m := cell_rect(sh.mid).get_center()
			for seg in [[a, m], [m, b]]:
				var p0: Vector2 = seg[0]; var p1: Vector2 = seg[1]
				dst.draw_set_transform(p0.floor(), (p1 - p0).angle())
				dst.draw_texture_rect_region(effects, Rect2(0, -4.0 * px, p0.distance_to(p1), 8.0 * px), Rect2(16, 0, 16, 8), Color(1, 1, 1, 1.0 - k))
				dst.draw_set_transform(Vector2.ZERO)
		"deathray", "lightray":
			var h := floorf(8.0 * px * (1.0 - k))
			if h <= 0.0: return
			var src := Rect2(16, 16, 16, 8) if sh.kind == "deathray" else Rect2(16, 23, 16, 8)
			dst.draw_set_transform(a.floor(), (b - a).angle())
			dst.draw_texture_rect_region(effects, Rect2(0, -h / 2.0, a.distance_to(b) + cs * 0.5, h), src)
			dst.draw_set_transform(Vector2.ZERO)

# ---- SPD boss-room dressing (DECISIONS #185) ----
# Boss arenas keep their combat layout; only the art changes, from SPD's own custom boss tiles:
# Goo: sewer drains (WALL_DECO, dripping) along the top wall. Tengu: prison torches (WALL_DECO) there.
# DM-300: the inner pillars become CavesBossLevel pylons (PylonSprite, inactive) on their floor pads.
# King of Dwarves: CityBossLevel's 3x3 throne dais at the top of the hall and its entrance carpet running down
# to the far wall (city_boss.png), both walkable floor art like SPD's. Yog-Dzewa: HallsBossLevel stained-glass
# windows along the top wall and candle clusters (baked floor keyed out) in the corners.
func _ct(n: String, dir := "tiles") -> Texture2D:
	var key := dir + "/" + n
	if not _ctex.has(key): _ctex[key] = load("res://assets/%s/%s.png" % [dir, n])
	return _ctex[key]

func _ctile(r: Rect2, n: String, t: Vector2i, ci: CanvasItem = null) -> void:
	(self if ci == null else ci).draw_texture_rect_region(_ct(n), r, Rect2(t * 16, Vector2(16, 16)))

## A DM-300 pylon cell: an inner pillar (a wall with no wall beside it) in DM-300's arena.
func _pylon(c: Vector2i) -> bool:
	if _boss != "dm300" or c.x < 1 or c.y < 1 or c.x >= _aw() - 1 or c.y >= _ah() - 1 or not _is_wall(c): return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _is_wall(c + d): return false
	return true

## A plain top-wall face (no door, no stitched side, no deco) that a boss room may dress.
func _plain_top_face(c: Vector2i, v: int) -> bool:
	return c.y == 0 and c.x >= 1 and c.x < _aw() - 1 and v in [S_RAISED_WALL, S_RAISED_WALL_ALT]

## The King's carpet and dais with only their red cloth darkened (pixels where red clearly leads green and blue,
## times 0.5), so the red danger tiles read on top of it; the gold trim, the throne and the floor margins keep
## SPD's colours. Built once from city_boss.png and cached.
func _carpet_tex() -> Texture2D:
	if _ctex.has("carpet"): return _ctex["carpet"]
	var img: Image = _ct("city_boss").get_image()
	if img.is_compressed(): img.decompress()
	img = img.duplicate(); img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.r > c.g + 0.15 and c.r > c.b + 0.15 and c.g < 0.15:
				img.set_pixel(x, y, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, c.a))
	_ctex["carpet"] = ImageTexture.create_from_image(img)
	return _ctex["carpet"]


func _boss_ground(c: Vector2i, r: Rect2, v: int, ci: CanvasItem = null) -> void:
	var dst: CanvasItem = self if ci == null else ci
	var t := _t(c)
	match _boss:
		"yog":
			if _plain_top_face(c, v): _ctile(r, "halls_special", Vector2i(c.x % 2, 6), ci)
			var corner := (c.x == 1 or c.x == _aw() - 2) and (c.y == 1 or c.y == _ah() - 2)
			if corner and t == Combat.T.FLOOR:
				dst.draw_texture_rect_region(_keyed("halls_special", Vector2i(2 + (c.x + c.y) % 6, 5), [Vector2i(3, 1), Vector2i(5, 4)]), r, Rect2(0, 0, 16, 16))
		"king":   # the red cloth is drawn darker (_carpet_tex) so the red danger tiles still stand out on it
			var mid := _aw() / 2 - 1
			if _dais_ok() and absi(c.x - mid) <= 1 and c.y >= 1 and c.y <= 3:   # DK's throne: 3x3 at the top
				dst.draw_texture_rect_region(_carpet_tex(), r, Rect2(Vector2i(2 + c.x - mid, 12 + c.y) * 16, Vector2(16, 16)))
			elif c.x == mid and c.y >= (4 if _dais_ok() else 1) and c.y < _ah() - 1 and t == Combat.T.FLOOR:   # carpet runner
				dst.draw_texture_rect_region(_carpet_tex(), r, Rect2(Vector2i(0, 15 if c.y == _ah() - 2 else 14) * 16, Vector2(16, 16)))
		"dm300":
			if _pylon(c): _ctile(r, "caves_boss", Vector2i(5, 4), ci)   # the pylon's floor pad

## The throne dais only goes down where all nine cells are open floor.
func _dais_ok() -> bool:
	var mid := _aw() / 2 - 1
	for y in range(1, 4):
		for x in range(mid - 1, mid + 2):
			if _t(Vector2i(x, y)) != Combat.T.FLOOR: return false
	return true

## A custom tile with its baked floor keyed out: pixels in the colours of the `bg` tiles that connect to the
## border go transparent, so the arena's own floor shows round the props (the camp's _masked, DECISIONS #179).
func _keyed(n: String, t: Vector2i, bg: Array) -> Texture2D:
	var key := "%s|%s" % [n, t]
	if _ctex.has(key): return _ctex[key]
	var src: Image = _ct(n).get_image()
	if src.is_compressed(): src.decompress()
	var img := src.get_region(Rect2i(t * 16, Vector2i(16, 16))); img.convert(Image.FORMAT_RGBA8)
	var cols := {}
	for b in bg:
		for y in 16:
			for x in 16: cols[src.get_pixel(b.x * 16 + x, b.y * 16 + y).to_html()] = true
	var st := []
	for i in 16: st.append_array([Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)])
	var seen := {}
	while not st.is_empty():
		var p: Vector2i = st.pop_back()
		if seen.has(p) or p.x < 0 or p.y < 0 or p.x > 15 or p.y > 15: continue
		seen[p] = true
		if cols.has(img.get_pixel(p.x, p.y).to_html()):
			img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
			st.append_array([p + Vector2i.RIGHT, p + Vector2i.LEFT, p + Vector2i.DOWN, p + Vector2i.UP])
	var tx := ImageTexture.create_from_image(img)
	_ctex[key] = tx
	return tx

## SPD WindParticle.Wind over every pit cell the hero can see (Level.addVisuals): one faint white mote per cell
## every 2.5 s, living 1-2 s, drifting 5 px/s x its size (1-3 px) along one level-wide heading, alpha rising and
## falling to size x 0.2. Stateless: each mote is seeded by its cell and cycle, sizes are whole art pixels.
func _chasm_wind(cs: float, ps: float, ci: CanvasItem = null, at_time := -1.0, local := false) -> void:
	var dst: CanvasItem = self if ci == null else ci
	var time := anim_t if at_time < 0.0 else at_time
	var ang := float(variance.get(Vector2i(-2, -2), 0)) / 100.0 * TAU
	var dir := Vector2(cos(ang), sin(ang))
	for y in _ah():
		for x in _aw():
			var c := Vector2i(x, y)
			if _t(c) != Combat.T.CHASM or (lighting and not _visible(c)): continue
			var sd := x * 31 + y * 17
			var cyc := floorf((time + SceneFX._rnd(sd, 3) * 2.5) / 2.5)
			var age := time + SceneFX._rnd(sd, 3) * 2.5 - cyc * 2.5
			var seq := sd * 1000 + int(cyc)
			var life := 1.0 + SceneFX._rnd(seq, 5)
			if age > life: continue
			var sz := 1.0 + floorf(SceneFX._rnd(seq, 7) * 3.0)
			var p := 1.0 - age / life
			var a := (p if p < 0.5 else 1.0 - p) * sz * 0.2
			var at := Vector2(x + SceneFX._rnd(seq, 9), y + SceneFX._rnd(seq, 11)) * cs + dir * 5.0 * sz * (age - life / 2.0) * ps
			var pos := (at - Vector2(VITA_BAKE_LO, VITA_BAKE_LO) * cs) if local else (origin() + at)
			dst.draw_rect(Rect2(pos.floor(), Vector2(sz, sz) * maxf(1.0, floorf(ps))), Color(1, 1, 1, a))
