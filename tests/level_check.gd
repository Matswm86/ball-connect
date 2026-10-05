extends Node

## Dev-only level checker. Run headless:
##   godot --headless --audio-driver Dummy res://tests/level_check.tscn
## For every data/levels/level_NN.json it checks the touch layout on a
## 1080x1920 screen (touch areas >= 12.7 mm, no overlap, clear of the MWM Play
## home corner, the restart corner and the bottom wrist strip), then finds a
## solution on a 20 px grid and replays it through the game's own LineDrawer
## (the same _start_drag / _continue_drag / _end_drag a finger drives).
## A level only passes when that replay makes GameManager report a win.
## Exit code = number of failing levels.

const GRID: float = 20.0
## Gap the solver keeps between its lines and other lines (2.5 mm, finger room).
const CLEAR: float = 40.0
const BALL_MARGIN: float = 12.0
const SCREEN_MARGIN: float = 24.0
const CORNER: float = 232.0  # MWM Play home square (top-left), restart (top-right)
const WRIST_Y: float = 1664.0
const MIN_HIT_PX: float = 200.0  # 12.7 mm at 400 dpi
const MAX_ROUTINGS: int = 4000

var game: Node
var board: Node3D
var cam: Camera3D
var ld: Node2D

var _cols: int = 0
var _rows: int = 0
var _origin: Vector2
var _valid: PackedByteArray
var _ball_near: PackedInt32Array  # nearest ball per node
var _ball_edge: PackedFloat32Array  # distance from the node to that ball's edge
var _routings: int = 0


func _ready() -> void:
	get_tree().root.size = Vector2i(1080, 1920)
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(5)
	board = game.get_node("Board3D")
	ld = game.get_node("LineDrawer")
	cam = get_viewport().get_camera_3d()
	var files: int = 0
	while FileAccess.file_exists("res://data/levels/level_%02d.json" % (files + 1)):
		files += 1
	var failed: int = 0
	if files != game.max_level:
		print("FAIL level files %d != GameManager.max_level %d" % [files, game.max_level])
		failed += 1
	var worst_hit: float = INF
	for n in range(1, files + 1):
		game.load_level(n)
		await _frames(1)
		var res: Dictionary = _check_level(n)
		worst_hit = minf(worst_hit, res["min_hit"])
		if not res["ok"]:
			failed += 1
	print(
		(
			"SUMMARY levels=%d failed=%d smallest touch area %.0f px = %.1f mm @400dpi, %.1f mm @430dpi"
			% [files, failed, worst_hit, worst_hit * 25.4 / 400.0, worst_hit * 25.4 / 430.0]
		)
	)
	get_tree().quit(failed)


func _screen(p: Vector2) -> Vector2:
	return cam.unproject_position(board.px_to_world(p, board.TUBE_HEIGHT))


func _check_level(n: int) -> Dictionary:
	var balls: Array = game.balls
	var problems: Array = []
	var by_color: Dictionary = {}
	var min_hit: float = INF
	for b in balls:
		by_color[b.color_name] = by_color.get(b.color_name, []) + [b]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var in_corner: bool = false
		for i in range(72):
			var s: Vector2 = _screen(
				b.position + Vector2.from_angle(TAU * i / 72.0) * b.hit_radius()
			)
			lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
			hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
			if s.y < CORNER and (s.x < CORNER or s.x > 1080.0 - CORNER):
				in_corner = true
		if hi.y >= WRIST_Y:
			problems.append("%s touch area reaches wrist strip y=%.0f" % [b.color_name, hi.y])
		if in_corner:
			problems.append("%s touch area in a top corner square" % b.color_name)
		min_hit = minf(min_hit, minf(hi.x - lo.x, hi.y - lo.y))
		var c: Vector2 = _screen(b.position)
		var r_px: float = (_screen(b.position + Vector2(b.radius, 0)) - c).length()
		if c.x - r_px < 0.0 or c.x + r_px > 1080.0:
			problems.append("%s ball not fully on screen" % b.color_name)
	for i in range(balls.size()):
		for j in range(i + 1, balls.size()):
			var d: float = balls[i].position.distance_to(balls[j].position)
			if d < balls[i].hit_radius() + balls[j].hit_radius():
				problems.append(
					(
						"touch areas overlap: %s/%s %.0f px apart"
						% [balls[i].color_name, balls[j].color_name, d]
					)
				)
	for k in by_color:
		if by_color[k].size() != 2:
			problems.append("colour %s has %d balls" % [k, by_color[k].size()])
	if min_hit < MIN_HIT_PX:
		problems.append("touch area %.0f px < %.0f px" % [min_hit, MIN_HIT_PX])

	var pairs: Array = []
	for k in by_color:
		if by_color[k].size() == 2:
			pairs.append(by_color[k])
	var straight: Array = _straight_report(pairs)

	_build_grid()
	_routings = 0
	var order: Array = []
	var routes: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	var found: bool = _solve(pairs, [], _base_dist(), order, routes)
	var ms: int = Time.get_ticks_msec() - t0
	var replay_ok: bool = false
	if found:
		ld.setup(balls)
		for k in order:
			var pts: Array = routes[k]
			ld._start_drag(pts[0])
			for i in range(1, pts.size() - 1):
				ld._continue_drag(pts[i])
			ld._end_drag(pts[pts.size() - 1])
		replay_ok = game.won and ld.completed_pair_count() == pairs.size()
	var ok: bool = problems.is_empty() and found and replay_ok
	var lens: Array = []
	for k in order:
		lens.append("%s %d turns" % [k, _bends(routes[k])])
	print(
		(
			"LEVEL %d %s pairs=%d touch>=%.0f px (%.1f mm @400, %.1f mm @430) straight-drag pairs=%s"
			% [
				n,
				"PASS" if ok else "FAIL",
				pairs.size(),
				min_hit,
				min_hit * 25.4 / 400.0,
				min_hit * 25.4 / 430.0,
				str(straight),
			]
		)
	)
	print(
		(
			"  solver: %s in %d routings, %d ms; order+route: %s; replay through LineDrawer: %s"
			% [
				"solved" if found else "NO SOLUTION",
				_routings,
				ms,
				", ".join(lens),
				"won=true" if replay_ok else "NOT WON",
			]
		)
	)
	for p in problems:
		print("  problem: ", p)
	return {"ok": ok, "min_hit": min_hit}


