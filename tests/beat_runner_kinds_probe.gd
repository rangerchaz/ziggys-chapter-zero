## Phase 3 probe, runnable headless:
##
##     godot --headless --path . res://tests/beat_runner_kinds_probe.tscn
##
## Exercises the three beat kinds this phase adds:
##
## - `dialogue`: BeatRunner opens the real DialogueUI panel showing an
##   existing line from the named NPC's own content file (DialogueDB), not
##   a new/duplicated string literal.
## - `decision`: opens an N-option prompt built purely from the beat's own
##   `choices` array (content/chapters/fixture-beatrunner-kinds.json's
##   `demo_decision` beat: 3 choices, writes "demo.chapter.decision") -
##   never DialogueDB.get_closing_choices()' hardcoded Caroline path - and
##   selecting one persists that exact key/value pair to the real save
##   file via GameState.flags/SaveManager.
## - `end`: fires immediately after the decision beat's selection is
##   acknowledged (the very next conversation_completed), without crashing,
##   and never actually swaps the scene out from under this test
##   (auto_return_to_title = false) - chapter_ended is asserted instead.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const BeatRunnerScript := preload("res://scripts/systems/beat_runner.gd")

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_fail(label)
		printerr("  FAIL: %s" % label)


func _run() -> void:
	var state: Node = get_node(^"/root/GameState")
	var save_mgr: Node = get_node(^"/root/SaveManager")
	state.reset()
	_delete_save(save_mgr)

	await _check_dialogue_kind(state)
	state.reset()
	_delete_save(save_mgr)

	await _check_decision_and_end_kind(state, save_mgr)
	state.reset()
	_delete_save(save_mgr)


