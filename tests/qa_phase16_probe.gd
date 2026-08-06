## Phase 16 windowed QA capture (not a deliverable test - just screenshots
## for visual review of the baked room). Needs a real GPU window at the
## acceptance criterion's target resolution, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase16_probe.tscn
##
## Walks the real (now baked-mesh) room through: the pre-brownout
## two-temperature establishing shot, the real F9 brownout's mid-fade and
## full-brownout frames, an NPC dialogue frame, and (via the real F10
## closing-time debug key) the four-option closing decision prompt. Saves
## to res://.turkey/screenshots/phase-16/ per the phase spec. Exits 0 once
## everything is written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://.turkey/screenshots/phase-16"

var _frames := 0
var _elapsed := 0.0
var _fired_at := -1.0
var _room: Node3D
var _bd: Node
var _player: CharacterBody3D
var _caroline: NpcHuman
var _cam: Camera3D
var _state := &"settle"
var _wait_start := 0.0
var _ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)
	_bd = _room.get_node(^"BrownoutDirector")
	# Same establishing framing ziggys_room.tscn's own default Camera3D
	# uses, on a free camera so the player can be moved for later shots
	# without disturbing this view.
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	_cam.global_transform = Transform3D(
			Vector3(-0.95906, -0.057131, 0.27739),
			Vector3(0, 0.979453, 0.20174),
			Vector3(-0.28321, 0.193481, -0.93935),
			Vector3(1.9, 2.5, -4.45))


func _process(delta: float) -> void:
	_frames += 1

	# CSG (now baked mesh) build / shader compile stalls the first several
	# dozen frames regardless of the beat - settle at a real framerate
	# first, same lesson as every earlier phase's windowed probe.
	if _frames < 90:
		return

	if _state == &"settle":
		for child in _room.get_children():
			if child is MeckiePlayerController:
				_player = child
		for raw in get_tree().get_nodes_in_group(&"npcs"):
			if raw.npc_id == &"caroline":
				_caroline = raw
		if _player == null or _caroline == null:
			printerr("QA PHASE 16 PROBE FAIL: player or Caroline not found")
			get_tree().quit(1)
			return
		# Out of frame for the establishing/brownout shots.
		_player.global_position = Vector3(0, 6, 0)
		_player.velocity = Vector3.ZERO
		_cam.current = true
		_shot("pre_brownout_two_temperature.png")
		_press_key(KEY_F9)
		_fired_at = 0.0
		_state = &"brownout"
		return

	if _state == &"brownout":
		_fired_at += delta
		if _fired_at >= _bd.fade_duration * 0.5 and _fired_at - delta < _bd.fade_duration * 0.5:
			_shot("mid_fade.png")
		if _fired_at >= _bd.fade_duration + 0.3 and _fired_at - delta < _bd.fade_duration + 0.3:
			_shot("full_brownout.png")
		if _fired_at >= _bd.fade_duration + _bd.effect_hold + _bd.effect_release + 0.3:
			_state = &"approach_npc"
			_wait_start = _frames
		return

	if _state == &"approach_npc":
		if _frames - _wait_start >= 10:
			_player.global_position = _caroline.global_position + Vector3(0, 0, 0.8)
			_player.velocity = Vector3.ZERO
			_cam.global_position = _caroline.global_position + Vector3(1.6, 1.7, 2.2)
			_cam.look_at(_caroline.global_position + Vector3(0, 1.0, 0), Vector3.UP)
			_state = &"wait_prox"
			_wait_start = _frames
		return

	if _state == &"wait_prox":
		if _frames - _wait_start >= 20:
			_press_key(KEY_E)
			_state = &"wait_dialogue"
			_wait_start = _frames
		return

	if _state == &"wait_dialogue":
		if _frames - _wait_start >= 20:
			var dialogue: Control = _room.get_node(^"UI/DialogueUI")
			if not dialogue.visible:
				printerr("QA PHASE 16 PROBE FAIL: dialogue never opened for Caroline")
				_ok = false
			_shot("npc_dialogue.png")
			_press_key(KEY_ESCAPE)
			_state = &"wait_dialogue_closed"
			_wait_start = _frames
		return

	if _state == &"wait_dialogue_closed":
		if _frames - _wait_start >= 15:
			_press_key(KEY_F10)
			_state = &"wait_closing_time"
			_wait_start = _frames
		return

	if _state == &"wait_closing_time":
		if _frames - _wait_start >= 20:
			var gs: Node = get_node(^"/root/GameState")
			if not gs.closing_time_reached:
				printerr("QA PHASE 16 PROBE FAIL: closing_time_reached never flipped after F10")
				_ok = false
				_report()
				return
			_player.global_position = _caroline.global_position + Vector3(0, 0, 0.8)
			_player.velocity = Vector3.ZERO
			_state = &"wait_closing_prox"
			_wait_start = _frames
		return

	if _state == &"wait_closing_prox":
		if _frames - _wait_start >= 20:
			_press_key(KEY_E)
			_state = &"wait_closing_question"
			_wait_start = _frames
		return

	if _state == &"wait_closing_question":
		if _frames - _wait_start >= 15:
			_press_key(KEY_E)
			_state = &"wait_choices"
			_wait_start = _frames
		return

	if _state == &"wait_choices":
		if _frames - _wait_start >= 15:
			var dialogue: Control = _room.get_node(^"UI/DialogueUI")
			var container: VBoxContainer = dialogue.get_node(^"%ChoicesContainer")
			if not container.visible or container.get_child_count() != 4:
				printerr("QA PHASE 16 PROBE FAIL: four-option prompt did not appear")
				_ok = false
				_report()
				return
			_shot("four_option_decision.png")
			_report()
		return


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


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false
	else:
		var warm := 0
		var total := 0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				var c := image.get_pixel(x, y)
				total += 1
				if c.r > 0.22 and c.r > c.b * 1.5:
					warm += 1
		print("saved %s (current cam: %s, brownout_fired: %s, warm px: %.2f%%)" % [
				file_name, get_viewport().get_camera_3d(),
				get_node(^"/root/GameState").brownout_fired, 100.0 * warm / total])


func _report() -> void:
	if _ok:
		print("QA PHASE 16 PROBE DONE")
		get_tree().quit(0)
	else:
		printerr("QA PHASE 16 PROBE FAIL")
		get_tree().quit(1)
