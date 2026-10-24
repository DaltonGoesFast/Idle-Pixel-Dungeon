## Keybinds: combat InputMap actions, defaults, rebind helpers, and persistence in GameState.settings.keybinds.
## Desktop-first; Mobile keeps the same map so Auto/Desktop players can use a keyboard on any build.
class_name Keybinds
extends RefCounted

## Display order in Settings. Auto is T (not A) so it does not clash with WASD west.
const ACTION_ORDER: PackedStringArray = [
	"combat_move_n", "combat_move_s", "combat_move_w", "combat_move_e",
	"combat_move_nw", "combat_move_ne", "combat_move_sw", "combat_move_se",
	"combat_wait", "combat_search", "combat_bag", "combat_hint", "combat_auto",
	"combat_potion", "combat_skill_1", "combat_skill_2", "combat_cancel",
]

const LABELS := {
	"combat_move_n": "Move north", "combat_move_s": "Move south",
	"combat_move_w": "Move west", "combat_move_e": "Move east",
	"combat_move_nw": "Move NW", "combat_move_ne": "Move NE",
	"combat_move_sw": "Move SW", "combat_move_se": "Move SE",
	"combat_wait": "Wait", "combat_search": "Search", "combat_bag": "Bag",
	"combat_hint": "Hint", "combat_auto": "Auto battle", "combat_potion": "Potion",
	"combat_skill_1": "Skill 1", "combat_skill_2": "Skill 2", "combat_cancel": "Cancel",
}

## Direction vectors for move_* actions (Chebyshev step).
const MOVE_DIR := {
	"combat_move_n": Vector2i(0, -1), "combat_move_s": Vector2i(0, 1),
	"combat_move_w": Vector2i(-1, 0), "combat_move_e": Vector2i(1, 0),
	"combat_move_nw": Vector2i(-1, -1), "combat_move_ne": Vector2i(1, -1),
	"combat_move_sw": Vector2i(-1, 1), "combat_move_se": Vector2i(1, 1),
}

static func defaults() -> Dictionary:
	return {
		"combat_move_n": [KEY_W, KEY_UP, KEY_KP_8],
		"combat_move_s": [KEY_S, KEY_DOWN, KEY_KP_2],
		"combat_move_w": [KEY_A, KEY_LEFT, KEY_KP_4],
		"combat_move_e": [KEY_D, KEY_RIGHT, KEY_KP_6],
		"combat_move_nw": [KEY_Q, KEY_KP_7],
		"combat_move_ne": [KEY_E, KEY_KP_9],
		"combat_move_sw": [KEY_Z, KEY_KP_1],
		"combat_move_se": [KEY_C, KEY_KP_3],
		"combat_wait": [KEY_SPACE, KEY_KP_5],
		"combat_search": [KEY_R],
		"combat_bag": [KEY_I],
		"combat_hint": [KEY_H],
		"combat_auto": [KEY_T],
		"combat_potion": [KEY_P],
		"combat_skill_1": [KEY_1],
		"combat_skill_2": [KEY_2],
		"combat_cancel": [KEY_ESCAPE],
	}

## Merged map: defaults overridden by settings.keybinds (action -> array of keycode ints).
static func resolved(settings: Dictionary = GameState.settings) -> Dictionary:
	var out := defaults()
	var saved = settings.get("keybinds", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return out
	for action in out.keys():
		if not saved.has(action):
			continue
		var raw = saved[action]
		if typeof(raw) != TYPE_ARRAY:
			continue
		var keys: Array = []
		for k in raw:
			var code := int(k)
			if code > 0:
				keys.append(code)
		out[action] = keys
	return out

## Install or refresh every combat_* action on the InputMap from settings.
static func apply(settings: Dictionary = GameState.settings) -> void:
	var map := resolved(settings)
	for action in ACTION_ORDER:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for code in map.get(action, []):
			var ev := InputEventKey.new()
			ev.keycode = int(code) as Key
			InputMap.action_add_event(action, ev)

## Human-readable keys for an action ("W, Up, Numpad 8").
static func binding_text(action: String, settings: Dictionary = GameState.settings) -> String:
	var keys: Array = resolved(settings).get(action, [])
	if keys.is_empty():
		return "(none)"
	var parts: PackedStringArray = []
	for code in keys:
		parts.append(OS.get_keycode_string(int(code) as Key))
	return ", ".join(parts)

## Replace an action's keys with a single keycode; clears that key from other combat actions. Saves settings.
static func rebind(action: String, keycode: int) -> void:
	if action not in ACTION_ORDER or keycode <= 0:
		return
	var saved: Dictionary = GameState.settings.get("keybinds", {}).duplicate(true)
	if typeof(GameState.settings.get("keybinds", {})) != TYPE_DICTIONARY:
		saved = {}
	for other in ACTION_ORDER:
		var cur: Array = resolved().get(other, []).duplicate()
		cur = cur.filter(func(k): return int(k) != keycode)
		if other == action:
			cur = [keycode]
		# Only store overrides that differ from defaults to keep saves small; store all rebound for clarity.
		saved[other] = cur
	GameState.set_setting("keybinds", saved)
	apply()
	SaveSystem.save_game()

## Clear custom keybinds and restore defaults.
static func reset_defaults() -> void:
	GameState.set_setting("keybinds", {})
	apply()
	SaveSystem.save_game()

## True when the event just pressed this action (ignores echo).
static func just_pressed(action: String, event: InputEvent) -> bool:
	return event.is_action_pressed(action) and not event.is_echo()
