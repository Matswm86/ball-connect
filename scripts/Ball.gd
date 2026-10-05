extends Node2D

## Touch radius in board px, the same for every ball. Board px map to about
## 0.92-0.99 screen px, so 120 gives a 220-238 px wide touch area on a
## 1080-wide screen: at least 13 mm at 430 dpi (rule 1 asks for 12.7 mm).
## Levels keep ball centres at least 2 x HIT_RADIUS apart so areas never overlap.
const HIT_RADIUS: float = 120.0

var color_name: String = ""
var color: Color = Color.WHITE
var symbol: String = ""
var radius: float = 60.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.05, color.darkened(0.45))
	draw_circle(Vector2.ZERO, radius, color)
	var hi := Vector2(-radius * 0.3, -radius * 0.3)
	draw_circle(hi, radius * 0.32, color.lightened(0.55))


func hit_radius() -> float:
	return maxf(HIT_RADIUS, radius)


func contains_point(p: Vector2) -> bool:
	return position.distance_to(p) <= hit_radius()
