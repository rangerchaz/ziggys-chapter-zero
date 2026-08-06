## Phase 5 Meckie probe, runnable headless:
##
##     godot --headless --path . res://tests/meckie_probe.tscn
##
## Spawns the room with the playable Meckie and drives it with real input
## and physics: spawn at the Droid marker, SpringArm3D rig per the official
## pattern, camera-relative WASD movement, wall and bar blocking, spring-arm
## pull-in at the front wall, signature color swaps through meckie_id and
## raw signature_color, and capsule flood-fill reachability of all ten NPC
## slots from the Droid spawn. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

const CELL := 0.2
const X_MIN := -6.9
const X_MAX := 6.9
const Z_MIN := -4.9
const Z_MAX := 4.9
const CAPSULE_RADIUS := 0.28
const CAPSULE_HEIGHT := 1.56
const CAPSULE_Y := 0.85
const MARKER_SNAP := 0.55
const PIVOT := Vector3(0, 1.35, 0)

var _failures: Array[String] = []
var _room: Node3D
var _player: CharacterBody3D
var _rig: SpringArm3D
var _frames := 0


func _ready() -> void:
	_room = RoomScene.instantiate()
	add_child(_room)


func _fail(message: String) -> void:
	_failures.append(message)


func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		14:
			_check_spawn_and_rig()
			if _player == null or _rig == null:
				_report()
				return
			_check_signature_defaults()
			# Drive along the corridor behind the bar; with the camera yawed
			# to -PI/2, "forward" must be camera-relative +X.
			_rig.rotation.y = -PI / 2
			Input.action_press(&"move_forward")
		154:
			Input.action_release(&"move_forward")
			_check_moved_east_and_hit_wall()
			# Face the bar from the open floor and push into it, aiming
			# between two stools so the counter itself does the blocking.
			_teleport(Vector3(0.5, 0.05, -1.5), 0.0)
			Input.action_press(&"move_forward")
		244:
			Input.action_release(&"move_forward")
			_check_blocked_by_bar()
		274:
			_check_arm_free()
			# Back the Meckie against the front window; the arm now extends
			# into the wall and must pull the camera in.
			_teleport(Vector3(0, 0.05, 3.9), 0.0)
		304:
			_check_arm_pulled_in()
			_check_color_swap()
			_check_reachability()
			_report()


