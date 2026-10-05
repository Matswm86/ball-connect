extends Node2D

enum Press { NONE, PENDING, DRAG, IGNORE }

const SAMPLE_DIST: float = 10.0
const LINE_WIDTH: float = 16.0
const BALL_BLOCK_FACTOR: float = 0.6
const ENDPOINT_SNAP_FACTOR: float = 1.6
## Tap mode (rule 13, WCAG 2.5.1), next to dragging: tap a ball to select it,
## then tap its partner or tap cells one at a time. A touch stays a tap while
## the finger moves less than TAP_SLOP screen px; past that it is a drag.
const TAP_SLOP: float = 30.0
## Tap cells in board px, centred on every second dot of the floor grid.
## 160 board px is about 150 screen px (9.5 mm at 400 dpi); the tap anywhere
## inside a cell counts, and only cells next to the line end are offered.
const CELL: float = 160.0
const CELL_ORIGIN: Vector2 = Vector2(20, -40)
## Router for "tap the partner": grid step and gap kept from other lines.
const ROUTE_GRID: float = 30.0
const ROUTE_CLEAR: float = 26.0
const ROUTE_SEED_REACH: float = 70.0
## Router lines keep clear of the whole drawn ball: socket ring 1.26 x radius
## plus the tube (15 px) plus a gap. A drag may clip a ball's rim; a line the
## game draws for the child should not.
const ROUTE_BALL_KEEP: float = 1.3
const ROUTE_BALL_GAP: float = 25.0

var balls: Array = []
var paths: Dictionary = {}
var current_path: Array = []
var current_color: String = ""
var current_start_ball: Node2D = null
var enabled: bool = true
## True while current_start_ball was picked by a tap (not by a held finger).
var tap_selected: bool = false
## Board px area that tap cells and routes must stay inside (set by GameManager).
var board_rect: Rect2 = Rect2(0, 0, 1080, 1920)
## Bumped on every visual change so the 3D board knows when to rebuild meshes.
var revision: int = 0
## Maps a viewport touch position to board pixels (set by GameManager).
var input_mapper: Callable
var _press: Press = Press.NONE
var _press_screen: Vector2 = Vector2.ZERO
var _press_board: Vector2 = Vector2.ZERO
var _route_strict: bool = true

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
	tap_selected = false
	_press = Press.NONE
	revision += 1
	queue_redraw()


func completed_pair_count() -> int:
	return paths.size()


## [[x, y], ...] with numbers only, at least two points; else [].
func _parse_points(raw: Variant) -> Array:
	var pts: Array = []
	if not (raw is Array) or (raw as Array).size() < 2:
		return pts
	for e in raw:
		var ok: bool = e is Array and (e as Array).size() == 2
		ok = ok and (e[0] is float or e[0] is int) and (e[1] is float or e[1] is int)
		if not ok:
			return []
		pts.append(Vector2(float(e[0]), float(e[1])))
	return pts


func _restore_line(color_key: String, raw: Variant) -> bool:
	var pts: Array = _parse_points(raw)
	var pair: Array = []
	for b in balls:
		if b.color_name == color_key:
			pair.append(b)
	if pts.is_empty() or pair.size() != 2 or paths.has(color_key):
		return false
	var first: Vector2 = pts[0]
	var last: Vector2 = pts[pts.size() - 1]
	var a: Node2D = pair[0] if first.distance_to(pair[0].position) < 1.0 else pair[1]
	var b2: Node2D = pair[1] if a == pair[0] else pair[0]
	if first.distance_to(a.position) >= 1.0 or last.distance_to(b2.position) >= 1.0:
		return false
	current_start_ball = a
	current_color = color_key
	current_path = [a.position]
	for i in range(1, pts.size() - 1):
		if _segment_blocked(current_path[current_path.size() - 1], pts[i], false, null):
			return false
		current_path.append(pts[i])
	if _segment_blocked(current_path[current_path.size() - 1], b2.position, true, b2):
		return false
	current_path.append(b2.position)
	paths[color_key] = current_path.duplicate()
	current_path = []
	current_start_ball = null
	current_color = ""
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var screen: Vector2 = event.position
	var pos: Vector2 = screen
	if input_mapper.is_valid():
		pos = input_mapper.call(pos)
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(screen, pos)
		else:
			_on_release(pos)
	else:
		_on_move(screen, pos)


## Without a tap selection a press on a ball starts a drag at once, exactly as
## before, so the ball lifts on touch-down. With a selection the press waits:
## release in place = tap, move past TAP_SLOP = drag.
func _on_press(screen: Vector2, pos: Vector2) -> void:
	_press_screen = screen
	_press_board = pos
	_press = Press.PENDING
	if not tap_selected:
		_start_drag(pos)


