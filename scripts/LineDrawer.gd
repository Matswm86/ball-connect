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

signal pair_completed
signal all_paths_changed


func setup(b: Array) -> void:
	balls = b
	enabled = true
	clear_all()


func clear_all() -> void:
	paths.clear()
	current_path.clear()
	current_color = ""
	current_start_ball = null
	queue_redraw()


func completed_pair_count() -> int:
	return paths.size()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_start_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventScreenDrag:
		_continue_drag(event.position)


func _start_drag(p: Vector2) -> void:
	for b in balls:
		if b.contains_point(p):
			paths.erase(b.color_name)
			current_color = b.color_name
			current_start_ball = b
			current_path = [b.position]
			emit_signal("all_paths_changed")
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
	queue_redraw()


func _end_drag(p: Vector2) -> void:
	if current_start_ball == null:
		return
	var best_ball: Node2D = null
	var best_dist: float = INF
	for b in balls:
		if b == current_start_ball:
			continue
		if b.color_name != current_color:
			continue
		var d: float = b.position.distance_to(p)
		if d <= b.radius * ENDPOINT_SNAP_FACTOR and d < best_dist:
			best_ball = b
			best_dist = d
	if best_ball != null:
		var last: Vector2 = current_path[current_path.size() - 1]
		if not _segment_blocked(last, best_ball.position, true, best_ball):
			current_path.append(best_ball.position)
			paths[current_color] = current_path.duplicate()
			_reset_drag()
			emit_signal("pair_completed")
			return
	_reset_drag()


func _reset_drag() -> void:
	current_path.clear()
	current_color = ""
	current_start_ball = null
	emit_signal("all_paths_changed")
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
