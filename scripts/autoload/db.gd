## DB: read-only game content loaded from res://data/*.json.
## All balance numbers live in data files so they can be tuned without touching code.
extends Node

var heroes: Dictionary
var mobs: Dictionary
var items: Dictionary      # equipment/curios (keys not starting with "_")
var materials: Dictionary  # stackable materials & consumables
var icons: Dictionary
var recipes: Dictionary
var facilities: Dictionary
var rooms: Array
var boss_rooms: Array
var biomes: Dictionary
var doors: Array
var specials: Array
var traps: Dictionary
var milestones: Array
var milestone_categories: Array   # display order of milestone categories (DECISIONS #195)
var tips: Dictionary
var talents: Dictionary
var biome_rooms: Dictionary
## Memo of id -> icon cell for stable (non-unknown) ids. Cleared on reload().
var _icon_index_cache: Dictionary = {}

func _init() -> void:
	reload()

func reload() -> void:
	heroes = _strip(_load("heroes"))
	mobs = _strip(_load("mobs"))
	var it := _load("items")
	materials = it.get("_materials", {})
	items = _strip(it)
	icons = _load("icons")
	recipes = _strip(_load("recipes"))
	facilities = _strip(_load("facilities"))
	var r := _load("rooms")
	rooms = r.rooms; boss_rooms = r.boss_rooms; biome_rooms = r.get("biome_rooms", {})
	traps = _strip(_load("traps"))
	var ms: Dictionary = _load("milestones")
	milestones = ms.get("milestones", []); milestone_categories = ms.get("categories", [])
	tips = _load("tutorial").get("tips", {})
	talents = _load("talents")
	biomes = _load("biomes")
	var ev := _load("events")
	doors = ev.doors; specials = ev.specials
	_icon_index_cache.clear()

func _load(name: String) -> Dictionary:
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DB: cannot open " + path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	if typeof(v) != TYPE_DICTIONARY:
		push_error("DB: bad json " + path)
		return {}
	return v

static func _strip(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		if not String(k).begins_with("_"): o[k] = d[k]
	return o

func item(id: String) -> Dictionary:
	return items.get(id, {})

func mat_name(id: String) -> String:
	if materials.get(id, {}).get("unknown", false): return GameState.mat_label(id)
	return materials.get(id, {}).get("name", id.capitalize())

func display_name(id: String) -> String:
	if items.has(id): return items[id].name
	return mat_name(id)

## Icon index into assets/sprites/items.png (16x16 cells, 16 per row).
## Unknown potions/scrolls depend on GameState.looks and are not memoized.
func icon_index(id: String) -> int:
	if _icon_index_cache.has(id): return int(_icon_index_cache[id])
	var idx: int
	if icons.has(id):
		idx = int(icons[id])
	elif materials.get(id, {}).get("unknown", false):
		var lk: String = GameState.mat_icon_key(id)
		idx = int(icons.get(lk, 0)) if lk != "" else 0
		return idx
	else:
		var key: String = items.get(id, materials.get(id, {})).get("icon", "SOMETHING")
		idx = int(icons.get(key, 0))
	_icon_index_cache[id] = idx
	return idx
