extends Node

## Dev-only: boots the game, checks the touch mapping round-trips, draws one
## pair plus a half-finished drag, and saves screenshots. Run under Xvfb.

var out_dir: String = OS.get_environment("CAPTURE_DIR")


func _ready() -> void:
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(40)
	var board: Node3D = game.get_node("Board3D")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var worst: float = 0.0
	for b in game.balls:
		var screen: Vector2 = cam.unproject_position(
			board.px_to_world(b.position, board.TUBE_HEIGHT)
		)
		worst = maxf(worst, board.screen_to_board(screen).distance_to(b.position))
	print("MAPPING worst round-trip error px: ", worst)
	await _shot("01_level_start")

	var s := func(p: Vector2) -> Vector2:
		return cam.unproject_position(board.px_to_world(p, board.TUBE_HEIGHT))
	await _drag(
		[s.call(Vector2(540, 350)), s.call(Vector2(540, 950)), s.call(Vector2(540, 1550))], true
	)
	await _frames(20)
	print("PAIRS completed: ", game.line_drawer.completed_pair_count())
	await _shot("02_green_connected")
	await _drag(
		[s.call(Vector2(180, 350)), s.call(Vector2(180, 600)), s.call(Vector2(260, 820))], false
	)
	await _frames(10)
	await _shot("03_dragging_red")
	board.celebrate()
	await _frames(4)
	await _shot("04_celebrate")
	get_tree().quit()


func _drag(points: Array, release: bool) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = points[0]
	Input.parse_input_event(down)
	await _frames(2)
	for i in range(points.size() - 1):
		for k in range(1, 21):
			var ev := InputEventScreenDrag.new()
			ev.position = points[i].lerp(points[i + 1], k / 20.0)
			Input.parse_input_event(ev)
			await _frames(1)
	if release:
		var up := InputEventScreenTouch.new()
		up.pressed = false
		up.position = points[points.size() - 1]
		Input.parse_input_event(up)
		await _frames(2)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
