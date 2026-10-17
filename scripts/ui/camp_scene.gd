## CampScene: the Surface Camp drawn as a small SPD-tile clearing (DECISIONS #82).
## A night sky with SPD's surface clouds over a grass clearing with a campfire. Facility NPCs stand around it:
## Blacksmith (Forge), Wandmaker (Enchanter), Alchemy pot, Shopkeeper (Guild) and the Stash chest.
## Tap an NPC to open its facility window. Everything is drawn in _draw at an integer pixel scale.
extends Control

signal picked(page: String)

const SPOTS := [   # page, sprite, frame w, frame h, x frac, y frac of the ground (feet), label
	["Forge", "blacksmith", 13, 16, 0.17, 0.42, "Forge"],
	["Enchanter", "wandmaker", 12, 14, 0.83, 0.42, "Enchanter"],
	["Alchemy", "_pot", 16, 16, 0.18, 0.97, "Alchemy"],
	["Guild", "shopkeeper", 14, 14, 0.82, 0.97, "Guild"],
	["Stash", "_chest", 16, 16, 0.50, 0.97, "Stash"],
]
const FIRE_Y := 0.5   # campfire height, as a fraction of the ground
const FAC := {"Forge": "blacksmith", "Enchanter": "enchanter", "Alchemy": "alchemy", "Guild": "guild"}
var hero := "warrior"
var t := 0.0
var tex := {}
var tiles: Texture2D
var items: Texture2D
var surface: Texture2D
## SPD idle animations (BlacksmithSprite / WandmakerSprite / ShopkeeperSprite.java): [fps, frames]
const NPC_IDLE := {"blacksmith": [15, [0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 3]],
	"wandmaker": [10, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 3, 3, 3, 3, 2, 1]],
	"shopkeeper": [10, [1, 1, 1, 1, 1, 0, 0, 0, 0]]}
var hero_anim := {}
var hot := ""   # spot under the last press (highlight)

func _ready() -> void:
	tiles = load("res://assets/tiles/tiles_sewers.png"); items = load("res://assets/sprites/items.png")
	surface = load("res://assets/ui/surface.png")
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true

var _acc := 0.0
func _process(d: float) -> void:
	# Perf (DECISIONS #88): the scene's pixel animations run at ~15 fps, so redraw at 15 fps, not every frame
	t += d; _acc += d
	if _acc >= 1.0 / 15.0 and is_visible_in_tree():
		_acc = 0.0; queue_redraw()

func _sprite(n: String) -> Texture2D:
	if not tex.has(n): tex[n] = load("res://assets/sprites/%s.png" % n)
	return tex[n]

## Integer pixel scale: the clearing is ~11 tiles wide, and the scale is never below 2.
func k() -> float:
	return maxf(2.0, floorf(minf(size.x / (16.0 * 11.0), size.y / (16.0 * 6.0))))

var _mask_cache := {}

