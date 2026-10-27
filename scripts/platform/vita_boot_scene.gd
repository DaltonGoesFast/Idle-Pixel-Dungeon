## Vita's first scene. main.gd took ~29s to parse on device (it preloads camp) and db.gd took ~8.5s
## inside the autoload, both before any pixel that is not the flat engine splash. This scene draws
## a loading line first, then does that work one step per frame so the label can paint.
extends Control

var _label: Label
var _step := -1
var _main: PackedScene

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.12, 0.28)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.text = "Loading Idle PD"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_label)
	VitaBoot.mark("boot scene")

func _process(_delta: float) -> void:
	# Even steps only change the label, so the frame can paint before the next load blocks.
	_step += 1
	match _step:
		0:
			return
		1:
			_label.text = "Loading data"
		2:
			VitaBoot.mark("before data")
			DB.reload()
			var had := SaveSystem.load_game()
			if not had and GameState.heroes.is_empty():
				GameState.new_game()
			VitaBoot.mark("data heroes=%d save=%s" % [GameState.heroes.size(), had])
		3:
			_label.text = "Loading camp"
		4:
			VitaBoot.mark("before camp script")
			load("res://scripts/ui/camp_screen.gd")
			VitaBoot.mark("camp script")
		5:
			_label.text = "Loading interface"
		6:
			VitaBoot.mark("before main scene")
			_main = load("res://scenes/main.tscn")
			VitaBoot.mark("main scene")
		7:
			_label.text = "Opening camp"
		_:
			set_process(false)
			get_tree().change_scene_to_packed(_main)
