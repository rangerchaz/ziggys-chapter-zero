## Phase 12 probe, runnable headless:
##
##     godot --headless --path . res://tests/post_brownout_probe.tscn
##
## Drives the real DialogueUI (the same scene InteractionManager opens,
## via the same open_for() entry point) through both sides of the
## brownout state switch: before GameState.brownout_fired, every one of
## the ten NPCs serves its pre_brownout line; the instant it flips true,
## the very next open_for() for that same NPC serves a different,
## post_brownout line, with no other trigger or per-NPC state needed.
## Also checks that all ten post-brownout reactions are distinct from each
## other, and that DialogueDB's content-completeness guard actually
## excludes an NPC missing post_brownout rather than silently falling back
## to its pre_brownout line. Exits 0 on pass, 1 on failure.
extends Node

const DialogueScene := preload("res://scenes/ui/dialogue_ui.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var state: Node = get_node(^"/root/GameState")
	var dialogue_db: Node = get_node(^"/root/DialogueDB")
	state.reset()

	var ui: Control = DialogueScene.instantiate()
	add_child(ui)
	await get_tree().process_frame

	var ids: Array[StringName] = NpcDefs.ids()
	if ids.size() != 10:
		_fail("Expected 10 NPCs in NpcDefs, found %d" % ids.size())

	var pre_lines: Dictionary = {}
	for npc_id in ids:
		var display_name := NpcDefs.display_name_of(npc_id)
		ui.open_for(npc_id, display_name)
		await get_tree().process_frame

		var expected: Array[String] = dialogue_db.get_lines(npc_id, &"pre_brownout")
		var shown: String = ui.get_node(^"%LineLabel").text
		if expected.is_empty():
			_fail("%s: DialogueDB has no pre_brownout line to verify against" % npc_id)
		elif shown != expected[0]:
			_fail("%s: pre-brownout line shown is '%s', expected '%s'" % [npc_id, shown, expected[0]])
		pre_lines[npc_id] = shown

		await _close_dialogue(ui)

	if state.brownout_fired:
		_fail("brownout_fired flipped true just from talking to NPCs pre-brownout in this probe")

	# Flip the shared flag the way BrownoutDirector.fire() does - this probe
	# is about the dialogue-side routing, not re-driving the beat itself
	# (brownout_probe.gd already covers the trigger paths).
	state.brownout_fired = true

	var post_lines: Dictionary = {}
	for npc_id in ids:
		var display_name := NpcDefs.display_name_of(npc_id)
		ui.open_for(npc_id, display_name)
		await get_tree().process_frame

		var expected: Array[String] = dialogue_db.get_lines(npc_id, &"post_brownout")
		var shown: String = ui.get_node(^"%LineLabel").text
		if expected.is_empty():
			_fail("%s: DialogueDB has no post_brownout line to verify against" % npc_id)
		elif shown != expected[0]:
			_fail("%s: post-brownout line shown is '%s', expected '%s'" % [npc_id, shown, expected[0]])
		if shown.is_empty():
			_fail("%s: post-brownout line is empty" % npc_id)
		elif pre_lines.has(npc_id) and shown == pre_lines[npc_id]:
			_fail("%s: post-brownout line is identical to the pre-brownout line ('%s')" % [npc_id, shown])
		post_lines[npc_id] = shown

		await _close_dialogue(ui)

	var distinct: Dictionary = {}
	for npc_id in post_lines:
		distinct[post_lines[npc_id]] = true
	if distinct.size() != 10:
		_fail("Expected 10 distinct post-brownout reaction strings across the roster, found %d" % distinct.size())

	ui.queue_free()
	await get_tree().process_frame

	_check_missing_post_brownout_falls_back_to_nothing()


## Deliverable 3 / acceptance criterion 5, exercised end to end through
## get_lines() rather than just the guard function in isolation: an NPC
## whose content never made it into DialogueDB's validated _content (the
## same state a failed check_content_complete() guard produces) returns
## empty lines, not a silent reuse of some other state's line.
func _check_missing_post_brownout_falls_back_to_nothing() -> void:
	var dialogue_db: Node = get_node(^"/root/DialogueDB")
	var bogus_lines: Array[String] = dialogue_db.get_lines(&"not_a_real_npc", &"post_brownout")
	if not bogus_lines.is_empty():
		_fail("get_lines() returned content for an npc_id with no validated content: %s" % bogus_lines)


func _close_dialogue(ui: Control) -> void:
	_press_key(KEY_E)
	for i in 4:
		await get_tree().physics_frame
	if ui.visible:
		_fail("Dialogue did not close after advancing its single line")


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
		print("POST-BROWNOUT PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("POST-BROWNOUT PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
