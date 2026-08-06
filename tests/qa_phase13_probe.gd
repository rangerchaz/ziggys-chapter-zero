## Phase 13 windowed QA probe. Needs a real GPU window, so run WITHOUT
## --headless:
##
##     godot --path . res://tests/qa_phase13_probe.tscn
##
## Walks the real room through the whole closing-time flow end to end:
## presses the real debug_closing_time (F10) key to jump straight there
## (firing the brownout on the way, same as a fresh room would need),
## shoots the room-wide "last call" cue banner, walks Droid up to Caroline
## to shoot her special closing-time interact prompt, opens her real
## dialogue via the actual InteractionManager/DialogueUI path to shoot the
## closing question, advances to shoot the four-option decision prompt
## (proving all four buttons render distinct and readable, with the first
## one visibly focus-highlighted), selects one via the real ui_accept key
## (keyboard path, not a synthetic signal emit) to shoot the acknowledgement
## line, then advances once more to shoot the cue banner gone and
## GameState.closing_decision recorded. Saves to
## tests/artifacts/qa/phase13/. Exits 0 once everything is written and the
## decision landed.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase13"

var _frames := 0
var _room: Node3D
var _player: CharacterBody3D
var _cam: Camera3D
var _caroline: NpcHuman
var _state := &"settle"
var _wait_start := 0.0
var _ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)
	_cam = Camera3D.new()
	_cam.fov = 65.0
	add_child(_cam)


func _process(_delta: float) -> void:
	_frames += 1

	# CSG build / shader compile stalls the first several dozen frames
	# regardless of the beat - settle at a real framerate first (same
	# lesson as every earlier phase's windowed probe).
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
			printerr("QA PHASE 13 PROBE FAIL: player or Caroline not found")
			get_tree().quit(1)
			return
		_press_key(KEY_F10)
		_state = &"wait_closing_time"
		_wait_start = _frames
		return

	if _state == &"wait_closing_time":
		# The debug key also fires the real brownout beat, so give its fade
		# + effect sequence room to finish before trusting the screenshot.
		var bd: Node = _room.get_node(^"BrownoutDirector")
		if _frames - _wait_start >= int((bd.fade_duration + bd.effect_hold + bd.effect_release + 1.0) * 60):
			var gs: Node = get_node(^"/root/GameState")
			if not gs.closing_time_reached:
				printerr("QA PHASE 13 PROBE FAIL: closing_time_reached never flipped after F10")
				get_tree().quit(1)
				return
			_frame_on(_caroline, Vector3(0, 0, 3.2))
			_shot("closing_cue_banner.png")
			_state = &"wait_prox"
			_wait_start = _frames
		return

	if _state == &"wait_prox":
		if _frames - _wait_start >= 20:
			_frame_on(_caroline, Vector3(0, 0, 0.8))
			_state = &"wait_prompt"
			_wait_start = _frames
		return

	if _state == &"wait_prompt":
		if _frames - _wait_start >= 20:
			_shot("caroline_closing_prompt.png")
			_press_key(KEY_E)
			_state = &"wait_question"
			_wait_start = _frames
		return

	if _state == &"wait_question":
		if _frames - _wait_start >= 15:
			_shot("closing_question.png")
			_press_key(KEY_E)
			_state = &"wait_choices"
			_wait_start = _frames
		return

	if _state == &"wait_choices":
		if _frames - _wait_start >= 15:
			var dialogue: Control = _room.get_node(^"UI/DialogueUI")
			var container: VBoxContainer = dialogue.get_node(^"%ChoicesContainer")
			if not container.visible or container.get_child_count() != 4:
				printerr("QA PHASE 13 PROBE FAIL: four-option prompt did not appear")
				get_tree().quit(1)
				return
			_shot("four_option_decision.png")
			# Real keyboard path: ui_accept activates the focused button,
			# same as a controller/keyboard player would select an answer.
			_press_key(KEY_ENTER)
			_state = &"wait_ack"
			_wait_start = _frames
		return

	if _state == &"wait_ack":
		if _frames - _wait_start >= 15:
			var gs: Node = get_node(^"/root/GameState")
			if gs.closing_decision == gs.NONE:
				printerr("QA PHASE 13 PROBE FAIL: GameState.closing_decision still NONE after selecting")
				get_tree().quit(1)
				return
			print("closing_decision recorded: %s" % gs.closing_decision)
			_shot("closing_acknowledgement.png")
			_press_key(KEY_E)
			_state = &"wait_done"
			_wait_start = _frames
		return

	if _state == &"wait_done":
		if _frames - _wait_start >= 15:
			_shot("chapter_end_cue_gone.png")
			_report()
		return


func _frame_on(npc: NpcHuman, offset: Vector3) -> void:
	_player.global_position = npc.global_position + offset
	_player.velocity = Vector3.ZERO
	_cam.global_position = npc.global_position + Vector3(1.6, 1.7, 2.4)
	_cam.look_at(npc.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	_cam.current = true


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
		print("saved " + file_name)


func _report() -> void:
	if _ok:
		print("QA PHASE 13 PROBE DONE")
		get_tree().quit(0)
	else:
		printerr("QA PHASE 13 PROBE FAIL")
		get_tree().quit(1)
