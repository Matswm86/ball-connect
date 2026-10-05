extends Node3D

## 3D view of the board. Gameplay stays in the 1080x1920 pixel space used by
## LineDrawer and the level JSON; this node mirrors that state into meshes each
## time LineDrawer.revision changes, and maps screen touches back to pixels.

const PX_PER_UNIT: float = 100.0
const BOARD_CENTER_PX: Vector2 = Vector2(540, 960)
const TUBE_RADIUS: float = 0.15
const TUBE_SIDES: int = 12
const TUBE_HEIGHT: float = 0.17
const CAMERA_FOV: float = 20.0
const CAMERA_TILT_DEG: float = 6.0
const VISIBLE_WIDTH: float = 11.4
## World units the view is shifted so the board sits about 80 px lower on
## screen, keeping the top-left 232 px square free (the MWM Play home button).
const BOARD_SCREEN_SHIFT: float = 0.85
## Symbol inside each ball, so pairs match by shape as well as colour (rule 36).
const SYMBOL_SIZE: float = 0.5  # symbol radius as a share of the ball radius
const SYMBOL_COLOR: Color = Color(0.141, 0.129, 0.114)  # DESIGN.md ink
## A drag that does not connect shrinks back to its ball and the ball shakes.
const SPRING_BACK_TIME: float = 0.45
const SHAKE_TIME: float = 0.4
const SHAKE_AMOUNT: float = 0.09
## A ball picked by a tap floats up and glows until the line is finished.
const TAP_LIFT: float = 0.35
const TAP_GLOW: float = 0.7
## Small discs on the cells the tapped line can grow into next.
const MARKER_RADIUS: float = 0.2
const MAX_MARKERS: int = 8
## Idle hint (rule 18): slow swell of one pair, 1 pulse per second (rule 37
## allows up to 3), 3 pulses, then still until the next idle period.
const HINT_HZ: float = 1.0
const HINT_PULSES: int = 3
const HINT_SCALE: float = 0.16
const HINT_GLOW: float = 0.75

var line_drawer: Node2D = null

var _camera: Camera3D
var _balls: Array = []
var _ball_nodes: Dictionary = {}  # Ball (Node2D) -> Node3D holding sphere + socket
var _ball_materials: Dictionary = {}  # Ball (Node2D) -> StandardMaterial3D
var _tube_root: Node3D
var _drag_tube: MeshInstance3D
var _drag_head: MeshInstance3D
var _connected: Dictionary = {}  # color name -> true
var _last_revision: int = -1
var _time: float = 0.0
var _floor_shader: Shader = preload("res://scripts/board_floor.gdshader")
var _spring_tube: MeshInstance3D
var _spring_path: Array = []
var _spring_color: Color = Color.WHITE
var _spring_t: float = 0.0
var _markers: Array = []  # MeshInstance3D pool for tap targets
var _hint_balls: Array = []
var _hint_t: float = -1.0  # seconds into the hint, < 0 = no hint
var _lift: Dictionary = {}  # Ball (Node2D) -> current tap lift in world units


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_floor()
	_build_dust()
	_tube_root = Node3D.new()
	add_child(_tube_root)
	_drag_tube = MeshInstance3D.new()
	add_child(_drag_tube)
	_drag_head = MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = TUBE_RADIUS * 1.9
	head_mesh.height = TUBE_RADIUS * 3.8
	_drag_head.mesh = head_mesh
	_drag_head.visible = false
	add_child(_drag_head)
	_spring_tube = MeshInstance3D.new()
	add_child(_spring_tube)
	var disc := CylinderMesh.new()
	disc.top_radius = MARKER_RADIUS
	disc.bottom_radius = MARKER_RADIUS
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	for i in range(MAX_MARKERS):
		var m := MeshInstance3D.new()
		m.mesh = disc
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_markers.append(m)


# ---------------------------------------------------------------- coordinates


