## Phase 16 windowed performance probe. Needs a real GPU window at the
## acceptance criterion's target resolution, so run WITHOUT --headless:
##
##     godot --path . res://tests/perf_phase16_probe.tscn
##
## Spawns the real (post-bake) room at 1920x1080 windowed, teleports the
## real player + its SpringArm3D/Camera3D rig through a tour of waypoints
## covering the whole room (door, bar, booths, oven, jukebox, table,
## window), and samples Engine.get_frames_per_second() at each stop after
## letting the view settle. Prints a per-waypoint and overall min/avg/max
## report to stdout for PERFORMANCE.md. Exits 0 once the tour completes
## (this is a measurement tool, not a pass/fail gate - the acceptance bar
## is judged from the numbers it prints).
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

## label -> [player position, look-at target]
const WAYPOINTS := [
	["door", Vector3(5.6, 0, 3.5), Vector3(0, 1, -1)],
	["bar", Vector3(0.5, 0, -1.8), Vector3(0, 1, -3.6)],
	["booths", Vector3(-4.5, 0, 0.5), Vector3(-6, 1, 0.5)],
	["oven", Vector3(-4.2, 0, -2.8), Vector3(-5.5, 1.5, -3.8)],
	["jukebox", Vector3(5.5, 0, 2.3), Vector3(6.7, 1, 2.5)],
	["table_center", Vector3(2.2, 0, 0.4), Vector3(2.2, 1, 1.4)],
	["window", Vector3(-1.1, 0, 3.5), Vector3(-1.1, 1.8, 5.1)],
	["room_wide", Vector3(0, 0, 0), Vector3(-1, 1, -3.6)],
]
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 40

var _frames := 0
var _room: Node3D
var _player: CharacterBody3D
var _wp_index := 0
var _stage_frame := 0
var _samples: Array[float] = []
var _all_samples: Array[float] = []
var _per_waypoint: Array[Dictionary] = []
var _started := false


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)


func _process(_delta: float) -> void:
	_frames += 1
	# CSG (now baked mesh) build / shader compile stalls the first several
	# dozen frames - settle at a real framerate before sampling anything.
	if _frames < 120:
		return

	if not _started:
		for child in _room.get_children():
			if child is MeckiePlayerController:
				_player = child
		if _player == null:
			printerr("PERF PHASE 16 PROBE FAIL: player not found")
			get_tree().quit(1)
			return
		_started = true
		_stage_frame = 0
		return

	if _wp_index >= WAYPOINTS.size():
		_report()
		return

	var wp: Array = WAYPOINTS[_wp_index]
	_stage_frame += 1

	if _stage_frame == 1:
		_player.velocity = Vector3.ZERO
		_player.global_position = wp[1]
		_player.get_node(^"CameraRig").global_position = wp[1] + Vector3(0, 1.35, 0)
		var to_target: Vector3 = (wp[2] - (wp[1] + Vector3(0, 1.35, 0)))
		_player.get_node(^"CameraRig").rotation = Vector3(
				clampf(-asin(to_target.normalized().y), -1.1, 0.45),
				atan2(-to_target.x, -to_target.z), 0)
		return

	if _stage_frame <= SETTLE_FRAMES:
		return

	if _stage_frame <= SETTLE_FRAMES + SAMPLE_FRAMES:
		var fps := Engine.get_frames_per_second()
		_samples.append(fps)
		_all_samples.append(fps)
		return

	# Waypoint done: record its stats and move to the next.
	var mn: float = _samples.min()
	var mx: float = _samples.max()
	var avg: float = 0.0
	for s in _samples:
		avg += s
	avg /= _samples.size()
	_per_waypoint.append({"label": wp[0], "min": mn, "avg": avg, "max": mx})
	print("%s: min %.1f  avg %.1f  max %.1f fps" % [wp[0], mn, avg, mx])
	_samples.clear()
	_wp_index += 1
	_stage_frame = 0


func _report() -> void:
	var mn: float = _all_samples.min()
	var mx: float = _all_samples.max()
	var avg: float = 0.0
	for s in _all_samples:
		avg += s
	avg /= _all_samples.size()
	print("---")
	print("OVERALL: min %.1f  avg %.1f  max %.1f fps over %d samples at 1920x1080 windowed" \
			% [mn, avg, mx, _all_samples.size()])
	print("PERF PHASE 16 PROBE DONE")
	get_tree().quit(0)
