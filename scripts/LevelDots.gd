extends Control

## Level progress as dots instead of the words "Level N" (non-readers):
## finished levels filled, the current one larger with a ring, later ones hollow.

const DOT_RADIUS: float = 12.0
const DOT_GAP: float = 48.0
const ACCENT: Color = Color(0.45, 0.95, 0.88)

var count: int = 1
var current: int = 1


func show_level(level: int, total: int) -> void:
	current = level
	count = total
	queue_redraw()


func _draw() -> void:
	var width: float = DOT_GAP * float(count - 1)
	var y: float = size.y * 0.5
	for i in range(count):
		var p := Vector2(size.x * 0.5 - width * 0.5 + DOT_GAP * i, y)
		var n: int = i + 1
		if n < current:
			draw_circle(p, DOT_RADIUS, ACCENT)
		elif n == current:
			draw_circle(p, DOT_RADIUS * 1.5, ACCENT)
			draw_circle(p, DOT_RADIUS * 1.5 + 6.0, Color(1, 1, 1, 0.9), false, 4.0, true)
		else:
			draw_circle(p, DOT_RADIUS, Color(ACCENT, 0.55), false, 4.0, true)