func _teleport(pos: Vector3, rig_yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_rig.global_position = pos + PIVOT
	_rig.rotation = Vector3(-0.32, rig_yaw, 0)


func _check_spawn_and_rig() -> void:
	if _room.get_node_or_null(^"PlayerSpawner") == null:
		_fail("Room has no PlayerSpawner node")
	for child in _room.get_children():
		if child is MeckiePlayerController:
			_player = child
	if _player == null:
		_fail("No player-controlled Meckie was spawned into the room")
		return
	if _player.scene_file_path != "res://scenes/characters/meckie_player.tscn":
		_fail("Spawned player is not an instance of meckie_player.tscn")
	var droid_spawn: Vector3 = \
			_room.get_node(^"Markers/MeckieSpawns/MeckieSpawnDroid").global_position
	if _player.global_position.distance_to(droid_spawn) > 0.3:
		_fail("Player did not spawn at the Droid marker (at %s)" % _player.global_position)
	if _player.get_node_or_null(^"CollisionShape3D") == null:
		_fail("Player has no CollisionShape3D")

	var meshes := _player.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() < 6:
		_fail("Meckie body should be built from primitive meshes, found %d" % meshes.size())
	var accents := 0
	for mesh in meshes:
		if mesh.is_in_group(&"signature_accents"):
			accents += 1
	if accents < 3:
		_fail("Expected at least 3 signature accent meshes, found %d" % accents)

	var rig := _player.get_node_or_null(^"CameraRig")
	if rig == null or rig is not SpringArm3D:
		_fail("Player has no SpringArm3D CameraRig")
		return
	_rig = rig
	if not _rig.top_level:
		_fail("SpringArm3D should have top_level enabled")
	if absf(_rig.spring_length - 3.5) > 0.6:
		_fail("spring_length %f is not ~3.5" % _rig.spring_length)
	if _rig.collision_mask != 1:
		_fail("SpringArm3D collision mask should target room geometry (layer 1)")
	var camera: Camera3D = _rig.get_node_or_null(^"Camera3D")
	if camera == null:
		_fail("CameraRig has no Camera3D child")
	elif _room.get_viewport().get_camera_3d() != camera:
		_fail("Player camera is not the current camera")


func _check_signature_defaults() -> void:
	var droid: Color = MeckieDefs.color_of(&"droid")
	var light: OmniLight3D = _player.get_node_or_null(^"SignatureLight")
	if light == null:
		_fail("Player has no SignatureLight OmniLight3D")
	elif not light.light_color.is_equal_approx(droid):
		_fail("SignatureLight is not the Droid cyan")
	var plate: MeshInstance3D = _player.get_node_or_null(^"Visual/Faceplate")
	if plate == null:
		_fail("Player has no floating faceplate")
		return
	var material := plate.material_override as StandardMaterial3D
	if material == null or not material.emission_enabled \
			or not material.emission.is_equal_approx(droid):
		_fail("Faceplate emissive is not driven by the Droid signature color")


func _check_moved_east_and_hit_wall() -> void:
	var pos := _player.global_position
	if pos.x < 6.0:
		_fail("Camera-relative forward should have driven the player east to the wall (x=%f)" % pos.x)
	if pos.x > 6.85:
		_fail("Player passed through the east wall (x=%f)" % pos.x)
	if pos.z > -3.5:
		_fail("Player drifted out of the corridor (z=%f)" % pos.z)
	var diff := absf(wrapf(_player.rotation.y - (-PI / 2), -PI, PI))
	if diff > 0.35:
		_fail("Body did not rotate toward its travel direction (yaw off by %f)" % diff)


func _check_blocked_by_bar() -> void:
	var z := _player.global_position.z
	if z < -3.15:
		_fail("Player pushed through the bar counter (z=%f)" % z)
	if z > -2.6:
		_fail("Player never reached the bar (z=%f), movement seems broken" % z)


func _check_arm_free() -> void:
	if _rig.get_hit_length() < 3.2:
		_fail("Spring arm should be at full length in open floor (hit %f)" % _rig.get_hit_length())


func _check_arm_pulled_in() -> void:
	if _rig.get_hit_length() > 2.0:
		_fail("Spring arm did not pull in against the front wall (hit %f)" % _rig.get_hit_length())


func _check_color_swap() -> void:
	var light: OmniLight3D = _player.get_node(^"SignatureLight")
	var plate: MeshInstance3D = _player.get_node(^"Visual/Faceplate")
	_player.meckie_id = &"eva"
	var eva: Color = MeckieDefs.color_of(&"eva")
	if not _player.signature_color.is_equal_approx(eva):
		_fail("Setting meckie_id to eva did not adopt Eva's signature color")
	if not light.light_color.is_equal_approx(eva):
		_fail("Setting meckie_id did not recolor the cast light")
	var material := plate.material_override as StandardMaterial3D
	if material == null or not material.emission.is_equal_approx(eva):
		_fail("Setting meckie_id did not recolor the emissive accents")
	var custom := Color(0.3, 1.0, 0.5)
	_player.signature_color = custom
	if not light.light_color.is_equal_approx(custom) \
			or not material.emission.is_equal_approx(custom):
		_fail("Setting signature_color directly did not drive light and emissive")
	_player.meckie_id = &"droid"


func _check_reachability() -> void:
	var cols := int(round((X_MAX - X_MIN) / CELL)) + 1
	var rows := int(round((Z_MAX - Z_MIN) / CELL)) + 1
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var space := _room.get_world_3d().direct_space_state

	# Exclude every Meckie body (player and the Phase 6 idle NPCs): this
	# check is about static geometry, and the idles drift around markers.
	var exclude: Array[RID] = []
	for child in _room.get_children():
		if child is CharacterBody3D:
			exclude.append(child.get_rid())

	var walkable: Array[bool] = []
	walkable.resize(cols * rows)
	for zi in rows:
		for xi in cols:
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.exclude = exclude
			params.transform = Transform3D(Basis.IDENTITY,
					Vector3(X_MIN + xi * CELL, CAPSULE_Y, Z_MIN + zi * CELL))
			walkable[zi * cols + xi] = space.intersect_shape(params, 1).is_empty()

	var spawn: Vector3 = \
			_room.get_node(^"Markers/MeckieSpawns/MeckieSpawnDroid").global_position
	var start_x := clampi(int(round((spawn.x - X_MIN) / CELL)), 0, cols - 1)
	var start_z := clampi(int(round((spawn.z - Z_MIN) / CELL)), 0, rows - 1)
	if not walkable[start_z * cols + start_x]:
		_fail("Droid spawn cell is not walkable")
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

	var window := int(ceil(MARKER_SNAP / CELL))
	for slot in _room.get_node(^"Markers/NpcSlots").get_children():
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
			_fail("NPC slot %s is not reachable from the Droid spawn" % slot.name)


func _report() -> void:
	if _failures.is_empty():
		print("MECKIE PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("MECKIE PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
