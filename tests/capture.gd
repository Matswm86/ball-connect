extends Node

## Dev-only: boots the game, checks the touch mapping round-trips, plays the
## first levels with real touch events and saves screenshots. Run under Xvfb
## with a fresh user dir (XDG_DATA_HOME) so the game starts at level 1.

var out_dir: String = OS.get_environment("CAPTURE_DIR")
var game: Node
var board: Node3D
var cam: Camera3D


func _ready() -> void:
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(40)
	board = game.get_node("Board3D")
	cam = get_viewport().get_camera_3d()
	var worst: float = 0.0
	for b in game.balls:
		worst = maxf(worst, board.screen_to_board(_s(b.position)).distance_to(b.position))
	print("MAPPING worst round-trip error px: ", worst)
	print("LEVEL at start: ", game.current_level)
	for name in ["ResetButton", "NextButton"]:
		var r: Rect2 = game.get_node("UI/" + name).get_global_rect()
		print("TOUCH %s rect %s = %.1f x %.1f mm @400dpi" % [name, r, _mm(r.size.x), _mm(r.size.y)])
	await _shot("01_level1")

	# Level 1: a drag that starts 90 board px beside the red ball (inside the
	# padded touch area) and ends 90 px short of its partner still connects.
	var red: Array = _pair("red")
	await _drag([red[0].position + Vector2(90, 0), red[1].position + Vector2(0, -90)], true)
	print("L1 red from 90 px off: pairs=", game.line_drawer.completed_pair_count())
	var blue: Array = _pair("blue")
	await _drag([blue[0].position, blue[0].position.lerp(blue[1].position, 0.6)], false)
	await _frames(6)
	await _shot("02_level1_dragging_blue")
	await _release(blue[1].position)
	print("L1 after blue: pairs=%d won=%s" % [game.line_drawer.completed_pair_count(), game.won])
	await _frames(70)
	await _shot("03_level1_win")
	var next_btn: Control = game.get_node("UI/NextButton")
	print("WIN next arrow visible=%s disabled=%s" % [next_btn.visible, next_btn.disabled])
	await _tap(next_btn.get_global_rect().get_center())
	await _frames(40)
	print("After next arrow: level=", game.current_level)
	await _shot("04_level2")

	game.load_level(3)
	game.current_level = 3
	await _frames(40)
	await _shot("05_level3")
	# Straight red drag is blocked by the yellow ball: the line must spring back.
	red = _pair("red")
	await _drag([red[0].position, red[1].position], false)
	await _frames(4)
	await _shot("06_level3_red_blocked_drag")
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = _s(red[1].position)
	Input.parse_input_event(up)
	await _frames(3)
	print(
		(
			"L3 straight red: pairs=%d, spring-back left %.2f s"
			% [game.line_drawer.completed_pair_count(), board._spring_t]
		)
	)
	await _shot("07_level3_spring_back")
	await _frames(30)
	# The one-bend route connects.
	await _drag([red[0].position, Vector2(840, 480), red[1].position], true)
	print("L3 red with one bend: pairs=", game.line_drawer.completed_pair_count())
	await _frames(20)
	await _shot("08_level3_red_bent")
	await _tap(game.get_node("UI/ResetButton").get_global_rect().get_center())
	await _frames(20)
	print("After restart tap: pairs=", game.line_drawer.completed_pair_count())
	get_tree().quit()


func _pair(color: String) -> Array:
	var out: Array = []
	for b in game.balls:
		if b.color_name == color:
			out.append(b)
	return out


func _mm(px: float) -> float:
	return px * 25.4 / 400.0


func _s(p: Vector2) -> Vector2:
	return cam.unproject_position(board.px_to_world(p, board.TUBE_HEIGHT))


## Board points in, real screen touches out.
func _drag(points: Array, release: bool) -> void:
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
	if release:
		await _release(points[points.size() - 1])


func _release(p: Vector2) -> void:
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = _s(p)
	Input.parse_input_event(up)
	await _frames(2)


func _tap(screen_pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = screen_pos
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = screen_pos
	Input.parse_input_event(up)
	await _frames(3)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
