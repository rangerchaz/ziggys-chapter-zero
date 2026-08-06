## Phase 7 probe, runnable headless:
##
##     godot --headless --path . res://tests/npc_probe.tscn
##
## Verifies the ten named regulars: exactly ten npc_human figures tagged
## in the "npcs" group with unique ids matching NpcDefs, npc_human.gd
## carries no long string literals (a proxy for "zero dialogue strings"),
## a real player Meckie can reach an approachable point within each NPC's
## interaction radius and its Area3D fires body_entered/body_exited as it
## arrives and leaves, and a capsule swept straight at each NPC's center
## is blocked rather than passing through. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const PlayerScene := preload("res://scenes/characters/meckie_player.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 12:
		await get_tree().physics_frame

	var npcs: Array[NpcHuman] = []
	for raw in get_tree().get_nodes_in_group(&"npcs"):
		if raw is NpcHuman:
			npcs.append(raw)
		else:
			_fail("Node '%s' is in the npcs group but is not an NpcHuman" % raw.name)

	_check_roster(npcs)
	_check_no_dialogue_strings()

	var player: CharacterBody3D = PlayerScene.instantiate()
	player.meckie_id = &"droid"
	add_child(player)
	player.global_position = Vector3(0, 6, 0)
	for i in 6:
		await get_tree().physics_frame

	for npc in npcs:
		await _check_npc_interaction(npc, player)

	room.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _check_roster(npcs: Array[NpcHuman]) -> void:
	if npcs.size() != 10:
		_fail("Expected 10 NPCs in the 'npcs' group, found %d" % npcs.size())

	var ids: Array = []
	for npc in npcs:
		if npc.npc_id == &"":
			_fail("%s has an empty npc_id" % npc.name)
		elif npc.npc_id in ids:
			_fail("Duplicate npc_id '%s'" % npc.npc_id)
		else:
			ids.append(npc.npc_id)
		if npc.get_node_or_null(^"InteractionArea") == null:
			_fail("%s has no InteractionArea" % npc.npc_id)

	var expected: Array = NpcDefs.ids()
	ids.sort()
	expected.sort()
	if ids != expected:
		_fail("npc ids %s do not match the roster %s" % [ids, expected])


## Presentation/identity only, per the Phase 7 brief - no dialogue strings.
## A real content check needs a writer's eye, so this is a coarse proxy:
## flag any quoted literal long enough to plausibly be a line of dialogue
## rather than an id or a first name.
func _check_no_dialogue_strings() -> void:
	var file := FileAccess.open("res://scripts/characters/npc_human.gd", FileAccess.READ)
	if file == null:
		_fail("Could not read npc_human.gd to check for dialogue strings")
		return
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var idx := 0
		while true:
			idx = stripped.find("\"", idx)
			if idx == -1:
				break
			var close := stripped.find("\"", idx + 1)
			if close == -1:
				break
			var literal := stripped.substr(idx + 1, close - idx - 1)
			if literal.length() > 50:
				_fail("npc_human.gd has a long string literal (possible dialogue): '%s'" % literal)
			idx = close + 1


func _check_npc_interaction(npc: NpcHuman, player: CharacterBody3D) -> void:
	var area: Area3D = npc.get_node(^"InteractionArea")
	var entered: Array = []
	var exited: Array = []
	var on_enter := func(body: Node) -> void:
		if body == player:
			entered.append(true)
	var on_exit := func(body: Node) -> void:
		if body == player:
			exited.append(true)
	area.body_entered.connect(on_enter)
	area.body_exited.connect(on_exit)

	var far_point: Vector3 = npc.global_position + Vector3(0, 5.15, 6)
	player.global_position = far_point
	player.velocity = Vector3.ZERO
	for i in 4:
		await get_tree().physics_frame

	# Find a point within interaction range that is not itself obstructed,
	# proving the NPC is approachable rather than sealed off by its own
	# collision or nearby furniture.
	var space := npc.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.5
	var approach: Vector3 = Vector3.ZERO
	var reached := false
	for angle in [0.0, PI / 2, PI, -PI / 2, PI / 4, -PI / 4, 3 * PI / 4, -3 * PI / 4]:
		var dir := Vector3(sin(angle), 0, cos(angle))
		var candidate: Vector3 = npc.global_position + dir * (npc.interaction_radius * 0.55)
		candidate.y = 0.85
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, candidate)
		if space.intersect_shape(params, 1).is_empty():
			approach = candidate
			reached = true
			break
	if not reached:
		_fail("%s has no approachable point within interaction range" % npc.npc_id)
	else:
		player.global_position = approach
		player.velocity = Vector3.ZERO
		for i in 8:
			await get_tree().physics_frame
		if entered.is_empty():
			_fail("%s InteractionArea never fired body_entered for the approaching player" % npc.npc_id)

	# The NPC's own body must block a capsule swept straight at its center.
	var from: Vector3 = npc.global_position + Vector3(0, 0, 1.2)
	from.y = 0.85
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = shape
	sweep.transform = Transform3D(Basis.IDENTITY, from)
	sweep.motion = Vector3(0, 0, -1.0)
	var result := space.cast_motion(sweep)
	if result[0] >= 0.999:
		_fail("%s can be walked through - capsule swept through unblocked" % npc.npc_id)

	if reached:
		player.global_position = far_point
		player.velocity = Vector3.ZERO
		for i in 10:
			await get_tree().physics_frame
		if exited.is_empty():
			_fail("%s InteractionArea never fired body_exited when the player left" % npc.npc_id)

	area.body_entered.disconnect(on_enter)
	area.body_exited.disconnect(on_exit)


func _report() -> void:
	if _failures.is_empty():
		print("NPC PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("NPC PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
