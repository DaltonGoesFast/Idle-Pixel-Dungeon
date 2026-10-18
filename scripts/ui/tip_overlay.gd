## TipOverlay: modal tutorial card drawn above every screen (first-run onboarding + contextual tips).
## Content comes from data/tutorial.json; Main queues tips and screens check `Main.tip_open()` to pause.
extends Control

signal closed(id: String)

var queue: Array = []      # [{id, pages}]
var page := 0
var box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false

func is_open() -> bool:
	return visible

func push(id: String) -> void:
	if queue.any(func(q): return q.id == id): return
	var t: Dictionary = DB.tips[id]
	queue.append({"id": id, "pages": t.get("pages", [t])})
	if queue.size() == 1: page = 0; _render()

## A one-off card in the same tip look (not from tutorial.json, not affected by "Skip tips"): goes first in the
## queue; OK calls on_ok. link_text/url add a second button that opens the url (DECISIONS #197 data notice).
func push_notice(id: String, title: String, text: String, on_ok: Callable, link_text := "", url := "") -> void:
	if queue.any(func(q): return q.id == id): return
	queue.push_front({"id": id, "pages": [{"title": title, "text": text}], "notice": true, "on_ok": on_ok, "link": link_text, "url": url})
	page = 0; _render()

var card: PanelContainer
var _tween: Tween

## Card width for an overlay of size `vs`: at most 26 em, always leaving a margin on both sides.
static func card_width(vs: Vector2) -> float:
	return floorf(minf(vs.x - 2.0 * margin(vs), UIKit.font_size * 26.0))

static func margin(vs: Vector2) -> float:
	return floorf(maxf(UIKit.font_size * 0.75, vs.x * 0.04))

## The card is laid out by containers (MarginContainer -> CenterContainer), so it is always centred on the
## overlay's real size after its wrapped text is measured; it fades in only once it has been sized (DECISIONS #95).
func _render() -> void:
	for c in get_children(): c.queue_free()
	if queue.is_empty(): visible = false; return
	visible = true
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(dim)
	var cur: Dictionary = queue[0]
	var p: Dictionary = cur.pages[page]
	var vs := size if size.x > 0 else get_viewport_rect().size
	var m := margin(vs)
	var mc := MarginContainer.new(); mc.set_anchors_and_offsets_preset(PRESET_FULL_RECT); mc.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]: mc.add_theme_constant_override("margin_" + side, int(m))
	add_child(mc)
	var cc := CenterContainer.new(); cc.mouse_filter = MOUSE_FILTER_IGNORE; mc.add_child(cc)
	card = UIKit.card(); cc.add_child(card)
	var w := card_width(vs)
	card.custom_minimum_size.x = w
	box = UIKit.vbox(card)
	var h := UIKit.header(p.title); h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; h.custom_minimum_size.x = 1; box.add_child(h)
	var l := UIKit.label(p.text); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 1
	l.size_flags_horizontal = SIZE_EXPAND_FILL; box.add_child(l)
	if cur.pages.size() > 1: box.add_child(UIKit.label("%d / %d" % [page + 1, cur.pages.size()], 0.75, Color("9a8f7c")))
	var row := UIKit.hbox(box)
	if cur.get("notice", false):
		var okn := UIKit.button("OK", next); okn.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(okn)
		var btns: Array = [okn]
		if String(cur.get("link", "")) != "":
			var u := String(cur.url)
			var lk := UIKit.button(String(cur.link), func(): OS.shell_open(u)); lk.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(lk)
			btns.append(lk)
		for b in btns: b.clip_text = true; b.custom_minimum_size.x = 1
		card.modulate.a = 0.0
		var mn := card
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(mn): return
		if _tween: _tween.kill()
		_tween = create_tween(); _tween.tween_property(mn, "modulate:a", 1.0, 0.15)
		return
	var last: bool = page >= cur.pages.size() - 1
	var ok := UIKit.button("Got it" if last else "Next", next); ok.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(ok)
	var skip := UIKit.button("Skip tips", skip_all); skip.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(skip)
	for b in [ok, skip]: b.clip_text = true; b.custom_minimum_size.x = 1
	card.modulate.a = 0.0
	var me := card
	await get_tree().process_frame
	await get_tree().process_frame   # wrapped label heights settle on the second pass
	if not is_instance_valid(me): return
	if _tween: _tween.kill()
	_tween = create_tween(); _tween.tween_property(me, "modulate:a", 1.0, 0.15)

func next() -> void:
	if queue.is_empty(): return
	Sfx.play("click")
	page += 1
	if page >= queue[0].pages.size(): _finish_current()
	else: _render()

func _finish_current() -> void:
	var cur: Dictionary = queue.pop_front()
	var id: String = cur.id
	if cur.get("notice", false):
		var cb: Callable = cur.get("on_ok", Callable())
		if cb.is_valid(): cb.call()
	elif not (id in GameState.tutorial_done): GameState.tutorial_done.append(id)
	SaveSystem.save_game()
	page = 0
	closed.emit(id)
	_render()

func skip_all() -> void:
	GameState.settings.tutorial = false
	while not queue.is_empty() and not queue[0].get("notice", false): _finish_current()
	# a notice stays until its own OK
	queue = queue.filter(func(q): return q.get("notice", false))
	_render()
	GameState.touch()
