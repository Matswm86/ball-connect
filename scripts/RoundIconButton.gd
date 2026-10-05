extends Button

## Round picture button with no text (MWM Play DESIGN.md icon style: filled,
## rounded shapes on a disc). The whole control rect is the touch area, which
## can be larger than the disc (rule 5). Fires on release (Button default).

const INK: Color = Color(0.141, 0.129, 0.114)
const CARD: Color = Color(1, 1, 1)
const GREEN: Color = Color(0.122, 0.478, 0.353)
const GREEN_SOFT: Color = Color(0.890, 0.941, 0.918)

## "restart" (circular arrow, white disc) or "next" (arrow, green disc).
@export var kind: String = "restart"
@export var disc_radius: float = 68.0
## Disc centre inside the control; negative means the middle of the rect.
@export var disc_center: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


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
	else:
		draw_circle(c, r, GREEN_SOFT if down else CARD)
		draw_circle(c, r - 2.5, INK, false, 5.0, true)
		_draw_restart(c, r, INK)


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
