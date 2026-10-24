extends SceneTree
func _init() -> void:
	var CS = load("res://scripts/ui/camp_scene.gd")
	var fails := []
	for sz in [Vector2(400,500), Vector2(924,1605), Vector2(1100,750), Vector2(1280,800), Vector2(1800,1000), Vector2(2368,2008)]:
		var scene = CS.new()
		scene.theme = UIKit.make_theme(int(clampf(minf(sz.x,sz.y)/24.0, 14, 60)))
		scene.size = sz
		var cs = 16.0 * scene.k()
		for g in scene.grass_clumps():
			var base: Rect2 = g[0]
			var span = Rect2(base.position - Vector2(0, cs), Vector2(cs, cs * 2.0))
			for s in scene.SPOTS:
				if scene.spot_rect(s).intersects(span):
					fails.append("%s %s hits %s" % [sz, s[0], base.position])
	print("FAILS ", fails.size())
	for f in fails.slice(0, 30): print(f)
	quit(0)
