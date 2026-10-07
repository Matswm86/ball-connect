extends Node

## Dev-only: checks tap-to-connect, the idle hint, the half-finished board
## save and the safe-area inset with real touch events, and saves screenshots.
## Run under Xvfb with a fresh user dir (XDG_DATA_HOME). CAPTURE_PHASE:
##   play    - tap mode, drag next to tap, idle hint, then leaves two lines on
##             level 4 and closes (the save happens on each line and on close)
##   restore - a second start: the level 4 lines must come back
##   bad     - corrupt and old saves start a fresh board
##   inset   - fake 120 px top cutout on levels 1 and 8
##   music   - music switch: tap off, saved, tap on; then hidden in the shell

var out_dir: String = OS.get_environment("CAPTURE_DIR")
var game: Node
var board: Node3D
var cam: Camera3D
var ld: Node2D


func _ready() -> void:
	var phase: String = OS.get_environment("CAPTURE_PHASE")
	if phase == "bad":
		_write_bad_saves_then_check()
		return
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(40)
	board = game.get_node("Board3D")
	ld = game.get_node("LineDrawer")
	cam = get_viewport().get_camera_3d()
	match phase:
		"play":
			await _phase_play()
		"restore":
			await _phase_restore()
		"inset":
			await _phase_inset()
		"music":
			await _phase_music()
	get_tree().quit()


func _phase_play() -> void:
	game.load_level(1)
	game.current_level = 1
	await _frames(40)
	var red: Array = _pair("red")
	var blue: Array = _pair("blue")
	# A tap with a little finger wobble (12 px) is still a tap.
	await _tap(_s(red[0].position), Vector2(12, 6))
	await _frames(20)
	print(
		(
			"TAP red ball: tap_selected=%s held=%s path=%d"
			% [ld.tap_selected, _name(ld.current_start_ball), ld.current_path.size()]
		)
	)
	await _shot("10_tap_selected_ball")
	print("TAP targets offered: ", ld.tap_targets())
	# Cell by cell: two cells straight down from the red ball.
	await _tap(_s(Vector2(270, 850)))
	await _tap(_s(Vector2(250, 1010)))
	await _frames(20)
	print("CELLS laid: path=%s" % [ld.current_path])
	await _shot("11_cells_half_laid")
	# A cell two steps away is refused (ball shakes, line stays).
	await _tap(_s(Vector2(580, 1320)))
	print(
		(
			"FAR cell refused: path len=%d still selected=%s"
			% [ld.current_path.size(), ld.tap_selected]
		)
	)
	# Tap a cell already on the line: back to it (undo).
	await _tap(_s(Vector2(260, 840)))
	print("UNDO to first cell: path len=%d" % ld.current_path.size())
	await _tap(_s(Vector2(260, 1000)))
	await _tap(_s(red[1].position))
	await _frames(30)
	print("CELLS + partner tap: red done=%s pairs=%d" % [ld.paths.has("red"), ld.paths.size()])
	# Tapping a finished line's ball clears it, as a drag start does.
	await _tap(_s(red[1].position))
	await _frames(10)
	print(
		(
			"TAP finished red ball: red cleared=%s selected=%s"
			% [not ld.paths.has("red"), ld.tap_selected]
		)
	)
	# Tapping the selected ball again cancels.
	await _tap(_s(red[1].position))
	print("TAP same ball again: selected=%s" % ld.tap_selected)
	# Select red, then tap blue: reselects blue.
	await _tap(_s(red[0].position))
	await _tap(_s(blue[0].position))
	print(
		(
			"TAP other ball: now held=%s tap_selected=%s"
			% [_name(ld.current_start_ball), ld.tap_selected]
		)
	)
	# With blue selected, a real drag from the red ball still works.
	await _drag([red[0].position, red[1].position])
	print(
		(
			"DRAG red while blue tapped: red done=%s tap_selected=%s"
			% [ld.paths.has("red"), ld.tap_selected]
		)
	)
	# A press on a ball that moves past the slop is a drag, never a tap: it
	# ends away from the partner, so it springs back and nothing is selected.
	await _drag([blue[0].position, blue[0].position + Vector2(0, 200)])
	print(
		(
			"SHORT DRAG blue (200 px, no partner): selected=%s spring=%.2f"
			% [ld.tap_selected, board._spring_t]
		)
	)
	await _frames(40)

	# Tap the ball, tap the partner: level 3 red needs a bend round yellow.
	game.load_level(3)
	game.current_level = 3
	await _frames(40)
	red = _pair("red")
	await _tap(_s(red[0].position))
	var t0: int = Time.get_ticks_usec()
	var tail: Array = ld._find_route(red[0].position, red[1])
	print(
		"ROUTER level 3 red: %d ms, %d points" % [(Time.get_ticks_usec() - t0) / 1000, tail.size()]
	)
	await _tap(_s(red[1].position))
	print("TAP-TAP red on level 3: done=%s route=%s" % [ld.paths.has("red"), ld.paths.get("red")])
	await _frames(40)
	await _shot("12_tap_connected_pair")

	# Idle hint: level 2, no touch for 8 s.
	game.load_level(2)
	game.current_level = 2
	await _frames(10)
	var t_idle: int = Time.get_ticks_msec()
	while not board.hint_active() and Time.get_ticks_msec() - t_idle < 12000:
		await _frames(1)
	print(
		(
			"HINT after %.1f s idle: active=%s balls=%s"
			% [
				(Time.get_ticks_msec() - t_idle) / 1000.0,
				board.hint_active(),
				_names(board._hint_balls)
			]
		)
	)
	await get_tree().create_timer(0.5).timeout
	await _shot("13_idle_hint")
	await _tap(_s(Vector2(540, 1500)))
	print("HINT after a touch: active=%s" % board.hint_active())

	# Half-finished board: level 4, two lines, then the app closes.
	game.load_level(4)
	game.current_level = 4
	await _frames(40)
	for c in ["orange", "green"]:
		var pr: Array = _pair(c)
		await _tap(_s(pr[0].position))
		await _tap(_s(pr[1].position))
	await _frames(30)
	print("BOARD before close: lines=%s" % [ld.paths.keys()])
	await _shot("14_level4_before_close")
	game.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	print("SAVE file: ", FileAccess.get_file_as_string(game.SAVE_PATH).left(160), "...")