## A `dialogue` beat with no `after` fires the instant it's reached and
## shows Chad's own pre_brownout content, not a string authored in
## beat_runner.gd itself.
func _check_dialogue_kind(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	var bd: Node = room.get_node(^"BrownoutDirector")
	var runner: Node = BeatRunnerScript.new()
	runner.dialogue_ui_path = dialogue.get_path()
	runner.brownout_director_path = bd.get_path()
	add_child(runner)
	await get_tree().process_frame

	var dialogue_db: Node = get_node(^"/root/DialogueDB")
	var expected_lines: Array[String] = dialogue_db.get_lines(&"chad", dialogue_db.STATE_PRE_BROWNOUT)
	_expect(not expected_lines.is_empty(), "precondition: chad has pre_brownout content to compare against")

	runner.load_beats([{"id": "say_hi", "kind": "dialogue", "npc": "chad"}])
	await get_tree().process_frame

	_expect(runner.has_fired("say_hi"), "dialogue beat is marked fired once reached")
	_expect(dialogue.visible, "dialogue-kind beat opens the DialogueUI panel")
	_expect(dialogue.get_node(^"%LineLabel").text == expected_lines[0],
			"dialogue-kind beat shows an existing DialogueDB line for the named NPC (no new string literal)")

	await _finish_lines_dialogue(dialogue, expected_lines.size())
	_expect(not dialogue.visible, "dialogue-kind conversation closes cleanly once advanced through")

	runner.queue_free()
	room.queue_free()
	await get_tree().process_frame


## Drives the full sequence off the real fixture chapter file: dialogue ->
## decision -> end, exactly as ChapterDB/BeatRunner would run it in the
## shipped game.
func _check_decision_and_end_kind(state: Node, save_mgr: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	var bd: Node = room.get_node(^"BrownoutDirector")
	var runner: Node = BeatRunnerScript.new()
	runner.dialogue_ui_path = dialogue.get_path()
	runner.brownout_director_path = bd.get_path()
	runner.auto_return_to_title = false
	add_child(runner)
	await get_tree().process_frame

	var ended_ids: Array[String] = []
	runner.chapter_ended.connect(func(id: String) -> void: ended_ids.append(id))

	var dialogue_db: Node = get_node(^"/root/DialogueDB")
	var chad_lines: Array[String] = dialogue_db.get_lines(&"chad", dialogue_db.STATE_PRE_BROWNOUT)

	runner.start("fixture-beatrunner-kinds")
	await get_tree().process_frame

	_expect(runner.has_fired("say_hi"), "fixture's dialogue beat 'say_hi' fires on start")
	_expect(not runner.has_fired("demo_decision"), "fixture's decision beat has not fired yet (waiting on 1 conversation)")

	# Finish Chad's conversation - this is the completed conversation the
	# decision beat's `after: {conversations: 1}` trigger is waiting for.
	await _finish_lines_dialogue(dialogue, chad_lines.size())
	await get_tree().process_frame

	_expect(runner.has_fired("demo_decision"), "decision beat fires once the dialogue beat's conversation completes")
	_expect(dialogue.visible, "decision beat opens the DialogueUI choice prompt")

	var container: VBoxContainer = dialogue.get_node(^"%ChoicesContainer")
	_expect(container.visible, "decision beat's choice prompt is showing")
	var visible_count := 0
	for i in container.get_child_count():
		if container.get_child(i).visible:
			visible_count += 1
	_expect(visible_count == 3, "decision beat with 3 choices presents exactly 3 options (saw %d)" % visible_count)

	var button_texts: Dictionary = {}
	for i in container.get_child_count():
		var button: Button = container.get_child(i)
		if button.visible:
			button_texts[button.text] = true
	_expect(button_texts.size() == 3, "all 3 visible choice buttons carry distinct text")

	# Pick the middle option ("b").
	var chosen_button: Button = container.get_child(1)
	chosen_button.pressed.emit()
	await get_tree().process_frame

	_expect(state.get_flag("demo.chapter.decision") == "b",
			"selecting the 2nd option writes GameState.flags['demo.chapter.decision'] = 'b' (got '%s')" % state.get_flag("demo.chapter.decision"))
	_expect(not container.visible, "choice buttons hide once the decision is made")

	var saved: Variant = _read_save(save_mgr)
	_expect(saved != null, "a save file exists after the decision")
	if saved != null:
		_expect(saved.get("demo.chapter.decision") == "b",
				"the exact chosen key/value pair is persisted to the save file")
		_expect(saved.get(save_mgr.KEY_CLOSING_DECISION) == "",
				"Chapter Zero's own closing_decision key is still present and untouched")
		_expect(saved.has(save_mgr.KEY_SELECTED_MECKIE) and saved.has(save_mgr.KEY_BROWNOUT_SEEN),
				"Chapter Zero's other two reserved keys are still present")

	_expect(runner.has_fired("wrap_up"),
			"the 'end' beat fires immediately after the decision beat's completion, without crashing")
	_expect(ended_ids.has("fixture-beatrunner-kinds"),
			"'end' beat emits chapter_ended for the running chapter id")
	_expect(not dialogue.visible, "no dialogue panel is left open once the chapter has ended")

	runner.queue_free()
	room.queue_free()
	await get_tree().process_frame


## Presses [E] `line_count` times to walk a LINES-mode conversation to
## completion (the last press closes the panel).
func _finish_lines_dialogue(dialogue: Control, line_count: int) -> void:
	for i in line_count:
		_press_key(KEY_E)
		await get_tree().process_frame


func _read_save(save_mgr: Node) -> Variant:
	if not FileAccess.file_exists(save_mgr.SAVE_PATH):
		return null
	var file := FileAccess.open(save_mgr.SAVE_PATH, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else null


func _delete_save(save_mgr: Node) -> void:
	if FileAccess.file_exists(save_mgr.SAVE_PATH):
		DirAccess.remove_absolute(save_mgr.SAVE_PATH)
	if FileAccess.file_exists(save_mgr.SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(save_mgr.SAVE_PATH + ".tmp")


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
		print("BEAT RUNNER KINDS PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("BEAT RUNNER KINDS PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
