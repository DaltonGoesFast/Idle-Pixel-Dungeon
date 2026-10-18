## SettingsPanel: builds the settings controls into any container (Camp "Settings" tab and the
## in-delve Settings card share it). All values live in GameState.settings and are saved.
class_name SettingsPanel
extends RefCounted

const TEXT_SIZES := [["Small", 0.85], ["Normal", 1.0], ["Large", 1.15], ["Huge", 1.3]]
const DELVE_SPEEDS := [["Slow", 0.5], ["Normal", 1.0], ["Fast", 1.5], ["Faster", 2.0]]

## The Developer section (cheats, timer skip, wipe save) is left out of the browser build (DECISIONS #199).
## Android, Windows and source/editor runs keep it. A saved dev_tools=true is ignored on web.
static func dev_tools_allowed(is_web: bool = OS.has_feature("web")) -> bool:
	return not is_web

static func build(v: VBoxContainer, show_dev := true) -> void:
	v.add_child(UIKit.label("SPD Tactics " + UIKit.version(), 0.8, Color("c9a96e")))
	_build_update(v)
	v.add_child(UIKit.header("Audio"))
	for k in [["sfx", "Sound effects"], ["music", "Music"]]:
		var row := UIKit.hbox(v)
		var l := UIKit.label("%s: %d%%" % [k[1], int(float(GameState.settings[k[0]]) * 100)]); l.custom_minimum_size.x = UIKit.font_size * 10; l.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(l)
		var s := HSlider.new(); s.min_value = 0; s.max_value = 1; s.step = 0.05; s.value = GameState.settings[k[0]]
		s.custom_minimum_size.y = UIKit.btn_height(); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(x):
			GameState.settings[k[0]] = x; Sfx.refresh_volume(); l.text = "%s: %d%%" % [k[1], int(x * 100)])
		s.drag_ended.connect(func(_c): Sfx.play("click"); SaveSystem.save_game())
		row.add_child(s)
	v.add_child(UIKit.header("Feel"))
	var hap: bool = GameState.settings.get("haptics", true)
	v.add_child(UIKit.button("Haptics: %s" % ("ON" if hap else "OFF"), func():
		GameState.set_setting("haptics", not hap); Sfx.buzz(50); SaveSystem.save_game(); GameState.touch()))
	v.add_child(UIKit.label("Vibrates when you take damage, trigger a trap, or an enemy telegraphs an attack (phones only).", 0.75, Color("9a8f7c")))
	var li: bool = GameState.settings.get("lighting", true)
	v.add_child(UIKit.button("Lighting & fog: %s" % ("ON" if li else "OFF"), func():
		GameState.set_setting("lighting", not li); SaveSystem.save_game(); GameState.touch()))
	v.add_child(UIKit.label("SPD-style torchlight in fights: the light shrinks as your torch burns down. Turn off for full brightness.", 0.75, Color("9a8f7c")))
	v.add_child(UIKit.header("Delve speed"))
	var sf := HFlowContainer.new(); v.add_child(sf)
	for t in DELVE_SPEEDS:
		var cur := absf(float(GameState.settings.get("delve_speed", 1.0)) - float(t[1])) < 0.01
		var b := UIKit.button(("> " if cur else "") + t[0], func():
			GameState.set_setting("delve_speed", t[1]); SaveSystem.save_game(); GameState.touch())
		b.custom_minimum_size.x = UIKit.font_size * 5; sf.add_child(b)
	v.add_child(UIKit.label("How fast the Delve Bar explores (%d s per floor at Normal). The x3 button in a run stacks on top." % int(100.0 / 5.0), 0.75, Color("9a8f7c")))
	v.add_child(UIKit.header("Text size"))
	var flow := HFlowContainer.new(); v.add_child(flow)
	for t in TEXT_SIZES:
		var cur := absf(float(GameState.settings.get("text_scale", 1.0)) - float(t[1])) < 0.01
		var b := UIKit.button(("> " if cur else "") + t[0], func():
			GameState.set_setting("text_scale", t[1]); SaveSystem.save_game(); GameState.touch())
		b.custom_minimum_size.x = UIKit.font_size * 5; flow.add_child(b)
	v.add_child(UIKit.header("Help"))
	var tut: bool = GameState.settings.get("tutorial", true)
	v.add_child(UIKit.button("Tutorial tips: %s" % ("ON" if tut else "OFF"), func():
		GameState.set_setting("tutorial", not tut); SaveSystem.save_game(); GameState.touch()))
	v.add_child(UIKit.button("Replay the tutorial tips", func():
		GameState.tutorial_done.clear(); GameState.settings.tutorial = true; SaveSystem.save_game(); GameState.touch()))
	if not show_dev or not dev_tools_allowed(): return
	var dev: bool = GameState.settings.get("dev_tools", false)
	v.add_child(UIKit.button("Developer tools: %s" % ("shown" if dev else "hidden"), func():
		GameState.set_setting("dev_tools", not dev); GameState.touch()))
	if dev:
		v.add_child(UIKit.header("Developer"))
		v.add_child(UIKit.button("Unlock all heroes", func():
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			GameState.touch()))
		v.add_child(UIKit.button("+100 gold, +10 of every material", func():
			for k in ["gold", "iron_ore", "dark_gold", "seeds", "arcane_resin", "iron_key", "ration", "torch", "potion_healing", "scroll_passage", "scroll_upgrade"]: GameState.add_mat(k, 100 if k == "gold" else 10)
			GameState.touch()))
		v.add_child(UIKit.button("Fast-forward 1 hour (timers)", func(): GameState.time_offset += 3600; GameState.tick_identify(); GameState.touch()))
		v.add_child(UIKit.button("Wipe save (new game)", func(): SaveSystem.wipe()))
	v.add_child(UIKit.label("Art, sounds and music: Shattered Pixel Dungeon by Evan Debenham (GPL-3.0). This game is GPL-3.0. See CREDITS.md.", 0.75, Color("9a8f7c")))

## Update section (Android / Windows).
static func _build_update(v: VBoxContainer) -> void:
	if not Updater.supports_platform():
		return
	v.add_child(UpdateBlock.new())

## Live status + button; connects to Updater while in the tree.
class UpdateBlock extends VBoxContainer:
	var _status: Label
	var _btn: Button

	func _ready() -> void:
		add_theme_constant_override("separation", int(UIKit.font_size * 0.35))
		add_child(UIKit.header("Update"))
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
