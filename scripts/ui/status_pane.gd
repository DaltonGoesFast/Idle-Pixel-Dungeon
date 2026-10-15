## StatusPane: SPD's status_pane.png hero pane (portrait box + bars), drawn at integer pixel scale.
## bars: [{frac: 0..1, kind: "hp"|"shield"|"exp", text}] drawn as SPD's large HP / shield / exp strips.
class_name StatusPane
extends Control

const BG := Rect2(0, 0, 82, 38)          # small pane: portrait box on the left, frame to the right
const BG_MARGIN_L := 32
const BG_MARGIN_R := 5
const BARS := {"hp": Rect2(0, 103, 128, 9), "shield": Rect2(0, 112, 128, 9), "exp": Rect2(0, 121, 128, 7)}

var tex: Texture2D
var hero_sprite: Texture2D
var hero_fw := 12
var hero_fh := 15
var title := ""
var bars: Array = []

func _init() -> void:
	tex = load("res://assets/ui/status_pane.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_hero(sprite: String, fw: int, fh: int) -> void:
	hero_sprite = load("res://assets/sprites/%s.png" % sprite); hero_fw = fw; hero_fh = fh

func _k() -> int:
	return UIKit.px_scale

func refresh(t: String, b: Array) -> void:
	title = t; bars = b
	custom_minimum_size = Vector2(0, (BG.size.y + 4) * _k())
	queue_redraw()

func _draw() -> void:
	var k := float(_k())
	var w := size.x
	var h := BG.size.y * k
	# left part (portrait box) at 1:1, middle stretched, right cap
	draw_texture_rect_region(tex, Rect2(0, 0, BG_MARGIN_L * k, h), Rect2(0, 0, BG_MARGIN_L, BG.size.y))
	var mid_w := w - (BG_MARGIN_L + BG_MARGIN_R) * k
	draw_texture_rect_region(tex, Rect2(BG_MARGIN_L * k, 0, mid_w, h), Rect2(BG_MARGIN_L, 0, BG.size.x - BG_MARGIN_L - BG_MARGIN_R, BG.size.y))
	draw_texture_rect_region(tex, Rect2(w - BG_MARGIN_R * k, 0, BG_MARGIN_R * k, h), Rect2(BG.size.x - BG_MARGIN_R, 0, BG_MARGIN_R, BG.size.y))
	# portrait: first frame of the hero sprite, centred in the 28x28 box
	if hero_sprite:
		var sc := floorf(k * 1.5)
		var sz := Vector2(hero_fw, hero_fh) * sc
		var box := Rect2(Vector2(2, 2) * k, Vector2(26, 26) * k)
		draw_texture_rect_region(hero_sprite, Rect2((box.get_center() - sz / 2.0).floor(), sz), Rect2(0, 0, hero_fw, hero_fh))
	var font := get_theme_default_font()
	var fs := UIKit.font_px(UIKit.font_size)
	var x0 := (BG_MARGIN_L + 2) * k
	draw_string_outline(font, Vector2(x0, fs * 0.95), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(k), Color.BLACK)
	draw_string(font, Vector2(x0, fs * 0.95), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffff44"))
	# bars stacked under the title
	var bw := w - x0 - BG_MARGIN_R * k - 2 * k
	var y := fs * 1.15
	var bh := maxf(6.0, (h - y - 3 * k) / maxf(1.0, bars.size()))
	for b in bars:
		var r: Rect2 = BARS[b.kind]
		draw_rect(Rect2(x0, y, bw, bh - k), Color(0, 0, 0, 0.55))
		var f := clampf(float(b.frac), 0.0, 1.0)
		if f > 0.0: draw_texture_rect_region(tex, Rect2(x0, y, bw * f, bh - k), Rect2(r.position, Vector2(maxf(1.0, r.size.x * f), r.size.y)))
		var tfs := UIKit.font_px(minf(fs * 0.8, bh * 0.95))
		draw_string_outline(font, Vector2(x0 + 2 * k, y + bh * 0.78), b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, int(k), Color.BLACK)
		draw_string(font, Vector2(x0 + 2 * k, y + bh * 0.78), b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color.WHITE)
		y += bh
