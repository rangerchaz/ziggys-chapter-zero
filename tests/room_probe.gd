## Phase 3 room probe, runnable headless:
##
##     godot --headless --path . res://tests/room_probe.tscn
##
## Loads the assembled bar interior and verifies with real physics queries:
## every prop is an instanced scene, the marker set exists with distinct
## transforms, walls/glass/bar/booths/oven/floor are solid, capsule motion
## into them is blocked, and every NPC slot is reachable on foot from the
## player spawn (grid flood fill with a standing capsule). Exits 0 on pass,
## 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

const PROP_SCENES: Array[String] = [
	"res://scenes/props/bar_counter.tscn",
	"res://scenes/props/bar_stool.tscn",
	"res://scenes/props/booth.tscn",
	"res://scenes/props/pizza_oven.tscn",
	"res://scenes/props/jukebox.tscn",
	"res://scenes/props/neon_sign.tscn",
	"res://scenes/props/pendant_lamp.tscn",
	"res://scenes/props/table.tscn",
]

const CELL := 0.2
const X_MIN := -6.9
const X_MAX := 6.9
const Z_MIN := -4.9
const Z_MAX := 4.9
const CAPSULE_RADIUS := 0.28
const CAPSULE_HEIGHT := 1.5
const CAPSULE_Y := 0.85
## How far an NPC slot marker may sit from the nearest reachable floor cell
## and still count as reachable (slots hug the furniture they belong to).
const MARKER_SNAP := 0.55

## Rays from open air that must hit solid collision (label -> [from, to]).
## CSG collision is a concave trimesh (hollow to interior overlap queries),
## so solidity is asserted by hitting each surface from outside.
const SOLID_RAYS := {
	"floor": [Vector3(0, 0.5, 0.5), Vector3(0, -0.5, 0.5)],
	"ceiling": [Vector3(0, 2.5, 0), Vector3(0, 3.6, 0)],
	"back wall": [Vector3(0, 1.2, -4), Vector3(0, 1.2, -5.5)],
	"west wall": [Vector3(-6, 1, 3.8), Vector3(-7.5, 1, 3.8)],
	"east wall": [Vector3(6, 1, 0), Vector3(7.5, 1, 0)],
	"front wall pier": [Vector3(6.7, 1, 4), Vector3(6.7, 1, 5.5)],
	"window glass": [Vector3(-1.1, 1.8, 4), Vector3(-1.1, 1.8, 5.5)],
	"bar counter": [Vector3(1, 0.8, -2.5), Vector3(1, 0.8, -3.6)],
	"booth 1 bench": [Vector3(-6.75, 0.3, 0.5), Vector3(-6.75, 0.3, -0.6)],
	"booth 2 bench": [Vector3(-6.75, 0.3, 3.3), Vector3(-6.75, 0.3, 2)],
	"pizza oven": [Vector3(-5.5, 0.7, -2), Vector3(-5.5, 0.7, -3.8)],
	"jukebox": [Vector3(5.5, 0.8, 2.5), Vector3(7, 0.8, 2.5)],
	"bar stool": [Vector3(-1, 0.73, -2), Vector3(-1, 0.73, -2.85)],
	"table": [Vector3(2.2, 0.74, 0.5), Vector3(2.2, 0.74, 1.4)],
}

## Capsule sweeps that must be stopped by collision: [from, motion].
const BLOCKED_SWEEPS := {
	"front window": [Vector3(0, 0.9, 3.5), Vector3(0, 0, 3)],
	"bar counter": [Vector3(1, 0.9, -2), Vector3(0, 0, -2.5)],
	"booth 1": [Vector3(-3, 0.9, -0.6), Vector3(-3.5, 0, 0)],
	"pizza oven": [Vector3(-5.5, 0.9, -1.8), Vector3(0, 0, -2.5)],
	"west wall": [Vector3(-5.5, 0.9, 3.8), Vector3(-3, 0, 0)],
	"floor": [Vector3(0, 0.95, 0.5), Vector3(0, -1.5, 0)],
}

var _failures: Array[String] = []
var _room: Node3D
var _frames := 0
var _done := false