func _on_move(screen: Vector2, pos: Vector2) -> void:
	if _press == Press.PENDING:
		if screen.distance_to(_press_screen) < TAP_SLOP:
			return
		_press = Press.DRAG
		if tap_selected:
			if _nearest_ball(_press_board, null, "") == null:
				_press = Press.IGNORE  # a swipe on empty board keeps the selection
				return
			_cancel_selection()
			_start_drag(_press_board)
	if _press == Press.DRAG:
		_continue_drag(pos)


func _on_release(pos: Vector2) -> void:
	var kind: Press = _press
	_press = Press.NONE
	if kind == Press.DRAG:
		_end_drag(pos)
	elif kind == Press.PENDING:
		_on_tap(_press_board)


# ---------------------------------------------------------------- tap mode


func _on_tap(p: Vector2) -> void:
	if not tap_selected:
		if current_start_ball != null:
			# The press already picked the ball up: a tap keeps it selected.
			tap_selected = true
			revision += 1
			queue_redraw()
		return
	var b: Node2D = _nearest_ball(p, null, "")
	if b == current_start_ball:
		_cancel_selection()
	elif b != null and b.color_name == current_color:
		_finish_to(b)
	elif b != null:
		_cancel_selection()
		_start_drag(p)
		tap_selected = current_start_ball != null
	else:
		_tap_cell(p)


func _cancel_selection() -> void:
	tap_selected = false
	_reset_drag()


## Extends the tapped line to the centre of the tapped cell when that cell is
## next to the line end and the step is legal. A cell already on the line
## takes the line back to it (undo).
func _tap_cell(p: Vector2) -> void:
	var c: Vector2 = cell_center(cell_of(p))
	for i in range(1, current_path.size()):
		if (current_path[i] as Vector2).is_equal_approx(c):
			current_path.resize(i + 1)
			revision += 1
			queue_redraw()
			return
	if not _is_tap_target(c):
		drag_failed.emit(current_start_ball, [])
		return
	current_path.append(c)
	revision += 1
	queue_redraw()


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - CELL_ORIGIN.x) / CELL), floori((p.y - CELL_ORIGIN.y) / CELL))


func cell_center(cell: Vector2i) -> Vector2:
	return CELL_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func _is_tap_target(c: Vector2) -> bool:
	if current_path.is_empty() or not board_rect.has_point(c):
		return false
	var last: Vector2 = current_path[current_path.size() - 1]
	var step: Vector2i = cell_of(c) - cell_of(last)
	if step == Vector2i.ZERO or absi(step.x) > 1 or absi(step.y) > 1:
		return false
	if _nearest_ball(c, null, "") != null:
		return false  # a tap there would hit a ball, not the cell
	return not _segment_blocked(last, c, false, null)


## Cells the selected line can grow into next (shown as small markers).
func tap_targets() -> Array:
	var out: Array = []
	if not tap_selected or current_path.is_empty():
		return out
	var here: Vector2i = cell_of(current_path[current_path.size() - 1])
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2 = cell_center(here + Vector2i(dx, dy))
			if _is_tap_target(c) and not current_path.has(c):
				out.append(c)
	return out


## Tap on the partner: a straight line when nothing is in the way, otherwise
## the route with the fewest bends the router finds. No route = spring back.
func _finish_to(partner: Node2D) -> void:
	var last: Vector2 = current_path[current_path.size() - 1]
	var tail: Array = []
	for strict in [true, false]:
		_route_strict = strict
		if _route_step_ok(last, partner.position, partner):
			tail = [partner.position]
		else:
			tail = _find_route(last, partner)
		if not tail.is_empty():
			break
	_route_strict = true
	if tail.is_empty():
		var failed_ball: Node2D = current_start_ball
		var failed_path: Array = current_path.duplicate()
		_cancel_selection()
		drag_failed.emit(failed_ball, failed_path)
		return
	current_path.append_array(tail)
	paths[current_color] = current_path.duplicate()
	tap_selected = false
	_reset_drag()
	emit_signal("pair_completed")


