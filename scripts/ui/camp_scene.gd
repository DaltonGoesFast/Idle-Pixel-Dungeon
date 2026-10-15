## CampScene: the Surface Camp drawn as a small SPD-tile clearing (DECISIONS #82).
## A night sky with SPD's surface clouds over a grass clearing with a campfire. Facility NPCs stand around it:
## Blacksmith (Forge), Wandmaker (Enchanter), Alchemy pot, Shopkeeper (Guild) and the Stash chest.
## Tap an NPC to open its facility window. Everything is drawn in _draw at an integer pixel scale.
extends Control

signal picked(page: String)

const SPOTS := [   # page, sprite, frame w, frame h, x frac, y frac (feet), label
	["Forge", "blacksmith", 13, 16, 0.17, 0.50, "Forge"],
	["Enchanter", "wandmaker", 12, 14, 0.83, 0.50, "Enchanter"],
	["Alchemy", "_pot", 16, 16, 0.22, 0.90, "Alchemy"],
	["Guild", "shopkeeper", 14, 14, 0.78, 0.90, "Guild"],
	["Stash", "_chest", 16, 16, 0.50, 0.95, "Stash"],
]
const FAC := {"Forge": "blacksmith", "Enchanter": "enchanter", "Alchemy": "alchemy", "Guild": "guild"}
var hero := "warrior"
var t := 0.0
var tex := {}
var tiles: Texture2D
var items: Texture2D
var surface: Texture2D
var hot := ""   # spot under the last press (highlight)

func _ready() -> void:
	tiles = load("res://assets/tiles/tiles_sewers.png"); items = load("res://assets/sprites/items.png")
	surface = load("res://assets/ui/surface.png")
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true

func _process(d: float) -> void:
	t += d; queue_redraw()

func _sprite(n: String) -> Texture2D:
	if not tex.has(n): tex[n] = load("res://assets/sprites/%s.png" % n)
	return tex[n]

## Integer pixel scale: the clearing is ~11 tiles wide, and the scale is never below 2.
func k() -> float:
	return maxf(2.0, floorf(minf(size.x / (16.0 * 11.0), size.y / (16.0 * 6.0))))

func _tile(r: Rect2, idx: int, tx: Texture2D = null) -> void:
	draw_texture_rect_region(tx if tx else tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

func spot_rect(s: Array) -> Rect2:
	var kk := k()
	var sz := Vector2(s[2], s[3]) * kk * (1.5 if s[1].begins_with("_") else 2.0)
	var feet := Vector2(size.x * float(s[4]), size.y * float(s[5]) - UIKit.font_size * 1.1)
	return Rect2((feet - Vector2(sz.x / 2.0, sz.y)).floor(), sz)

func _draw() -> void:
	var kk := k(); var cs := 16.0 * kk
	var sky_h := floorf(size.y * 0.28)
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
	var fire := Vector2(size.x * 0.5, size.y * 0.62)
	draw_rect(Rect2(0, sky_h, size.x, size.y - sky_h), Color("2f4a22"))
	for y in rows:
		for x in cols:
			var rc := Rect2(ox + x * cs, sky_h + y * cs, cs, cs)
			var h := (x * 73856093) ^ (y * 19349663)
			var ctr := rc.get_center()
			var path := absf(ctr.x - fire.x) < cs * 0.6 and ctr.y > fire.y
			_tile(rc, (0 if h % 3 else 6) if path else (2 if h % 4 else 8))
			if y == 0: _tile(rc, 122 if h % 2 else 125)
	# campfire: embers tile + flickering pixel flames + warm glow
	var fr := Rect2((fire - Vector2(cs, cs) / 2.0).floor(), Vector2(cs, cs))
	draw_circle(fire, cs * (1.9 + 0.08 * sin(t * 7.0)), Color(1.0, 0.6, 0.2, 0.10))
	draw_circle(fire, cs * 1.1, Color(1.0, 0.7, 0.3, 0.10))
	_tile(fr, 3)
	for i in 7:
		var ph := t * 9.0 + i * 1.7
		var hgt := (4.0 + 5.0 * absf(sin(ph))) * kk
		var fx := fire.x + (i - 3) * 1.6 * kk + sin(ph * 0.7) * kk
		var col := Color("ffd24a") if i % 2 else Color("ff7a1a")
		draw_rect(Rect2(Vector2(fx, fire.y + 2 * kk - hgt).floor(), Vector2(kk * 2, hgt)), col)
	# the selected hero rests by the fire (idle frame 0)
	var hs := _sprite(hero)
	var hz := Vector2(12, 15) * kk * 2.0
	draw_texture_rect_region(hs, Rect2(Vector2(fire.x + cs * 0.9, fire.y + kk * 6 - hz.y).floor(), hz), Rect2(0, 0, 12, 15))
	# facilities
	var font := get_theme_default_font()
	var fs := UIKit.font_px(UIKit.font_size * 0.85)
	for s in SPOTS:
		var sr := spot_rect(s)
		draw_texture_rect_region(load("res://assets/ui/shadow.png"), Rect2(sr.position.x + sr.size.x * 0.1, sr.end.y - kk * 3, sr.size.x * 0.8, kk * 5), Rect2(0, 0, 6, 6), Color(1, 1, 1, 0.6))
		if hot == s[0]: draw_rect(sr.grow(kk * 2), Color(1, 1, 0.6, 0.18))
		match s[1]:
			"_pot": _tile(sr, 64)
			"_chest": draw_texture_rect_region(items, sr, Rect2(4 * 16, 2 * 16, 16, 16))
			_:
				var fw: int = s[2]
				var frame := 0 if fmod(t + s[4] * 5.0, 3.0) < 2.6 else 1
				draw_texture_rect_region(_sprite(s[1]), sr, Rect2(frame * fw, 0, fw, s[3]))
		# name plate: SPD-ish yellow text with a dark backing; facility level as "Lv2"
		var lbl: String = s[6]
		if FAC.has(s[0]): lbl += " Lv%d" % GameState.facility_level(FAC[s[0]])
		var ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var lp := Vector2(sr.get_center().x - ts.x / 2.0, sr.end.y + fs * 0.2)
		draw_rect(Rect2(lp - Vector2(kk * 2, 0), Vector2(ts.x + kk * 4, fs * 1.15)), Color(0, 0, 0, 0.55))
		draw_string(font, lp + Vector2(0, fs * 0.9), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffff44") if _has_news(s[0]) else Color.WHITE)
		if _has_news(s[0]):   # "!" badge: something ready (identified item, affordable upgrade)
			var bp := Vector2(sr.end.x - kk * 2, sr.position.y - kk * 2)
			draw_circle(bp, kk * 3.5, Color("ff5a2a")); draw_string(font, bp + Vector2(-fs * 0.18, fs * 0.33), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## Badge rule: a facility upgrade is affordable, or an identification is finished.
func _has_news(page: String) -> bool:
	if FAC.has(page) and GameState.can_upgrade_facility(FAC[page]) == "": return true
	if page == "Enchanter": return GameState.id_queue.any(func(q): return float(q.ready_at) <= GameState.now())
	return false

func _gui_input(e: InputEvent) -> void:
	var press: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if not press: return
	for s in SPOTS:
		if spot_rect(s).grow(UIKit.font_size * 0.8).has_point(e.position):
			hot = s[0]; Sfx.play("click"); picked.emit(s[0]); accept_event(); return
