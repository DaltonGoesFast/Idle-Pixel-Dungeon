## UIKit: small helpers for building touch-friendly UI in code (big targets, SPD item icons).
class_name UIKit
extends RefCounted

static var font_size := 24
static var _items_tex: Texture2D

static func btn_height() -> float:
	return font_size * 2.4

static func button(text: String, cb: Callable, enabled := true, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size.y = btn_height()
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tooltip != "": b.tooltip_text = tooltip
	b.pressed.connect(func(): Sfx.play("click"); cb.call())
	return b

## A button that shows why it is disabled underneath (reason == "" => enabled).
static func action(text: String, cb: Callable, reason: String) -> Control:
	var v := VBoxContainer.new()
	v.add_child(button(text, cb, reason == ""))
	if reason != "":
		var l := label(reason, 0.75, Color("c9a96e"))
		v.add_child(l)
	return v

static func label(text: String, scale := 1.0, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(font_size * scale))
	if color != Color.WHITE: l.add_theme_color_override("font_color", color)
	return l

static func header(text: String) -> Label:
	return label(text, 1.3, Color("ffd27a"))

static func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", chrome("window"))
	return p

# ------------------------------------------------------------ SPD chrome (interfaces/chrome.png 9-patches, DECISIONS #66)
## name -> [x, y, w, h, margin] in chrome.png pixels (from SPD Chrome.java)
const CHROME := {"window": [0, 0, 20, 20, 6], "silver": [86, 0, 22, 22, 7], "toast": [20, 0, 9, 9, 4],
	"toast_tr": [20, 9, 9, 9, 4], "red_button": [38, 0, 6, 6, 2], "grey_button": [38, 6, 6, 6, 2],
	"tab_set": [64, 0, 20, 20, 6], "tab_selected": [65, 22, 8, 13, 3], "tab_unselected": [75, 22, 8, 13, 3]}
static var px_scale := 3
static var _chrome_tex: Texture2D
static var _chrome_k := 0
static var pixel_font: FontFile

## The chrome atlas upscaled by an integer factor (nearest) so 9-patch borders stay crisp pixels.
static func _chrome_atlas() -> Texture2D:
	if _chrome_tex == null or _chrome_k != px_scale:
		var img: Image = (load("res://assets/ui/chrome.png") as Texture2D).get_image()
		img.resize(img.get_width() * px_scale, img.get_height() * px_scale, Image.INTERPOLATE_NEAREST)
		_chrome_tex = ImageTexture.create_from_image(img); _chrome_k = px_scale
	return _chrome_tex

static func chrome(name: String, tint := Color.WHITE, pad := -1.0) -> StyleBoxTexture:
	var r: Array = CHROME[name]; var k := px_scale
	var sb := StyleBoxTexture.new()
	sb.texture = _chrome_atlas()
	sb.region_rect = Rect2(r[0] * k, r[1] * k, r[2] * k, r[3] * k)
	sb.set_texture_margin_all(r[4] * k)
	sb.modulate_color = tint
	sb.set_content_margin_all(pad if pad >= 0 else maxf(r[4] * k, font_size * 0.5))
	return sb

static func vbox(parent: Control = null, sep := -1) -> VBoxContainer:
	var v := VBoxContainer.new()
	if sep >= 0: v.add_theme_constant_override("separation", sep)
	if parent: parent.add_child(v)
	return v

static func hbox(parent: Control = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	if parent: parent.add_child(h)
	return h

## SPD item icon (16x16 cell in items.png) scaled to `px` with nearest filtering.
static func icon(id: String, px := -1) -> TextureRect:
	if _items_tex == null: _items_tex = load("res://assets/sprites/items.png")
	var at := AtlasTexture.new()
	at.atlas = _items_tex
	var idx := DB.icon_index(id)
	at.region = Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16)
	var t := TextureRect.new()
	t.texture = at
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s := px if px > 0 else int(font_size * 1.5)
	s = maxi(16, int(s / 16) * 16)
	t.custom_minimum_size = Vector2(s, s)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tint: String = DB.materials.get(id, {}).get("tint", "")
	if tint != "": t.modulate = Color(tint)
	return t

## Row: [icon] text
static func icon_row(id: String, text: String, scale := 1.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_child(icon(id))
	var l := label(text, scale)
	if text.length() < 12: l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c); c.queue_free()

static func make_theme(fs: int) -> Theme:
	font_size = fs
	px_scale = clampi(int(round(fs / 9.0)), 2, 6)
	var th := Theme.new()
	th.default_font_size = fs
	if pixel_font == null:
		pixel_font = load("res://assets/fonts/pixel_font.ttf")
		pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		pixel_font.hinting = TextServer.HINTING_NONE
		pixel_font.fallbacks = [ThemeDB.fallback_font]
	th.default_font = pixel_font
	var bp := fs * 0.4
	var normal := chrome("red_button", Color.WHITE, bp)
	var hover := chrome("red_button", Color(1.15, 1.15, 1.15), bp)
	var pressed := chrome("red_button", Color(1.4, 1.4, 1.4), bp)
	var disabled := chrome("grey_button", Color(0.6, 0.6, 0.6), bp)
	for t in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
		th.set_stylebox(t[0], "Button", t[1])
	th.set_color("font_disabled_color", "Button", Color("7a6a55"))
	th.set_color("font_color", "Label", Color("eee3cf"))
	var tab := chrome("tab_unselected", Color.WHITE, fs * 0.5)
	var tab_sel := chrome("tab_selected", Color.WHITE, fs * 0.5)
	th.set_stylebox("panel", "PanelContainer", chrome("window"))
	th.set_stylebox("panel", "TabContainer", chrome("tab_set"))
	th.set_stylebox("tab_unselected", "TabBar", tab)
	th.set_stylebox("tab_hovered", "TabBar", hover)
	th.set_stylebox("tab_selected", "TabBar", tab_sel)
	var pb_bg := StyleBoxFlat.new(); pb_bg.bg_color = Color("1f1a14"); pb_bg.set_corner_radius_all(4)
	var pb_fg := StyleBoxFlat.new(); pb_fg.bg_color = Color("d9a441"); pb_fg.set_corner_radius_all(4)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fg)
	th.set_constant("separation", "VBoxContainer", int(fs * 0.4))
	th.set_constant("separation", "HBoxContainer", int(fs * 0.4))
	# fat scrollbars for touch
	var grab := StyleBoxFlat.new(); grab.bg_color = Color("8a6d42"); grab.set_corner_radius_all(4); grab.content_margin_left = fs * 0.3; grab.content_margin_right = fs * 0.3
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("scroll", "VScrollBar", pb_bg)
	return th
