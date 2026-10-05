extends Node2D

const COLOR_MAP: Dictionary = {
	"red": Color(0.95, 0.22, 0.30),
	"blue": Color(0.20, 0.65, 0.97),
	"green": Color(0.30, 0.86, 0.32),
	"yellow": Color(0.98, 0.92, 0.20),
	"orange": Color(0.98, 0.55, 0.10),
	"pink": Color(0.95, 0.40, 0.85),
	"cyan": Color(0.20, 0.92, 0.92),
	"purple": Color(0.66, 0.32, 0.95)
}

const SAVE_PATH: String = "user://ball_connect_save.json"
const SAVE_VERSION: int = 1

@export var levels_path: String = "res://data/levels/"
@export var start_level: int = 1
@export var max_level: int = 5

var current_level: int = 1
var balls: Array = []
var ball_scene: PackedScene = preload("res://scenes/Ball.tscn")
var won: bool = false
var highest_level: int = 1

@onready var ball_layer: Node2D = $BallLayer
@onready var line_drawer: Node2D = $LineDrawer
@onready var board_3d: Node3D = $Board3D
@onready var level_label: Label = $UI/LevelLabel
@onready var win_label: Label = $UI/WinLabel
@onready var hint_label: Label = $UI/HintLabel
@onready var reset_button: Button = $UI/ResetButton


func _ready() -> void:
	current_level = start_level
	_load_progress()
	board_3d.line_drawer = line_drawer
	line_drawer.input_mapper = board_3d.screen_to_board
	_style_ui()
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
	board_3d.setup(balls)


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
		board_3d.celebrate()
		_save_progress(_next_level())
		win_label.modulate.a = 0.0
		create_tween().tween_property(win_label, "modulate:a", 1.0, 0.5).set_delay(0.4)


func _unhandled_input(event: InputEvent) -> void:
	if not won:
		return
	if event is InputEventScreenTouch and event.pressed:
		_advance()


func _advance() -> void:
	current_level = _next_level()
	load_level(current_level)


func _next_level() -> int:
	return 1 if current_level + 1 > max_level else current_level + 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_progress(_next_level() if won else current_level)


# Level progress survives app restarts. Board state is not saved: the
# player resumes at the start of the level they were on.
func _save_progress(level: int) -> void:
	highest_level = maxi(highest_level, level)
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Dictionary = {
		"version": SAVE_VERSION, "current_level": level, "highest_level": highest_level
	}
	f.store_string(JSON.stringify(data))
	f.close()


# Missing, unreadable or corrupt save: keep the defaults and start fresh.
func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_warning("Save file unreadable, starting fresh")
		return
	var data: Dictionary = json.data
	var level: Variant = data.get("current_level")
	if not (level is float or level is int):
		push_warning("Save file has no level, starting fresh")
		return
	current_level = clampi(int(level), 1, max_level)
	var best: Variant = data.get("highest_level", current_level)
	highest_level = (
		clampi(int(best), current_level, max_level)
		if (best is float or best is int)
		else current_level
	)
	print("Save: resuming at level %d (highest %d)" % [current_level, highest_level])


func _style_ui() -> void:
	var accent := Color(0.45, 0.95, 0.88)
	for label in [level_label, hint_label, win_label]:
		label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.07, 0.9))
		label.add_theme_constant_override("outline_size", 14)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		label.add_theme_constant_override("shadow_offset_y", 6)

	level_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	level_label.offset_top = 60
	level_label.offset_bottom = 160
	level_label.add_theme_color_override("font_color", accent)

	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_label.add_theme_font_size_override("font_size", 88)

	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -110
	hint_label.offset_bottom = -30

	reset_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	reset_button.offset_left = -250
	reset_button.offset_right = -40
	reset_button.offset_top = 66
	reset_button.offset_bottom = 156
	reset_button.add_theme_font_size_override("font_size", 40)
	reset_button.text = "Reset"
	reset_button.focus_mode = Control.FOCUS_NONE
	var states: Dictionary = {
		"normal": Color(0.06, 0.16, 0.19, 0.85),
		"hover": Color(0.09, 0.23, 0.27, 0.9),
		"pressed": Color(0.14, 0.34, 0.38, 0.95),
	}
	for state in states:
		var box := StyleBoxFlat.new()
		box.bg_color = states[state]
		box.border_color = accent
		box.set_border_width_all(4)
		box.set_corner_radius_all(45)
		box.shadow_color = Color(accent, 0.25)
		box.shadow_size = 12
		reset_button.add_theme_stylebox_override(state, box)
	reset_button.add_theme_color_override("font_color", accent)
	reset_button.add_theme_color_override("font_hover_color", Color.WHITE)
	reset_button.add_theme_color_override("font_pressed_color", Color.WHITE)
