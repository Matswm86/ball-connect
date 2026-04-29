extends Node2D

const COLOR_MAP: Dictionary = {
	"red":    Color(0.95, 0.22, 0.30),
	"blue":   Color(0.20, 0.65, 0.97),
	"green":  Color(0.30, 0.86, 0.32),
	"yellow": Color(0.98, 0.92, 0.20),
	"orange": Color(0.98, 0.55, 0.10),
	"pink":   Color(0.95, 0.40, 0.85),
	"cyan":   Color(0.20, 0.92, 0.92),
	"purple": Color(0.66, 0.32, 0.95)
}

@export var levels_path: String = "res://data/levels/"
@export var start_level: int = 1
@export var max_level: int = 5

var current_level: int = 1
var balls: Array = []
var ball_scene: PackedScene = preload("res://scenes/Ball.tscn")
var won: bool = false

@onready var ball_layer: Node2D = $BallLayer
@onready var line_drawer: Node2D = $LineDrawer
@onready var level_label: Label = $UI/LevelLabel
@onready var win_label: Label = $UI/WinLabel
@onready var hint_label: Label = $UI/HintLabel
@onready var reset_button: Button = $UI/ResetButton

func _ready() -> void:
	current_level = start_level
	line_drawer.pair_completed.connect(_on_pair_completed)
	reset_button.pressed.connect(_on_reset_pressed)
	load_level(current_level)

func _on_reset_pressed() -> void:
	load_level(current_level)

func load_level(n: int) -> void:
	for b in balls:
		b.queue_free()
	balls.clear()
	line_drawer.setup([])
	won = false
	win_label.visible = false
	hint_label.visible = false
	reset_button.visible = true

	var path: String = "%slevel_%02d.json" % [levels_path, n]
	if not FileAccess.file_exists(path):
		level_label.text = "All levels complete"
		hint_label.text = "Add more JSON files to data/levels/"
		hint_label.visible = true
		return

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var raw: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(raw)
	if data == null or not (data is Dictionary):
		level_label.text = "Bad level JSON"
		return

	level_label.text = "Level %d" % n
	var radius: float = float(data.get("ball_radius", 60))

	for b_data in data["balls"]:
		var ball: Node2D = ball_scene.instantiate()
		ball.color_name = String(b_data["color"])
		ball.color = COLOR_MAP.get(b_data["color"], Color.WHITE)
		ball.radius = radius
		ball.position = Vector2(float(b_data["x"]), float(b_data["y"]))
		ball_layer.add_child(ball)
		balls.append(ball)

	line_drawer.setup(balls)

func _total_pairs() -> int:
	var seen: Dictionary = {}
	for b in balls:
		seen[b.color_name] = true
	return seen.size()

func _on_pair_completed() -> void:
	if line_drawer.completed_pair_count() == _total_pairs():
		won = true
		line_drawer.enabled = false
		win_label.text = "Level %d complete\nTap to continue" % current_level
		win_label.visible = true
		reset_button.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not won:
		return
	if event is InputEventScreenTouch and event.pressed:
		_advance()

func _advance() -> void:
	current_level += 1
	if current_level > max_level:
		current_level = 1
	load_level(current_level)
