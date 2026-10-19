class_name TouchScroll
extends Node
## Phone-friendly scrolling for every ScrollContainer (DECISIONS #93).
## Godot's built-in drag loses to Buttons/slots that eat the press, so this node watches raw pointer input
## (touch is emulated as mouse) before the GUI does:
## - a press inside a scrollable ScrollContainer is remembered; nothing is consumed yet, so taps still work;
## - once the pointer moves more than THRESHOLD px (scaled for the screen), it becomes a drag: the press under
##   the finger is cancelled (a synthetic pointer-out motion, so the Button won't fire on release), and the
##   innermost container that can scroll on the drag axis follows the finger;
## - on release the drag velocity carries on with exponential friction (kinetic scroll).

const THRESHOLD_FS := 0.55      # drag threshold as a fraction of the UI font size (~12-16 px on the Fold)
const FRICTION := 4.0           # velocity decays by e^-FRICTION per second
const MIN_SPEED := 20.0         # px/s below which momentum stops

var press_pos := Vector2.ZERO
var pressing := false
var dragging := false
var target: ScrollContainer
var _chain: Array = []          # scrollable ancestors, innermost first
var vel := Vector2.ZERO
var _last_t := 0
var _cancel := false            # our own synthetic event: let it through untouched
var momentum: ScrollContainer
var _masked: BaseButton          # button whose press we cancelled (mask restored after the release)
var _hov: Control

## Topmost visible Control under `p` that takes mouse input (own hit test: works headless and in tests).
func control_at(n: Node, p: Vector2) -> Control:
	for i in range(n.get_child_count() - 1, -1, -1):
		var ch := n.get_child(i)
		if (ch is CanvasItem or ch is CanvasLayer) and not ch.visible: continue
		var hit := control_at(ch, p)
		if hit: return hit
	if n is Control and n.is_visible_in_tree() and n.mouse_filter != Control.MOUSE_FILTER_IGNORE and n.get_global_rect().has_point(p):
		# clipped away by a scrolling ancestor? then it is not really under the finger
		var a := n.get_parent()
		while a:
			if a is Control and a.clip_contents and not a.get_global_rect().has_point(p): return null
			a = a.get_parent()
		return n
	return null

func threshold() -> float:
	return clampf(UIKit.font_size * THRESHOLD_FS, 10.0, 16.0)

static func can_scroll(sc: ScrollContainer, axis: int) -> bool:
	if not is_instance_valid(sc) or not sc.is_visible_in_tree() or sc.get_child_count() == 0: return false
	var bar: ScrollBar = sc.get_v_scroll_bar() if axis == 1 else sc.get_h_scroll_bar()
	var mode := sc.vertical_scroll_mode if axis == 1 else sc.horizontal_scroll_mode
	return mode != ScrollContainer.SCROLL_MODE_DISABLED and bar.max_value - bar.page > 1.0

static func scroll_chain(c: Control) -> Array:
	var out := []
	var n: Node = c
	while n:
		if n is ScrollContainer: out.append(n)
		n = n.get_parent()
	return out

func _input(e: InputEvent) -> void:
	if _cancel: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			momentum = null; vel = Vector2.ZERO
			var hov := control_at(get_tree().root, e.position)
			if hov == null or hov is ScrollBar or hov is Slider: pressing = false; return
			_hov = hov; _chain = scroll_chain(hov)
			pressing = not _chain.is_empty(); dragging = false; press_pos = e.position; _last_t = Time.get_ticks_usec()
		else:
			if dragging:
				get_viewport().set_input_as_handled()   # the finger lifted after a drag: never a tap
				if vel.length() > MIN_SPEED: momentum = target
				if _masked: (func(b): if is_instance_valid(b): b.button_mask = MOUSE_BUTTON_MASK_LEFT).call_deferred(_masked); _masked = null
			pressing = false; dragging = false
	elif e is InputEventMouseMotion and pressing:
		var d: Vector2 = e.position - press_pos
		if not dragging:
			if d.length() < threshold(): return
			var axis := 1 if absf(d.y) >= absf(d.x) else 0
			target = null
			for sc in _chain:     # innermost container that can scroll this way (no nested conflicts)
				if can_scroll(sc, axis): target = sc; break
			if target == null: pressing = false; return
			dragging = true
			_cancel_press(e.position)
		var now := Time.get_ticks_usec(); var dt := maxf(0.001, (now - _last_t) / 1e6); _last_t = now
		var rel: Vector2 = e.relative
		target.scroll_vertical -= int(round(rel.y)); target.scroll_horizontal -= int(round(rel.x))
		vel = vel.lerp(-rel / dt, 0.5)
		get_viewport().set_input_as_handled()

## Tell the control under the finger the pointer left it, so its pending press is dropped.
func _cancel_press(pos: Vector2) -> void:
	_cancel = true
	var m := InputEventMouseMotion.new(); m.position = Vector2(-10000, -10000); m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)
	_cancel = false
	# and mask the button under it so the release can't fire `pressed` (restored after the release)
	var n: Node = _hov
	while n and not (n is BaseButton) and not (n is ScrollContainer): n = n.get_parent()
	if n is BaseButton: _masked = n; _masked.button_mask = 0
	var f := get_viewport().gui_get_focus_owner()
	if f is BaseButton: f.release_focus()

func _process(delta: float) -> void:
	if momentum == null: return
	if not is_instance_valid(momentum) or vel.length() < MIN_SPEED: momentum = null; return
	var before := Vector2(momentum.scroll_horizontal, momentum.scroll_vertical)
	momentum.scroll_vertical += int(round(vel.y * delta)); momentum.scroll_horizontal += int(round(vel.x * delta))
	vel *= exp(-FRICTION * delta)
	if Vector2(momentum.scroll_horizontal, momentum.scroll_vertical) == before: momentum = null   # hit an end

## Theme every ScrollContainer as it enters the tree: wide SPD scrollbars, a small deadzone.
static func style(sc: ScrollContainer) -> void:
	sc.scroll_deadzone = 12
	var w := float(maxi(10, int(UIKit.font_size * 0.5)))
	sc.get_v_scroll_bar().custom_minimum_size.x = w; sc.get_h_scroll_bar().custom_minimum_size.y = w
	# container-level drag is ours; let children pass events up
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
