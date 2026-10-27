## CampScene: the Surface Camp drawn as a small SPD-tile clearing (DECISIONS #82, #225).
## A night sky with drifting SPD surface clouds and twinkling stars over a grass clearing with a campfire.
## All unlocked heroes sit around the fire. Facility NPCs: Blacksmith, Wandmaker, Alchemy pot (bubbling),
## Shopkeeper, Stash chest. Tap an NPC for its facility, or a hero to select them.
extends Control

signal picked(page: String)
signal hero_picked(c: String)

## Spots / seats / fire_y come from data/camp_layout.json via LiveLayout (DECISIONS #233).
var SPOTS: Array:
	get: return LiveLayout.spots
var HERO_SEATS: Array:
	get: return LiveLayout.seats
var FIRE_Y: float:
	get: return LiveLayout.fire_y
const FAC := {"Forge": "blacksmith", "Enchanter": "enchanter", "Alchemy": "alchemy", "Guild": "guild"}
var hero := "warrior"   # selected class (highlighted seat)
var t := 0.0
var tex := {}
var tiles: Texture2D
var items: Texture2D
var surface: Texture2D
var water: Texture2D
## SPD idle animations (BlacksmithSprite / WandmakerSprite / ShopkeeperSprite.java): [fps, frames]
const NPC_IDLE := {"blacksmith": [15, [0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 3]],
	"wandmaker": [10, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 3, 3, 3, 3, 2, 1]],
	"shopkeeper": [10, [1, 1, 1, 1, 1, 0, 0, 0, 0]]}
var hero_anims := {}   # class -> idle dict from anims.json
var hot := ""   # spot under the last press (highlight)

func _ready() -> void:
	name = "CampScene"
	tiles = load("res://assets/tiles/tiles_sewers.png"); items = load("res://assets/sprites/items.png")
	surface = load("res://assets/ui/surface.png"); water = load("res://assets/tiles/water0.png")
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	_shadow = load("res://assets/ui/shadow.png")
	_ground = Control.new()
	_ground.name = "CampGround"
	_ground.mouse_filter = MOUSE_FILTER_IGNORE
	_ground.texture_filter = TEXTURE_FILTER_NEAREST
	_ground.show_behind_parent = true
	_ground.z_index = -1
	_ground.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_ground.draw.connect(_paint_ground)
	add_child(_ground)
	if not LiveLayout.layout_changed.is_connected(_on_layout):
		LiveLayout.layout_changed.connect(_on_layout)
	resized.connect(_sync_ground)

var _acc := 0.0
var _shadow: Texture2D
var _star_rng := RandomNumberGenerator.new()
var _ground: Control
var _ground_key := ""
var _ground_draws := 0
var _paint: CanvasItem

func _on_layout() -> void:
	_ground_key = ""
	_sync_ground()
	queue_redraw()

func _process(d: float) -> void:
	# Camp motion (clouds, fire, stars, pot) at ~60 fps so drift and flicker stay smooth (#225).
	t += d; _acc += d
	_sync_ground()
	if _acc >= 1.0 / 60.0 and is_visible_in_tree():
		_acc = 0.0; queue_redraw()

## The grass grid does not move with the fire, stars, or clouds. One bake, then the node stays (DECISIONS #244).
func _sync_ground() -> void:
	if _ground == null: return
	var key := "%s|%s|%s" % [size, sky_height(), FIRE_Y]
	if key == _ground_key: return
	_ground_key = key
	_ground_draws += 1
	_ground.queue_redraw()

func _paint_ground() -> void:
	var t0 := Time.get_ticks_usec()
	_paint = _ground
	var kk := k(); var cs := 16.0 * kk
	var sky_h := sky_height()
	var cols := int(ceil(size.x / cs)) + 1
	var rows := int(ceil((size.y - sky_h) / cs)) + 1
	var ox := floorf((size.x - cols * cs) / 2.0)
	var fire := Vector2(size.x * 0.5, ground_y(FIRE_Y))
	_ground.draw_rect(Rect2(0, sky_h, size.x, size.y - sky_h), Color("2f4a22"))
	for y in rows:
		for x in cols:
			var rc := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var hh := (x * 73856093) ^ (y * 19349663)
			var ctr := rc.get_center()
			var path := absf(ctr.x - fire.x) < cs * 0.6 and ctr.y > fire.y
			_tile(rc, (0 if hh % 3 else 6) if path else (2 if hh % 4 else 8))
	_paint = null
	draw_us_sum += int(Time.get_ticks_usec() - t0)

