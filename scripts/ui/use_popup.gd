## UsePopup: the result of using a potion, scroll, ration or torch from the Backpack, as a small SPD message
## window (item sprite + name, then the effect lines, then OK). It used to print at the top of the scrolled Bag
## window, out of sight once the player had scrolled down (DECISIONS #214).
## Lives on its own CanvasLayer just under the tutorial tips' layer, so it draws over every screen window (the
## Bag stays open underneath and is usable again once it closes) while a tip still draws and takes input first.
class_name UsePopup
extends Control

const LAYER := 90   # above every screen window, under Main.TIP_LAYER (100) so tips stay topmost (DECISIONS #213)
const DIM := 0.3
const NODE := "UsePopupLayer"

var title := ""
var lines: Array = []
var item_key := ""
var card: PanelContainer
var _host: Node

## Show `lines` for `key` (shown as `name_text`). Replaces a pop-up that is already open. Returns the pop-up.
static func open(key: String, name_text: String, effect_lines: Array) -> UsePopup:
	var tree := Engine.get_main_loop() as SceneTree
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	close_open()
	var cl := CanvasLayer.new(); cl.name = NODE; cl.layer = LAYER
	var p := UsePopup.new(); p.name = "UsePopup"
	p.item_key = key; p.title = name_text; p.lines = effect_lines.duplicate(); p._host = host
	cl.add_child(p)
	host.add_child(cl)
	return p

## The open pop-up, or null.
static func current() -> UsePopup:
	var tree := Engine.get_main_loop() as SceneTree
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var cl := host.get_node_or_null(NODE)
	if cl == null or cl.is_queued_for_deletion(): return null
	return cl.get_node_or_null("UsePopup") as UsePopup

static func close_open() -> void:
	var p := current()
	if p: p.close(false)

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_STOP
	_render()
	get_viewport().size_changed.connect(_render)

## Tap outside the window closes it, like SPD's windows. A touch also arrives as an emulated mouse click
## (input_devices/pointing/emulate_mouse_from_touch), so the raw touch only counts when that is off; otherwise
## one tap would close twice and click twice (Bugbot on #109).
func _gui_input(e: InputEvent) -> void:
	var tap := e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed
	if e is InputEventScreenTouch and e.pressed and not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true):
		tap = true
	if tap:
		accept_event(); close()

func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled(); close()

## SPD WndMessage look: the window chrome, [sprite] name in the title colour, the lines, one OK button.
func _render() -> void:
	theme = _pick_theme()
	for c in get_children(): c.queue_free()
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, DIM); dim.mouse_filter = MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(dim)
	var vs := size if size.x > 0 else get_viewport_rect().size
	var m := floorf(maxf(UIKit.font_size * 0.75, vs.x * 0.04))
	var cc := CenterContainer.new(); cc.mouse_filter = MOUSE_FILTER_IGNORE; cc.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(cc)
	card = UIKit.card(); card.name = "UsePopupCard"; card.mouse_filter = MOUSE_FILTER_STOP; cc.add_child(card)
	card.custom_minimum_size.x = floorf(minf(vs.x - 2.0 * m, UIKit.font_size * 22.0))
	var v := UIKit.vbox(card)
	var tr := UIKit.hbox(v)
	if item_key != "" and (DB.materials.has(item_key) or DB.items.has(item_key)):
		var ic := UIKit.icon(item_key); ic.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(ic)
	var h := UIKit.header(title); h.name = "UsePopupTitle"; h.custom_minimum_size.x = 1
	h.size_flags_horizontal = SIZE_EXPAND_FILL; h.size_flags_vertical = SIZE_SHRINK_CENTER; tr.add_child(h)
	for t in lines:
		var s := String(t)
		var hi := s.to_lower().begins_with("milestone") or s.to_lower().contains("milestones reached") or s.to_lower().begins_with("level up")
		var l := UIKit.label(s, 0.95, Color("ffff88") if hi else Color.WHITE); l.custom_minimum_size.x = 1
		l.size_flags_horizontal = SIZE_EXPAND_FILL; v.add_child(l)
	var ok := UIKit.button("OK", func(): close(false)); ok.name = "UsePopupOK"; v.add_child(ok)

## A CanvasLayer breaks Control theme inheritance, so take the SPD theme Main built (it rebuilds it on relayout).
func _pick_theme() -> Theme:
	var main_node = _host if is_instance_valid(_host) else null
	if not (main_node is Control and (main_node as Control).theme != null):
		main_node = null
		for c in get_tree().root.find_children("*", "Control", true, false):
			if c.get("tips") != null and (c as Control).theme != null: main_node = c; break
	if main_node: return (main_node as Control).theme
	return get_tree().root.theme

var _closed := false
func close(sfx := true) -> void:
	if _closed: return
	_closed = true
	if sfx: Sfx.play("click")
	var cl := get_parent()
	if cl and cl.name == NODE:
		cl.name = NODE + "_closing"   # a new pop-up opened this frame can take the name
		cl.queue_free()
	else: queue_free()
