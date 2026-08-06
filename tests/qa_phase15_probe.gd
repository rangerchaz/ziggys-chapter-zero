## Phase 15 windowed QA probe. Needs a real GPU window, so run WITHOUT
## --headless: godot --path . res://tests/qa_phase15_probe.tscn
## Shoots the title screen's quit-confirm plate and the in-room pause
## menu (including its Settings sub-screen) for visual review.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const TitleScene := preload("res://scenes/ui/title_screen.tscn")

const OUT_DIR := "res://tests/artifacts/qa/phase15"

var _frames := 0
var _state := &"title_settle"
var _title: Control
var _room: Node3D
var _pause_menu: CanvasLayer


func _ready() -> void:
	# This probe triggers the real pause menu, which sets get_tree().paused
	# - without ALWAYS here the probe's own _process (driving the state
	# machine below) would freeze the instant the room pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	_title = TitleScene.instantiate()
	add_child(_title)


func _press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("saved %s" % name)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 90:
		return

	match _state:
		&"title_settle":
			_shot("01_title")
			_press_key(KEY_ESCAPE)
			_state = &"title_confirm_wait"
			_frames = 0
		&"title_confirm_wait":
			if _frames > 6:
				_shot("02_title_quit_confirm")
				_title.queue_free()
				_room = RoomScene.instantiate()
				add_child(_room)
				_state = &"room_settle"
				_frames = 0
		&"room_settle":
			# CSG build / shader compile stalls the first several dozen
			# frames regardless of pause - settle at a real framerate
			# first, same lesson as every earlier phase's windowed probe.
			if _frames > 100:
				_pause_menu = _room.get_node(^"PauseMenu")
				_press_key(KEY_ESCAPE)
				_state = &"pause_wait"
				_frames = 0
		&"pause_wait":
			if _frames > 6:
				_shot("03_pause_menu")
				_pause_menu.get_node(^"%SettingsButton").pressed.emit()
				_state = &"settings_wait"
				_frames = 0
		&"settings_wait":
			if _frames > 6:
				_shot("04_pause_settings")
				print("QA PHASE 15 PROBE DONE")
				get_tree().quit(0)
