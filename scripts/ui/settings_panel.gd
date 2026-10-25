## SettingsPanel: builds the settings controls into any container (Camp "Settings" tab and the
## in-delve Settings card share it). All values live in GameState.settings and are saved.
## Categories use the vendor Upgrade fold pattern (DECISIONS #175): each section is a full-width
## tab that expands on tap; open/closed is remembered for the session in section_open.
class_name SettingsPanel
extends RefCounted

const Keybinds := preload("res://scripts/ui/keybinds.gd")

const TEXT_SIZES := [["Small", 0.85], ["Normal", 1.0], ["Large", 1.15], ["Huge", 1.3]]
const DELVE_SPEEDS := [["Slow", 0.5], ["Normal", 1.0], ["Fast", 1.5], ["Faster", 2.0]]
const INTERFACES := [["Auto", "auto"], ["Mobile", "mobile"], ["Desktop", "desktop"]]

const WIPE_BTN := "Wipe save data"
const WIPE_TITLE := "Wipe save data?"
const WIPE_BODY := "All progress — heroes, camp, gear, milestones — will be permanently deleted. This can't be undone."
const WIPE_CONFIRM := "Wipe"
const WIPE_CANCEL := "Cancel"
const CREDITS := "Art, sounds and music: Shattered Pixel Dungeon by Evan Debenham (GPL-3.0). This game is GPL-3.0. See CREDITS.md."

## Section key -> fold open (kept while the app runs), same idea as CampScreen.fac_open.
static var section_open := {}

## The Developer section (cheats, timer skip) is left out of the browser build (DECISIONS #199).
## Wipe save data is always in the main Settings list, with a confirm (DECISIONS #212).
## Android, Windows and source/editor runs keep Developer tools. A saved dev_tools=true is ignored on web.
static func dev_tools_allowed(is_web: bool = OS.has_feature("web")) -> bool:
	return not is_web

