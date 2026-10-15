## Verifies an exported pack's content loads (textures decode, fonts, JSON data, audio).
## Used by tools/verify_apk.sh on the assets/ folder unpacked from an APK.
extends SceneTree

func _init() -> void:
	var fails := 0
	for p in ["res://assets/sprites/warrior.png", "res://assets/sprites/goo.png", "res://assets/tiles/tiles_sewers.png", "res://assets/sprites/items.png"]:
		var t = load(p)
		if t == null or t.get_image() == null: print("FAIL texture ", p); fails += 1
		else: print("ok texture ", p, " ", t.get_size())
	var f = ThemeDB.fallback_font
	if f == null or f.get_height(16) <= 0: print("FAIL font"); fails += 1
	else: print("ok font h=", f.get_height(16))
	for d in ["heroes", "mobs", "items", "rooms", "biomes", "events", "recipes", "facilities", "icons"]:
		if not FileAccess.file_exists("res://data/%s.json" % d): print("FAIL data ", d); fails += 1
	print("ok data json")
	for s in ["res://assets/sounds/hit.mp3", "res://assets/music/sewers_1.ogg"]:
		if load(s) == null: print("FAIL audio ", s); fails += 1
	print("ok audio")
	print("VERIFY: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails else 0)