## A level tile with its baked floor keyed out (DECISIONS #179): SPD draws the alchemy pot and embers on a floor
## tile, which shows as a stone/plank square on the camp grass. Pixels whose colour belongs to the `bg` tiles are
## cleared (only those connected to the border when `flood`, so the pot's own rim survives); the pot's empty
## interior is filled with a dark brew colour. Returned as a 16x16 texture at the tile's position (0,0).
func _masked(idx: int, bg: Array, flood: bool) -> Texture2D:
	if _mask_cache.has(idx): return _mask_cache[idx]
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
		for p in inner: img.set_pixel(p.x, p.y, Color("3b2a1e"))
	else:
		for y in 16:
			for x in 16:
				if cols.has(img.get_pixel(x, y).to_html()): img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tx := ImageTexture.create_from_image(img)
	_mask_cache[idx] = tx
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
	if tx is ImageTexture and tx.get_width() == 16:
		draw_texture_rect_region(tx, r, Rect2(0, 0, 16, 16)); return
	draw_texture_rect_region(tx if tx else tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

## Sky height: about two tiles at most, so a short panel is mostly ground where the NPCs stand.
func sky_height() -> float:
	return floorf(minf(size.y * 0.28, 16.0 * k() * 2.5))

## A point at fraction `fy` of the ground (0 = horizon, 1 = bottom edge).
func ground_y(fy: float) -> float:
	var top := sky_height()
	return top + (size.y - top) * fy

func spot_rect(s: Array) -> Rect2:
	var kk := k()
	var sz := Vector2(s[2], s[3]) * kk * (1.5 if s[1].begins_with("_") else 2.0)
	var feet := Vector2(size.x * float(s[4]), ground_y(float(s[5])) - UIKit.font_size * 1.1)
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

func _draw() -> void:
	var kk := k(); var cs := 16.0 * kk
	var sky_h := sky_height()
	# night sky + stars + drifting SPD clouds (surface.png 88,0 / 88,20 / 88,42)
	draw_texture_rect(_sky_tex(kk, sky_h), Rect2(0, 0, size.x, sky_h), false)
	var r := RandomNumberGenerator.new(); r.seed = 7
	for i in 40:
		var p := Vector2(r.randf() * size.x, r.randf() * sky_h * 0.9)
		# static sky (DECISIONS #181): each star keeps one brightness, nothing in the sky changes with time
		draw_rect(Rect2(p.floor(), Vector2(kk, kk)), Color(1, 1, 0.9, 0.35 + 0.5 * r.randf()))
	for i in 3:
		var cl: Rect2 = [Rect2(88, 0, 49, 20), Rect2(88, 20, 49, 22), Rect2(88, 42, 50, 18)][i]
		var cx: float = fmod(size.x * 0.06 + i * size.x / 2.5, size.x + cl.size.x * kk) - cl.size.x * kk   # fixed, no drift
		draw_texture_rect_region(surface, Rect2(Vector2(cx, minf(4 * kk + i * 9 * kk, sky_h - cl.size.y * kk * 0.75)).floor(), cl.size * kk * 0.75), cl, Color(1, 1, 1, 0.55))
	# ground: grass with alternates, a stone path to the fire, tall grass along the horizon
	var cols := int(ceil(size.x / cs)) + 1
	var rows := int(ceil((size.y - sky_h) / cs)) + 1
	var ox := floorf((size.x - cols * cs) / 2.0)
	var fire := Vector2(size.x * 0.5, ground_y(FIRE_Y))
	draw_rect(Rect2(0, sky_h, size.x, size.y - sky_h), Color("2f4a22"))
	for y in rows:
		for x in cols:
			var rc := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var h := (x * 73856093) ^ (y * 19349663)
			var ctr := rc.get_center()
			var path := absf(ctr.x - fire.x) < cs * 0.6 and ctr.y > fire.y
			_tile(rc, (0 if h % 3 else 6) if path else (2 if h % 4 else 8))
	var props := _prop_rects(cs)   # barrels: base cell + the cell its top reaches into
	# horizon: a row of SPD raised high grass (DECISIONS #179) whose tops reach up into the sky
	var grass := []   # [rect, kind, sway]: drawn after the night pass so the blades are not darkened twice
	for x in cols:
		var hr := Rect2(ox + x * cs, sky_h, cs, cs)
		if not _hits_prop(hr, cs, props): grass.append([hr, 0 if (x * 7) % 3 else 1, 0.0])
	# scenery (DECISIONS #179): SPD grass tufts and tall grass sway around the clearing, barrels by the Guild
	# and the Forge, all from the sewers tile sheet; kept off the path and the NPC spots
	for y in rows:
		for x in cols:
			var h2 := absi((x * 2654435761) ^ (y * 40503) ^ 0x5bd1)
			var rc2 := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var c2 := rc2.get_center()
			if absf(c2.x - fire.x) < cs * 1.6 or y == 0: continue
			# the clump covers its cell and the cell above (overhang) and is drawn over the NPCs: keep both clear
			var span := Rect2(rc2.position - Vector2(0, cs), Vector2(cs, cs * 2.0))
			if SPOTS.any(func(sp): return spot_rect(sp).merge(label_rect(sp)).grow(cs * 0.3).intersects(span)): continue
			if _hits_prop(rc2, cs, props): continue
			if h2 % 9 == 0:   # tall grass clump: SPD raised high grass, top half in the cell above
				grass.append([rc2, h2 & 1, roundf(sin(t * 1.6 + x * 0.9 + y)) * kk])
	_scenery(kk, cs, fire)
	# campfire: SPD embers tile under a FlameParticle fire with sparks and smoke, and a flickering warm glow
	var fr := Rect2((fire - Vector2(cs, cs) / 2.0).floor(), Vector2(cs, cs))
	var flk := SceneFX.flicker(t)
	var ground := Rect2(0, sky_h, size.x, size.y - sky_h)   # firelight and fire particles stay off the sky
	SceneFX.glow(self, fire, cs * 2.6 * flk, Color(1.0, 0.55, 0.2, 0.22), ground)
	_tile(fr, 3, _masked(3, [0, 1, 2, 6, 8], false))   # SPD embers with the stone floor keyed out: specks on the grass
	SceneFX.fire(self, fire + Vector2(0, kk * 4), kk, t, 14.0, true, 2.2, sky_h)
	# the selected hero rests by the fire (idle frame 0)
	var hs := _sprite(hero)
	var hz := Vector2(12, 15) * kk * 2.0
	if hero_anim.get("_for", "") != hero:   # hero idle from data/anims.json (generated from the SPD *Sprite.java)
		var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/anims.json"))
		hero_anim = all.get(hero, {}).get("idle", {"fps": 1, "frames": [0]}); hero_anim._for = hero
	var hfl: Array = hero_anim.frames; var hf := int(hfl[int(t * float(hero_anim.fps)) % hfl.size()])
	var cols_h := int(hs.get_width() / 12)
	var frad := minf(size.x, size.y - sky_h) * 0.75   # firelight reach: warm amber flicker on nearby sprites
	var hr := Rect2(Vector2(fire.x + cs * 0.9, fire.y + kk * 6 - hz.y).floor(), hz)
	draw_texture_rect_region(hs, hr, Rect2((hf % cols_h) * 12, (hf / cols_h + GameState.armor_tier(hero)) * 15, 12, 15), SceneFX.firelit(hr.get_center(), fire, frad, flk))
	# facilities
	var font := get_theme_default_font()
	var fs := UIKit.font_px(UIKit.font_size * 0.85)
	for s in SPOTS:
		var sr := spot_rect(s)
		draw_texture_rect_region(load("res://assets/ui/shadow.png"), Rect2(sr.position.x + sr.size.x * 0.1, sr.end.y - kk * 3, sr.size.x * 0.8, kk * 5), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.6))
		if hot == s[0]: draw_rect(sr.grow(kk * 2), Color(1, 1, 0.6, 0.18))
		match s[1]:
			"_pot": draw_texture_rect_region(_masked(64, [4, 10], true), sr, Rect2(0, 0, 16, 16), SceneFX.firelit(sr.get_center(), fire, frad, flk))   # pot without its baked plank floor
			"_chest":   # trimmed SPD frame, centred on whole pixels (DECISIONS #89)
				var cr := UIKit.item_rect(36); var cz := cr.size * floorf(sr.size.x / 16.0)
				draw_texture_rect_region(items, Rect2((sr.get_center() - cz / 2.0).floor(), cz), cr, SceneFX.firelit(sr.get_center(), fire, frad, flk))
			_:
				var fw: int = s[2]
				var an: Array = NPC_IDLE[s[1]]; var fl: Array = an[1]
				var frame: int = fl[int((t + s[4] * 3.0) * float(an[0])) % fl.size()]
				draw_texture_rect_region(_sprite(s[1]), sr, Rect2(frame * fw, 0, fw, s[3]), SceneFX.firelit(sr.get_center(), fire, frad, flk))
	# night: the clearing darkens away from the fire, the sky stays readable (DECISIONS #179)
	SceneFX.darkness(self, Rect2(0, sky_h, size.x, size.y - sky_h), fire, minf(size.x, size.y - sky_h) * 0.62 * flk, 0.5)
	SceneFX.glow(self, fire, cs * 1.2 * flk, Color(1.0, 0.7, 0.3, 0.12), ground)
	# grass blades over the darkened ground, lit at half the night's strength (the floor keeps the full darkening)
	var lrad := minf(size.x, size.y - sky_h) * 0.62   # unflickered: the horizon tops sit in the sky and stay static
	for g in grass:
		var gc: Vector2 = (g[0] as Rect2).get_center()
		var d := clampf((gc.distance_to(fire) / lrad - 0.3) / 0.65, 0.0, 1.0)
		var v := 1.0 - 0.5 * d * 0.5
		_raised(g[0], g[1], g[2], Color(v, v, v))
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
		if _has_news(s[0]):   # "!" badge: something ready (identified item, affordable upgrade)
			var bp := Vector2(sr.end.x - kk * 2, sr.position.y - kk * 2)
			draw_circle(bp, kk * 3.5, Color("ff5a2a")); draw_string(font, bp + Vector2(-fs * 0.18, fs * 0.33), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

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

## Badge rule: a facility upgrade is affordable, or an identification is finished.
func _has_news(page: String) -> bool:
	if FAC.has(page) and GameState.can_upgrade_facility(FAC[page]) == "": return true
	if page == "Enchanter": return GameState.id_queue.any(func(q): return float(q.ready_at) <= GameState.now())
	return false

func _gui_input(e: InputEvent) -> void:
	var press: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if not press: return
	var page := spot_at(e.position)
	if page == "": return
	hot = page; Sfx.play("click"); picked.emit(page); accept_event()
