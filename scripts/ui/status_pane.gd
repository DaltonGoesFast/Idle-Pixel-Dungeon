## StatusPane: a port of SPD's StatusPane.java in "large" mode (DECISIONS #74), drawn at integer pixel scale k.
## Layout in SPD game pixels (x right, y down), all multiplied by k:
##   bg        NinePatch(status_pane.png 0,64,41,39; left 33, right 4) stretched to the pane width
##   avatar    hero frame centred at (15,16) in the portrait box; level number centred at (15,33) in the badge strip
##   buffs     row at (31,0..16): hero name, then BuffIndicator icons; depth icon (sized to the floor digits) + floor # + danger at the right end
##   hp        bar at (30,19), 9 tall: shield (blue, one segment per hit it stops, DECISIONS #210) after hp (red) like SPD's shieldHP/hp scale.x; "HP/HT" centred
##   minis     torch/food row at (30,29), 9 tall like the HP bar, equal widths, same left/right edges (DECISIONS #133)
class_name StatusPane
extends Control

const BG := Rect2(0, 64, 41, 39)
const BG_L := 33
const BG_R := 4
const HP := Rect2(0, 103, 128, 9)
const SHIELD := Rect2(0, 112, 128, 9)
const EXP := Rect2(0, 121, 128, 7)
## SPD MenuPane depth number colour (Icons / BitmapText hardlight 0xCACFC2).
const DEPTH_COL := Color("cacfc2")
## pixel_font.ttf cap height (1456) over the em (2048). The depth digits occupy this, not the full ascent.
const DEPTH_CAP_EM := 1456.0 / 2048.0

## Minis drawn as an item icon + percent instead of a bar, keyed by the first word of their text.
const MINI_ICONS := {"Torch": "torch", "Food": "ration"}

var tex: Texture2D
var buffs_tex: Texture2D
var items_tex: Texture2D
var icons_tex: Texture2D
var hero_sprite: Texture2D
var hero_fw := 12
var hero_fh := 15
var d := {}   # name, level, hp, ht, shield, shield_max, buffs [int], floor, feeling, danger, minis [{kind, frac, text}]
## Cap drawn width (0 = fill parent). Desktop sets this so bars don't span ultrawide screens.
var max_w := 0.0

