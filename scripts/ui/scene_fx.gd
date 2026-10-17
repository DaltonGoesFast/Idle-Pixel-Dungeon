class_name SceneFX
## Shared SPD-style scene effects for the camp and delve scenes (DECISIONS #179).
## Stateless: every particle's position is a function of time and its index, so nothing is allocated per frame
## and the effects cost a few dozen quads. Particles are whole-pixel squares at the scene's integer scale, the
## way SPD's PixelParticle draws them.

static var _light: GradientTexture2D
static var _glow: GradientTexture2D

static func _frac(x: float) -> float: return x - floorf(x)
static func _rnd(i: int, salt: int) -> float: return _frac(sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453)

## Darkness with a soft round hole: transparent in the middle, `dark` at the rim (outside it the caller fills
## with the same colour, so no ring shows).
static func light_tex() -> GradientTexture2D:
	if _light == null:
		var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.3, 0.95, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 1.0), Color(0, 0, 0, 1.0)])
		_light = GradientTexture2D.new(); _light.gradient = g; _light.fill = GradientTexture2D.FILL_RADIAL
		_light.fill_from = Vector2(0.5, 0.5); _light.fill_to = Vector2(1.0, 0.5); _light.width = 128; _light.height = 128
	return _light

## Warm additive-looking glow: opaque white centre fading out; tint it with modulate.
static func glow_tex() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_glow = GradientTexture2D.new(); _glow.gradient = g; _glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5); _glow.fill_to = Vector2(1.0, 0.5); _glow.width = 64; _glow.height = 64
	return _glow

## Torch/fire flicker multiplier around 1.0 (two incommensurate sines, like SPD's torch light).
static func flicker(t: float) -> float:
	return 1.0 + 0.035 * sin(t * 9.0) + 0.025 * sin(t * 23.0 + 1.3)

## Darken everything in `area` except a pool of light at `c` with radius `rad`. Every quad is clipped to `area`
## (the light quad by its texture region), so nothing outside it (the camp sky) is touched.
static func darkness(ci: CanvasItem, area: Rect2, c: Vector2, rad: float, alpha: float, tint := Color(0.02, 0.01, 0.04)) -> void:
	var lr := Rect2(c - Vector2.ONE * rad, Vector2.ONE * rad * 2.0)
	var dark := Color(tint.r, tint.g, tint.b, alpha)
	var a := area
	var cl := lr.intersection(a)
	if cl.has_area():
		var ts := Vector2(light_tex().get_width(), light_tex().get_height())
		ci.draw_texture_rect_region(light_tex(), cl, Rect2((cl.position - lr.position) / lr.size * ts, cl.size / lr.size * ts), dark)
	var y0 := clampf(lr.position.y, a.position.y, a.end.y); var y1 := clampf(lr.end.y, a.position.y, a.end.y)
	ci.draw_rect(Rect2(a.position.x, a.position.y, a.size.x, y0 - a.position.y), dark)
	ci.draw_rect(Rect2(a.position.x, y1, a.size.x, a.end.y - y1), dark)
	var x0 := clampf(lr.position.x, a.position.x, a.end.x); var x1 := clampf(lr.end.x, a.position.x, a.end.x)
	ci.draw_rect(Rect2(a.position.x, y0, x0 - a.position.x, y1 - y0), dark)
	ci.draw_rect(Rect2(x1, y0, a.end.x - x1, y1 - y0), dark)

## Tinted glow; with a `clip` rect it is cut to that rect by texture region (the camp keeps it off the sky).
static func glow(ci: CanvasItem, c: Vector2, rad: float, col: Color, clip := Rect2()) -> void:
	var gr := Rect2(c - Vector2.ONE * rad, Vector2.ONE * rad * 2.0)
	if not clip.has_area():
		ci.draw_texture_rect(glow_tex(), gr, false, col); return
	var cl := gr.intersection(clip)
	if not cl.has_area(): return
	var ts := Vector2(glow_tex().get_width(), glow_tex().get_height())
	ci.draw_texture_rect_region(glow_tex(), cl, Rect2((cl.position - gr.position) / gr.size * ts, cl.size / gr.size * ts), col)