## A* on a ROUTE_GRID lattice that keeps ROUTE_CLEAR from other lines
## and balls, then string-pulled with the same _segment_blocked rule a drag
## obeys. Returns the points after `from`, ending on the partner, or [].
func _find_route(from: Vector2, partner: Node2D) -> Array:
	var origin: Vector2 = board_rect.position
	var cols: int = int(board_rect.size.x / ROUTE_GRID) + 1
	var rows: int = int(board_rect.size.y / ROUTE_GRID) + 1
	var total: int = cols * rows
	var blocked := PackedByteArray()
	blocked.resize(total)
	var segs: Array = []
	for color_key in paths.keys():
		var pts: Array = paths[color_key]
		for i in range(pts.size() - 1):
			segs.append([pts[i], pts[i + 1]])
	for i in range(current_path.size() - 2):
		segs.append([current_path[i], current_path[i + 1]])
	for sg in segs:
		_stamp_segment(blocked, origin, cols, rows, sg[0], sg[1], ROUTE_CLEAR)
	for ball in balls:
		if ball == current_start_ball or ball == partner:
			continue
		var p: Vector2 = ball.position
		var keep_off: float = (
			ball.radius * ROUTE_BALL_KEEP + ROUTE_BALL_GAP + ROUTE_GRID * 0.5
			if _route_strict
			else ball.radius * BALL_BLOCK_FACTOR + ROUTE_CLEAR
		)
		_stamp_segment(blocked, origin, cols, rows, p, p, keep_off)
	var cost := PackedFloat32Array()
	cost.resize(total)
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(total)
	prev.fill(-1)
	var open: Array = []
	for i in range(total):
		var q: Vector2 = origin + Vector2(i % cols, i / cols) * ROUTE_GRID
		var d: float = q.distance_to(from)
		if d <= ROUTE_SEED_REACH and blocked[i] == 0 and _route_step_ok(from, q, null):
			cost[i] = d
			_heap_push(open, [d + q.distance_to(partner.position), i])
	var goal: int = -1
	while not open.is_empty():
		var top: Array = _heap_pop(open)
		var i: int = top[1]
		var here: Vector2 = origin + Vector2(i % cols, i / cols) * ROUTE_GRID
		if top[0] > cost[i] + here.distance_to(partner.position) + 0.01:
			continue
		if here.distance_to(partner.position) <= partner.radius:
			goal = i
			break
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var c: int = i % cols + dx
				var r: int = i / cols + dy
				if c < 0 or r < 0 or c >= cols or r >= rows:
					continue
				var j: int = r * cols + c
				if blocked[j] != 0:
					continue
				var nc: float = cost[i] + ROUTE_GRID * (1.4142 if dx != 0 and dy != 0 else 1.0)
				if nc < cost[j]:
					cost[j] = nc
					prev[j] = i
					var there: Vector2 = origin + Vector2(c, r) * ROUTE_GRID
					_heap_push(open, [nc + there.distance_to(partner.position), j])
	if goal < 0:
		return []
	var nodes: Array = []
	var k: int = goal
	while k >= 0:
		nodes.push_front(origin + Vector2(k % cols, k / cols) * ROUTE_GRID)
		k = prev[k]
	return _pull_string([from] + _corners(nodes) + [partner.position], partner)


## Fewest-bend version of a route: from each point jump to the furthest later
## point the drag rules allow. Works on current_path so self-crossings count.
func _pull_string(pts: Array, partner: Node2D) -> Array:
	var keep: int = current_path.size()
	var out: Array = []
	var i: int = 0
	var last_idx: int = pts.size() - 1
	while i < last_idx:
		var next: int = -1
		for j in range(last_idx, i, -1):
			if _route_step_ok(pts[i], pts[j], partner if j == last_idx else null):
				next = j
				break
		if next < 0:
			out.clear()
			break
		out.append(pts[next])
		current_path.append(pts[next])
		i = next
	current_path.resize(keep)
	return out


## A router step: legal under the drag rules and, in strict mode (tried
## first), clear of every other ball.
func _route_step_ok(a: Vector2, b: Vector2, end_ball: Node2D) -> bool:
	if _segment_blocked(a, b, end_ball != null, end_ball):
		return false
	if not _route_strict:
		return true
	for ball in balls:
		if ball == current_start_ball or ball == end_ball:
			continue
		var keep_off: float = ball.radius * ROUTE_BALL_KEEP + ROUTE_BALL_GAP
		if _segment_hits_circle(a, b, ball.position, keep_off):
			return false
	return true


func _corners(nodes: Array) -> Array:
	if nodes.size() < 3:
		return nodes
	var out: Array = [nodes[0]]
	for i in range(1, nodes.size() - 1):
		var d1: Vector2 = (nodes[i] - nodes[i - 1]).normalized()
		var d2: Vector2 = (nodes[i + 1] - nodes[i]).normalized()
		if not d1.is_equal_approx(d2):
			out.append(nodes[i])
	out.append(nodes[nodes.size() - 1])
	return out


func _stamp_segment(
	blocked: PackedByteArray,
	origin: Vector2,
	cols: int,
	rows: int,
	a: Vector2,
	b: Vector2,
	reach: float
) -> void:
	var c0: int = maxi(0, int((minf(a.x, b.x) - reach - origin.x) / ROUTE_GRID))
	var c1: int = mini(cols - 1, int((maxf(a.x, b.x) + reach - origin.x) / ROUTE_GRID) + 1)
	var r0: int = maxi(0, int((minf(a.y, b.y) - reach - origin.y) / ROUTE_GRID))
	var r1: int = mini(rows - 1, int((maxf(a.y, b.y) + reach - origin.y) / ROUTE_GRID) + 1)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var q: Vector2 = origin + Vector2(c, r) * ROUTE_GRID
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < reach:
				blocked[r * cols + c] = 1


func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		while true:
			var l: int = 2 * i + 1
			var r: int = l + 1
			var m: int = i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var tmp: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = tmp
			i = m
	return top


# ---------------------------------------------------------------- drag


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
