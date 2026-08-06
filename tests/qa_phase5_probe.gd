## Phase 5 QA-only capture (not a deliverable test - just screenshots for the
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase5_probe.tscn
##
## Spawns Sid (the one signature color meckie_render_probe.gd doesn't already
## cover). Reuses the spawned Meckie's own CameraRig (SpringArm3D + Camera3D,
## already proven correct by meckie_render_probe.gd) for a close third-person
## read, plus a separate fixed external camera at the known Sid spawn-marker
## coordinates (scenes/room/ziggys_room.tscn) for a wide room-context shot.
## Saves to tests/artifacts/qa/. Exits 0 once both are written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const SID_MARKER := Vector3(-4.2, 0, -2.8)

var _frames := 0
var _player: CharacterBody3D
var _rig: SpringArm3D
var _wide_cam: Camera3D


func _ready() -> void:
	var room := RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	_player = room.get_node(^"PlayerSpawner").spawn(&"sid")
	_wide_cam = Camera3D.new()
	_wide_cam.fov = 70.0
	add_child(_wide_cam)
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/qa")


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		5:
			_rig = _player.get_node(^"CameraRig")
			# Wide shot: fixed external camera near the spawn marker,
			# looking back at the character, room context visible - same
			# style as tests/qa_visual_probe.gd's waypoint shots.
			_wide_cam.global_position = SID_MARKER + Vector3(3.0, 2.0, 2.6)
			_wide_cam.look_at(SID_MARKER + Vector3(0, 0.9, 0), Vector3.UP)
			_wide_cam.current = true
		20:
			_shot("meckie_sid_spawn_overview.png")
			# Close third-person read via the character's own SpringArm3D
			# rig, posed the same way meckie_render_probe.gd poses Droid/Eva.
			_player.global_position = SID_MARKER + Vector3(0, 0.05, 0)
			_player.velocity = Vector3.ZERO
			_player.rotation.y = PI
			_rig.global_position = _player.global_position + Vector3(0, 1.35, 0)
			_rig.rotation = Vector3(-0.3, 0, 0)
			_player.get_node(^"CameraRig/Camera3D").make_current()
		40:
			_shot("meckie_sid_closeup.png")
			print("QA PHASE 5 PROBE DONE")
			get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("res://tests/artifacts/qa/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