static func build(v: VBoxContainer, show_dev := true, on_wiped: Callable = Callable(), on_rebuild: Callable = Callable()) -> void:
	v.add_child(UIKit.label("SPD Tactics " + UIKit.version(), 0.8, Color("c9a96e")))
	_build_update(v, show_dev, on_wiped, on_rebuild)
	var audio := _section(v, "audio", "Audio", show_dev, on_wiped, on_rebuild)
	if audio:
		for k in [["sfx", "Sound effects"], ["music", "Music"]]:
			var row := UIKit.hbox(audio)
			var l := UIKit.label("%s: %d%%" % [k[1], int(float(GameState.settings[k[0]]) * 100)]); l.custom_minimum_size.x = UIKit.font_size * 10; l.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(l)
			var s := HSlider.new(); s.min_value = 0; s.max_value = 1; s.step = 0.05; s.value = GameState.settings[k[0]]
			s.custom_minimum_size.y = UIKit.btn_height(); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.value_changed.connect(func(x):
				GameState.settings[k[0]] = x; Sfx.refresh_volume(); l.text = "%s: %d%%" % [k[1], int(x * 100)])
			s.drag_ended.connect(func(_c): Sfx.play("click"); SaveSystem.save_game())
			row.add_child(s)
	var feel := _section(v, "feel", "Feel", show_dev, on_wiped, on_rebuild)
	if feel:
		var hap: bool = GameState.settings.get("haptics", true)
		feel.add_child(UIKit.button("Haptics: %s" % ("ON" if hap else "OFF"), func():
			GameState.set_setting("haptics", not hap); Sfx.buzz(50); SaveSystem.save_game(); GameState.touch()))
		feel.add_child(UIKit.label("Vibrates when you take damage, trigger a trap, or an enemy telegraphs an attack (phones only).", 0.75, Color("9a8f7c")))
		var li: bool = GameState.settings.get("lighting", true)
		feel.add_child(UIKit.button("Lighting & fog: %s" % ("ON" if li else "OFF"), func():
			GameState.set_setting("lighting", not li); SaveSystem.save_game(); GameState.touch()))
		feel.add_child(UIKit.label("SPD-style torchlight in fights: the light shrinks as your torch burns down. Turn off for full brightness.", 0.75, Color("9a8f7c")))
	var speed := _section(v, "delve_speed", "Delve speed", show_dev, on_wiped, on_rebuild)
	if speed:
		var sf := HFlowContainer.new(); speed.add_child(sf)
		for t in DELVE_SPEEDS:
			var cur := absf(float(GameState.settings.get("delve_speed", 1.0)) - float(t[1])) < 0.01
			var b := UIKit.button(("> " if cur else "") + t[0], func():
				GameState.set_setting("delve_speed", t[1]); SaveSystem.save_game(); GameState.touch())
			b.custom_minimum_size.x = UIKit.font_size * 5; sf.add_child(b)
		speed.add_child(UIKit.label("How fast the Delve Bar explores (%d s per floor at Normal). The x3 button in a run stacks on top." % int(100.0 / 5.0), 0.75, Color("9a8f7c")))
	var text := _section(v, "text_size", "Text size", show_dev, on_wiped, on_rebuild)
	if text:
		var flow := HFlowContainer.new(); text.add_child(flow)
		for t in TEXT_SIZES:
			var cur := absf(float(GameState.settings.get("text_scale", 1.0)) - float(t[1])) < 0.01
			var b := UIKit.button(("> " if cur else "") + t[0], func():
				GameState.set_setting("text_scale", t[1]); SaveSystem.save_game(); GameState.touch())
			b.custom_minimum_size.x = UIKit.font_size * 5; flow.add_child(b)
	var iface := _section(v, "interface", "Interface", show_dev, on_wiped, on_rebuild)
	if iface:
		var iface_flow := HFlowContainer.new(); iface.add_child(iface_flow)
		var cur_iface := String(GameState.settings.get("interface", "auto"))
		for t in INTERFACES:
			var cur := cur_iface == String(t[1])
			var b := UIKit.button(("> " if cur else "") + t[0], func():
				GameState.set_setting("interface", t[1]); SaveSystem.save_game(); GameState.touch())
			b.custom_minimum_size.x = UIKit.font_size * 5; iface_flow.add_child(b)
		iface.add_child(UIKit.label("Auto uses Desktop on PC and the browser, Mobile on phones. Desktop combat is full-grid with a bottom toolbar like vanilla SPD.", 0.75, Color("9a8f7c")))
	_build_keybinds(v, show_dev, on_wiped, on_rebuild)
	var help := _section(v, "help", "Help", show_dev, on_wiped, on_rebuild)
	if help:
		var tut: bool = GameState.settings.get("tutorial", true)
		help.add_child(UIKit.button("Tutorial tips: %s" % ("ON" if tut else "OFF"), func():
			GameState.set_setting("tutorial", not tut); SaveSystem.save_game(); GameState.touch()))
		help.add_child(UIKit.button("Replay the tutorial tips", func():
			GameState.tutorial_done.clear(); GameState.settings.tutorial = true; SaveSystem.save_game(); GameState.touch()))
	var patrols := _section(v, "patrols", "Patrols", show_dev, on_wiped, on_rebuild)
	if patrols:
		var alerts: bool = GameState.settings.get("patrol_notify", false)
		patrols.add_child(UIKit.button("Patrol alerts: %s" % ("ON" if alerts else "OFF"), func():
			PatrolBridge.set_alerts(not alerts)))
		patrols.add_child(UIKit.label("On Android, a notification when a patrol is ready to recall. Off by default. PC and the browser ignore it.", 0.75, Color("9a8f7c")))
	if show_dev and dev_tools_allowed():
		var dev: bool = GameState.settings.get("dev_tools", false)
		var label := "Developer"
		if dev: label += "  (shown)"
		var body := _section(v, "developer", label, show_dev, on_wiped, on_rebuild)
		if body:
			body.add_child(UIKit.button("Developer tools: %s" % ("shown" if dev else "hidden"), func():
				GameState.set_setting("dev_tools", not dev); GameState.touch()))
			if dev:
				if LiveLayout.desktop_allowed():
					body.add_child(UIKit.button("Open Live Editor (0)", func():
						preload("res://scripts/ui/live_editor.gd").open()))
					body.add_child(UIKit.label("Hotkey 0 (top-row). Second window: drag Camp/UI layout, edit text and balance. Saves to data/*.json (run from the Godot project so res:// is writable).", 0.75, Color("9a8f7c")))
				body.add_child(UIKit.button("Unlock all heroes", func():
					for c in GameState.heroes: GameState.heroes[c].unlocked = true
					GameState.touch()))
				body.add_child(UIKit.button("+100 gold, +10 of every material", func():
					for k in ["gold", "iron_ore", "dark_gold", "seeds", "arcane_resin", "iron_key", "ration", "torch", "potion_healing", "scroll_passage", "scroll_upgrade"]: GameState.add_mat(k, 100 if k == "gold" else 10)
					GameState.touch()))
				body.add_child(UIKit.button("Fast-forward 1 hour (timers)", func(): GameState.skip_time(3600)))
	# Wipe is always in the main Settings list (every platform, Camp and delve), above the credits (DECISIONS #212).
	v.add_child(UIKit.button(WIPE_BTN, func(): show_wipe_confirm(v, show_dev, on_wiped, on_rebuild)))
	v.add_child(UIKit.label(CREDITS, 0.75, Color("9a8f7c")))

