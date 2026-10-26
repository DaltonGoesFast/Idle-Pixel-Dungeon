## Home-screen patrol widget and return alerts (DECISIONS #229).
## The snapshot and the alarm list are pure data. Android's PatrolWidget plugin stores them and
## draws the widget; PC, web, Vita, and an export without the plugin no-op.
extends Node

signal open_guild

const PLUGIN := "PatrolWidget"
## Camp page a widget or notification tap asks for. Guild, on the Patrols section.
const OPEN_PAGE := "Guild"
const OPEN_SECTION := "patrols"

var queued_open := false

func _ready() -> void:
	var p = _plugin()
	if p != null:
		if p.has_signal("open_guild"):
			p.open_guild.connect(_on_plugin_open)
		if p.has_signal("notification_permission"):
			p.notification_permission.connect(_on_notification_permission)
		if String(p.consumeOpenTarget()) == "guild":
			queued_open = true
	# SaveSystem has already loaded (this autoload is after it). Publish whatever is on disk.
	push()

func _plugin():
	if Engine.has_singleton(PLUGIN):
		return Engine.get_singleton(PLUGIN)
	return null

## True once, when a widget or notification tap asked to open the Guild. Cold start reads the
## plugin before Main connects; later taps arrive on open_guild.
func take_open() -> bool:
	if not queued_open:
		return false
	queued_open = false
	return true

func _on_plugin_open() -> void:
	open_guild.emit()

## Android 13+ asks the first time alerts are turned on. Granted turns the setting on.
## 1 = granted. Anything else leaves alerts off.
func _on_notification_permission(granted: int) -> void:
	if int(granted) != 1:
		GameState.set_setting("patrol_notify", false)
		GameState.say("Patrol alerts stay off until notifications are allowed.")
		SaveSystem.save_game()
		push()
		GameState.touch()
		return
	GameState.set_setting("patrol_notify", true)
	SaveSystem.save_game()
	push()
	GameState.touch()

## Settings toggle. On PC and web, and on Android with no plugin, this only saves the flag.
func set_alerts(on: bool) -> void:
	if on:
		var p = _plugin()
		if p != null and p.has_method("needsNotificationPermission") and bool(p.needsNotificationPermission()):
			p.requestNotificationPermission()
			return
	GameState.set_setting("patrol_notify", on)
	SaveSystem.save_game()
	push()
	GameState.touch()

## Write the current snapshot. No plugin means nothing happens and the game keeps running.
func push(gs = null) -> void:
	var p = _plugin()
	if p == null or not p.has_method("updateSnapshot"):
		return
	p.updateSnapshot(JSON.stringify(snapshot(gs)))

## Widget payload. back_at is a unix timestamp on the wall clock, so the widget can count down
## after the process is gone. reward is the full haul, not whatever has accrued so far.
func snapshot(gs = null) -> Dictionary:
	var g = gs if gs != null else GameState
	var body := {"v": 1, "notify": bool(g.settings.get("patrol_notify", false)), "patrols": _patrol_rows(g)}
	body["alarms"] = alarm_plan(body)
	return body

## One alarm per patrol that is still out. notify is false when the player only wants the widget
## to flip to "Patrol back!" (the plugin still wakes for that, and does not post a notification).
func alarm_plan(snap: Dictionary) -> Array:
	var notify := bool(snap.get("notify", false))
	var out: Array = []
	for row in snap.get("patrols", []):
		if bool(row.get("full", false)):
			continue
		out.append({
			"id": String(row.get("id", "")),
			"at": int(row.get("back_at", 0)),
			"notify": notify,
			"title": "Patrol back!",
			"body": "%s is back from the %s." % [String(row.get("hero", "A hero")), String(row.get("biome", "patrol"))],
		})
	return out

func _patrol_rows(g) -> Array:
	var unix_now := int(floor(Time.get_unix_time_from_system()))
	var rows: Array = []
	for c in g.heroes:
		var p: Dictionary = g.heroes[c].get("patrol", {})
		if p.is_empty() or not DB.biomes.has(p.get("biome", "")):
			continue
		var max_h := float(p.get("max_h", g.patrol_max_hours(c)))
		var back_game := float(p.get("start", g.now())) + max_h * 3600.0
		var remaining := maxf(0.0, back_game - g.now())
		var full := remaining < 0.5
		var back_at := unix_now if full else unix_now + ceili(remaining)
		var full_y: Dictionary = g.patrol_preview(c, back_game)
		rows.append({
			"id": String(c),
			"hero": String(DB.heroes[c].name),
			"biome": String(DB.biomes[p.biome].name),
			"back_at": back_at,
			"full": full,
			"reward": reward_line(full_y),
		})
	rows.sort_custom(func(a, b):
		var af := bool(a.full)
		var bf := bool(b.full)
		if af != bf:
			return af
		return int(a.back_at) < int(b.back_at))
	return rows

## "12 Gold, 4 Iron Ore, 1 curio". Gold first, then the other materials, curios last. Zeros dropped.
static func reward_line(y: Dictionary) -> String:
	var keys: Array = []
	for k in y:
		if String(k).begins_with("_") or int(y[k]) <= 0:
			continue
		keys.append(String(k))
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ag := a == "gold"
		var bg := b == "gold"
		if ag != bg:
			return ag
		return a < b)
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%d %s" % [int(y[k]), DB.mat_name(k)])
	var curios := int(y.get("_curios", 0))
	if curios > 0:
		parts.append("%d curio%s" % [curios, "" if curios == 1 else "s"])
	return ", ".join(parts)
