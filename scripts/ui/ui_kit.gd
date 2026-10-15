## UIKit: small helpers for building touch-friendly UI in code (big targets, SPD item icons).
class_name UIKit
extends RefCounted

static var font_size := 24
static var _items_tex: Texture2D

## SPD's pixel_font.ttf draws one font pixel per 100 units (2048 per em), so sizes that are
## multiples of 20.48 give whole-pixel glyphs. Every text size is snapped to that grid (DECISIONS #71).
const FONT_PX := 20.48
static func font_px(sz: float) -> int:
	return int(round(maxf(1.0, round(sz / FONT_PX)) * FONT_PX))

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
	l.add_theme_font_size_override("font_size", font_px(font_size * scale))
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
static var _toolbar_tex: Texture2D
static var _toolbar_k := 0
static var _ui_icons := {}

## App version shown on Camp and Settings (project.godot application/config/version).
static func version() -> String:
	return "v" + String(ProjectSettings.get_setting("application/config/version", "?"))

## SPD toolbar.png, upscaled like the chrome atlas.
static func _toolbar_atlas() -> Texture2D:
	if _toolbar_tex == null or _toolbar_k != px_scale:
		var img: Image = (load("res://assets/ui/toolbar.png") as Texture2D).get_image()
		img.resize(img.get_width() * px_scale, img.get_height() * px_scale, Image.INTERPOLATE_NEAREST)
		_toolbar_tex = ImageTexture.create_from_image(img); _toolbar_k = px_scale
	return _toolbar_tex

## SPD toolbar button frame (grey bevelled slot, toolbar.png 64,0 22x24, 3px border).
static func toolbar_style(tint := Color.WHITE) -> StyleBoxTexture:
	var k := px_scale
	var sb := StyleBoxTexture.new()
	sb.texture = _toolbar_atlas(); sb.region_rect = Rect2(64 * k, 0, 22 * k, 24 * k)
	sb.set_texture_margin_all(3 * k); sb.modulate_color = tint
	sb.set_content_margin_all(maxf(3 * k, font_size * 0.3))
	return sb

## SPD toolbar icons: backpack / wait (clock) / search (magnifier), from toolbar.png.
const TOOLBAR_ICONS := {"backpack": Rect2(161, 0, 14, 15), "wait": Rect2(178, 2, 12, 12), "search": Rect2(194, 2, 12, 12)}
static func toolbar_icon(name: String) -> Texture2D:
	if not _ui_icons.has(name):
		var at := AtlasTexture.new(); at.atlas = load("res://assets/ui/toolbar.png"); at.region = TOOLBAR_ICONS[name]
		var img := at.get_image(); img.resize(int(at.region.size.x) * px_scale, int(at.region.size.y) * px_scale, Image.INTERPOLATE_NEAREST)
		_ui_icons[name] = ImageTexture.create_from_image(img)
	return _ui_icons[name]

## Restyle a button as an SPD toolbar slot (used for the in-run action bars).
static func as_toolbar(b: Button, icon_name := "") -> Button:
	b.add_theme_stylebox_override("normal", toolbar_style())
	b.add_theme_stylebox_override("hover", toolbar_style(Color(1.12, 1.12, 1.12)))
	b.add_theme_stylebox_override("pressed", toolbar_style(Color(0.8, 0.8, 0.8)))
	b.add_theme_stylebox_override("disabled", toolbar_style(Color(0.55, 0.55, 0.55)))
	b.add_theme_color_override("font_color", Color("ffffff"))
	b.add_theme_color_override("font_outline_color", Color("000000"))
	b.add_theme_constant_override("outline_size", maxi(2, px_scale))
	if icon_name != "": b.icon = toolbar_icon(icon_name); b.expand_icon = false
	return b
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
	th.default_font_size = font_px(fs)
	if pixel_font == null:
		pixel_font = load("res://assets/fonts/pixel_font.ttf")
		pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		pixel_font.hinting = TextServer.HINTING_NONE
		var sys := SystemFont.new()   # glyphs the pixel font lacks (project custom_font is the pixel font itself)
		sys.font_names = PackedStringArray(["sans-serif"])
		pixel_font.fallbacks = [sys]
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
	# progress bars: SPD toast frame + the status pane's yellow exp strip
	var pb_bg := chrome("toast", Color(0.7, 0.7, 0.7), 0)
	var pb_fg := StyleBoxTexture.new(); pb_fg.texture = load("res://assets/ui/status_pane.png"); pb_fg.region_rect = Rect2(0, 121, 128, 7)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fg)
	th.set_constant("separation", "VBoxContainer", int(fs * 0.4))
	th.set_constant("separation", "HBoxContainer", int(fs * 0.4))
	# fat scrollbars for touch
	var grab := chrome("grey_button", Color.WHITE, fs * 0.3)
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("scroll", "VScrollBar", chrome("toast", Color(0.6, 0.6, 0.6), fs * 0.15))
	# sliders (Settings): SPD grey slot + red knob colour
	th.set_stylebox("slider", "HSlider", chrome("toast", Color(0.7, 0.7, 0.7), fs * 0.15))
	th.set_stylebox("grabber_area", "HSlider", chrome("red_button", Color.WHITE, fs * 0.15))
	th.set_stylebox("grabber_area_highlight", "HSlider", chrome("red_button", Color(1.15, 1.15, 1.15), fs * 0.15))
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_outline_color", "Button", Color.BLACK)
	th.set_constant("outline_size", "Button", px_scale)
	th.set_color("font_outline_color", "Label", Color.BLACK)
	return th
