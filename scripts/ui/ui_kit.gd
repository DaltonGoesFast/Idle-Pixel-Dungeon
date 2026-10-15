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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a241c"); sb.border_color = Color("5a4a32")
	sb.set_border_width_all(2); sb.set_corner_radius_all(6); sb.set_content_margin_all(font_size * 0.6)
	p.add_theme_stylebox_override("panel", sb)
	return p

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
	var th := Theme.new()
	th.default_font_size = fs
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("4a3b28"); normal.border_color = Color("8a6d42")
	normal.set_border_width_all(2); normal.set_corner_radius_all(6); normal.set_content_margin_all(fs * 0.4)
	var hover := normal.duplicate(); hover.bg_color = Color("5c4930")
	var pressed := normal.duplicate(); pressed.bg_color = Color("6e5636"); pressed.border_color = Color("ffd27a")
	var disabled := normal.duplicate(); disabled.bg_color = Color("2e261c"); disabled.border_color = Color("3e3324")
	for t in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
		th.set_stylebox(t[0], "Button", t[1])
	th.set_color("font_disabled_color", "Button", Color("7a6a55"))
	th.set_color("font_color", "Label", Color("eee3cf"))
	var tab := normal.duplicate(); tab.set_content_margin_all(fs * 0.5)
	var tab_sel := pressed.duplicate(); tab_sel.set_content_margin_all(fs * 0.5)
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
