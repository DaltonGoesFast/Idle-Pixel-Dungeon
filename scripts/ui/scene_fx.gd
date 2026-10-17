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

## Magic sparkle (SPD Speck.LIGHT-like): pixels that blink in and out around `c` within radius `r`.
static func twinkle(ci: CanvasItem, c: Vector2, k: float, t: float, r: float, col: Color) -> void:
	for i in 7:
		var life := 1.1 + 0.5 * _rnd(i, 8); var ph := _frac(t / life + _rnd(i, 9))
		var sd := floorf(t / life + _rnd(i, 9))
		var p := c + Vector2(_rnd(i + int(sd) * 7, 10) - 0.5, _rnd(i + int(sd) * 7, 11) - 0.5) * 2.0 * r - Vector2(0, ph * 4.0 * k)
		var a := sin(ph * PI)
		var cc := col; cc.a = a
		ci.draw_rect(Rect2(p.floor(), Vector2(k, k)), cc)
		if a > 0.7: ci.draw_rect(Rect2((p - Vector2(k, 0)).floor(), Vector2(k * 3, k)), Color(cc.r, cc.g, cc.b, a * 0.5)); ci.draw_rect(Rect2((p - Vector2(0, k)).floor(), Vector2(k, k * 3)), Color(cc.r, cc.g, cc.b, a * 0.5))

## Warm firelight on a sprite near a fire (DECISIONS #181): white far away, up to `amt` toward a flickering
## amber within `rad` of the fire. Multiplied into the sprite's modulate, so it costs nothing extra.
static func firelit(p: Vector2, fire: Vector2, rad: float, flk: float, amt := 0.35) -> Color:
	var w := clampf(1.0 - p.distance_to(fire) / rad, 0.0, 1.0) * amt * (0.75 + (flk - 1.0) * 6.0)
	return Color.WHITE.lerp(Color(1.0, 0.72, 0.45), clampf(w, 0.0, 1.0))

## SPD region wall visuals on WALL_DECO cells (SewerLevel.Sink, PrisonLevel.Torch, CavesLevel.Vein,
## CityLevel.Smoke), stateless: each particle is a function of time and its slot. Drawn after the darkness pass.
## `clip` (optional) keeps the Prison torch halo and flames inside the scene area (the battle arena's cells).
static func wall_visual(ci: CanvasItem, t: float, biome: String, rc: Rect2, tid: int, k: float, clip := Rect2()) -> void:
	var c := rc.get_center(); var sd := int(rc.position.x / maxf(1.0, k))
	match biome:
		"sewers":   # drips from the drain: 2px WaterParticles falling (acc 50) for 0.4 s
			for i in 4:
				var ph := _frac(t / 0.4 + float(i) / 4.0)
				var cyc := floorf(t / 0.4 + float(i) / 4.0)
				var x := c.x + (_rnd(i + int(cyc) * 5, sd) * 4.0 - 2.0) * k
				var y := c.y + (3.0 + 4.0 * ph * ph) * k
				var col := Color("b6ccc2").lerp(Color("3b6653"), _rnd(i, sd + 1)); col.a = 0.5 * (1.0 - ph * 0.5)
				ci.draw_rect(Rect2(Vector2(x, y).floor(), Vector2(2, 2) * k), col)
		"prison":   # wall torch: FlameParticle pour + Halo(12, 0xFFFFCC, 0.4); the sconce is lit by its own flame
			var fl := flicker(t + float(sd))
			ci.draw_texture_rect_region(load("res://assets/tiles/tiles_prison.png"), rc, Rect2((tid % 16) * 16, (tid / 16) * 16, 16, 16), Color(1, 0.95, 0.85, 0.8))
			glow(ci, c + Vector2(0, k), 12.0 * k * fl * 1.8, Color(1.0, 1.0, 0.8, 0.3), clip)
			fire(ci, c + Vector2(0, 3.0 * k), k, t + float(sd) * 0.37, 2.0, false, 0.45, clip.position.y if clip.has_area() else -INF)
		"caves":   # ore vein: white sparkles that swell and shrink over 0.5 s, about one a second
			for i in 2:
				var ph := _frac(t + float(i) * 0.5 + _rnd(sd, i))
				if ph > 0.5: continue
				var cyc := floorf(t + float(i) * 0.5 + _rnd(sd, i))
				var p := rc.position + Vector2(_rnd(int(cyc) + i, sd), _rnd(int(cyc) + i, sd + 7)) * rc.size
				var am := (ph * 4.0) if ph < 0.25 else (2.0 - ph * 4.0)
				var sz := maxf(1.0, roundf(am * 2.0)) * k
				ci.draw_rect(Rect2((p - Vector2(sz, sz) / 2.0).floor(), Vector2(sz, sz)), Color(1, 1, 1, clampf(am, 0.0, 1.0)))
		"city":   # CityLevel.Smoke: a SmokeParticle every 0.2 s (10 alive) from a 12x12 box, 2 s life, drifting
			# (-2..4, -3..-6) px/s, growing 3 -> 6 px; alpha fades in to 0.2 over the first fifth, then falls from
			# 0.2 to 0, so the big late puffs are the faintest and the overlap reads as haze, not dark squares
			for i in 10:
				var ph := _frac(t / 2.0 + float(i) / 10.0)
				var sq := i + int(floorf(t / 2.0 + float(i) / 10.0)) * 11
				var age := ph * 2.0
				var x := c.x + (_rnd(sq, sd) * 12.0 - 6.0 + (_rnd(sq, sd + 5) * 6.0 - 2.0) * age) * k
				var y := c.y + (_rnd(sq, sd + 3) * 12.0 - 4.0 - (3.0 + _rnd(sq, sd + 9) * 3.0) * age) * k
				var am := ph if ph < 0.2 else (1.0 - ph) * 0.25
				var sz := floorf(3.0 + ph * 3.0) * k
				ci.draw_rect(Rect2(Vector2(x, y).floor(), Vector2(sz, sz)), Color(0, 0, 0, am))

