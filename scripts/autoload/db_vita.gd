## Vita stand-in for DB. Parsing db.gd during autoload took ~8.5s on device, before the loading
## card existed. reload() loads that script on the card ("Loading data"), then reads the JSON.
## Desktop, Android, and web keep scripts/autoload/db.gd as the DB autoload.
extends Node

var _real: Node

func _ensure() -> Node:
	if _real == null:
		var scr: Script = load("res://scripts/autoload/db.gd")
		_real = scr.new()
		_real.name = "DBReal"
		add_child(_real)
	return _real

func reload() -> void:
	_ensure().reload()

func item(id: String) -> Dictionary:
	return _ensure().item(id)

func mat_name(id: String) -> String:
	return _ensure().mat_name(id)

func display_name(id: String) -> String:
	return _ensure().display_name(id)

func icon_index(id: String) -> int:
	return _ensure().icon_index(id)

func _get(property: StringName) -> Variant:
	return _ensure().get(property)