## Which pairs connect with one straight drag, drawing them in turn.
func _straight_report(pairs: Array) -> Array:
	ld.setup(game.balls)
	var out: Array = []
	for pr in pairs:
		ld._start_drag(pr[0].position)
		var a: Vector2 = pr[0].position
		var b: Vector2 = pr[1].position
		var steps: int = int(a.distance_to(b) / 15.0)
		for i in range(1, steps):
			ld._continue_drag(a.lerp(b, float(i) / steps))
		ld._end_drag(b)
		if ld.paths.has(pr[0].color_name):
			out.append(pr[0].color_name)
	ld.setup(game.balls)
	game.won = false
	return out


## Turns sharper than 30 degrees along a route, ignoring short grid jogs.
func _bends(pts: Array) -> int:
	var dirs: Array = []
	for i in range(1, pts.size()):
		var seg: Vector2 = pts[i] - pts[i - 1]
		if seg.length() >= 60.0:
			dirs.append(seg.normalized())
	var count: int = 0
	for i in range(1, dirs.size()):
		if absf(dirs[i].angle_to(dirs[i - 1])) > deg_to_rad(30.0):
			count += 1
	return count


# ---------------------------------------------------------------- grid solver


func _build_grid() -> void:
	var tl: Vector2 = board.screen_to_board(Vector2(SCREEN_MARGIN, SCREEN_MARGIN))
	var br: Vector2 = board.screen_to_board(Vector2(1080 - SCREEN_MARGIN, 1920 - SCREEN_MARGIN))
	var tr: Vector2 = board.screen_to_board(Vector2(1080 - SCREEN_MARGIN, SCREEN_MARGIN))
	_origin = Vector2(minf(tl.x, br.x), tl.y)
	_cols = int((maxf(tr.x, br.x) - _origin.x) / GRID) + 1
	_rows = int((br.y - _origin.y) / GRID) + 1
	_valid = PackedByteArray()
	_valid.resize(_cols * _rows)
	for r in range(_rows):
		for c in range(_cols):
			var s: Vector2 = _screen(_node_pos(c, r))
			var inside: bool = (
				s.x >= SCREEN_MARGIN
				and s.x <= 1080 - SCREEN_MARGIN
				and s.y >= SCREEN_MARGIN
				and s.y <= 1920 - SCREEN_MARGIN
			)
			_valid[r * _cols + c] = 1 if inside else 0
	_ball_near = PackedInt32Array()
	_ball_near.resize(_cols * _rows)
	_ball_edge = PackedFloat32Array()
	_ball_edge.resize(_cols * _rows)
	for i in range(_cols * _rows):
		var p: Vector2 = _node_pos(i % _cols, i / _cols)
		var best: float = INF
		for bi in range(game.balls.size()):
			var b: Node2D = game.balls[bi]
			var e: float = p.distance_to(b.position) - b.radius
			if e < best:
				best = e
				_ball_near[i] = bi
		_ball_edge[i] = best


func _node_pos(c: int, r: int) -> Vector2:
	return _origin + Vector2(c, r) * GRID


## Distance from every node to the nearest placed line (none yet).
func _base_dist() -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(_cols * _rows)
	dist.fill(INF)
	return dist