## Collapsed category tab: expands a card of options under it. Returns the card body when open, else null.
static func _section(v: VBoxContainer, key: String, label: String, show_dev: bool, on_wiped: Callable, on_rebuild: Callable) -> VBoxContainer:
	var open: bool = bool(section_open.get(key, false))
	var fold := UIKit.button(label, func():
		section_open[key] = not bool(section_open.get(key, false))
		_rebuild(v, show_dev, on_wiped, on_rebuild))
	fold.name = "SettingsFold_%s" % key
	fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fold.autowrap_mode = TextServer.AUTOWRAP_OFF
	if not open: UIKit.secondary(fold)
	v.add_child(fold)
	if not open: return null
	var card := UIKit.card(); v.add_child(card)
	return UIKit.vbox(card)

static func _rebuild(v: VBoxContainer, show_dev: bool, on_wiped: Callable, on_rebuild: Callable) -> void:
	if on_rebuild.is_valid():
		on_rebuild.call()
	else:
		UIKit.clear(v); build(v, show_dev, on_wiped, on_rebuild)

## SPD-style confirm: title, body, Wipe / Cancel. Cancel rebuilds Settings (and any host Close button via on_rebuild); Wipe deletes the save.
static func show_wipe_confirm(v: VBoxContainer, show_dev := true, on_wiped: Callable = Callable(), on_rebuild: Callable = Callable()) -> void:
	UIKit.clear(v)
	v.add_child(UIKit.header(WIPE_TITLE))
	v.add_child(UIKit.label(WIPE_BODY))
	v.add_child(UIKit.button(WIPE_CONFIRM, func(): _do_wipe(on_wiped)))
	v.add_child(UIKit.secondary(UIKit.button(WIPE_CANCEL, func():
		if on_rebuild.is_valid():
			on_rebuild.call()
		else:
			UIKit.clear(v); build(v, show_dev, on_wiped, on_rebuild))))

static func _do_wipe(on_wiped: Callable = Callable()) -> void:
	# Optional telemetry: anonymous id in user://telemetry.cfg is kept (SaveSystem.wipe only clears save.json).
	Telemetry.track("save_wiped", {})
	SaveSystem.wipe()
	if on_wiped.is_valid(): on_wiped.call()

## True when the built panel has the main Wipe save data button (not the confirm).
static func has_wipe_button(v: Node) -> bool:
	for c in v.get_children():
		if c is Button and String(c.text) == WIPE_BTN: return true
	return false

## True when the panel is showing the wipe confirm (title + Wipe + Cancel).
static func is_wipe_confirm(v: Node) -> bool:
	var title := false; var wipe := false; var cancel := false
	for c in v.get_children():
		if c is Label and String(c.text) == WIPE_TITLE: title = true
		elif c is Button and String(c.text) == WIPE_CONFIRM: wipe = true
		elif c is Button and String(c.text) == WIPE_CANCEL: cancel = true
	return title and wipe and cancel

## Combat keybinds list + Rebind / Reset (DECISIONS #232).
static func _build_keybinds(v: VBoxContainer, show_dev: bool, on_wiped: Callable, on_rebuild: Callable) -> void:
	var body := _section(v, "keybinds", "Keybinds", show_dev, on_wiped, on_rebuild)
	if body == null: return
	body.add_child(UIKit.label("Combat controls. Click Rebind, then press a key. Esc cancels listening; Backspace clears that binding.", 0.75, Color("9a8f7c")))
	for action in Keybinds.ACTION_ORDER:
		var row := UIKit.hbox(body)
		var name := UIKit.label(String(Keybinds.LABELS.get(action, action)), 0.85)
		name.custom_minimum_size.x = UIKit.font_size * 8; name.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name)
		var keys := UIKit.label(Keybinds.binding_text(action), 0.8, Color("c9a96e"))
		keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL; keys.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(keys)
		var act := action
		row.add_child(UIKit.button("Rebind", func():
			_show_rebind(v, act, show_dev, on_wiped, on_rebuild)))
	body.add_child(UIKit.button("Reset keybinds", func():
		Keybinds.reset_defaults(); GameState.touch()))