func _sprite(n: String) -> Texture2D:
	if not tex.has(n): tex[n] = load("res://assets/sprites/%s.png" % n)
	return tex[n]

## Integer pixel scale: cover fits ~12×7 tiles; wide/fullscreen fits ~16×9 so the clearing is not huge.
func k() -> float:
	var wide := size.x > size.y * 1.1
	var tw := 16.0 if wide else 12.0
	var th := 9.0 if wide else 7.0
	return maxf(2.0, floorf(minf(size.x / (16.0 * tw), size.y / (16.0 * th))))

var _mask_cache := {}

## A level tile with its baked floor keyed out (DECISIONS #179): SPD draws the alchemy pot and embers on a floor
## tile, which shows as a stone/plank square on the camp grass. Pixels whose colour belongs to the `bg` tiles are
## cleared (only those connected to the border when `flood`, so the pot's own rim survives); the pot's empty
## interior is filled with `fill` (pass transparent so scrolling water can show through the rim).
func _masked(idx: int, bg: Array, flood: bool, fill := Color("3b2a1e")) -> Texture2D:
	var key := "%d|%s" % [idx, fill.to_html(true)]
	if _mask_cache.has(key): return _mask_cache[key]
	var src: Image = tiles.get_image()
	if src.is_compressed(): src.decompress()
	var img := src.get_region(Rect2i((idx % 16) * 16, (idx / 16) * 16, 16, 16)); img.convert(Image.FORMAT_RGBA8)
	var cols := {}
	for b in bg:
		for y in 16:
			for x in 16: cols[src.get_pixel((b % 16) * 16 + x, (b / 16) * 16 + y).to_html()] = true
	var inner := []
	for y in 16:
		for x in 16:
			if img.get_pixel(x, y).a < 0.5: inner.append(Vector2i(x, y))
	if flood:
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
		if fill.a > 0.01:
			for p in inner: img.set_pixel(p.x, p.y, fill)
	else:
		for y in 16:
			for x in 16:
				if cols.has(img.get_pixel(x, y).to_html()): img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tx := ImageTexture.create_from_image(img)
	_mask_cache[key] = tx
	return tx

## SPD raised terrain (DungeonTileSheet.java): the base tile sits in its cell and its OVERHANG tile is drawn in
## the cell above, so tall grass and barrels show their full height. [base, overhang]:
## RAISED_HIGH_GRASS 122 / HIGH_GRASS_OVERHANG 234, RAISED_HIGH_GRASS_ALT 125 / HIGH_GRASS_OVERHANG_ALT 237,
## RAISED_REGION_DECO 130 / REGION_DECO_OVERHANG 242, RAISED_REGION_DECO_ALT 131 / REGION_DECO_ALT_OVERHANG 243
## (the sewers' region deco is the barrel). The base's baked floor is keyed out so the camp grass shows through.
const RAISED := [[122, 234], [125, 237], [130, 242], [131, 243]]
func _raised(r: Rect2, kind: int, sway := 0.0, mod := Color.WHITE) -> void:
	var pr: Array = RAISED[kind]
	# sway moves base and overhang together, so a clump bends as one plant instead of shearing at the seam
	draw_texture_rect_region(_masked(pr[0], [0, 1, 4, 10], true), Rect2(r.position + Vector2(sway, 0), r.size), Rect2(0, 0, 16, 16), mod)
	var ti: int = pr[1]
	draw_texture_rect_region(tiles, Rect2(r.position + Vector2(sway, -r.size.y), r.size), Rect2((ti % 16) * 16, (ti / 16) * 16, 16, 16), mod)