## SPD HallsLevel.Stream FireParticle: 0xEE7722, launched up at 40 px/s against +80 gravity, shrinking, ~0.5/s.
static func halls_stream(ci: CanvasItem, t: float, rc: Rect2, k: float) -> void:
	var sd := int(rc.position.x / maxf(1.0, k)) + int(rc.position.y)
	var per := 2.0 + _rnd(sd, 3)
	var ph := fposmod(t + _rnd(sd, 4) * per, per)
	if ph > 1.0: return
	var cyc := floorf((t + _rnd(sd, 4) * per) / per)
	var p := rc.position + Vector2(_rnd(int(cyc), sd), _rnd(int(cyc), sd + 1)) * rc.size
	var y := p.y + (-40.0 * ph + 40.0 * ph * ph) * k
	var sz := maxf(1.0, roundf(4.0 * (1.0 - ph))) * k
	var col := Color("ee7722"); col.a = (ph * 5.0) if ph < 0.2 else 1.0
	ci.draw_rect(Rect2(Vector2(p.x - sz / 2.0, y - sz / 2.0).floor(), Vector2(sz, sz)), col)

## SPD CityLevel.GreenFlame: ElmoParticle (0x22EE66, 0.6 s, size 4 shrinking, rising with acc -40).
static func green_flame(ci: CanvasItem, t: float, p: Vector2, k: float, sd: int) -> void:
	glow(ci, p, 10.0 * k, Color(0.2, 1.0, 0.45, 0.16))
	for i in 6:
		var ph := _frac(t / 0.6 + float(i) / 6.0)
		var cyc := floorf(t / 0.6 + float(i) / 6.0)
		var x := p.x + (_rnd(int(cyc) * 3 + i, sd) * 4.0 - 2.0) * k
		var y := p.y + (_rnd(int(cyc) * 3 + i, sd + 1) * 4.0 - 2.0 - 7.2 * ph * ph) * k
		var sz := maxf(1.0, roundf(4.0 * (1.0 - ph))) * k
		var am := (1.0 - ph) * 5.0 if ph > 0.8 else 1.0
		var col := Color("22ee66"); col.a = clampf(am, 0.0, 1.0)
		ci.draw_rect(Rect2(Vector2(x - sz / 2.0, y - sz / 2.0).floor(), Vector2(sz, sz)), col)
