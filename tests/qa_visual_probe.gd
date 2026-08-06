## Phase 3 QA visual probe. Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_visual_probe.tscn
##
## Loads the assembled room and sweeps a set of fixed camera waypoints,
## saving one screenshot per waypoint to tests/artifacts/qa/ so a
## fresh-context reviewer can evaluate the CSG set and props.
## Exits 0 when all screenshots are written, 1 otherwise.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

# name, camera origin, look-at target
var _waypoints := [
	["overview_from_door", Vector3(5.0, 2.0, 3.6), Vector3(-2.0, 1.3, -3.0)],
	["bar_and_stools", Vector3(0.5, 1.5, -0.8), Vector3(0.5, 0.9, -3.4)],
	["booths_west", Vector3(-3.2, 1.6, 1.0), Vector3(-6.0, 0.9, 0.5)],
	["jukebox_east", Vector3(4.6, 1.5, 2.0), Vector3(6.7, 1.1, 2.5)],
	["pizza_oven", Vector3(-3.0, 1.6, -3.0), Vector3(-5.5, 1.2, -3.8)],
	["window_and_street", Vector3(2.5, 1.7, 0.2), Vector3(-3.5, 0.6, 8.0)],
	["street_from_outside", Vector3(0.0, 1.8, 8.0), Vector3(-1.1, 1.6, -1.0)],
	["street_sidewalk_check", Vector3(-2.0, 1.5, 6.5), Vector3(-1.1, 1.3, 3.0)],
	["neon_sign_ceiling", Vector3(-1.0, 1.2, 3.5), Vector3(-1.1, 2.6, 4.9)],
	["tables_center", Vector3(1.0, 1.6, -0.5), Vector3(2.2, 0.8, 1.4)],
	["plan_view", Vector3(0.02, 3.0, 0.0), Vector3(0.0, 0.0, -0.01)],
]

var _camera: Camera3D
var _index := -1
var _wait_frames := 0
var _all_ok := true


func _ready() -> void:
	var room := RoomScene.instantiate()
	# Phase 5 spawns a player whose camera would steal the waypoint sweep.
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	add_child(_camera)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/qa")
	_advance()


func _advance() -> void:
	_index += 1
	if _index >= _waypoints.size():
		print("QA VISUAL PROBE %s (%d/%d screenshots saved)" % [
			"PASS" if _all_ok else "FAIL", _index, _waypoints.size()
		])
		get_tree().quit(0 if _all_ok else 1)
		return
	var wp: Array = _waypoints[_index]
	_camera.global_transform = Transform3D.IDENTITY.looking_at(
		(wp[2] as Vector3) - (wp[1] as Vector3), Vector3.UP
	)
	_camera.global_position = wp[1]
	_camera.look_at(wp[2] as Vector3, Vector3.UP)
	_wait_frames = 0


func _process(_delta: float) -> void:
	if _index < 0 or _index >= _waypoints.size():
		return
	_wait_frames += 1
	if _wait_frames < 20:
		return
	var wp: Array = _waypoints[_index]
	var image := get_viewport().get_texture().get_image()
	var path := "res://tests/artifacts/qa/%s.png" % wp[0]
	var err := image.save_png(path)
	if err != OK:
		printerr("QA VISUAL PROBE FAIL (save_png error %d for %s)" % [err, wp[0]])
		_all_ok = false
	_advance()
