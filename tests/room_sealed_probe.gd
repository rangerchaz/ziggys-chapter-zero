## Regression probe: the room is sealed - the player cannot leave it.
##
## The bug this guards: FrontWall/DoorCut subtracts a 1.2 x 2.2 opening from
## the front wall, and nothing filled it with collision. Walking through the
## doorway dropped the player out of the world with no way back. Sixteen
## phases of QA never tried to leave the room.
##
## Casts rays from inside the bar outward through the doorway and through
## each wall, and asserts every one of them hits something solid.
extends Node

const DOOR_CENTER := Vector3(5.6, 1.1, 5.1)

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _ready() -> void:
	print("=== room sealed probe ===")
	var room: Node = load("res://scenes/room/ziggys_room.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().world_3d.direct_space_state

	# Straight out through the doorway, at three heights: ankle, waist, head.
	for h in [0.3, 1.1, 1.9]:
		var from := Vector3(DOOR_CENTER.x, h, 3.0)
		var to := Vector3(DOOR_CENTER.x, h, 8.0)
		_check(not _cast(space, from, to).is_empty(),
				"doorway blocked at height %.1f" % h)

	# Doorway edges, in case the blocker is too narrow.
	for dx in [-0.5, 0.5]:
		var from := Vector3(DOOR_CENTER.x + dx, 1.1, 3.0)
		var to := Vector3(DOOR_CENTER.x + dx, 1.1, 8.0)
		_check(not _cast(space, from, to).is_empty(),
				"doorway blocked at x offset %+.1f" % dx)

	# The other three walls, so this probe covers the whole shell.
	var walls := {
		"front wall (window side)": [Vector3(-2.0, 1.1, 3.0), Vector3(-2.0, 1.1, 8.0)],
		"back wall": [Vector3(0.0, 1.1, -3.0), Vector3(0.0, 1.1, -8.0)],
		"west wall": [Vector3(-3.0, 1.1, 0.0), Vector3(-10.0, 1.1, 0.0)],
		"east wall": [Vector3(3.0, 1.1, 0.0), Vector3(10.0, 1.1, 0.0)],
		"floor": [Vector3(0.0, 1.0, 0.0), Vector3(0.0, -5.0, 0.0)],
	}
	for label in walls:
		var pair: Array = walls[label]
		_check(not _cast(space, pair[0], pair[1]).is_empty(), "%s is solid" % label)

	if _failures.is_empty():
		print("room sealed probe: PASS")
	else:
		print("room sealed probe: FAIL (", _failures.size(), ")")
		for f in _failures:
			print("   - ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_areas = false
	return space.intersect_ray(params)
