## StatusPane: a port of SPD's StatusPane.java in "large" mode (DECISIONS #74), drawn at integer pixel scale k.
## Layout in SPD game pixels (x right, y down), all multiplied by k:
##   bg        NinePatch(status_pane.png 0,64,41,39; left 33, right 4) stretched to the pane width
##   avatar    hero frame centred at (15,16) in the portrait box; level number centred at (15,33) in the badge strip
##   buffs     row at (31,0..16): hero name, then BuffIndicator icons; depth + danger at the right end
##   hp        bar at (30,19), 9 tall: shield (grey) under hp (red) like SPD's shieldHP/hp scale.x; "HP/HT" centred
##   exp       bar at (30,30), 7 tall: delve shows Torch (yellow) | Satiety (grey) halves with centred text
class_name StatusPane
extends Control

const BG := Rect2(0, 64, 41, 39)
const BG_L := 33
const BG_R := 4
const HP := Rect2(0, 103, 128, 9)
const SHIELD := Rect2(0, 112, 128, 9)
const EXP := Rect2(0, 121, 128, 7)

var tex: Texture2D
var buffs_tex: Texture2D
var hero_sprite: Texture2D
var hero_fw := 12
var hero_fh := 15
var d := {}   # name, level, hp, ht, shield, shield_max, buffs [int], depth, danger, minis [{kind, frac, text}]

func _init() -> void:
	tex = load("res://assets/ui/status_pane.png")
	buffs_tex = load("res://assets/ui/buffs.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_hero(sprite: String, fw: int, fh: int) -> void:
	hero_sprite = load("res://assets/sprites/%s.png" % sprite); hero_fw = fw; hero_fh = fh

func _k() -> float:
	return float(maxi(2, UIKit.px_scale))

func set_data(data: Dictionary) -> void:
	d = data
	custom_minimum_size = Vector2(0, 40 * _k())
	queue_redraw()

## Pixel-font size whose glyphs fit a bar of h pixels (pixel_font cap ~ 0.73 em).
func _fit_fs(h: float) -> int:
	var fs := UIKit.FONT_PX
	while fs + UIKit.FONT_PX * 0.5 <= h * 1.05 / 0.73 * 0.82 and fs < UIKit.font_size * 1.1: fs += UIKit.FONT_PX * 0.5
	return int(round(fs))

func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color, k: float) -> void:
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(maxf(2.0, k)), Color.BLACK)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _centred(font: Font, r: Rect2, s: String, fs: int, col: Color, k: float) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := font.get_ascent(fs)
	var base := r.position.y + (r.size.y + asc * 0.72) / 2.0
	_text(font, Vector2(floorf(r.position.x + (r.size.x - w) / 2.0), floorf(base)), s, fs, col, k)

func _strip(src: Rect2, dst: Rect2, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0: return
	draw_texture_rect_region(tex, Rect2(dst.position, Vector2(floorf(dst.size.x * frac), dst.size.y)), Rect2(src.position, Vector2(maxf(1.0, src.size.x * frac), src.size.y)))

func _draw() -> void:
	if d.is_empty(): return
	var k := _k()
	var w := size.x
	var font := get_theme_default_font()
	# background nine-patch (only stretched horizontally, like SPD)
	var h := BG.size.y * k
	draw_texture_rect_region(tex, Rect2(0, 0, BG_L * k, h), Rect2(BG.position, Vector2(BG_L, BG.size.y)))
	var mid := w - (BG_L + BG_R) * k
	if mid > 0: draw_texture_rect_region(tex, Rect2(BG_L * k, 0, mid, h), Rect2(BG.position + Vector2(BG_L, 0), Vector2(BG.size.x - BG_L - BG_R, BG.size.y)))
	draw_texture_rect_region(tex, Rect2(w - BG_R * k, 0, BG_R * k, h), Rect2(BG.position + Vector2(BG.size.x - BG_R, 0), Vector2(BG_R, BG.size.y)))
	# avatar centred at (15,16)
	if hero_sprite:
		var sc := k * 1.5 if k < 4 else floorf(k * 1.5)
		var sz := Vector2(hero_fw, hero_fh) * sc
		var c := Vector2(15, 16) * k
		draw_texture_rect_region(hero_sprite, Rect2((c - sz / 2.0).floor(), sz), Rect2(0, 0, hero_fw, hero_fh))
	# level number centred in the badge strip under the portrait (SPD: level at x+(30-w)/2, y+33)
	var lfs := _fit_fs(7 * k)
	_centred(font, Rect2(Vector2(1, 29) * k, Vector2(28, 8) * k), str(int(d.get("level", 1))), lfs, Color("ffffaa"), k)
	# top row: name + buff icons, depth / danger right-aligned
	var x0 := 31 * k
	var tfs := _fit_fs(14 * k)
	var name: String = d.get("name", "")
	_text(font, Vector2(x0, floorf(13 * k)), name, tfs, Color("ffff44"), k)
	var bx := x0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 4 * k
	var isz := 7.0 * k
	for idx in d.get("buffs", []):
		var i := int(idx)
		draw_texture_rect_region(buffs_tex, Rect2(bx, 5 * k, isz, isz), Rect2((i % 18) * 7, (i / 18) * 7, 7, 7))
		bx += isz + k
	var right := w - (BG_R + 2) * k
	var depth: String = d.get("depth", "")
	if depth != "":
		var dw := font.get_string_size(depth, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		_text(font, Vector2(right - dw, floorf(13 * k)), depth, tfs, Color("ffffff"), k)
		right -= dw + 3 * k
	var danger := int(d.get("danger", 0))
	if danger > 0:
		var s := str(danger)
		var sw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		_text(font, Vector2(right - sw, floorf(13 * k)), s, tfs, Color("ff6666"), k)
		var skull := UIKit.spd_icon("skull")
		draw_texture_rect(skull, Rect2(right - sw - 9 * k, 5 * k, 8 * k, 8 * k), false)
	# HP bar (30,19) 9 tall: shield first (hp+shield), then hp on top
	var bar := Rect2(Vector2(30 * k, 19 * k), Vector2(w - 30 * k - (BG_R + 1) * k, 9 * k))
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var ht := maxf(1.0, float(d.get("ht", 1)))
	var hp := float(d.get("hp", 0))
	var sh := float(d.get("shield", 0))
	_strip(SHIELD, bar, (hp + sh) / maxf(ht, hp + sh))
	_strip(HP, bar, hp / maxf(ht, hp + sh))
	var hp_txt := "%d/%d" % [int(hp), int(ht)]
	if sh > 0: hp_txt = "%d+%d/%d" % [int(hp), int(sh), int(ht)]
	_centred(font, bar, hp_txt, _fit_fs(bar.size.y), Color.WHITE, k)
	# EXP row (30,30) 7 tall: compact minis side by side
	var minis: Array = d.get("minis", [])
	if minis.size() > 0:
		var row := Rect2(Vector2(30 * k, 30 * k), Vector2(bar.size.x, 7 * k))
		var mw := floorf((row.size.x - k * (minis.size() - 1)) / minis.size())
		var mx := row.position.x
		for m in minis:
			var r := Rect2(mx, row.position.y, mw, row.size.y)
			draw_rect(r, Color(0, 0, 0, 0.6))
			_strip(EXP if m.kind == "exp" else SHIELD, r, float(m.frac))
			_centred(font, r, m.text, _fit_fs(r.size.y), Color.WHITE, k)
			mx += mw + k