func _phase_music() -> void:
	var btn: Control = game.get_node("UI/MusicButton")
	var r: Rect2 = btn.get_global_rect()
	print("MUSIC button rect %s visible=%s kind=%s" % [r, btn.visible, btn.kind])
	print(
		(
			"MUSIC at start: on=%s audible=%s bus=%s"
			% [game.music_on, game.music.is_audible(), game.music.player.bus]
		)
	)
	await _frames(200)  # fade-in is 3 s
	print("MUSIC after fade: volume_db=%.1f" % game.music.player.volume_db)
	await _shot("40_music_on")
	await _tap(r.get_center())
	await _frames(60)
	print(
		(
			"MUSIC after tap: on=%s kind=%s paused=%s"
			% [game.music_on, btn.kind, game.music.player.stream_paused]
		)
	)
	var f := FileAccess.open("user://ball_connect_save.json", FileAccess.READ)
	print("MUSIC save: ", f.get_as_text())
	f.close()
	await _shot("41_music_off")
	var pos: float = game.music.player.get_playback_position()
	await _tap(r.get_center())
	await _frames(30)
	print(
		(
			"MUSIC after 2nd tap: on=%s audible=%s resumed from %.2f s (now %.2f s)"
			% [
				game.music_on,
				game.music.is_audible(),
				pos,
				game.music.player.get_playback_position()
			]
		)
	)
	var before_level: float = game.music.player.get_playback_position()
	game.load_level(2)
	await _frames(10)
	print(
		(
			"MUSIC across level change: %.2f s -> %.2f s, playing=%s"
			% [before_level, game.music.player.get_playback_position(), game.music.player.playing]
		)
	)
	game.music.notification(NOTIFICATION_APPLICATION_PAUSED)
	print("MUSIC app paused: stream_paused=%s" % game.music.player.stream_paused)
	game.music.notification(NOTIFICATION_APPLICATION_RESUMED)
	print("MUSIC app resumed: stream_paused=%s" % game.music.player.stream_paused)
	# Inside MWM Play: own switch hidden, music plays even with the saved switch off.
	await _tap(r.get_center())
	await _frames(30)
	var scene_path: String = game.scene_file_path
	game.queue_free()
	await _frames(2)
	Engine.set_meta(&"mwm_play_shell", true)
	game = load(scene_path).instantiate()
	add_child(game)
	await _frames(40)
	print(
		(
			"SHELL: button visible=%s saved music_on=%s audible=%s"
			% [game.get_node("UI/MusicButton").visible, game.music_on, game.music.is_audible()]
		)
	)
	await _shot("42_in_shell")
	Engine.remove_meta(&"mwm_play_shell")


func _phase_restore() -> void:
	await _frames(20)
	print("RESTORE level=%d lines=%s" % [game.current_level, ld.paths.keys()])
	await _shot("15_restored_after_restart")
	game._on_reset_pressed()
	await _frames(5)
	print("RESTART button: lines=%d" % ld.paths.size())


