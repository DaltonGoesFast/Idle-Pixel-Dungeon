## Renders screenshots of combat at cover + inner sizes (needs a display, e.g. xvfb-run)
extends SceneTree
var m; var f := 0
func _init() -> void:
	m = load("res://main.tscn").instantiate(); root.add_child(m)
func _process(_d: float) -> bool:
	f += 1
	if f == 3: m._start_run(); m._start_combat(0); m.combat.hero_wait(); m._after_action()
	if f == 10: root.get_texture().get_image().save_png("/workspace/builds/shot_cover.png"); get_root().size = Vector2i(1856, 2160) ; DisplayServer.window_set_size(Vector2i(928,1080))
	if f == 20: root.get_texture().get_image().save_png("/workspace/builds/shot_inner.png"); quit()
	return false