func _stamp_path(dist: PackedFloat32Array, pts: Array) -> void:
	var reach: float = CLEAR + 80.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var c0: int = maxi(0, int((minf(a.x, b.x) - reach - _origin.x) / GRID))
		var c1: int = mini(_cols - 1, int((maxf(a.x, b.x) + reach - _origin.x) / GRID) + 1)
		var r0: int = maxi(0, int((minf(a.y, b.y) - reach - _origin.y) / GRID))
		var r1: int = mini(_rows - 1, int((maxf(a.y, b.y) + reach - _origin.y) / GRID) + 1)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var p: Vector2 = _node_pos(c, r)
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
				var idx: int = r * _cols + c
				dist[idx] = minf(dist[idx], p.distance_to(q))


func _solve(
	pairs: Array, done: Array, dist: PackedFloat32Array, order: Array, routes: Dictionary
) -> bool:
	if done.size() == pairs.size():
		return true
	if _routings >= MAX_ROUTINGS:
		return false
	var todo: Array = []
	for pr in pairs:
		if not done.has(pr[0].color_name):
			todo.append(pr)
	todo.sort_custom(
		func(x: Array, y: Array) -> bool:
			return (
				x[0].position.distance_to(x[1].position) < y[0].position.distance_to(y[1].position)
			)
	)
	for pr in todo:
		var route: Array = _route(pr[0], pr[1], dist)
		_routings += 1
		if route.is_empty():
			continue
		var next_dist: PackedFloat32Array = dist.duplicate()
		_stamp_path(next_dist, route)
		var k: String = pr[0].color_name
		order.append(k)
		routes[k] = route
		if _solve(pairs, done + [k], next_dist, order, routes):
			return true
		order.pop_back()
		routes.erase(k)
		if _routings >= MAX_ROUTINGS:
			return false
	return false


## Dijkstra on the grid from ball a to ball b. Nodes closer than BALL_MARGIN to
## a ball edge (other than a or b) or closer than CLEAR to a placed line are
## blocked; nodes near obstacles cost more, so lines leave room for others.
func _route(a: Node2D, b: Node2D, dist: PackedFloat32Array) -> Array:
	var total: int = _cols * _rows
	var cost := PackedFloat32Array()
	cost.resize(total)
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(total)
	prev.fill(-1)
	var open: Array = []  # [cost, idx], kept small by a binary heap
	for i in range(total):
		var p: Vector2 = _node_pos(i % _cols, i / _cols)
		if p.distance_to(a.position) <= a.radius and _passable(i, dist, a, b):
			cost[i] = p.distance_to(a.position)
			_push(open, [cost[i], i])
	var goal: int = -1
	var dirs: Array = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1)
	]
	while not open.is_empty():
		var top: Array = _pop(open)
		var i: int = top[1]
		if top[0] > cost[i]:
			continue
		var p: Vector2 = _node_pos(i % _cols, i / _cols)
		if p.distance_to(b.position) <= b.radius:
			goal = i
			break
		for d in dirs:
			var c: int = i % _cols + d.x
			var r: int = i / _cols + d.y
			if c < 0 or r < 0 or c >= _cols or r >= _rows:
				continue
			var j: int = r * _cols + c
			if not _passable(j, dist, a, b):
				continue
			var step: float = GRID * (1.4142 if d.x != 0 and d.y != 0 else 1.0)
			var pen: float = maxf(0.0, 48.0 - _room(j, dist, a, b)) * 0.4
			var nc: float = cost[i] + step + pen
			if nc < cost[j]:
				cost[j] = nc
				prev[j] = i
				_push(open, [cost[j], j])
	if goal < 0:
		return []
	var nodes: Array = []
	var k: int = goal
	while k >= 0:
		nodes.push_front(_node_pos(k % _cols, k / _cols))
		k = prev[k]
	return [a.position] + _simplify(nodes) + [b.position]


func _passable(i: int, dist: PackedFloat32Array, a: Node2D, b: Node2D) -> bool:
	if _valid[i] == 0:
		return false
	var p: Vector2 = _node_pos(i % _cols, i / _cols)
	if p.distance_to(a.position) <= a.radius or p.distance_to(b.position) <= b.radius:
		return true
	return _room(i, dist, a, b) >= 0.0


## Spare room at a node: how far it is past the line gap and the ball margin.
## The route's own two balls never count as obstacles.
func _room(i: int, dist: PackedFloat32Array, a: Node2D, b: Node2D) -> float:
	var room: float = dist[i] - CLEAR
	var near: Node2D = game.balls[_ball_near[i]]
	if near != a and near != b:
		room = minf(room, _ball_edge[i] - BALL_MARGIN)
	return room


## Drop grid points that lie on a straight run, keeping corners.
func _simplify(nodes: Array) -> Array:
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


func _push(heap: Array, item: Array) -> void:
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


func _pop(heap: Array) -> Array:
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


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