func _phase_inset() -> void:
	for n in [1, 8]:
		game.fake_safe_top = 0.0
		game.apply_safe_area()
		game.load_level(n)
		game.current_level = n
		await _frames(40)
		var r0: Rect2 = game.reset_button.get_global_rect()
		game.fake_safe_top = 120.0
		game.apply_safe_area()
		await _frames(10)
		var r: Rect2 = game.reset_button.get_global_rect()
		var dots: Rect2 = game.level_dots.get_global_rect()
		print(
			(
				"INSET level %d: restart hit %s -> %s, disc centre y %.0f, dots top %.0f"
				% [n, r0, r, game.reset_button.disc_center.y, dots.position.y]
			)
		)
		_report_overlap(r)
		await _shot("16_inset120_level%d" % n)


## Ball touch circles (screen px) that reach into the restart touch area.
func _report_overlap(r: Rect2) -> void:
	var worst: float = 0.0
	for b in game.balls:
		var c: Vector2 = _s(b.position)
		var rad: float = (_s(b.position + Vector2(b.hit_radius(), 0)) - c).length()
		var q: Vector2 = Vector2(
			clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y)
		)
		var into: float = rad - c.distance_to(q)
		if into > 0.0:
			print("  OVERLAP %s ball touch area %.0f px into restart area" % [b.color_name, into])
			worst = maxf(worst, into)
	print("  overlap worst %.0f px" % worst)
	if worst > 0.0:
		var probe := Vector2(r.position.x + 20, r.end.y - 10)
		var bpos: Vector2 = board.screen_to_board(probe)
		print(
			(
				"  touch at %s: restart takes it=%s, ball there=%s"
				% [
					probe,
					game.reset_button._has_point(probe - r.position),
					game._ball_at_screen(probe)
				]
			)
		)
		var disc := Vector2(
			r.position.x + game.reset_button.disc_center.x, game.reset_button.disc_center.y
		)
		print(
			(
				"  touch on disc centre %s: restart takes it=%s"
				% [disc, game.reset_button._has_point(disc - r.position)]
			)
		)
		print("  board point under probe %s" % bpos)


func _write_bad_saves_then_check() -> void:
	var path: String = "user://ball_connect_save.json"
	var cases: Dictionary = {
		"corrupt json": "{not json",
		"bad board points":
		'{"version":3,"current_level":2,"highest_level":2,"board":{"level":2,"paths":{"red":[[1,2],"x"]}}}',
		"line through a ball":
		'{"version":3,"current_level":3,"highest_level":3,"board":{"level":3,"paths":{"red":[[300,520],[300,1320]]}}}',
		"v2 save": '{"version":2,"current_level":5,"highest_level":6}',
		"v1 save": '{"current_level":3}',
	}
	for k in cases:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[k])
		f.close()
		var g: Node = load("res://scenes/Game.tscn").instantiate()
		add_child(g)
		await _frames(3)
		print(
			(
				"BAD SAVE %s -> level %d, lines %d"
				% [k, g.current_level, g.get_node("LineDrawer").paths.size()]
			)
		)
		g.queue_free()
		await _frames(2)
	get_tree().quit()


func _pair(color: String) -> Array:
	var out: Array = []
	for b in game.balls:
		if b.color_name == color:
			out.append(b)
	return out


func _name(b: Node2D) -> String:
	return "none" if b == null else b.color_name


func _names(arr: Array) -> Array:
	return arr.map(func(b: Node2D) -> String: return b.color_name)


func _s(p: Vector2) -> Vector2:
	return cam.unproject_position(board.px_to_world(p, board.TUBE_HEIGHT))


func _tap(screen_pos: Vector2, wobble: Vector2 = Vector2.ZERO) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = screen_pos
	Input.parse_input_event(down)
	await _frames(3)
	if wobble != Vector2.ZERO:
		var mv := InputEventScreenDrag.new()
		mv.position = screen_pos + wobble
		Input.parse_input_event(mv)
		await _frames(2)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = screen_pos + wobble
	Input.parse_input_event(up)
	await _frames(3)


## Board points in, real screen touches out (press, 20 moves per leg, release).
func _drag(points: Array) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = _s(points[0])
	Input.parse_input_event(down)
	await _frames(2)
	for i in range(points.size() - 1):
		for k in range(1, 21):
			var ev := InputEventScreenDrag.new()
			ev.position = _s(points[i].lerp(points[i + 1], k / 20.0))
			Input.parse_input_event(ev)
			await _frames(1)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = _s(points[points.size() - 1])
	Input.parse_input_event(up)
	await _frames(3)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
