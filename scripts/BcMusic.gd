class_name BcMusic
extends Node

## Calm background music: one seamless 2-minute loop (tools/render_music.py,
## see CREDITS.md). A child of the Game scene, not an autoload, so the MWM Play
## shell can host the game unchanged; levels load inside the same scene, so the
## loop keeps playing across level changes. Plays on the "Music" bus (created
## here if missing; MWM Play makes its own and mutes it from its settings).
## Pauses while the app is in the background or loses focus, then resumes
## where it was.

const BUS := &"Music"
const TRACK := "res://assets/music/calm_loop.ogg"
## Player level: the track's body (about -16 dBFS RMS) plays near -28 dBFS,
## quiet under play.
const BASE_DB: float = -12.0
const SILENT_DB: float = -60.0
const FADE_IN_S: float = 3.0
const FADE_OUT_S: float = 0.6

var enabled: bool = false
var player: AudioStreamPlayer
var _fade: Tween
var _in_background: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var bi: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, BUS)
		AudioServer.set_bus_send(bi, &"Master")
	player = AudioStreamPlayer.new()
	var s: AudioStreamOggVorbis = load(TRACK) as AudioStreamOggVorbis
	if s == null:
		push_warning("BcMusic: missing " + TRACK)
	else:
		s.loop = true
		player.stream = s
	player.bus = BUS
	player.volume_db = SILENT_DB
	add_child(player)


## On: fade in (from where it paused, or from the start). Off: fade out and pause.
func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	if player.stream == null:
		return
	if on:
		if not player.playing:
			player.play()
		player.stream_paused = _in_background
		_fade_to(BASE_DB, FADE_IN_S, false)
	else:
		_fade_to(SILENT_DB, FADE_OUT_S, true)


func is_audible() -> bool:
	return enabled and player.playing and not player.stream_paused


func _fade_to(db: float, secs: float, pause_after: bool) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween().set_ignore_time_scale(true)
	_fade.tween_property(player, "volume_db", db, secs)
	if pause_after:
		_fade.tween_callback(func() -> void: player.stream_paused = true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_in_background = true
			if player != null and player.playing:
				player.stream_paused = true
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_in_background = false
			if player != null and enabled and player.playing:
				player.stream_paused = false
				player.volume_db = SILENT_DB
				_fade_to(BASE_DB, 1.0, false)


func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null