func px_to_world(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(
		(p.x - BOARD_CENTER_PX.x) / PX_PER_UNIT, height, (p.y - BOARD_CENTER_PX.y) / PX_PER_UNIT
	)


## Converts a viewport touch position to board pixel coordinates by casting a
## ray from the camera onto the plane the tubes are drawn on.
func screen_to_board(screen_pos: Vector2) -> Vector2:
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector2(-10000, -10000)
	var t: float = (TUBE_HEIGHT - origin.y) / dir.y
	var hit: Vector3 = origin + dir * t
	return Vector2(hit.x * PX_PER_UNIT + BOARD_CENTER_PX.x, hit.z * PX_PER_UNIT + BOARD_CENTER_PX.y)


# ---------------------------------------------------------------- scene setup


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.52, 0.72)
	sky_mat.sky_horizon_color = Color(0.85, 0.78, 0.66)
	sky_mat.ground_horizon_color = Color(0.35, 0.38, 0.40)
	sky_mat.ground_bottom_color = Color(0.05, 0.07, 0.09)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.035, 0.05)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	key.look_at_from_position(Vector3(-4, 10, -5), Vector3.ZERO)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, -150, 0)
	rim.light_color = Color(0.55, 0.80, 1.0)
	rim.light_energy = 0.45
	add_child(rim)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	var dist: float = (VISIBLE_WIDTH * 0.5) / tan(deg_to_rad(CAMERA_FOV * 0.5))
	var tilt: float = deg_to_rad(CAMERA_TILT_DEG)
	var target := Vector3(0, 0, -BOARD_SCREEN_SHIFT)
	_camera.position = target + Vector3(0, dist * cos(tilt), dist * sin(tilt))
	add_child(_camera)
	_camera.look_at(target, Vector3.FORWARD)
	_camera.current = true


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 80)
	var mat := ShaderMaterial.new()
	mat.shader = _floor_shader
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = mat
	add_child(floor_mesh)


func _build_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.amount = 60
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(6, 0.3, 9)
	dust.position = Vector3(0, 0.4, 0)
	dust.direction = Vector3.UP
	dust.spread = 30.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.2
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 0.8))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	dust.color_ramp = fade
	var mote := SphereMesh.new()
	mote.radius = 0.025
	mote.height = 0.05
	mote.radial_segments = 6
	mote.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.7, 1.0, 0.95)
	mote.material = mat
	dust.mesh = mote
	add_child(dust)


# ---------------------------------------------------------------- level state


