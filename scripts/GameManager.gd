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
## Shape inside each ball, so a pair also matches by shape (colour-blind cue).
const SYMBOL_MAP: Dictionary = {
	"red": "heart",
	"blue": "circle",
	"green": "triangle",
	"yellow": "star",
	"orange": "square",
	"pink": "diamond",
	"cyan": "plus",
	"purple": "moon"
}

const SAVE_PATH: String = "user://ball_connect_save.json"
## Version 2 (2026-10-05): three easy levels were put in front, so old
## level N >= 2 is now level N + 3 and old level 1 maps to the new level 1.
const SAVE_VERSION: int = 2
const LEVELS_ADDED_IN_V2: int = 3
## The next-level arrow ignores taps until this long after a win, so the
## finger that finished the last line cannot skip the win screen by accident.
const NEXT_ARROW_DELAY: float = 0.9
## Touch areas in screen px (1080 wide): 232 px = 14.7 mm at 400 dpi,
## 13.7 mm at 430 dpi; the next arrow is 360 px = 22.9 / 21.3 mm.
const RESTART_HIT: float = 232.0
const NEXT_HIT: float = 360.0

@export var levels_path: String = "res://data/levels/"
@export var start_level: int = 1
@export var max_level: int = 8

var current_level: int = 1
var balls: Array = []
var ball_scene: PackedScene = preload("res://scenes/Ball.tscn")
var won: bool = false
var highest_level: int = 1

@onready var ball_layer: Node2D = $BallLayer
@onready var line_drawer: Node2D = $LineDrawer
@onready var board_3d: Node3D = $Board3D
@onready var level_dots: Control = $UI/LevelDots
@onready var hint_label: Label = $UI/HintLabel
@onready var reset_button: Button = $UI/ResetButton
@onready var next_button: Button = $UI/NextButton


func _ready() -> void:
	current_level = start_level
	_load_progress()
	board_3d.line_drawer = line_drawer
	line_drawer.input_mapper = board_3d.screen_to_board
	_style_ui()
	line_drawer.pair_completed.connect(_on_pair_completed)
	line_drawer.drag_failed.connect(board_3d.play_fail)
	reset_button.pressed.connect(_on_reset_pressed)
	next_button.pressed.connect(_advance)
	load_level(current_level)


func _on_reset_pressed() -> void:
	load_level(current_level)


func load_level(n: int) -> void:
	for b in balls:
		b.queue_free()
	balls.clear()
	line_drawer.setup([])
	won = false
	next_button.visible = false
	hint_label.visible = false
	reset_button.visible = true

	var path: String = "%slevel_%02d.json" % [levels_path, n]
	if not FileAccess.file_exists(path):
		hint_label.text = "All levels complete"
		hint_label.text = "Add more JSON files to data/levels/"
		hint_label.visible = true
		return

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var raw: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(raw)
	if data == null or not (data is Dictionary):
		hint_label.text = "Bad level JSON"
		hint_label.visible = true
		return

	level_dots.show_level(n, max_level)
	var radius: float = float(data.get("ball_radius", 60))

	for b_data in data["balls"]:
		var ball: Node2D = ball_scene.instantiate()
		ball.color_name = String(b_data["color"])
		ball.color = COLOR_MAP.get(b_data["color"], Color.WHITE)
		ball.symbol = SYMBOL_MAP.get(b_data["color"], "circle")
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
		reset_button.visible = false
		board_3d.celebrate()
		_save_progress(_next_level())
		next_button.visible = true
		next_button.disabled = true
		next_button.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(next_button, "modulate:a", 1.0, 0.5).set_delay(NEXT_ARROW_DELAY - 0.5)
		tw.tween_callback(func() -> void: next_button.disabled = false)


func _advance() -> void:
	if not won:
		return
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
	var version: Variant = data.get("version", 1)
	var old_format: bool = not (version is float or version is int) or int(version) < 2
	current_level = clampi(_migrate_level(int(level), old_format), 1, max_level)
	var best: Variant = data.get("highest_level", level)
	highest_level = (
		clampi(_migrate_level(int(best), old_format), current_level, max_level)
		if (best is float or best is int)
		else current_level
	)
	print("Save: resuming at level %d (highest %d)" % [current_level, highest_level])


## Save version 1 numbered the old five levels 1-5. Old level 1 was the hard
## board that is now level 4; a player there starts the new easy ramp instead.
func _migrate_level(level: int, old_format: bool) -> int:
	if not old_format or level <= 1:
		return level
	return level + LEVELS_ADDED_IN_V2


func _style_ui() -> void:
	hint_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	hint_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.07, 0.9))
	hint_label.add_theme_constant_override("outline_size", 14)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -110
	hint_label.offset_bottom = -30

	# Dots sit between the MWM Play home corner (top-left 232 px) and restart.
	level_dots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	level_dots.offset_left = -300
	level_dots.offset_right = 300
	level_dots.offset_top = 64
	level_dots.offset_bottom = 144
	level_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Restart: touch area runs to the top-right screen corner (rule 7).
	reset_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	reset_button.offset_left = -RESTART_HIT
	reset_button.offset_right = 0
	reset_button.offset_top = 0
	reset_button.offset_bottom = RESTART_HIT
	reset_button.disc_radius = 68.0
	reset_button.disc_center = Vector2(RESTART_HIT - 104.0, 104.0)

	next_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	next_button.offset_left = -NEXT_HIT * 0.5
	next_button.offset_right = NEXT_HIT * 0.5
	next_button.offset_top = -NEXT_HIT * 0.5
	next_button.offset_bottom = NEXT_HIT * 0.5
	next_button.disc_radius = NEXT_HIT * 0.5 - 20.0