func _init() -> void:
	tex = load("res://assets/ui/status_pane.png")
	buffs_tex = load("res://assets/ui/buffs.png")
	icons_tex = load("res://assets/ui/icons.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

var hero_row := 0
func set_hero(sprite: String, fw: int, fh: int, row := 0) -> void:
	hero_row = row; hero_sprite = load("res://assets/sprites/%s.png" % sprite); hero_fw = fw; hero_fh = fh

func _k() -> float:
	return float(maxi(2, UIKit.px_scale))

func set_max_w(w: float) -> void:
	max_w = maxf(0.0, w)
	_apply_min_size()
	queue_redraw()

func _apply_min_size() -> void:
	custom_minimum_size = Vector2(max_w if max_w > 0.0 else 0.0, PANE_H * _k())

func set_data(data: Dictionary) -> void:
	d = data
	_apply_min_size()
	queue_redraw()

const PANE_H := 39     # SPD bg height: everything fits inside the nine-patch
const BAR_H := 9       # HP and every mini bar share this height
const BAR_X := 30
const HP_Y := 19
const MINI_Y := 29

## Bar rects in pixels for a pane `w` wide at scale k (also used by the layout test).
static func layout(w: float, k: float, n_minis: int) -> Dictionary:
	var hp := Rect2(Vector2(BAR_X, HP_Y) * k, Vector2(w - BAR_X * k - (BG_R + 1) * k, BAR_H * k))
	var minis := []
	if n_minis > 0:
		var mw := floorf((hp.size.x - k * (n_minis - 1)) / n_minis)
		for i in n_minis: minis.append(Rect2(hp.position.x + i * (mw + k), MINI_Y * k, mw, BAR_H * k))
	return {"hp": hp, "minis": minis, "level": Rect2(Vector2(1, 29) * k, Vector2(28, 8) * k), "height": PANE_H * k}

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

const BARRIER_BLUE := Color("3f8fff")
const BARRIER_DIV := Color("0a1a3a")
## Barrier as a blue section of `bar` from frac a to b, split by thin dark dividers into `segs` equal parts.
## Shared by the status pane and the grid's over-sprite bar.
static func barrier_segs(ci: CanvasItem, bar: Rect2, a: float, b: float, segs: int, line: float) -> void:
	var r := barrier_seg_rects(bar, a, b, segs, line)
	if r.is_empty(): return
	ci.draw_rect(r.blue, BARRIER_BLUE)
	for dv in r.dividers: ci.draw_rect(dv, BARRIER_DIV)

## The blue rect and the divider rects barrier_segs draws ({} = no blue). A divider is `line` wide but never more
## than a third of a segment (at least 1 px): 9-10 segments on the small bar over the hero were 3-4 px each with
## 2-3 px dividers, so that bar read as dark navy stripes instead of blue (DECISIONS #210).
static func barrier_seg_rects(bar: Rect2, a: float, b: float, segs: int, line: float) -> Dictionary:
	var x0 := floorf(bar.position.x + bar.size.x * clampf(a, 0, 1))
	var x1 := floorf(bar.position.x + bar.size.x * clampf(b, 0, 1))
	if x1 <= x0: return {}
	var n := maxi(1, segs)
	var lw := divider_width((x1 - x0) / float(n), line)
	var dividers := []
	for i in range(1, n):
		var x := floorf(x0 + (x1 - x0) * i / float(n))
		dividers.append(Rect2(x, bar.position.y, lw, bar.size.y))
	return {"blue": Rect2(x0, bar.position.y, x1 - x0, bar.size.y), "dividers": dividers}

## Divider width for segments `seg_w` px wide: `line`, capped at a third of a segment, at least 1 px.
static func divider_width(seg_w: float, line: float) -> float:
	return clampf(floorf(seg_w / 3.0), 1.0, maxf(1.0, line))

## Blood / shield / exp strips have 1px transparent corners for rounding. Stretch only the middle so
## those corners stay one game-pixel (× pane scale) instead of blowing out into black corner gaps.
func _strip(src: Rect2, dst: Rect2, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0: return
	var dw := floorf(dst.size.x * frac)
	if dw < 1.0: return
	_bar_patch(src, Rect2(dst.position, Vector2(dw, dst.size.y)))

func _bar_patch(src: Rect2, dst: Rect2) -> void:
	var sx := src.position.x; var sy := src.position.y
	var sw := src.size.x; var sh := src.size.y
	var dx := dst.position.x; var dy := dst.position.y
	var dw := dst.size.x; var dh := dst.size.y
	var m := maxf(1.0, floorf(dh / sh))   # 1 source px → pane scale
	if dw < m * 2.0:
		draw_texture_rect_region(tex, dst, Rect2(sx + 1.0, sy, maxf(1.0, sw - 2.0), sh))
		return
	var ml := m; var mr := m
	var mt := minf(m, floorf(dh / 2.0)); var mb := minf(m, dh - mt)
	draw_texture_rect_region(tex, Rect2(dx, dy, ml, mt), Rect2(sx, sy, 1, 1))
	draw_texture_rect_region(tex, Rect2(dx + dw - mr, dy, mr, mt), Rect2(sx + sw - 1, sy, 1, 1))
	draw_texture_rect_region(tex, Rect2(dx, dy + dh - mb, ml, mb), Rect2(sx, sy + sh - 1, 1, 1))
	draw_texture_rect_region(tex, Rect2(dx + dw - mr, dy + dh - mb, mr, mb), Rect2(sx + sw - 1, sy + sh - 1, 1, 1))
	if dw > ml + mr:
		draw_texture_rect_region(tex, Rect2(dx + ml, dy, dw - ml - mr, mt), Rect2(sx + 1, sy, sw - 2, 1))
		draw_texture_rect_region(tex, Rect2(dx + ml, dy + dh - mb, dw - ml - mr, mb), Rect2(sx + 1, sy + sh - 1, sw - 2, 1))
	if dh > mt + mb:
		draw_texture_rect_region(tex, Rect2(dx, dy + mt, ml, dh - mt - mb), Rect2(sx, sy + 1, 1, sh - 2))
		draw_texture_rect_region(tex, Rect2(dx + dw - mr, dy + mt, mr, dh - mt - mb), Rect2(sx + sw - 1, sy + 1, 1, sh - 2))
	if dw > ml + mr and dh > mt + mb:
		draw_texture_rect_region(tex, Rect2(dx + ml, dy + mt, dw - ml - mr, dh - mt - mb), Rect2(sx + 1, sy + 1, sw - 2, sh - 2))

func _draw() -> void:
	if d.is_empty(): return
	var k := _k()
	var w := size.x
	var font := get_theme_default_font()
	# background nine-patch (horizontal stretch; vertical follows the pane so a tall mini row fits)
	var h := size.y
	draw_texture_rect_region(tex, Rect2(0, 0, BG_L * k, h), Rect2(BG.position, Vector2(BG_L, BG.size.y)))
	var mid := w - (BG_L + BG_R) * k
	if mid > 0: draw_texture_rect_region(tex, Rect2(BG_L * k, 0, mid, h), Rect2(BG.position + Vector2(BG_L, 0), Vector2(BG.size.x - BG_L - BG_R, BG.size.y)))
	draw_texture_rect_region(tex, Rect2(w - BG_R * k, 0, BG_R * k, h), Rect2(BG.position + Vector2(BG.size.x - BG_R, 0), Vector2(BG_R, BG.size.y)))
	# avatar centred at (15,16)
	if hero_sprite:
		var sc := k * 1.5 if k < 4 else floorf(k * 1.5)
		var sz := Vector2(hero_fw, hero_fh) * sc
		var c := Vector2(15, 16) * k
		draw_texture_rect_region(hero_sprite, Rect2((c - sz / 2.0).floor(), sz), Rect2(0, hero_row * hero_fh, hero_fw, hero_fh))
	# level number centred in the badge strip under the portrait (SPD: level at x+(30-w)/2, y+33)
	var lfs := _fit_fs(7 * k)
	_centred(font, Rect2(Vector2(1, 29) * k, Vector2(28, 8) * k), str(int(d.get("level", 1))), lfs, Color("ffffaa"), k)
	# top row: name + buff icons, depth / danger right-aligned
	var x0 := 31 * k
	var tfs := _fit_fs(14 * k)
	var name: String = d.get("name", "")
	_text(font, Vector2(x0, floorf(13 * k)), name, tfs, Color("ffff44"), k)
	var bx := floorf(x0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 4 * k)
	var isz := 7.0 * k
	for idx in d.get("buffs", []):
		var i := int(idx)
		draw_texture_rect_region(buffs_tex, Rect2(bx, 5 * k, isz, isz), Rect2((i % 18) * 7, (i / 18) * 7, 7, 7))
		bx += isz + k
	var right := w - (BG_R + 2) * k
	# Depth: SPD MenuPane DEPTH_* glyph + floor number (feeling swaps the glyph; DECISIONS #241).
	var floor_n := int(d.get("floor", 0))
	if floor_n <= 0:
		var legacy: String = String(d.get("depth", ""))
		if legacy.begins_with("F"): floor_n = int(legacy.substr(1))
	if floor_n > 0:
		var num := str(floor_n)
		var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var src: Rect2 = UIKit.SPD_ICONS[UIKit.depth_icon_name(String(d.get("feeling", "")))]
		# Same header on the combat side panel and the delve bar. The glyph tracks the digits, not 7*k (DECISIONS #244).
		var ir := depth_icon_rect(right, nw, k, src.size, tfs)
		_text(font, Vector2(right - nw, floorf(13 * k)), num, tfs, DEPTH_COL, k)
		draw_texture_rect_region(icons_tex, ir, src)
		right -= nw + k + ir.size.x + 3 * k
	var danger := int(d.get("danger", 0))
	if danger > 0:
		var s := str(danger)
		var sw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		_text(font, Vector2(right - sw, floorf(13 * k)), s, tfs, Color("ff6666"), k)
		var skull := UIKit.spd_icon("skull")
		draw_texture_rect(skull, Rect2(right - sw - 9 * k, 5 * k, 8 * k, 8 * k), false)
	var lay := layout(w, k, d.get("minis", []).size())
	var bar: Rect2 = lay.hp
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var ht := maxf(1.0, float(d.get("ht", 1)))
	var hp := float(d.get("hp", 0))
	var sh := float(d.get("shield", 0))
	var tot := maxf(ht, hp + sh)
	_strip(HP, bar, hp / tot)
	if sh > 0: barrier_segs(self, bar, hp / tot, (hp + sh) / tot, int(d.get("shield_hits", 1)), maxf(1.0, floorf(k / 2.0)))
	var hp_txt := "%d/%d" % [int(hp), int(ht)]
	if sh > 0: hp_txt = "%d+%d/%d" % [int(hp), int(sh), int(ht)]
	_centred(font, bar, hp_txt, _fit_fs(bar.size.y), Color.WHITE, k)
	# EXP / supply row under HP
	var minis: Array = d.get("minis", [])
	for i in minis.size():
		var m: Dictionary = minis[i]
		var r: Rect2 = lay.minis[i]
		var ic: String = String(m.get("icon", ""))
		if ic == "": ic = MINI_ICONS.get(String(m.get("text", "")).get_slice(" ", 0), "")
		if ic != "": _mini_icon(font, r, ic, float(m.frac), k)
		else:
			draw_rect(r, Color(0, 0, 0, 0.6))
			_strip(EXP if m.kind == "exp" else SHIELD, r, float(m.frac))
			_centred(font, r, m.text, _fit_fs(r.size.y), Color.WHITE, k)

## Supply as a filled bar with an item icon on the left and a percent over the fill.
## The icon is fitted to the bar height, so torch and food are the same height as the HP bar.
func _mini_icon(font: Font, r: Rect2, id: String, frac: float, k: float) -> void:
	if items_tex == null: items_tex = load("res://assets/sprites/items.png")
	draw_rect(r, Color(0, 0, 0, 0.6))
	var fw := floorf(r.size.x * clampf(frac, 0.0, 1.0))
	if fw > 0.0:
		draw_rect(Rect2(r.position, Vector2(fw, r.size.y)), Color("e0a030") if id == "torch" else Color("9a8a68"))
	# item icon fitted to the bar height (trimmed pixels, nearest scaling), left-aligned with a 1px inset
	var vis := UIKit.item_rect(DB.icon_index(id))
	var isz := icon_size(vis.size, r.size.y)
	var origin := Vector2(floorf(r.position.x + k), floorf(r.position.y + (r.size.y - isz.y) / 2.0))
	var tint: String = DB.materials.get(id, {}).get("tint", "")
	draw_texture_rect_region(items_tex, Rect2(origin, isz), vis, Color(tint) if tint != "" else Color.WHITE)
	var pct := roundi(clampf(frac, 0.0, 1.0) * 100.0)
	var col := Color.WHITE if pct >= 30 else (Color("ff8800") if pct > 0 else Color("ff4444"))
	_centred(font, Rect2(origin.x + isz.x + k, r.position.y, r.end.x - origin.x - isz.x - k, r.size.y), "%d%%" % pct, _fit_fs(r.size.y), col, k)

## Icon size that fits inside a bar `h` tall (keeps aspect; integer multiple of the source when it fits).
static func icon_size(src: Vector2, h: float) -> Vector2:
	var fit := (h - 2.0) / maxf(1.0, src.y)
	var sc := floorf(fit) if fit >= 1.0 else fit
	return (src * sc).floor()

## Height of the depth number's digits at font size `fs` (the ink, not the line gap or the outline).
static func depth_digit_height(fs: int) -> float:
	return float(fs) * DEPTH_CAP_EM

## DEPTH_* frame scaled so its height matches the depth digits. Whole source-pixel steps keep the stairs crisp.
## SPD's MenuPane does the same match the other way: a 7px glyph beside text at scale 0.67 (DECISIONS #244).
static func depth_icon_size(src: Vector2, digit_h: float) -> Vector2:
	var sy := maxf(1.0, src.y)
	var sc := maxf(1.0, round(digit_h / sy))
	return Vector2(floorf(src.x * sc), floorf(sy * sc))

## Icon rect just left of the floor number, centred on the digit ink. `right` is the number's right edge.
static func depth_icon_rect(right: float, num_w: float, k: float, src: Vector2, fs: int) -> Rect2:
	var digit_h := depth_digit_height(fs)
	var isz := depth_icon_size(src, digit_h)
	var baseline := floorf(13.0 * k)
	var x := floorf(right - num_w - k - isz.x)
	var y := floorf(baseline - digit_h + (digit_h - isz.y) / 2.0)
	return Rect2(x, y, isz.x, isz.y)
