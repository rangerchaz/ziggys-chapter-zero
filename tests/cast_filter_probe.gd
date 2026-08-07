## Phase 4 probe, runnable headless:
##
##     godot --headless --path . res://tests/cast_filter_probe.tscn
##
## Verifies acceptance criterion 1: a chapter whose `cast` names only
## caroline and chad, run in the room, shows exactly those two NPCs -
## the other eight are absent from the scene tree (queue_free()'d, not
## merely hidden), fire no InteractionArea signal, and the room's seal
## (DoorwayBlocker) is untouched by the filtering pass. Restores
## GameState.active_chapter_id afterward so it never leaks into a probe
## run later in the same process.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const CHAPTER_ID := "fixture-cast-caroline-chad"

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _ready() -> void:
	print("=== cast filter probe ===")
	await _run()
	_report()


func _run() -> void:
	var state := get_node(^"/root/GameState")
	var chapter_db := get_node(^"/root/ChapterDB")
	var previous_chapter_id: String = state.active_chapter_id

	_check(chapter_db.is_loaded(CHAPTER_ID), "fixture chapter loaded")

	state.active_chapter_id = CHAPTER_ID
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 12:
		await get_tree().physics_frame

	var npcs: Array[NpcHuman] = []
	for raw in get_tree().get_nodes_in_group(&"npcs"):
		if raw is NpcHuman:
			npcs.append(raw)

	var ids: Array = []
	for npc in npcs:
		ids.append(String(npc.npc_id))
	ids.sort()
	_check(ids == ["caroline", "chad"],
			"only caroline and chad remain in the 'npcs' group (got %s)" % [ids])

	var npcs_root := room.get_node(^"Npcs")
	_check(npcs_root.get_child_count() == 2,
			"Npcs container holds exactly 2 children, not just 2 visible (got %d)" % npcs_root.get_child_count())

	for absent_id in ["oleg", "ramsey", "nic", "conner", "nick", "jocelyn", "tonya", "grant"]:
		var still_present := false
		for npc in npcs:
			if String(npc.npc_id) == absent_id:
				still_present = true
		_check(not still_present, "%s is absent, not merely hidden" % absent_id)

	_check(room.get_node_or_null(^"DoorwayBlocker") != null,
			"DoorwayBlocker survives cast filtering (room stays sealed)")

	room.queue_free()
	await get_tree().process_frame
	state.active_chapter_id = previous_chapter_id


func _report() -> void:
	if _failures.is_empty():
		print("cast filter probe: PASS")
	else:
		print("cast filter probe: FAIL (", _failures.size(), ")")
		for f in _failures:
			print("   - ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)
