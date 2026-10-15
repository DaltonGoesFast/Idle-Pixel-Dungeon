## Sfx: plays SPD sound effects and music (GPL-3.0 assets from Shattered Pixel Dungeon) and haptics.
## Music: each biome lists several tracks (data/biomes.json "music_tracks"); the track rotates per floor
## and changes crossfade. Volumes and haptics come from GameState.settings.
extends Node

const POOL := 6
const FADE := 0.8
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _cache := {}
var _music_name := ""
var _fade: Tween

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); _players.append(p)
	_music = AudioStreamPlayer.new(); add_child(_music)
	_music.finished.connect(func(): _music.play())

func _vol(lin: float) -> float:
	return linear_to_db(maxf(lin, 0.0001))

func play(name: String, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless" or float(GameState.settings.sfx) <= 0.0: return
	var s := _stream("res://assets/sounds/%s.mp3" % name)
	if s == null: return
	for p in _players:
		if not p.playing:
			p.stream = s; p.pitch_scale = pitch; p.volume_db = _vol(GameState.settings.sfx); p.play(); return

## Short vibration on phones (needs the VIBRATE permission, enabled in export_presets.cfg).
func buzz(ms := 40) -> void:
	if not GameState.settings.get("haptics", true): return
	if OS.has_feature("mobile"): Input.vibrate_handheld(ms)

func music(name: String) -> void:
	if DisplayServer.get_name() == "headless" or name == _music_name: return
	_music_name = name
	var s := _stream("res://assets/music/%s.ogg" % name)
	if _fade and _fade.is_valid(): _fade.kill()
	_fade = create_tween()
	if _music.playing: _fade.tween_property(_music, "volume_db", -40.0, FADE * 0.5)
	_fade.tween_callback(func():
		if s == null: _music.stop(); return
		_music.stream = s; _music.volume_db = -40.0; _music.play())
	_fade.tween_property(_music, "volume_db", _vol(GameState.settings.music), FADE)

## Track for a biome floor: rotates through the biome's tracks (floor 1 -> track 1, floor 2 -> track 2...).
static func biome_track(biome: Dictionary, floor: int) -> String:
	var tracks: Array = biome.get("music_tracks", [biome.music])
	return tracks[(floor - int(biome.floors[0])) % tracks.size()]

func current() -> String:
	return _music_name

func refresh_volume() -> void:
	if _fade and _fade.is_valid(): _fade.kill()
	_music.volume_db = _vol(GameState.settings.music)

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