## Listen for the next key; Esc cancels; Backspace clears the action's keys.
static func _show_rebind(v: VBoxContainer, action: String, show_dev: bool, on_wiped: Callable, on_rebuild: Callable) -> void:
	UIKit.clear(v)
	var title := String(Keybinds.LABELS.get(action, action))
	v.add_child(UIKit.header("Rebind: " + title))
	v.add_child(UIKit.label("Press a key… Esc cancels. Backspace clears.", 0.9, Color("9fd3ff")))
	v.add_child(UIKit.secondary(UIKit.button("Cancel", func():
		if on_rebuild.is_valid():
			on_rebuild.call()
		else:
			UIKit.clear(v); build(v, show_dev, on_wiped, on_rebuild))))
	v.set_meta("rebind_action", action)
	v.set_meta("rebind_show_dev", show_dev)
	v.set_meta("rebind_on_wiped", on_wiped)
	v.set_meta("rebind_on_rebuild", on_rebuild)
	if not v.has_node("RebindListener"):
		v.add_child(RebindListener.new())

## Update section (Android / Windows).
static func _build_update(v: VBoxContainer, show_dev: bool, on_wiped: Callable, on_rebuild: Callable) -> void:
	if not Updater.supports_platform():
		return
	var body := _section(v, "update", "Update", show_dev, on_wiped, on_rebuild)
	if body:
		body.add_child(UpdateBlock.new())

## Captures one key while the rebind panel is open, then rebuilds Settings.
class RebindListener extends Node:
	func _ready() -> void:
		set_process_unhandled_input(true)

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		var v: Node = get_parent()
		if v == null or not v.has_meta("rebind_action"):
			return
		var action: String = v.get_meta("rebind_action")
		var show_dev: bool = v.get_meta("rebind_show_dev", true)
		var on_wiped: Callable = v.get_meta("rebind_on_wiped", Callable())
		var on_rebuild: Callable = v.get_meta("rebind_on_rebuild", Callable())
		var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE:
			pass
		elif key == KEY_BACKSPACE:
			var saved: Dictionary = GameState.settings.get("keybinds", {}).duplicate(true)
			if typeof(saved) != TYPE_DICTIONARY:
				saved = {}
			saved[action] = []
			GameState.set_setting("keybinds", saved)
			Keybinds.apply()
			SaveSystem.save_game()
		else:
			Keybinds.rebind(action, int(key))
		if on_rebuild.is_valid():
			on_rebuild.call()
		else:
			UIKit.clear(v); SettingsPanel.build(v, show_dev, on_wiped, on_rebuild)
		queue_free()

## Live status + button; connects to Updater while in the tree. Host fold supplies the title.
class UpdateBlock extends VBoxContainer:
	var _status: Label
	var _btn: Button

	func _ready() -> void:
		add_theme_constant_override("separation", int(UIKit.font_size * 0.35))
		_status = UIKit.label("…", 0.8, Color("9a9488"))
		add_child(_status)
		_btn = UIKit.button("Check for update", func(): Updater.start_update())
		add_child(_btn)
		if OS.get_name() == "Windows":
			add_child(UIKit.label("Downloads the release zip. Unzip it and run spd-tactics.exe (keep the .pck beside it).", 0.75, Color("9a8f7c")))
		else:
			add_child(UIKit.label("Downloads the APK and opens Android's Install screen. Same signing key as previous sideloads keeps your save.", 0.75, Color("9a8f7c")))
		Updater.changed.connect(_refresh)
		_refresh()
		if Updater.state == Updater.State.IDLE and Updater.status_text == "":
			Updater.check_now()

	func _exit_tree() -> void:
		if Updater.changed.is_connected(_refresh):
			Updater.changed.disconnect(_refresh)

	func _refresh() -> void:
		if _status == null or _btn == null:
			return
		_status.text = Updater.status_text if Updater.status_text != "" else "…"
		match Updater.state:
			Updater.State.CHECKING:
				_btn.text = "Checking…"; _btn.disabled = true
			Updater.State.READY:
				_btn.text = "Update to v%s" % Updater.remote_version; _btn.disabled = false
			Updater.State.DOWNLOADING:
				_btn.text = "Downloading %d%%" % int(Updater.progress * 100.0); _btn.disabled = true
			Updater.State.DONE:
				_btn.text = ("Update to v%s" % Updater.remote_version) if Updater.remote_version != "" else "Done"
				_btn.disabled = false
			Updater.State.ERROR:
				_btn.text = "Try again"; _btn.disabled = false
			_:
				_btn.text = "Check for update"; _btn.disabled = false
