## Headless UI flow smoke test: godot --headless --path . -s tests/flow.gd
extends SceneTree
var m
var f := 0
func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
func _process(_d: float) -> bool:
	f += 1
	if f == 2: m._start_run(); m.progress = 21.9
	if f == 10: print("state after 22%% = ", m.state, " (3=COMBAT)"); m.combat.hero_wait(); m._after_action()
	if f == 12:
		m.state = m.S.DELVE; m.next_enc = 1; m.progress = 45
	if f == 15: print("state at 45%% = ", m.state, " (2=CHOICE)"); m._chest(); print("pack ", m.pack)
	if f == 20:
		root.size = Vector2i(1856, 2160); m._relayout(); print("unfolded vertical=", m.split.vertical)
		root.size = Vector2i(968, 2376); m._relayout(); print("cover vertical=", m.split.vertical)
		m._floor_done(); m._extract(); print("stash ", m.stash, " state ", m.state)
		print("FLOW OK"); quit()
	return false