## SPD FlameParticle (0xEE7722 fading, shrinking, rising) + sparks + SmokeParticle, at base `p` (fire centre on
## the ground), pixel size `k`. `w` is the fire width in source pixels.
## Particles above `top` (screen y) are skipped, so smoke and sparks never cross into a static sky.
static func fire(ci: CanvasItem, p: Vector2, k: float, t: float, w := 8.0, smoke := true, hs := 1.0, top := -INF) -> void:
	# smoke first (behind the flames): grey puffs rising slowly and drifting
	if smoke:
		for i in 6:
			var life := 2.6; var ph := _frac(t / life + float(i) / 6.0)
			var x := p.x + (_rnd(i, 1) - 0.5) * w * 0.6 * k + sin(t * 0.8 + i) * 2.0 * k + ph * 5.0 * k
			var y := p.y - (8.0 + ph * 26.0) * k * hs
			var s := floorf(2.0 + ph * 3.0) * k
			if y < top: continue
			ci.draw_rect(Rect2(Vector2(x, y).floor(), Vector2(s, s)), Color(0.35, 0.33, 0.33, 0.28 * (1.0 - ph)))
	for i in 22:
		var life := 0.55 + 0.35 * _rnd(i, 2); var ph := _frac(t / life + _rnd(i, 3))
		var x := p.x + (_rnd(i, 4) - 0.5) * w * k * (1.0 - ph * 0.6) + sin(t * 6.0 + i) * k * 0.6
		var y := p.y - (1.0 + ph * (9.0 + 5.0 * _rnd(i, 5))) * k * hs
		var s := maxf(1.0, floorf(3.0 * hs * (1.0 - ph) + 0.5)) * k
		var c: Color = Color("ffe680").lerp(Color("ee7722"), clampf(ph * 1.8, 0, 1)).lerp(Color("aa2200"), clampf(ph * 2.0 - 1.0, 0, 1))
		c.a = 1.0 - ph * ph
		if y - s / 2.0 < top: continue
		ci.draw_rect(Rect2(Vector2(x - s / 2.0, y - s / 2.0).floor(), Vector2(s, s)), c)
	for i in 5:   # sparks: single pixels that fly higher and wobble
		var life := 1.4; var ph := _frac(t / life + _rnd(i, 6))
		var x := p.x + (_rnd(i, 7) - 0.5) * w * k + sin(t * 4.0 + i * 2.0) * 3.0 * k * ph
		var y := p.y - (4.0 + ph * 24.0) * k * hs
		if y < top: continue
		ci.draw_rect(Rect2(Vector2(x, y).floor(), Vector2(k, k)), Color(1.0, 0.75, 0.3, 1.0 - ph))

## Small radial burst of pixel sparks (item pickup), `age` 0..1.
static func sparkle(ci: CanvasItem, c: Vector2, k: float, age: float, col := Color(1, 0.95, 0.5)) -> void:
	if age >= 1.0: return
	for i in 8:
		var ang := TAU * float(i) / 8.0 + 0.4
		var r := (3.0 + age * 10.0) * k
		var pc := c + Vector2(cos(ang), sin(ang)) * r
		var cc := col; cc.a = 1.0 - age
		ci.draw_rect(Rect2(pc.floor(), Vector2(k, k)), cc)

## Warm firelight on a sprite near a fire (DECISIONS #181): white far away, up to `amt` toward a flickering
## amber within `rad` of the fire. Multiplied into the sprite's modulate, so it costs nothing extra.
static func firelit(p: Vector2, fire: Vector2, rad: float, flk: float, amt := 0.35) -> Color:
	var w := clampf(1.0 - p.distance_to(fire) / rad, 0.0, 1.0) * amt * (0.75 + (flk - 1.0) * 6.0)
	return Color.WHITE.lerp(Color(1.0, 0.72, 0.45), clampf(w, 0.0, 1.0))
