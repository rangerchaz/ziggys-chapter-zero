## Phase 12 windowed QA probe. Needs a real GPU window, so run WITHOUT
## --headless:
##
##     godot --path . res://tests/qa_phase12_probe.tscn
##
## Shoots one NPC's dialogue pre-beat, fires the real brownout beat via the
## actual F9 debug path (same as qa_phase11_probe), waits for the dark
## window, then walks the player up to four NPCs spanning distinct room
## roles (bar, card table, jukebox, booth) and opens each one's real
## dialogue via the InteractionManager/DialogueUI path to shoot its
## post-brownout reaction line on screen, alongside that NPC's dimmed
## FaceLight in the darkened room. Saves to tests/artifacts/qa/phase12/.
## Exits 0 once everything is written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase12"

# Spread across room roles: bar/kitchen, card table, jukebox, booth.
const TOUR: Array[StringName] = [&"caroline", &"oleg", &"grant", &"tonya"]

var _frames := 0
var _elapsed := 0.0
var _fired_at := -1.0
var _room: Node3D
var _bd: Node
var _player: CharacterBody3D
var _cam: Camera3D
var _npcs: Dictionary = {}
var _tour_index := 0
var _state := &"settle"
var _wait_start := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)
	_bd = _room.get_node(^"BrownoutDirector")
	_cam = Camera3D.new()
	_cam.fov = 65.0
	add_child(_cam)


func _process(delta: float) -> void:
	_frames += 1

	# CSG build / shader compile stalls the first several dozen frames
	# regardless of the beat - settle at a real framerate before trusting
	# any screenshot or timing (same lesson as Phase 10/11's probes).
	if _frames < 90:
		return

	if _state == &"settle":
		for child in _room.get_children():
			if child is MeckiePlayerController:
				_player = child
		for raw in get_tree().get_nodes_in_group(&"npcs"):
			_npcs[raw.npc_id] = raw
		if _player == null or _npcs.size() != 10:
			printerr("QA PHASE 12 PROBE FAIL: player or NPCs not found")
			get_tree().quit(1)
			return
		_frame_on(TOUR[0])
		_state = &"wait_prox_pre_beat"
		_wait_start = _frames
		return

	if _state == &"wait_prox_pre_beat":
		if _frames - _wait_start >= 20:
			_shot("before_beat_caroline_prompt.png")
			_press_key(KEY_E)
			_state = &"pre_beat_dialogue"
			_wait_start = _frames
		return

	if _state == &"pre_beat_dialogue":
		if _frames - _wait_start >= 15:
			_shot("before_beat_caroline_dialogue_open.png")
			_press_key(KEY_E)
			_state = &"close_pre_beat"
			_wait_start = _frames
		return

	if _state == &"close_pre_beat":
		if _frames - _wait_start >= 10:
			_press_key(KEY_F9)
			_fired_at = 0.0
			_state = &"firing"
		return

	if _state == &"firing":
		_fired_at += delta
		if _fired_at >= _bd.fade_duration + 0.3:
			_shot("after_beat_room_dark.png")
			_tour_index = 0
			_advance_tour()
		return

	if _state == &"wait_prox_tour":
		if _frames - _wait_start >= 20:
			_press_key(KEY_E)
			_state = &"tour_wait_open"
			_wait_start = _frames
		return

	if _state == &"tour_wait_open":
		if _frames - _wait_start >= 15:
			var npc_id: StringName = TOUR[_tour_index]
			_shot("post_brownout_%s_dialogue.png" % npc_id)
			_press_key(KEY_E)
			_state = &"tour_wait_close"
			_wait_start = _frames
		return

	if _state == &"tour_wait_close":
		if _frames - _wait_start >= 10:
			_tour_index += 1
			_advance_tour()
		return


func _advance_tour() -> void:
	if _tour_index >= TOUR.size():
		print("QA PHASE 12 PROBE DONE")
		get_tree().quit(0)
		return
	var npc_id: StringName = TOUR[_tour_index]
	_frame_on(npc_id)
	_state = &"wait_prox_tour"
	_wait_start = _frames


func _frame_on(npc_id: StringName) -> void:
	var npc: NpcHuman = _npcs[npc_id]
	_player.global_position = npc.global_position + Vector3(0, 0, 0.8)
	_player.velocity = Vector3.ZERO
	_cam.global_position = npc.global_position + Vector3(1.6, 1.7, 2.2)
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
	else:
		print("saved " + file_name)
