## Phase 9 QA-only capture (not a deliverable test - just screenshots for
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase9_probe.tscn
##
## Spawns the room with Droid as the player, walks up to Caroline to shoot
## the interact prompt, opens her dialogue to shoot the dialogue panel,
## advances to shoot the closed state, then walks up to the overlapping
## Chad/Oleg pair to shoot the "nearest of two" prompt. Saves to
## tests/artifacts/qa/phase9/. Exits 0 once everything is written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase9"

var _frames := 0
var _room: Node3D
var _player: CharacterBody3D
var _cam: Camera3D
var _caroline: NpcHuman
var _chad: NpcHuman
var _oleg: NpcHuman


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)
	_cam = Camera3D.new()
	_cam.fov = 65.0
	add_child(_cam)


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		20:
			for child in _room.get_children():
				if child is MeckiePlayerController:
					_player = child
			for raw in get_tree().get_nodes_in_group(&"npcs"):
				if raw.npc_id == &"caroline":
					_caroline = raw
				elif raw.npc_id == &"chad":
					_chad = raw
				elif raw.npc_id == &"oleg":
					_oleg = raw
			if _player == null or _caroline == null or _chad == null or _oleg == null:
				printerr("QA PHASE 9 PROBE FAIL: player or NPCs not found")
				get_tree().quit(1)
				return
			# Stand Droid next to Caroline, camera framing both for context.
			_player.global_position = _caroline.global_position + Vector3(0, 0, 0.8)
			_player.velocity = Vector3.ZERO
			_cam.global_position = _caroline.global_position + Vector3(1.6, 1.7, 2.2)
			_cam.look_at(_caroline.global_position + Vector3(0, 1.0, 0), Vector3.UP)
			_cam.current = true
		40:
			_shot("prompt_near_caroline.png")
			var esc := InputEventKey.new()
			esc.keycode = KEY_E
			esc.physical_keycode = KEY_E
			esc.pressed = true
			Input.parse_input_event(esc)
			var esc_up := InputEventKey.new()
			esc_up.keycode = KEY_E
			esc_up.physical_keycode = KEY_E
			esc_up.pressed = false
			Input.parse_input_event(esc_up)
		55:
			_shot("dialogue_open_caroline.png")
		56:
			var e2 := InputEventKey.new()
			e2.keycode = KEY_E
			e2.physical_keycode = KEY_E
			e2.pressed = true
			Input.parse_input_event(e2)
			var e2_up := InputEventKey.new()
			e2_up.keycode = KEY_E
			e2_up.physical_keycode = KEY_E
			e2_up.pressed = false
			Input.parse_input_event(e2_up)
		70:
			_shot("dialogue_closed_after_advance.png")
			# Chad and Oleg overlap; park Droid closer to Chad.
			_player.global_position = _chad.global_position + Vector3(0.3, 0, 0)
			_player.velocity = Vector3.ZERO
			_cam.global_position = _chad.global_position + Vector3(0.5, 2.0, 2.6)
			_cam.look_at((_chad.global_position + _oleg.global_position) * 0.5 + Vector3(0, 1.0, 0), Vector3.UP)
		90:
			_shot("prompt_nearest_of_overlap_chad.png")
			print("QA PHASE 9 PROBE DONE")
			get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
