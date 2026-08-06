## Phase 7 QA-only capture (not a deliverable test - just screenshots for
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_npc_probe.tscn
##
## Loads the full room with all ten regulars in place and shoots the bar
## line (Caroline behind the counter, four standing patrons), the booth
## row (four seated patrons), and the table/jukebox corner (Grant), plus
## one wide overview, so the poses/silhouettes/face lighting can be
## reviewed without opening the editor. Saves to tests/artifacts/qa/phase7/.
## Exits 0 once everything is written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase7"

var _room: Node3D
var _cam: Camera3D
var _frames := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	_room = RoomScene.instantiate()
	_room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(_room)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		20:
			_cam.global_position = Vector3(5.6, 3.3, 5.0)
			_cam.look_at(Vector3(-1, 1.1, -1.5), Vector3.UP)
		35:
			_shot("room_overview_all_npcs.png")
			# Bar line: Caroline behind the counter, four patrons around it.
			_cam.global_position = Vector3(1, 1.85, 0.4)
			_cam.look_at(Vector3(1, 1.5, -3.4), Vector3.UP)
		55:
			_shot("bar_line_caroline_and_patrons.png")
			_cam.global_position = Vector3(3.6, 1.7, -3.7)
			_cam.look_at(Vector3(2.5, 1.55, -4.2), Vector3.UP)
		75:
			_shot("caroline_behind_bar_closeup.png")
			# Booth row: four seated patrons.
			_cam.global_position = Vector3(-2.6, 1.7, 0.6)
			_cam.look_at(Vector3(-4.5, 1.4, 0.5), Vector3.UP)
		95:
			_shot("booth_row_seated_patrons.png")
			_cam.global_position = Vector3(-3.6, 1.5, -1.6)
			_cam.look_at(Vector3(-4.5, 1.35, -0.9), Vector3.UP)
		115:
			_shot("booth_closeup_conner_nick.png")
			# Table / jukebox corner: Grant standing.
			_cam.global_position = Vector3(4.6, 1.6, 1.7)
			_cam.look_at(Vector3(3.2, 1.4, 1.4), Vector3.UP)
		135:
			_shot("table_jukebox_grant.png")
			print("QA NPC PROBE DONE")
			get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
