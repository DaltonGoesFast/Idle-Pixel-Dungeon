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

func _render() -> void:
	for c in get_children(): c.queue_free()
	if queue.is_empty(): visible = false; return
	visible = true
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(dim)
	var cur: Dictionary = queue[0]
	var p: Dictionary = cur.pages[page]
	var vs := get_viewport_rect().size
	var card := UIKit.card(); add_child(card)
	var w := minf(vs.x * 0.9, UIKit.font_size * 26.0)
	card.custom_minimum_size.x = w
	box = UIKit.vbox(card)
	box.add_child(UIKit.header(p.title))
	var l := UIKit.label(p.text); l.custom_minimum_size.x = w - UIKit.font_size * 1.5; box.add_child(l)
	if cur.pages.size() > 1: box.add_child(UIKit.label("%d / %d" % [page + 1, cur.pages.size()], 0.75, Color("9a8f7c")))
	var row := UIKit.hbox(box)
	var last: bool = page >= cur.pages.size() - 1
	var ok := UIKit.button("Got it" if last else "Next", next); ok.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(ok)
	var skip := UIKit.button("Skip all tips", skip_all); skip.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(skip)
	await get_tree().process_frame
	if is_instance_valid(card): card.position = ((vs - card.size) / 2.0).floor()

func next() -> void:
	if queue.is_empty(): return
	Sfx.play("click")
	page += 1
	if page >= queue[0].pages.size(): _finish_current()
	else: _render()

func _finish_current() -> void:
	var id: String = queue.pop_front().id
	if not (id in GameState.tutorial_done): GameState.tutorial_done.append(id)
	SaveSystem.save_game()
	page = 0
	closed.emit(id)
	_render()

func skip_all() -> void:
	GameState.settings.tutorial = false
	while not queue.is_empty(): _finish_current()
	GameState.touch()
