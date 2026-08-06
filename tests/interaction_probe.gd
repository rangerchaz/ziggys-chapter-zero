## Phase 9 probe, runnable headless:
##
##     godot --headless --path . res://tests/interaction_probe.tscn
##
## Drives the real room with a real player and real input: for all ten
## NPCs, walking into range shows the prompt naming that NPC and walking
## away hides it; pressing interact opens the dialogue UI with that NPC's
## actual pre_brownout line from DialogueDB (never a placeholder), and
## player movement is suppressed while it is open and restored the instant
## it closes. Also covers advancing a synthetic multi-line entry to its
## close, two overlapping NPC ranges resolving to exactly one (nearest)
## prompt, and Escape mid-dialogue closing cleanly rather than quitting or
## soft-locking input. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const PlayerScene := preload("res://scenes/characters/meckie_player.tscn")
const DialogueScene := preload("res://scenes/ui/dialogue_ui.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var dialogue_db: Node = get_node(^"/root/DialogueDB")

	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 12:
		await get_tree().physics_frame

	var interaction: InteractionManager = room.get_node(^"InteractionManager")
	var prompt_ui: Control = room.get_node(^"UI/InteractPrompt")
	var dialogue_ui: Control = room.get_node(^"UI/DialogueUI")

	var player: CharacterBody3D = PlayerScene.instantiate()
	player.meckie_id = &"droid"
	add_child(player)
	player.global_position = Vector3(0, 6, 0)
	for i in 6:
		await get_tree().physics_frame

	var npcs: Dictionary = {}
	for raw in get_tree().get_nodes_in_group(&"npcs"):
		if raw is NpcHuman:
			npcs[raw.npc_id] = raw
	if npcs.size() != 10:
		_fail("Expected 10 NPCs in the 'npcs' group, found %d" % npcs.size())

	for npc_id: StringName in NpcDefs.ids():
		if not npcs.has(npc_id):
			_fail("No NpcHuman found for '%s'" % npc_id)
			continue
		await _check_npc_flow(npcs[npc_id], player, interaction, prompt_ui, dialogue_ui, dialogue_db)

	await _check_multiline_advance()
	await _check_overlap_prompts_exactly_one(npcs, player, interaction, prompt_ui)
	await _check_escape_closes_and_restores(npcs[&"caroline"], player, interaction, prompt_ui, dialogue_ui)

	room.queue_free()
	player.queue_free()
	await get_tree().process_frame


## Full walk-up -> prompt -> interact -> dialogue -> suppressed movement ->
## advance/close -> restored movement -> walk-away -> prompt hides cycle
## for one NPC.
func _check_npc_flow(npc: NpcHuman, player: CharacterBody3D, interaction: InteractionManager,
		prompt_ui: Control, dialogue_ui: Control, dialogue_db: Node) -> void:
	var shown: Array = []
	# Plain ints captured by a lambda are captured by value in GDScript, so
	# mutating them inside the closure would not reach this outer scope;
	# a single-element array is a reference type and does propagate.
	var hidden := [0]
	var on_shown := func(id: StringName, display_name: String) -> void:
		shown.append([id, display_name])
	var on_hidden := func() -> void:
		hidden[0] += 1
	interaction.npc_prompt_shown.connect(on_shown)
	interaction.npc_prompt_hidden.connect(on_hidden)

	# Start far away: no prompt.
	player.global_position = npc.global_position + Vector3(0, 5.15, 6)
	player.velocity = Vector3.ZERO
	for i in 6:
		await get_tree().physics_frame
	if prompt_ui.visible:
		_fail("%s: prompt visible while player is far away" % npc.npc_id)

	var approach := _find_approach_point(npc)
	if not approach["reached"]:
		_fail("%s: no approachable point within interaction range" % npc.npc_id)
		interaction.npc_prompt_shown.disconnect(on_shown)
		interaction.npc_prompt_hidden.disconnect(on_hidden)
		return

	player.global_position = approach["point"]
	player.velocity = Vector3.ZERO
	for i in 8:
		await get_tree().physics_frame

	if not prompt_ui.visible:
		_fail("%s: prompt did not appear when player entered range" % npc.npc_id)
	elif not String(prompt_ui.get_node(^"%PromptLabel").text).contains(npc.display_name):
		_fail("%s: prompt text '%s' does not name the NPC" % [npc.npc_id, prompt_ui.get_node(^"%PromptLabel").text])
	if shown.is_empty() or shown[-1][0] != npc.npc_id:
		_fail("%s: npc_prompt_shown did not fire with this npc_id" % npc.npc_id)

	# Interact opens the dialogue with this NPC's real content.
	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame

	if not dialogue_ui.visible:
		_fail("%s: dialogue UI did not open on interact" % npc.npc_id)
		interaction.npc_prompt_shown.disconnect(on_shown)
		interaction.npc_prompt_hidden.disconnect(on_hidden)
		return

	var expected_lines: Array = dialogue_db.get_lines(npc.npc_id, &"pre_brownout")
	if expected_lines.is_empty():
		_fail("%s: DialogueDB has no pre_brownout lines to verify against" % npc.npc_id)
	else:
		var speaker: String = dialogue_ui.get_node(^"%SpeakerLabel").text
		var line: String = dialogue_ui.get_node(^"%LineLabel").text
		if speaker != npc.display_name:
			_fail("%s: dialogue speaker shows '%s', expected '%s'" % [npc.npc_id, speaker, npc.display_name])
		if line != expected_lines[0]:
			_fail("%s: dialogue line is '%s', expected the JSON line '%s'" % [npc.npc_id, line, expected_lines[0]])
		if line.is_empty():
			_fail("%s: dialogue line is empty (placeholder), not real content" % npc.npc_id)

	# Movement and camera input must be suppressed while open.
	var before: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	for i in 16:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	var moved_while_open := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if moved_while_open > 0.02:
		_fail("%s: player moved %f while dialogue was open, expected suppressed input" % [npc.npc_id, moved_while_open])

	# Advance the single pre_brownout line: this must close the dialogue.
	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if dialogue_ui.visible:
		_fail("%s: dialogue did not close after advancing its final line" % npc.npc_id)

	# Movement must work again immediately.
	var before_restored: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	for i in 16:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	var moved_after_close := Vector2(player.global_position.x - before_restored.x, player.global_position.z - before_restored.z).length()
	if moved_after_close < 0.05:
		_fail("%s: player did not move after dialogue closed, input still suppressed" % npc.npc_id)

	# Walk away: prompt hides.
	player.global_position = npc.global_position + Vector3(0, 5.15, 6)
	player.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame
	if prompt_ui.visible:
		_fail("%s: prompt still visible after player walked away" % npc.npc_id)
	if hidden[0] == 0:
		_fail("%s: npc_prompt_hidden never fired after player walked away" % npc.npc_id)

	interaction.npc_prompt_shown.disconnect(on_shown)
	interaction.npc_prompt_hidden.disconnect(on_hidden)


## A standalone DialogueUI fed a synthetic multi-line entry: each advance
## before the last shows the next line and stays open; the final advance
## closes it. Real content is single-line per state right now, so this is
## the only way to exercise the multi-line path.
func _check_multiline_advance() -> void:
	var ui: Control = DialogueScene.instantiate()
	add_child(ui)
	await get_tree().process_frame

	var closed_count := [0]
	ui.closed.connect(func() -> void: closed_count[0] += 1)

	var lines: Array[String] = ["Line one.", "Line two.", "Line three."]
	ui.open_with_lines("Test Speaker", lines)
	await get_tree().process_frame

	if not ui.visible:
		_fail("Multiline: dialogue did not open")
	if ui.get_node(^"%LineLabel").text != "Line one.":
		_fail("Multiline: first line is '%s', expected 'Line one.'" % ui.get_node(^"%LineLabel").text)

	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if not ui.visible:
		_fail("Multiline: dialogue closed early after the first advance")
	if ui.get_node(^"%LineLabel").text != "Line two.":
		_fail("Multiline: second line is '%s', expected 'Line two.'" % ui.get_node(^"%LineLabel").text)

	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if not ui.visible:
		_fail("Multiline: dialogue closed early after the second advance")
	if ui.get_node(^"%LineLabel").text != "Line three.":
		_fail("Multiline: third line is '%s', expected 'Line three.'" % ui.get_node(^"%LineLabel").text)

	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if ui.visible:
		_fail("Multiline: dialogue stayed open after the final advance")
	if closed_count[0] != 1:
		_fail("Multiline: 'closed' fired %d time(s), expected exactly 1" % closed_count[0])

	ui.queue_free()
	await get_tree().process_frame


## Chad and Oleg stand 1m apart at the bar with overlapping interaction
## radii; a point closer to one than the other must prompt for exactly
## that one, and the prompt must switch (never show/imply both) as the
## nearer one changes.
func _check_overlap_prompts_exactly_one(npcs: Dictionary, player: CharacterBody3D,
		interaction: InteractionManager, prompt_ui: Control) -> void:
	if not npcs.has(&"chad") or not npcs.has(&"oleg"):
		_fail("Overlap check: Chad or Oleg NPC missing")
		return
	var chad: NpcHuman = npcs[&"chad"]
	var oleg: NpcHuman = npcs[&"oleg"]
	if chad.global_position.distance_to(oleg.global_position) > 1.4:
		_fail("Overlap check: Chad and Oleg are not close enough for overlapping ranges")
		return

	var hidden_count := [0]
	interaction.npc_prompt_hidden.connect(func() -> void: hidden_count[0] += 1)

	var y := chad.global_position.y
	var z := chad.global_position.z
	var near_chad: Vector3 = Vector3(chad.global_position.x + 0.3, y, z)
	player.global_position = near_chad
	player.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame

	if not prompt_ui.visible:
		_fail("Overlap check: no prompt while standing between two overlapping NPCs")
	elif not String(prompt_ui.get_node(^"%PromptLabel").text).contains(chad.display_name):
		_fail("Overlap check: nearer to Chad but prompt reads '%s'" % prompt_ui.get_node(^"%PromptLabel").text)

	var near_oleg: Vector3 = Vector3(oleg.global_position.x - 0.3, y, z)
	player.global_position = near_oleg
	player.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame

	if not prompt_ui.visible:
		_fail("Overlap check: prompt vanished while still inside Oleg's range")
	elif not String(prompt_ui.get_node(^"%PromptLabel").text).contains(oleg.display_name):
		_fail("Overlap check: nearer to Oleg but prompt reads '%s'" % prompt_ui.get_node(^"%PromptLabel").text)
	if hidden_count[0] != 0:
		_fail("Overlap check: prompt hid %d time(s) while the player stayed inside both ranges" % hidden_count[0])

	player.global_position = chad.global_position + Vector3(0, 5.15, 6)
	player.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame


## Escape while the dialogue is open must close it and hand control back
## cleanly: no crash, no quit, movement works again right away.
func _check_escape_closes_and_restores(npc: NpcHuman, player: CharacterBody3D,
		interaction: InteractionManager, prompt_ui: Control, dialogue_ui: Control) -> void:
	var approach := _find_approach_point(npc)
	if not approach["reached"]:
		_fail("Escape check: no approachable point near %s" % npc.npc_id)
		return
	player.global_position = approach["point"]
	player.velocity = Vector3.ZERO
	for i in 8:
		await get_tree().physics_frame

	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if not dialogue_ui.visible:
		_fail("Escape check: dialogue never opened for %s" % npc.npc_id)
		return

	_press_key(KEY_ESCAPE)
	for i in 6:
		await get_tree().physics_frame

	if dialogue_ui.visible:
		_fail("Escape check: dialogue still open after Escape")
	if get_tree() == null or not is_instance_valid(self):
		_fail("Escape check: tree/probe torn down, Escape likely quit or crashed")

	var before: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	for i in 16:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	var moved := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if moved < 0.05:
		_fail("Escape check: player input still stuck/suppressed after Escape closed the dialogue")

	player.global_position = npc.global_position + Vector3(0, 5.15, 6)
	player.velocity = Vector3.ZERO
	for i in 8:
		await get_tree().physics_frame


## Samples points around an NPC's interaction radius and returns the first
## one whose capsule query is unobstructed, matching npc_probe's approach.
func _find_approach_point(npc: NpcHuman) -> Dictionary:
	var space := npc.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.5
	for angle in [0.0, PI / 2, PI, -PI / 2, PI / 4, -PI / 4, 3 * PI / 4, -3 * PI / 4]:
		var dir := Vector3(sin(angle), 0, cos(angle))
		var candidate: Vector3 = npc.global_position + dir * (npc.interaction_radius * 0.55)
		candidate.y = 0.85
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, candidate)
		if space.intersect_shape(params, 1).is_empty():
			candidate.y = 0.0
			return {"reached": true, "point": candidate}
	return {"reached": false, "point": Vector3.ZERO}


func _press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _report() -> void:
	if _failures.is_empty():
		print("INTERACTION PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("INTERACTION PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
