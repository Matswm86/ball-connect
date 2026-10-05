extends Node2D

const SAMPLE_DIST: float = 10.0
const LINE_WIDTH: float = 16.0
const BALL_BLOCK_FACTOR: float = 0.6
const ENDPOINT_SNAP_FACTOR: float = 1.6

var balls: Array = []
var paths: Dictionary = {}
var current_path: Array = []
var current_color: String = ""
var current_start_ball: Node2D = null
var enabled: bool = true
## Bumped on every visual change so the 3D board knows when to rebuild meshes.
var revision: int = 0
## Maps a viewport touch position to board pixels (set by GameManager).
var input_mapper: Callable

signal pair_completed
signal all_paths_changed
## A drag that started on a ball ended without connecting. The path is what
## was drawn, so the board can show it springing back (rule 31).
signal drag_failed(ball: Node2D, path: Array)


func setup(b: Array) -> void:
	balls = b
	enabled = true
	clear_all()


func clear_all() -> void:
	paths.clear()
	current_path.clear()
	current_color = ""
	current_start_ball = null
	revision += 1
	queue_redraw()


func completed_pair_count() -> int:
	return paths.size()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var pos: Vector2 = event.position
	if input_mapper.is_valid():
		pos = input_mapper.call(pos)
	if event is InputEventScreenTouch:
		if event.pressed:
			_start_drag(pos)
		else:
			_end_drag(pos)
	else:
		_continue_drag(pos)


## A touch anywhere inside a ball's padded touch area starts from that ball;
## the nearest ball wins (rule 12).
func _start_drag(p: Vector2) -> void:
	var b: Node2D = _nearest_ball(p, null, "")
	if b != null:
		paths.erase(b.color_name)
		current_color = b.color_name
		current_start_ball = b
		current_path = [b.position]
		emit_signal("all_paths_changed")
		revision += 1
		queue_redraw()
		return
	current_start_ball = null
	current_color = ""
	current_path.clear()


func _continue_drag(p: Vector2) -> void:
	if current_start_ball == null or current_path.is_empty():
		return
	var last: Vector2 = current_path[current_path.size() - 1]
	if last.distance_to(p) < SAMPLE_DIST:
		return
	if _segment_blocked(last, p, false, null):
		return
	current_path.append(p)
	revision += 1
	queue_redraw()


func _end_drag(p: Vector2) -> void:
	if current_start_ball == null:
		return
	var best_ball: Node2D = _nearest_ball(p, current_start_ball, current_color)
	if best_ball != null:
		var last: Vector2 = current_path[current_path.size() - 1]
		if not _segment_blocked(last, best_ball.position, true, best_ball):
			current_path.append(best_ball.position)
			paths[current_color] = current_path.duplicate()
			_reset_drag()
			emit_signal("pair_completed")
			return
	var failed_ball: Node2D = current_start_ball
	var failed_path: Array = current_path.duplicate()
	_reset_drag()
	drag_failed.emit(failed_ball, failed_path)


## Nearest ball whose touch area holds p. A drag ends on a ball when the
## finger lifts inside its touch area or within the old 1.6 x radius snap.
func _nearest_ball(p: Vector2, skip: Node2D, only_color: String) -> Node2D:
	var best_ball: Node2D = null
	var best_dist: float = INF
	for b in balls:
		if b == skip:
			continue
		if only_color != "" and b.color_name != only_color:
			continue
		var reach: float = maxf(b.hit_radius(), b.radius * ENDPOINT_SNAP_FACTOR)
		var d: float = b.position.distance_to(p)
		if d <= reach and d < best_dist:
			best_ball = b
			best_dist = d
	return best_ball


func _reset_drag() -> void:
	current_path.clear()
	current_color = ""
	current_start_ball = null
	emit_signal("all_paths_changed")
	revision += 1
	queue_redraw()


func _segment_blocked(a: Vector2, b: Vector2, allow_endpoint: bool, endpoint_ball: Node2D) -> bool:
	for color_key in paths.keys():
		var pts: Array = paths[color_key]
		for i in range(pts.size() - 1):
			if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1]) != null:
				return true
	for i in range(current_path.size() - 2):
		if (
			Geometry2D.segment_intersects_segment(a, b, current_path[i], current_path[i + 1])
			!= null
		):
			return true
	for ball in balls:
		if ball == current_start_ball:
			continue
		if allow_endpoint and ball == endpoint_ball:
			continue
		if _segment_hits_circle(a, b, ball.position, ball.radius * BALL_BLOCK_FACTOR):
			return true
	return false


func _segment_hits_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	var ab: Vector2 = b - a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq <= 0.0001:
		return a.distance_to(center) <= radius
	var t: float = clamp((center - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return closest.distance_to(center) <= radius


func _color_for(name: String) -> Color:
	for b in balls:
		if b.color_name == name:
			return b.color
	return Color.WHITE


func _draw() -> void:
	for color_key in paths.keys():
		var pts: Array = paths[color_key]
		var c: Color = _color_for(color_key)
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], c, LINE_WIDTH, true)
	if current_path.size() >= 2 and current_color != "":
		var c2: Color = _color_for(current_color)
		for i in range(current_path.size() - 1):
			draw_line(current_path[i], current_path[i + 1], c2, LINE_WIDTH, true)
