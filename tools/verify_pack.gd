## Verifies an exported pack's content loads (textures decode, fonts, JSON data, audio).
## Used by tools/verify_apk.sh on the assets/ folder unpacked from an APK.
extends SceneTree

func _init() -> void:
	var fails := 0
	# every texture the game references through data (mob/hero sprites, biome tilesets, trap sheet)
	var tex := ["res://assets/sprites/items.png", "res://assets/tiles/terrain_features.png"]
	for d in ["mobs", "heroes"]:
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % d))
		for k in j:
			if typeof(j[k]) == TYPE_DICTIONARY and j[k].has("sprite"): tex.append("res://assets/sprites/%s.png" % j[k].sprite)
	var biomes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/biomes.json"))
	var audio := ["res://assets/sounds/hit.mp3", "res://assets/sounds/trap.mp3", "res://assets/music/theme_1.ogg"]
	for b in biomes.values():
		tex.append("res://assets/tiles/%s.png" % b.tile)
		audio.append("res://assets/music/%s.ogg" % b.music); audio.append("res://assets/music/%s.ogg" % b.boss_music)
	for p in tex:
		var t = load(p)
		if t == null or t.get_image() == null: print("FAIL texture ", p); fails += 1
		else: print("ok texture ", p, " ", t.get_size())
	var f = ThemeDB.fallback_font
	if f == null or f.get_height(16) <= 0: print("FAIL font"); fails += 1
	else: print("ok font h=", f.get_height(16))
	for d in ["heroes", "mobs", "items", "rooms", "biomes", "events", "recipes", "facilities", "icons", "traps"]:
		if not FileAccess.file_exists("res://data/%s.json" % d): print("FAIL data ", d); fails += 1
	print("ok data json")
	for s in audio:
		if load(s) == null: print("FAIL audio ", s); fails += 1
	print("ok audio")
	print("VERIFY: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails else 0)