## Night sky (DECISIONS #179): deep navy at the top to blue-purple at the horizon in 6 flat bands, each
## boundary dithered with a 4x4 Bayer pattern, rendered once per size at 1 texel per screen pixel-unit.
var _sky: ImageTexture
var _sky_key := Vector2.ZERO
const SKY_BANDS := ["0c0f26", "131733", "1b1f42", "25284f", "2f305c", "3c3a6b"]
func _sky_tex(kk: float, sky_h: float) -> ImageTexture:
	var w := int(ceil(size.x / kk)); var h := maxi(1, int(ceil(sky_h / kk)))
	if _sky != null and _sky_key == Vector2(w, h): return _sky
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var n := SKY_BANDS.size()
	for y in h:
		var f := float(y) / float(h) * float(n - 1)     # 0..n-1 down the sky
		var b := int(f); var frac := f - b
		var c0 := Color(SKY_BANDS[b]); var c1 := Color(SKY_BANDS[mini(b + 1, n - 1)])
		for x in w:
			# only the lower third of each band dithers into the next: wide flat bands, crisp pixel steps
			var tval := (float(bayer[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
			var mix := clampf((frac - 0.62) / 0.38, 0.0, 1.0)
			img.set_pixel(x, y, c1 if mix > tval else c0)
	_sky = ImageTexture.create_from_image(img); _sky_key = Vector2(w, h)
	return _sky

func _tile(r: Rect2, idx: int, tx: Texture2D = null) -> void:
	var ci: CanvasItem = _paint if _paint != null else self
	if tx is ImageTexture and tx.get_width() == 16:
		ci.draw_texture_rect_region(tx, r, Rect2(0, 0, 16, 16)); return
	ci.draw_texture_rect_region(tx if tx else tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

## Sky height: about two tiles at most, capped lower so the clearing has room for seated heroes.
func sky_height() -> float:
	return floorf(minf(size.y * 0.22, 16.0 * k() * 2.0))

## A point at fraction `fy` of the ground (0 = horizon, 1 = bottom edge).
func ground_y(fy: float) -> float:
	var top := sky_height()
	return top + (size.y - top) * fy

## On tall clearings (Fold cover / phones), pull facility y-fractions toward the fire so empty cobble
## does not dominate. `strength` < 1 softens the pull (heroes use a light pack so seats stay readable).
## Wide / near-square layouts leave spots alone.
func pack_y(fy: float, strength := 1.0) -> float:
	var gh := size.y - sky_height()
	var aspect := gh / maxf(1.0, size.x)
	var pack := clampf((aspect - 0.78) / 0.55, 0.0, 1.0) * clampf(strength, 0.0, 1.0)
	if pack <= 0.0:
		return fy
	return FIRE_Y + (fy - FIRE_Y) * lerpf(1.0, 0.58, pack)

func spot_rect(s: Array) -> Rect2:
	var kk := k()
	var sz := Vector2(s[2], s[3]) * kk * (1.5 if s[1].begins_with("_") else 2.0)
	var feet := Vector2(size.x * float(s[4]), ground_y(pack_y(float(s[5]))) - UIKit.font_size * 1.1)
	return Rect2((feet - Vector2(sz.x / 2.0, sz.y)).floor(), sz)

func _spot_label(s: Array) -> String:
	return s[6]

## Dark name plate drawn under the sprite. It has to be part of the click target: the plate hangs
## below the sprite padding, and long names (Enchanter, Alchemy) are wider than the sprite.
func label_rect(s: Array) -> Rect2:
	var sr := spot_rect(s)
	var fs := UIKit.font_px(UIKit.font_size * 0.85)
	var kk := k()
	var font := get_theme_default_font()
	var ts := font.get_string_size(_spot_label(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs) if font else Vector2(fs * 8.0, fs)
	var lp := Vector2(sr.get_center().x - ts.x / 2.0, sr.end.y + fs * 0.2).floor()
	return Rect2(lp - Vector2(kk * 2, 0), Vector2(ts.x + kk * 4, fs * 1.15))

## Which facility a point hits. The sprite and its name plate both count; a little padding is for fingers.
## When two pads overlap, the point on a sprite or plate wins over padding, then the nearer one.
func spot_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	var pad := UIKit.font_size * 0.35
	for s in SPOTS:
		var visual := spot_rect(s).merge(label_rect(s))
		if not visual.grow(pad).has_point(p): continue
		var d := visual.get_center().distance_squared_to(p)
		if not visual.has_point(p): d += 1.0e8
		if d < best_d:
			best_d = d
			best = s[0]
	return best

## Seat rect for an unlocked hero (empty if locked). Feet sit near the fire at HERO_SEATS offsets.
func hero_rect(c: String) -> Rect2:
	if not GameState.heroes.get(c, {}).get("unlocked", false): return Rect2()
	var kk := k(); var cs := 16.0 * kk
	var fire := Vector2(size.x * 0.5, ground_y(FIRE_Y))
	var hz := Vector2(12, 15) * kk * 2.0
	for seat in HERO_SEATS:
		if seat[0] != c: continue
		var feet := Vector2(fire.x + float(seat[1]) * cs, ground_y(pack_y(float(seat[2]), 0.35)) + kk * 6)
		return Rect2((feet - Vector2(hz.x / 2.0, hz.y)).floor(), hz)
	return Rect2()

## Every unlocked hero's footprint (for grass skip and draw order).
func hero_rects() -> Array:
	var out := []
	for seat in HERO_SEATS:
		var r := hero_rect(seat[0])
		if r.has_area(): out.append([String(seat[0]), r])
	return out

## Which seated hero a point hits (nearest unlocked sprite). Empty if none / on patrol (dimmed, not selectable).
func hero_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	var pad := UIKit.font_size * 0.25
	for pair in hero_rects():
		var c: String = pair[0]; var r: Rect2 = pair[1]
		if not GameState.heroes[c].get("patrol", {}).is_empty(): continue
		if not r.grow(pad).has_point(p): continue
		var d := r.get_center().distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best

## Idle frames for a class from data/anims.json (cached).
func _hero_idle(c: String) -> Dictionary:
	if not hero_anims.get("_loaded", false):
		var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/anims.json"))
		for hc in DB.heroes:
			hero_anims[hc] = all.get(hc, {}).get("idle", {"fps": 1, "frames": [0]})
		hero_anims._loaded = true
	return hero_anims.get(c, {"fps": 1, "frames": [0]})

## Scrolling water (DelveScene._water_cell style) into an arbitrary destination rect, amber-tinted for brew.
func _water_rect(dst: Rect2, o: Vector2, mod: Color) -> void:
	var kk := maxf(1.0, dst.size.x / 16.0)
	var ox := int(fposmod(o.x, 32.0)); var oy := int(fposmod(o.y, 32.0))
	var xs := [[ox, mini(16, 32 - ox), 0]]
	if 32 - ox < 16: xs.append([0, 16 - (32 - ox), 32 - ox])
	var ys := [[oy, mini(16, 32 - oy), 0]]
	if 32 - oy < 16: ys.append([0, 16 - (32 - oy), 32 - oy])
	for xp in xs:
		for yp in ys:
			draw_texture_rect_region(water,
				Rect2(dst.position + Vector2(xp[2], yp[2]) * kk, Vector2(xp[1], yp[1]) * kk),
				Rect2(xp[0], yp[0], xp[1], yp[1]), mod)

## Alchemy pot: scrolling water0 in the bowl, bubbles, then the rim (transparent interior) on top.
func _draw_pot(sr: Rect2, fire: Vector2, frad: float, flk: float) -> void:
	var kk := k()
	var pad := sr.size * 0.22
	var bowl := Rect2((sr.position + pad).floor(), (sr.size - pad * 2.0).floor())
	if bowl.has_area():
		_water_rect(bowl, Vector2(t * 6.0, t * 4.0), Color(0.92, 0.72, 0.38, 0.95))
		# rising brew bubbles inside the bowl
		for i in 5:
			var ph := t * (1.1 + 0.17 * i) + float(i) * 1.7
			var rise := fposmod(ph * 0.35, 1.0)
			var bx := bowl.position.x + bowl.size.x * (0.2 + 0.15 * i)
			var by := bowl.end.y - bowl.size.y * rise - kk
			var ba := (1.0 - rise) * 0.7
			if ba > 0.05:
				draw_rect(Rect2(Vector2(bx, by).floor(), Vector2(kk, kk)), Color(1.0, 0.95, 0.7, ba))
	var rim := _masked(64, [4, 10], true, Color(0, 0, 0, 0))
	draw_texture_rect_region(rim, sr, Rect2(0, 0, 16, 16), SceneFX.firelit(sr.get_center(), fire, frad, flk))

## Shadow + sprite for a facility spot (firelit). Drawn before the night pass, then again after raised grass.
func _draw_spot_sprite(s: Array, fire: Vector2, frad: float, flk: float) -> void:
	var kk := k()
	var sr := spot_rect(s)
	draw_texture_rect_region(_shadow, Rect2(sr.position.x + sr.size.x * 0.1, sr.end.y - kk * 3, sr.size.x * 0.8, kk * 5), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.6))
	if hot == s[0]: draw_rect(sr.grow(kk * 2), Color(1, 1, 0.6, 0.18))
	match s[1]:
		"_pot":
			_draw_pot(sr, fire, frad, flk)
		"_chest":
			var cr := UIKit.item_rect(36); var cz := cr.size * floorf(sr.size.x / 16.0)
			draw_texture_rect_region(items, Rect2((sr.get_center() - cz / 2.0).floor(), cz), cr, SceneFX.firelit(sr.get_center(), fire, frad, flk))
		_:
			var fw: int = s[2]
			var an: Array = NPC_IDLE[s[1]]; var fl: Array = an[1]
			var frame: int = fl[int((t + s[4] * 3.0) * float(an[0])) % fl.size()]
			draw_texture_rect_region(_sprite(s[1]), sr, Rect2(frame * fw, 0, fw, s[3]), SceneFX.firelit(sr.get_center(), fire, frad, flk))

## Draw one seated hero (idle, firelit). Patrol heroes are dimmed; the selected one gets a soft highlight.
func _draw_hero(c: String, r: Rect2, fire: Vector2, frad: float, flk: float) -> void:
	var kk := k()
	var hs := _sprite(c)
	var idle := _hero_idle(c)
	var hfl: Array = idle.frames
	var phase := float(["warrior", "mage", "rogue", "huntress"].find(c))
	var hf := int(hfl[int(t * float(idle.fps) + phase) % hfl.size()])
	var cols_h := int(hs.get_width() / 12)
	var src := Rect2((hf % cols_h) * 12, (hf / cols_h + GameState.armor_tier(c)) * 15, 12, 15)
	draw_texture_rect_region(_shadow, Rect2(r.position.x + r.size.x * 0.1, r.end.y - kk * 3, r.size.x * 0.8, kk * 5), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.55))
	var mod := SceneFX.firelit(r.get_center(), fire, frad, flk)
	if not GameState.heroes[c].get("patrol", {}).is_empty():
		mod = Color(mod.r * 0.45, mod.g * 0.45, mod.b * 0.5, 0.75)
	elif c == hero:
		draw_rect(r.grow(kk * 1.5), Color(1, 0.9, 0.4, 0.16))
		mod = Color(minf(1.0, mod.r * 1.12), minf(1.0, mod.g * 1.1), minf(1.0, mod.b * 1.05), mod.a)
	draw_texture_rect_region(hs, r, src, mod)

var draw_n := 0
var draw_us_sum := 0

func _draw() -> void:
	var _t0 := Time.get_ticks_usec()
	var kk := k(); var cs := 16.0 * kk
	var sky_h := sky_height()
	# night sky + twinkling stars + drifting SPD clouds (surface.png 88,0 / 88,20 / 88,42). Firelight stays off the sky (#225).
	draw_texture_rect(_sky_tex(kk, sky_h), Rect2(0, 0, size.x, sky_h), false)
	var r := _star_rng; r.seed = 7
	for i in 40:
		var p := Vector2(r.randf() * size.x, r.randf() * sky_h * 0.9)
		var base := 0.45 + 0.55 * r.randf()
		var phase := r.randf() * TAU
		# Faster, deeper pulse so twinkle reads at a glance (every 3rd star blinks harder).
		var w := 2.8 + r.randf() * 4.2
		var pulse := 0.5 + 0.5 * sin(t * w + phase)
		if i % 3 == 0: pulse = pulse * pulse * pulse
		var a := base * (0.12 + 0.88 * pulse)
		if a > 0.08:
			draw_rect(Rect2(p.floor(), Vector2(kk, kk)), Color(1, 1, 0.9, a))
	for i in 3:
		var cl: Rect2 = [Rect2(88, 0, 49, 20), Rect2(88, 20, 49, 22), Rect2(88, 42, 50, 18)][i]
		var span := size.x + cl.size.x * kk
		var drift := t * (5.0 + float(i) * 2.0) * kk   # ~5–9 px/s at scale 1; slow drift
		var cx: float = fposmod(size.x * 0.06 + i * size.x / 2.5 + drift, span) - cl.size.x * kk
		var cy := minf(4 * kk + i * 9 * kk, sky_h - cl.size.y * kk * 0.75)
		draw_texture_rect_region(surface, Rect2(Vector2(cx, cy).floor(), cl.size * kk * 0.75), cl, Color(1, 1, 1, 0.55))
	# ground: grass with alternates, a stone path to the fire, tall grass along the horizon
	var fire := Vector2(size.x * 0.5, ground_y(FIRE_Y))
	var seats: Array = hero_rects()
	# raised grass after the night pass (not darkened twice); never over NPCs, barrels, or seated heroes
	var grass: Array = grass_clumps(seats)
	_scenery(kk, cs, fire)
	# campfire: SPD embers tile under a FlameParticle fire with sparks and smoke, and a flickering warm glow
	var fr := Rect2((fire - Vector2(cs, cs) / 2.0).floor(), Vector2(cs, cs))
	var flk := SceneFX.flicker(t)
	var ground := Rect2(0, sky_h, size.x, size.y - sky_h)   # firelight and fire particles stay off the sky
	SceneFX.glow(self, fire, cs * 2.6 * flk, Color(1.0, 0.55, 0.2, 0.22), ground)
	_tile(fr, 3, _masked(3, [0, 1, 2, 6, 8], false))   # SPD embers with the stone floor keyed out: specks on the grass
	SceneFX.fire(self, fire + Vector2(0, kk * 4), kk, t, 14.0, true, 2.2, sky_h)
	var frad := minf(size.x, size.y - sky_h) * 0.75   # firelight reach: warm amber flicker on nearby sprites
	for pair in seats:
		_draw_hero(pair[0], pair[1], fire, frad, flk)
	var font := get_theme_default_font()
	var fs := UIKit.font_px(UIKit.font_size * 0.85)
	for s in SPOTS:
		_draw_spot_sprite(s, fire, frad, flk)
	# night: the clearing darkens away from the fire, the sky stays readable (DECISIONS #179)
	SceneFX.darkness(self, Rect2(0, sky_h, size.x, size.y - sky_h), fire, minf(size.x, size.y - sky_h) * 0.62 * flk, 0.5)
	SceneFX.glow(self, fire, cs * 1.2 * flk, Color(1.0, 0.7, 0.3, 0.12), ground)
	_fireflies(kk, cs, sky_h)
	# grass blades over the darkened ground, lit at half the night's strength (the floor keeps the full darkening)
	var lrad := minf(size.x, size.y - sky_h) * 0.62   # unflickered: the horizon tops sit in the sky and stay static
	for g in grass:
		var gc: Vector2 = (g[0] as Rect2).get_center()
		var d := clampf((gc.distance_to(fire) / lrad - 0.3) / 0.65, 0.0, 1.0)
		var v := 1.0 - 0.5 * d * 0.5
		_raised(g[0], g[1], g[2], Color(v, v, v))
	# raised tiles can overlap wide sprites on neighbor columns; paint props and characters again
	for b in _barrels(cs): _raised(b[0], b[1])
	for pair in seats:
		_draw_hero(pair[0], pair[1], fire, frad, flk)
	for s in SPOTS:
		_draw_spot_sprite(s, fire, frad, flk)
	for s in SPOTS:
		var sr := spot_rect(s)
		# name plate: SPD-ish yellow text with a dark backing
		var lbl := _spot_label(s)
		var lr := label_rect(s)
		draw_rect(lr, Color(0, 0, 0, 0.55))
		draw_string(font, lr.position + Vector2(kk * 2, fs * 0.9), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffff44") if _has_news(s[0]) else Color.WHITE)
		if FAC.has(s[0]):   # facility level: small dark badge on the sprite's top-left corner
			var bfs := UIKit.font_px(UIKit.font_size * 0.75)
			var lv := str(GameState.facility_level(FAC[s[0]]))
			var tw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x if font else bfs * 0.6
			var br := Rect2((sr.position - Vector2(kk * 2, kk * 2)).floor(), Vector2(tw + kk * 4, bfs * 1.1).floor())
			draw_rect(br, Color(0, 0, 0, 0.7)); draw_rect(br, Color("ffd27a"), false, maxf(1.0, kk * 0.5))
			draw_string(font, br.position + Vector2(kk * 2, bfs * 0.85), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color("ffd27a"))
		if _has_news(s[0]):   # "!" badge: upgrade affordable, or Scroll unlock ready (POLISH #37)
			var bp := Vector2(sr.end.x - kk * 2, sr.position.y - kk * 2)
			draw_circle(bp, kk * 3.5, Color("ff5a2a")); draw_string(font, bp + Vector2(-fs * 0.18, fs * 0.33), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# Live Editor layout selection (DECISIONS #233): bright outline while editing.
	if LiveLayout.editing and LiveLayout.sel_kind != "":
		var hr := _live_sel_rect()
		if hr.has_area():
			draw_rect(hr.grow(kk * 2), Color(0.2, 0.9, 1.0, 0.2))
			draw_rect(hr.grow(kk * 2), Color(0.3, 0.95, 1.0, 0.95), false, maxf(2.0, kk * 0.75))
	draw_n += 1
	draw_us_sum += int(Time.get_ticks_usec() - _t0)

## Rect for the Live Editor's current camp selection (empty if none / not on this scene).
func _live_sel_rect() -> Rect2:
	match LiveLayout.sel_kind:
		"fire":
			var f := Vector2(size.x * 0.5, ground_y(FIRE_Y))
			var cs := 16.0 * k()
			return Rect2((f - Vector2(cs, cs) / 2.0).floor(), Vector2(cs, cs))
		"spot":
			for s in SPOTS:
				if s[0] == LiveLayout.sel_id:
					return spot_rect(s).merge(label_rect(s))
		"seat":
			var r := hero_rect(LiveLayout.sel_id)
			if r.has_area(): return r
			for s in HERO_SEATS:
				if s[0] != LiveLayout.sel_id: continue
				var kk2 := k(); var cs2 := 16.0 * kk2
				var fire2 := Vector2(size.x * 0.5, ground_y(FIRE_Y))
				var hz := Vector2(12, 15) * kk2 * 2.0
				var feet := Vector2(fire2.x + float(s[1]) * cs2, ground_y(pack_y(float(s[2]), 0.35)) + kk2 * 6)
				return Rect2((feet - Vector2(hz.x / 2.0, hz.y)).floor(), hz)
	return Rect2()

## Props from the SPD sewers sheet: barrels (raised, transparent) beside the Guild and the Forge.
## [cell rect, raised kind]; the barrel's top is drawn in the cell above.
func _barrels(cs: float) -> Array:
	var kk := k(); var out := []
	for sp in SPOTS:
		var sr := spot_rect(sp)
		match sp[0]:
			"Guild":
				out.append([Rect2(Vector2(sr.position.x - cs * 1.9 - kk * 2, sr.end.y - cs * 0.9).floor(), Vector2(cs, cs)), 3])
				out.append([Rect2(Vector2(sr.position.x - cs - kk * 2, sr.end.y - cs).floor(), Vector2(cs, cs)), 2])
			"Forge":
				out.append([Rect2(Vector2(sr.position.x - cs - kk * 2, sr.end.y - cs).floor(), Vector2(cs, cs)), 2])
	return out

func _scenery(_kk: float, cs: float, _fire: Vector2) -> void:
	for b in _barrels(cs): _raised(b[0], b[1])

## Every prop's full footprint (its cell plus the overhang cell above), for keeping grass off props.
func _prop_rects(cs: float) -> Array:
	var out := []
	for b in _barrels(cs): out.append((b[0] as Rect2).grow_individual(0, cs, 0, 0))
	return out

## A grass clump spans its cell and the cell above (overhang): true if that touches any prop footprint.
func _hits_prop(rc: Rect2, cs: float, props: Array) -> bool:
	var span := Rect2(rc.position - Vector2(0, cs), Vector2(cs, cs * 2.0)).grow(-1.0)
	return props.any(func(p): return (p as Rect2).intersects(span))

## True when a clearing tuft would cover an NPC (horizon grass uses draw-order instead).
func _hits_spot(rc: Rect2, cs: float) -> bool:
	var span := Rect2(rc.position - Vector2(0, cs), Vector2(cs, cs * 2.0))
	return SPOTS.any(func(sp): return spot_rect(sp).merge(label_rect(sp)).grow(cs * 0.3).intersects(span))

## Raised grass clumps: [base rect, kind, sway]. Horizon is a full row (characters redrawn on top);
## clearing tufts stay off the path, NPCs, barrels, and seated heroes.
## `seats` is [[class, Rect2], ...] from hero_rects(); also accepts a bare Rect2 for older callers.
func grass_clumps(seats = null) -> Array:
	var kk := k(); var cs := 16.0 * kk
	var sky_h := sky_height()
	var cols := int(ceil(size.x / cs)) + 1
	var rows := int(ceil((size.y - sky_h) / cs)) + 1
	var ox := floorf((size.x - cols * cs) / 2.0)
	var fire := Vector2(size.x * 0.5, ground_y(FIRE_Y))
	var footprints: Array = []
	if seats is Rect2:
		if (seats as Rect2).has_area(): footprints.append(seats)
	elif seats is Array:
		for pair in seats:
			if pair is Rect2: footprints.append(pair)
			elif pair is Array and pair.size() >= 2: footprints.append(pair[1])
	else:
		for pair in hero_rects(): footprints.append(pair[1])
	var props := _prop_rects(cs)
	var grass := []
	# full horizon of SPD raised high grass; NPCs/barrels/heroes are painted after this pass
	for x in cols:
		var hr := Rect2(ox + x * cs, sky_h, cs, cs)
		grass.append([hr, 0 if (x * 7) % 3 else 1, 0.0])
	for y in rows:
		for x in cols:
			var h2 := absi((x * 2654435761) ^ (y * 40503) ^ 0x5bd1)
			var rc2 := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var c2 := rc2.get_center()
			if absf(c2.x - fire.x) < cs * 1.6 or y == 0: continue
			var span := Rect2(rc2.position - Vector2(0, cs), Vector2(cs, cs * 2.0))
			var on_hero := footprints.any(func(hr2): return (hr2 as Rect2).grow(cs * 0.3).intersects(span))
			if _hits_spot(rc2, cs) or _hits_prop(rc2, cs, props) or on_hero: continue
			if h2 % 9 == 0:
				grass.append([rc2, h2 & 1, roundf(sin(t * 1.6 + x * 0.9 + y)) * kk])
	return grass

## Badge rule: facility upgrade affordable, Scroll unlock affordable (POLISH #37), or an identification is finished.
func _has_news(page: String) -> bool:
	if FAC.has(page):
		var id: String = FAC[page]
		if GameState.can_upgrade_facility(id) == "": return true
		var need := GameState.sou_cap_cost(id)
		if need > 0 and GameState.mat("scroll_upgrade") >= need: return true
	if page == "Enchanter": return GameState.id_queue.any(func(q): return float(q.ready_at) <= GameState.now())
	return false

func _gui_input(e: InputEvent) -> void:
	if LiveLayout.camp_input(self, e):
		accept_event()
		return
	var press: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if not press: return
	# Heroes take priority when the tap is on a seat so overlapping pads don't open a facility by mistake.
	var hc := hero_at(e.position)
	if hc != "":
		Sfx.play("click"); hero_picked.emit(hc); accept_event(); return
	var page := spot_at(e.position)
	if page == "": return
	hot = page; Sfx.play("click"); picked.emit(page); accept_event()


## Night idle life: a few fireflies over the clearing, one art pixel of SPD's torch-halo yellow (0xFFFFCC) with a
## faint halo, wandering slowly and blinking. They stay below the horizon grass (sky animates separately).
func _fireflies(kk: float, cs: float, sky_h: float) -> void:
	var ground := Rect2(0, sky_h + cs * 1.5, size.x, size.y - sky_h - cs * 1.5)
	if not ground.has_area(): return
	for i in 8:
		var a := float(i) * 2.399
		var blink := sin(t * (0.7 + 0.13 * i) + a * 3.0)
		if blink <= 0.0: continue
		var al := blink
		var p := ground.position + Vector2((0.5 + 0.45 * sin(t * 0.11 + a * 5.0) * cos(t * 0.07 + a)) * ground.size.x,
			(0.5 + 0.42 * sin(t * 0.09 + a * 7.0)) * ground.size.y)
		p = (p / kk).floor() * kk
		SceneFX.glow(self, p + Vector2(kk, kk) / 2.0, kk * 4.0, Color(1.0, 1.0, 0.8, 0.18 * al), ground)
		draw_rect(Rect2(p, Vector2(kk, kk)), Color(1.0, 1.0, 0.8, 0.9 * al))