func _ready() -> void:
	_room = RoomScene.instantiate()
	add_child(_room)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	# CSG shapes build their meshes and collision bodies over the first
	# frames after entering the tree; give them time before querying.
	if _frames < 12:
		return
	_done = true
	_check_structure()
	_check_markers()
	_check_solids()
	_check_blocked_sweeps()
	_check_reachability()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _all_descendants(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		out.append(child)
		_all_descendants(child, out)


func _check_structure() -> void:
	var nodes: Array[Node] = []
	_all_descendants(_room, nodes)
	for path in PROP_SCENES:
		var found := false
		for node in nodes:
			if node.scene_file_path == path:
				found = true
				break
		if not found:
			_fail("Room has no instance of %s" % path)

	if _room.get_node_or_null("Shell") == null or \
			_room.get_node("Shell").scene_file_path != "res://scenes/room/ziggys_shell.tscn":
		_fail("Room shell is not an instance of ziggys_shell.tscn")


func _check_markers() -> void:
	var slots := _room.get_node_or_null("Markers/NpcSlots")
	if slots == null:
		_fail("Markers/NpcSlots is missing")
		return
	if slots.get_child_count() != 10:
		_fail("Expected 10 NPC slots, found %d" % slots.get_child_count())

	var spawns := _room.get_node_or_null("Markers/MeckieSpawns")
	if spawns == null:
		_fail("Markers/MeckieSpawns is missing")
		return
	if spawns.get_child_count() != 3:
		_fail("Expected 3 Meckie spawns, found %d" % spawns.get_child_count())

	if _room.get_node_or_null("Markers/PlayerSpawn") == null:
		_fail("Markers/PlayerSpawn is missing")
		return

	var markers: Array[Node] = []
	markers.append_array(slots.get_children())
	markers.append_array(spawns.get_children())
	markers.append(_room.get_node("Markers/PlayerSpawn"))
	for i in markers.size():
		if markers[i] is not Marker3D:
			_fail("%s is not a Marker3D" % markers[i].name)
		for j in range(i + 1, markers.size()):
			var a: Vector3 = markers[i].global_position
			var b: Vector3 = markers[j].global_position
			if a.distance_to(b) < 0.01:
				_fail("Markers %s and %s share a transform" % [markers[i].name, markers[j].name])


func _capsule() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	return shape


func _space() -> PhysicsDirectSpaceState3D:
	return _room.get_world_3d().direct_space_state


func _check_solids() -> void:
	for label: String in SOLID_RAYS:
		var ray := PhysicsRayQueryParameters3D.create(SOLID_RAYS[label][0], SOLID_RAYS[label][1])
		if _space().intersect_ray(ray).is_empty():
			_fail("No collision surface on the %s" % label)

	# The open floor by the door must NOT be solid, or the grid is useless.
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _capsule()
	params.transform = Transform3D(Basis.IDENTITY, Vector3(5.6, CAPSULE_Y, 4))
	if not _space().intersect_shape(params, 1).is_empty():
		_fail("Player spawn is obstructed")


func _check_blocked_sweeps() -> void:
	for label: String in BLOCKED_SWEEPS:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _capsule()
		params.transform = Transform3D(Basis.IDENTITY, BLOCKED_SWEEPS[label][0])
		params.motion = BLOCKED_SWEEPS[label][1]
		var result := _space().cast_motion(params)
		if result[0] >= 0.999:
			_fail("Capsule swept through the %s unblocked" % label)


func _check_reachability() -> void:
	var cols := int(round((X_MAX - X_MIN) / CELL)) + 1
	var rows := int(round((Z_MAX - Z_MIN) / CELL)) + 1
	var shape := _capsule()

	var walkable: Array[bool] = []
	walkable.resize(cols * rows)
	for zi in rows:
		for xi in cols:
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(Basis.IDENTITY,
				Vector3(X_MIN + xi * CELL, CAPSULE_Y, Z_MIN + zi * CELL))
			walkable[zi * cols + xi] = _space().intersect_shape(params, 1).is_empty()

	# Flood fill from the player spawn.
	var spawn: Vector3 = _room.get_node("Markers/PlayerSpawn").global_position
	var start_x := clampi(int(round((spawn.x - X_MIN) / CELL)), 0, cols - 1)
	var start_z := clampi(int(round((spawn.z - Z_MIN) / CELL)), 0, rows - 1)
	if not walkable[start_z * cols + start_x]:
		_fail("Player spawn cell is not walkable")
		return

	var reached: Array[bool] = []
	reached.resize(cols * rows)
	var queue: Array[Vector2i] = [Vector2i(start_x, start_z)]
	reached[start_z * cols + start_x] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.x >= cols or next.y < 0 or next.y >= rows:
				continue
			var index := next.y * cols + next.x
			if walkable[index] and not reached[index]:
				reached[index] = true
				queue.append(next)

	var reached_count := 0
	for flag in reached:
		if flag:
			reached_count += 1
	print("Reachable floor cells from spawn: %d / %d" % [reached_count, cols * rows])

	# Every NPC slot needs a reachable cell within MARKER_SNAP of it.
	var window := int(ceil(MARKER_SNAP / CELL))
	for slot in _room.get_node("Markers/NpcSlots").get_children():
		var pos: Vector3 = slot.global_position
		var cx := clampi(int(round((pos.x - X_MIN) / CELL)), 0, cols - 1)
		var cz := clampi(int(round((pos.z - Z_MIN) / CELL)), 0, rows - 1)
		var ok := false
		for dz in range(-window, window + 1):
			for dx in range(-window, window + 1):
				var xi := cx + dx
				var zi := cz + dz
				if xi < 0 or xi >= cols or zi < 0 or zi >= rows:
					continue
				if not reached[zi * cols + xi]:
					continue
				var cell_pos := Vector3(X_MIN + xi * CELL, pos.y, Z_MIN + zi * CELL)
				if cell_pos.distance_to(pos) <= MARKER_SNAP:
					ok = true
					break
			if ok:
				break
		if not ok:
			_fail("NPC slot %s is not reachable from the player spawn" % slot.name)


func _report() -> void:
	if _failures.is_empty():
		print("ROOM PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("ROOM PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
