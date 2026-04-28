extends Node2D

var color_name: String = ""
var color: Color = Color.WHITE
var radius: float = 60.0

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.05, color.darkened(0.45))
	draw_circle(Vector2.ZERO, radius, color)
	var hi := Vector2(-radius * 0.3, -radius * 0.3)
	draw_circle(hi, radius * 0.32, color.lightened(0.55))

func contains_point(p: Vector2) -> bool:
	return position.distance_to(p) <= radius