func setup(balls: Array) -> void:
	for node in _ball_nodes.values():
		node.queue_free()
	_ball_nodes.clear()
	_ball_materials.clear()
	_connected.clear()
	_lift.clear()
	for child in _tube_root.get_children():
		child.queue_free()
	_drag_tube.mesh = null
	_drag_head.visible = false
	_spring_tube.mesh = null
	_spring_t = 0.0
	stop_hint()
	_balls = balls
	_last_revision = -1

	var i: int = 0
	for b in balls:
		var holder := Node3D.new()
		holder.position = px_to_world(b.position)
		add_child(holder)

		var r: float = b.radius / PX_PER_UNIT
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 2.0
		sphere.radial_segments = 40
		sphere.rings = 20
		var mat := StandardMaterial3D.new()
		mat.albedo_color = b.color
		mat.roughness = 0.14
		mat.metallic = 0.05
		mat.metallic_specular = 0.7
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.8
		mat.clearcoat_roughness = 0.1
		mat.rim_enabled = true
		mat.rim = 0.35
		mat.rim_tint = 0.6
		mat.emission_enabled = true
		mat.emission = b.color
		mat.emission_energy_multiplier = 0.08
		var ball_mesh := MeshInstance3D.new()
		ball_mesh.name = "Sphere"
		ball_mesh.mesh = sphere
		ball_mesh.material_override = mat
		ball_mesh.position.y = r
		holder.add_child(ball_mesh)

		var mark := MeshInstance3D.new()
		mark.name = "Symbol"
		mark.mesh = _symbol_mesh(String(b.symbol), r * SYMBOL_SIZE)
		var mark_mat := StandardMaterial3D.new()
		mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark_mat.albedo_color = SYMBOL_COLOR
		mark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mark.material_override = mark_mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.position.y = r + 0.004
		ball_mesh.add_child(mark)

		var torus := TorusMesh.new()
		torus.inner_radius = r * 1.08
		torus.outer_radius = r * 1.26
		torus.rings = 40
		torus.ring_segments = 8
		var socket_mat := StandardMaterial3D.new()
		socket_mat.albedo_color = b.color.darkened(0.5)
		socket_mat.emission_enabled = true
		socket_mat.emission = b.color
		socket_mat.emission_energy_multiplier = 0.6
		socket_mat.roughness = 0.4
		var socket := MeshInstance3D.new()
		socket.mesh = torus
		socket.material_override = socket_mat
		socket.scale = Vector3(1, 0.25, 1)
		socket.position.y = 0.02
		socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(socket)

		holder.scale = Vector3.ONE * 0.01
		var tw := create_tween()
		tw.tween_interval(0.035 * i)
		tw.tween_property(holder, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(
			Tween.EASE_OUT
		)
		_ball_nodes[b] = holder
		_ball_materials[b] = mat
		i += 1


func celebrate() -> void:
	var i: int = 0
	for b in _balls:
		var sphere: Node3D = _ball_nodes[b].get_node("Sphere")
		var base_y: float = sphere.position.y
		var tw := create_tween()
		tw.tween_interval(0.05 * i)
		(
			tw
			. tween_property(sphere, "position:y", base_y + 0.9, 0.22)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(sphere, "position:y", base_y, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(
			Tween.EASE_OUT
		)
		_burst(px_to_world(b.position, 0.6), b.color, 36)
		i += 1


## Visible "no" for a drag that did not connect: the drawn line shrinks back
## into its ball and the ball shakes its head. Never a silent nothing.
func play_fail(ball: Node2D, path: Array) -> void:
	if not _ball_nodes.has(ball):
		return
	_spring_path = path.duplicate()
	_spring_color = ball.color
	_spring_t = SPRING_BACK_TIME if path.size() >= 2 else 0.0
	var holder: Node3D = _ball_nodes[ball]
	var home: Vector3 = px_to_world(ball.position)
	holder.position = home
	var tw := create_tween()
	var step: float = SHAKE_TIME / 6.0
	for i in range(5):
		var side: float = SHAKE_AMOUNT * (1.0 - i / 5.0) * (1.0 if i % 2 == 0 else -1.0)
		tw.tween_property(holder, "position", home + Vector3(side, 0, 0), step)
	tw.tween_property(holder, "position", home, step)


## Idle hint: pulse these balls (one pair) HINT_PULSES times.
func show_hint(hint_balls: Array) -> void:
	_hint_balls = hint_balls
	_hint_t = 0.0


func stop_hint() -> void:
	_hint_balls = []
	_hint_t = -1.0


func hint_active() -> bool:
	return _hint_t >= 0.0


# ---------------------------------------------------------------- per frame


func _process(delta: float) -> void:
	_time += delta
	if line_drawer == null:
		return
	if _spring_t > 0.0:
		# Capped step: a slow frame cannot skip the whole cue.
		_spring_t = maxf(_spring_t - minf(delta, 1.0 / 30.0), 0.0)
		var left: float = _spring_t / SPRING_BACK_TIME
		var cut: Array = _path_prefix(_spring_path, left * left)
		_spring_tube.mesh = _build_tube(cut) if cut.size() >= 2 else null
		_spring_tube.material_override = _tube_material(_spring_color, 1.2)
	elif _spring_tube.mesh != null:
		_spring_tube.mesh = null
	if line_drawer.revision != _last_revision:
		_last_revision = line_drawer.revision
		_sync_paths()
	_animate_balls(delta)


func _animate_balls(delta: float) -> void:
	var active: Node2D = line_drawer.current_start_ball
	var tapped: bool = line_drawer.tap_selected
	var k: float = 1.0 - exp(-delta * 14.0)
	var pulse: float = 0.0
	if _hint_t >= 0.0:
		_hint_t += delta
		if _hint_t >= HINT_PULSES / HINT_HZ:
			stop_hint()
		else:
			pulse = 0.5 - 0.5 * cos(TAU * HINT_HZ * _hint_t)
	for b in _balls:
		var holder: Node3D = _ball_nodes[b]
		if holder.scale.x < 0.99:
			continue  # spawn tween still running
		var sphere: Node3D = holder.get_node("Sphere")
		var target: float = 1.14 if b == active else 1.0
		var hinted: bool = _hint_balls.has(b)
		if hinted:
			target = maxf(target, 1.0 + HINT_SCALE * pulse)
		sphere.scale = sphere.scale.lerp(Vector3.ONE * target, k)
		# Lift is added as a delta so the win bounce tween keeps working.
		var lift_to: float = TAP_LIFT if (tapped and b == active) else 0.0
		var lift_was: float = _lift.get(b, 0.0)
		var lift_now: float = lerpf(lift_was, lift_to, k)
		sphere.position.y += lift_now - lift_was
		_lift[b] = lift_now
		var mat: StandardMaterial3D = _ball_materials[b]
		var glow: float = 0.08
		if _connected.has(b.color_name):
			glow = 0.55 + 0.15 * sin(_time * 3.0 + b.position.x * 0.01)
		elif b == active:
			glow = TAP_GLOW if tapped else 0.5
		if hinted:
			glow = maxf(glow, 0.08 + HINT_GLOW * pulse)
		mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, glow, k)


func _sync_paths() -> void:
	var paths: Dictionary = line_drawer.paths
	for color_key in _connected.keys():
		if not paths.has(color_key):
			_connected.erase(color_key)
	for child in _tube_root.get_children():
		child.queue_free()
	for color_key in paths.keys():
		var c: Color = line_drawer._color_for(color_key)
		var tube := MeshInstance3D.new()
		tube.mesh = _build_tube(paths[color_key])
		tube.material_override = _tube_material(c, 0.9)
		_tube_root.add_child(tube)
		if not _connected.has(color_key):
			_connected[color_key] = true
			for b in _balls:
				if b.color_name == color_key:
					_burst(px_to_world(b.position, 0.5), c, 22)

	var cur: Array = line_drawer.current_path
	if cur.size() >= 2 and line_drawer.current_color != "":
		var c2: Color = line_drawer._color_for(line_drawer.current_color)
		_drag_tube.mesh = _build_tube(cur)
		_drag_tube.material_override = _tube_material(c2, 1.4)
		_drag_head.material_override = _tube_material(c2.lightened(0.3), 2.2)
		_drag_head.position = px_to_world(cur[cur.size() - 1], TUBE_HEIGHT)
		_drag_head.visible = true
	else:
		_drag_tube.mesh = null
		_drag_head.visible = false
	_sync_markers()


func _sync_markers() -> void:
	var targets: Array = line_drawer.tap_targets()
	var mat: StandardMaterial3D = null
	if not targets.is_empty():
		var c: Color = line_drawer._color_for(line_drawer.current_color)
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(c.lightened(0.25), 0.55)
	for i in range(_markers.size()):
		var m: MeshInstance3D = _markers[i]
		m.visible = i < targets.size()
		if m.visible:
			m.position = px_to_world(targets[i], 0.03)
			m.material_override = mat


# ---------------------------------------------------------------- mesh helpers


## First `share` (0..1) of a polyline, measured along its length.
func _path_prefix(pts: Array, share: float) -> Array:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var want: float = total * share
	var out: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if want <= seg:
			if want > 0.5:
				out.append(a.lerp(b, want / seg))
			return out
		want -= seg
		out.append(b)
	return out


## Outline of a symbol in the XZ plane, centred on 0 and `size` in radius.
func _symbol_outline(kind: String, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"triangle":
			for i in range(3):
				var a: float = -PI / 2.0 + TAU * i / 3.0
				pts.append(Vector2(cos(a), sin(a) + 0.18) * size * 1.12)
		"square":
			var h: float = size * 0.78
			pts = PackedVector2Array(
				[Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
			)
		"diamond":
			pts = PackedVector2Array(
				[
					Vector2(0, -size * 1.1),
					Vector2(size * 0.78, 0),
					Vector2(0, size * 1.1),
					Vector2(-size * 0.78, 0)
				]
			)
		"star":
			for i in range(10):
				var a: float = -PI / 2.0 + TAU * i / 10.0
				var rr: float = size * (1.1 if i % 2 == 0 else 0.46)
				pts.append(Vector2(cos(a), sin(a) + 0.08) * rr)
		"heart":
			for i in range(40):
				var t: float = TAU * i / 40.0
				var x: float = 16.0 * pow(sin(t), 3)
				var y: float = 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(Vector2(x, -y - 2.6) * size / 15.0)
		"plus":
			var a2: float = size * 0.95
			var b2: float = size * 0.34
			pts = PackedVector2Array(
				[
					Vector2(-b2, -a2),
					Vector2(b2, -a2),
					Vector2(b2, -b2),
					Vector2(a2, -b2),
					Vector2(a2, b2),
					Vector2(b2, b2),
					Vector2(b2, a2),
					Vector2(-b2, a2),
					Vector2(-b2, b2),
					Vector2(-a2, b2),
					Vector2(-a2, -b2),
					Vector2(-b2, -b2)
				]
			)
		"moon":
			var outer := PackedVector2Array()
			var bite := PackedVector2Array()
			for i in range(32):
				var a3: float = TAU * i / 32.0
				outer.append(Vector2(cos(a3), sin(a3)) * size)
				bite.append(Vector2(cos(a3) * 0.8 + 0.5, sin(a3) * 0.8 - 0.15) * size)
			var parts: Array = Geometry2D.clip_polygons(outer, bite)
			pts = parts[0] if not parts.is_empty() else outer
		_:  # circle
			for i in range(32):
				var a5: float = TAU * i / 32.0
				pts.append(Vector2(cos(a5), sin(a5)) * size * 0.85)
	return pts


func _symbol_mesh(kind: String, size: float) -> ArrayMesh:
	var outline: PackedVector2Array = _symbol_outline(kind, size)
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for p in outline:
		verts.append(Vector3(p.x, 0, p.y))
		normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tube_material(c: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = glow
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## One Chaikin pass rounds the corners of the hand-drawn path; endpoints stay put.
func _smooth(pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


func _build_tube(raw_pts: Array) -> ArrayMesh:
	var pts: Array = []
	for p in _smooth(raw_pts):
		var w: Vector3 = px_to_world(p, TUBE_HEIGHT)
		if pts.is_empty() or pts[pts.size() - 1].distance_to(w) > 0.01:
			pts.append(w)
	if pts.size() < 2:
		return null

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var n: int = pts.size()
	for i in range(n):
		var prev: Vector3 = pts[max(i - 1, 0)]
		var next: Vector3 = pts[min(i + 1, n - 1)]
		var tangent: Vector3 = (next - prev).normalized()
		var side: Vector3 = tangent.cross(Vector3.UP).normalized()
		for s in range(TUBE_SIDES):
			var a: float = TAU * float(s) / float(TUBE_SIDES)
			var nrm: Vector3 = side * cos(a) + Vector3.UP * sin(a)
			verts.append(pts[i] + nrm * TUBE_RADIUS)
			normals.append(nrm)
	for i in range(n - 1):
		for s in range(TUBE_SIDES):
			var a0: int = i * TUBE_SIDES + s
			var b0: int = i * TUBE_SIDES + (s + 1) % TUBE_SIDES
			indices.append_array([a0, a0 + TUBE_SIDES, b0, b0, a0 + TUBE_SIDES, b0 + TUBE_SIDES])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _burst(at: Vector3, c: Color, count: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = count
	p.lifetime = 1.1
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	var spark := SphereMesh.new()
	spark.radius = 0.07
	spark.height = 0.14
	spark.radial_segments = 8
	spark.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c.lightened(0.2)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.5
	spark.material = mat
	p.mesh = spark
	p.position = at
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
