extends Button

## Round picture button with no text (MWM Play DESIGN.md icon style: filled,
## rounded shapes on a disc). The whole control rect is the touch area, which
## can be larger than the disc (rule 5). Fires on release (Button default).

const INK: Color = Color(0.141, 0.129, 0.114)
const CARD: Color = Color(1, 1, 1)
const GREEN: Color = Color(0.122, 0.478, 0.353)
const GREEN_SOFT: Color = Color(0.890, 0.941, 0.918)
const MUTED_CARD: Color = Color(0.80, 0.80, 0.79)
const MUTED_INK: Color = Color(0.40, 0.39, 0.37)

## "restart" (circular arrow, white disc), "next" (arrow, green disc),
## "music_on" (music note, white disc) or "music_off" (grey note, slashed).
@export var kind: String = "restart"
@export var disc_radius: float = 68.0
## Disc centre inside the control; negative means the middle of the rect.
@export var disc_center: Vector2 = Vector2(-1, -1)
## Optional: returns true for a screen point another target owns (a ball's
## touch area); the button then lets that touch through.
var pass_through: Callable


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	return not (pass_through.is_valid() and pass_through.call(get_global_transform() * point))


func _center() -> Vector2:
	return size * 0.5 if disc_center.x < 0.0 else disc_center


func _draw() -> void:
	var c: Vector2 = _center()
	var down: bool = is_pressed() or button_pressed
	var r: float = disc_radius * (0.93 if down else 1.0)
	if kind == "next":
		draw_circle(c + Vector2(0, 8), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, GREEN.darkened(0.25) if down else GREEN)
		draw_circle(c, r - 8.0, GREEN.lightened(0.08), false, 6.0, true)
		_draw_next_arrow(c, r, CARD)
	elif kind == "music_on" or kind == "music_off":
		var off: bool = kind == "music_off"
		draw_circle(c, r, GREEN_SOFT if down else (MUTED_CARD if off else CARD))
		draw_circle(c, r - 2.5, INK, false, 5.0, true)
		_draw_note(c, r, MUTED_INK if off else INK)
		if off:
			# Slash top-left to bottom-right: crosses only the stem, the head stays clear.
			var d := Vector2(r, r) * 0.55
			draw_line(c - d, c + d, MUTED_CARD, r * 0.2, true)
			draw_line(c - d, c + d, INK, r * 0.1, true)
	else:
		draw_circle(c, r, GREEN_SOFT if down else CARD)
		draw_circle(c, r - 2.5, INK, false, 5.0, true)
		_draw_restart(c, r, INK)


## Eighth note: oval head, stem up on the right, one flag.
func _draw_note(c: Vector2, r: float, col: Color) -> void:
	var head_c: Vector2 = c + Vector2(-r * 0.12, r * 0.28)
	var head := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		var p := Vector2(cos(a) * r * 0.22, sin(a) * r * 0.16).rotated(-0.45)
		head.append(head_c + p)
	draw_colored_polygon(head, col)
	var w: float = r * 0.09
	var stem_x: float = head_c.x + r * 0.17
	var top := Vector2(stem_x, c.y - r * 0.48)
	draw_line(Vector2(stem_x, head_c.y - r * 0.04), top, col, w, true)
	var flag := PackedVector2Array(
		[
			top + Vector2(-w * 0.5, 0),
			top + Vector2(r * 0.30, r * 0.22),
			top + Vector2(r * 0.24, r * 0.40),
			top + Vector2(w * 0.4, r * 0.22),
		]
	)
	draw_colored_polygon(flag, col)


## Thick circular arrow, open at the top, head pointing anticlockwise.
func _draw_restart(c: Vector2, r: float, col: Color) -> void:
	var ring: float = r * 0.42
	var w: float = r * 0.17
	var start: float = deg_to_rad(-60.0)
	var end: float = deg_to_rad(230.0)
	draw_arc(c, ring, start, end, 40, col, w, true)
	draw_circle(c + Vector2(cos(end), sin(end)) * ring, w * 0.5, col)
	var tip_dir := Vector2(cos(start), sin(start))
	var along := Vector2(-sin(start), cos(start))  # direction of travel at the start
	var base: Vector2 = c + tip_dir * ring
	var head := PackedVector2Array(
		[
			base + tip_dir * w * 1.35,
			base - tip_dir * w * 1.35,
			base - along * w * 1.7,
		]
	)
	draw_colored_polygon(head, col)


func _draw_next_arrow(c: Vector2, r: float, col: Color) -> void:
	var s: float = r * 0.5
	var pts := PackedVector2Array(
		[
			c + Vector2(-s * 0.95, -s * 0.28),
			c + Vector2(s * 0.05, -s * 0.28),
			c + Vector2(s * 0.05, -s * 0.75),
			c + Vector2(s * 0.95, 0),
			c + Vector2(s * 0.05, s * 0.75),
			c + Vector2(s * 0.05, s * 0.28),
			c + Vector2(-s * 0.95, s * 0.28),
		]
	)
	draw_colored_polygon(pts, col)
