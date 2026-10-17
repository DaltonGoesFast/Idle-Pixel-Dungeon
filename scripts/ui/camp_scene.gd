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

func _tile(r: Rect2, idx: int, tx: Texture2D = null) -> void:
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
	draw_rect(Rect2(0, 0, size.x, sky_h), Color("1d2342"))
	draw_rect(Rect2(0, sky_h * 0.55, size.x, sky_h * 0.45), Color("2b3157"))
	var r := RandomNumberGenerator.new(); r.seed = 7
	for i in 40:
		var p := Vector2(r.randf() * size.x, r.randf() * sky_h * 0.9)
		var tw := 0.5 + 0.5 * sin(t * 2.0 + i)
		draw_rect(Rect2(p.floor(), Vector2(kk, kk)), Color(1, 1, 0.9, 0.35 + 0.5 * tw))
	for i in 3:
		var cl: Rect2 = [Rect2(88, 0, 49, 20), Rect2(88, 20, 49, 22), Rect2(88, 42, 50, 18)][i]
		var cx: float = fmod(t * (6.0 + i * 3.0) * kk / 3.0 + i * size.x / 2.5, size.x + cl.size.x * kk) - cl.size.x * kk
		draw_texture_rect_region(surface, Rect2(Vector2(cx, 4 * kk + i * 9 * kk).floor(), cl.size * kk * 0.75), cl, Color(1, 1, 1, 0.55))
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
			if y == 0: _tile(rc, 122 if h % 2 else 125)
	# scenery (DECISIONS #179): SPD grass tufts and tall grass sway around the clearing, barrels by the Guild
	# and the Forge, all from the sewers tile sheet; kept off the path and the NPC spots
	for y in rows:
		for x in cols:
			var h2 := absi((x * 2654435761) ^ (y * 40503) ^ 0x5bd1)
			var rc2 := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var c2 := rc2.get_center()
			if absf(c2.x - fire.x) < cs * 1.6 or y == 0: continue
			if SPOTS.any(func(sp): return spot_rect(sp).grow(cs * 0.4).has_point(c2)): continue
			if h2 % 7 == 0:
				var sway := roundf(sin(t * 1.6 + x * 0.9 + y)) * kk
				_tile(Rect2(rc2.position + Vector2(sway, 0), rc2.size), [250, 251, 253, 254][h2 % 4])
	_scenery(kk, cs, fire)
	# campfire: SPD embers tile under a FlameParticle fire with sparks and smoke, and a flickering warm glow
	var fr := Rect2((fire - Vector2(cs, cs) / 2.0).floor(), Vector2(cs, cs))
	var flk := SceneFX.flicker(t)
	SceneFX.glow(self, fire, cs * 2.6 * flk, Color(1.0, 0.55, 0.2, 0.22))
	_tile(fr, 3)
	SceneFX.fire(self, fire + Vector2(0, kk * 4), kk, t, 12.0, true, 1.6)
	# the selected hero rests by the fire (idle frame 0)
	var hs := _sprite(hero)
	var hz := Vector2(12, 15) * kk * 2.0
	if hero_anim.get("_for", "") != hero:   # hero idle from data/anims.json (generated from the SPD *Sprite.java)
		var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/anims.json"))
		hero_anim = all.get(hero, {}).get("idle", {"fps": 1, "frames": [0]}); hero_anim._for = hero
	var hfl: Array = hero_anim.frames; var hf := int(hfl[int(t * float(hero_anim.fps)) % hfl.size()])
	var cols_h := int(hs.get_width() / 12)
	draw_texture_rect_region(hs, Rect2(Vector2(fire.x + cs * 0.9, fire.y + kk * 6 - hz.y).floor(), hz), Rect2((hf % cols_h) * 12, (hf / cols_h + GameState.armor_tier(hero)) * 15, 12, 15))
	# facilities
	var font := get_theme_default_font()
	var fs := UIKit.font_px(UIKit.font_size * 0.85)
	for s in SPOTS:
		var sr := spot_rect(s)
		draw_texture_rect_region(load("res://assets/ui/shadow.png"), Rect2(sr.position.x + sr.size.x * 0.1, sr.end.y - kk * 3, sr.size.x * 0.8, kk * 5), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.6))
		if hot == s[0]: draw_rect(sr.grow(kk * 2), Color(1, 1, 0.6, 0.18))
		match s[1]:
			"_pot": _tile(sr, 64)
			"_chest":   # trimmed SPD frame, centred on whole pixels (DECISIONS #89)
				var cr := UIKit.item_rect(36); var cz := cr.size * floorf(sr.size.x / 16.0)
				draw_texture_rect_region(items, Rect2((sr.get_center() - cz / 2.0).floor(), cz), cr)
			_:
				var fw: int = s[2]
				var an: Array = NPC_IDLE[s[1]]; var fl: Array = an[1]
				var frame: int = fl[int((t + s[4] * 3.0) * float(an[0])) % fl.size()]
				draw_texture_rect_region(_sprite(s[1]), sr, Rect2(frame * fw, 0, fw, s[3]))
	# night: the clearing darkens away from the fire, the sky stays readable (DECISIONS #179)
	SceneFX.darkness(self, Rect2(0, sky_h, size.x, size.y - sky_h), fire, minf(size.x, size.y - sky_h) * 0.62 * flk, 0.5)
	SceneFX.glow(self, fire, cs * 1.2 * flk, Color(1.0, 0.7, 0.3, 0.12))
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
func _scenery(kk: float, cs: float, _fire: Vector2) -> void:
	for sp in SPOTS:
		var sr := spot_rect(sp)
		match sp[0]:
			"Guild":
				_tile(Rect2(Vector2(sr.position.x - cs - kk * 2, sr.end.y - cs).floor(), Vector2(cs, cs)), 130)
				_tile(Rect2(Vector2(sr.position.x - cs * 1.6 - kk * 2, sr.end.y - cs * 0.8).floor(), Vector2(cs, cs)), 131)
			"Forge":
				_tile(Rect2(Vector2(sr.position.x - cs - kk * 2, sr.end.y - cs).floor(), Vector2(cs, cs)), 130)

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
