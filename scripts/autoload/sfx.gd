## Sfx: plays SPD sound effects and music (GPL-3.0 assets from Shattered Pixel Dungeon).
extends Node

const POOL := 6
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _cache := {}
var _music_name := ""

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); _players.append(p)
	_music = AudioStreamPlayer.new(); add_child(_music)
	_music.finished.connect(func(): _music.play())

func _vol(lin: float) -> float:
	return linear_to_db(maxf(lin, 0.0001))

func play(name: String, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless": return
	var s := _stream("res://assets/sounds/%s.mp3" % name)
	if s == null: return
	for p in _players:
		if not p.playing:
			p.stream = s; p.pitch_scale = pitch; p.volume_db = _vol(GameState.settings.sfx); p.play(); return

func music(name: String) -> void:
	if DisplayServer.get_name() == "headless" or name == _music_name: return
	_music_name = name
	var s := _stream("res://assets/music/%s.ogg" % name)
	if s == null: _music.stop(); return
	_music.stream = s; _music.volume_db = _vol(GameState.settings.music); _music.play()

func refresh_volume() -> void:
	_music.volume_db = _vol(GameState.settings.music)

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
