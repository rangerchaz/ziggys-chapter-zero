## Phase 5 probe, runnable headless:
##
##     godot --headless --path . res://tests/closing_time_probe.tscn
##
## ClosingTimeDirector no longer self-triggers (Phase 5 removed its own
## conversation_completed listener and debug_closing_time handling - see
## scripts/systems/closing_time_director.gd's header comment): reaching
## closing time for a data-driven chapter is now entirely BeatRunner's
## `decision` beat trigger, exercised here end to end against the real
## content/chapters/chapter-zero.json - 3 distinct conversations fire the
## brownout, 3 more distinct conversations since the brownout fire the
## closing decision beat, all four options are selectable, the chosen id
## lands on GameState.closing_decision (not the generic flags dict - the
## save file must keep its original three reserved keys, per
## docs/SAVE_FORMAT.md), and the chapter's `end` beat fires once the
## decision is acknowledged. ClosingTimeDirector.fire() itself remains a
## plain callable, exercised here via BeatRunner's debug_closing_time (F10)
## fallback for scenes with no chapter loaded, and via force-firing a still-
## pending `decision` beat when one is. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

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

	await _check_chapter_zero_end_to_end(state, save_mgr)
	state.reset()
	_delete_save(save_mgr)

	await _check_debug_key_fallback_no_chapter(state)
	state.reset()

	await _check_debug_key_force_fires_pending_decision(state)
	state.reset()


## Drives the real chapter-zero.json content through the room's own
## BeatRunner: brownout after 3 distinct conversations, the closing
## decision after 3 more distinct conversations since the brownout beat,
## all four options present and selectable, the pick landing on the typed
## GameState.closing_decision field (and, through it, the save file's
## original ziggys_chapter_zero.closing_decision key - never a new generic
## flags entry), and the chapter's `end` beat firing once the decision is
## acknowledged.
func _check_chapter_zero_end_to_end(state: Node, save_mgr: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var runner: Node = room.get_node(^"BeatRunner")
	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	runner.auto_return_to_title = false

	var ended_ids: Array[String] = []
	runner.chapter_ended.connect(func(id: String) -> void: ended_ids.append(id))

	runner.start("chapter-zero")
	await get_tree().process_frame

	_expect(runner.has_fired("settle"), "chapter-zero's on_start ambience beat fires immediately")
	_expect(not runner.has_fired("the_call"), "brownout beat has not fired yet (waiting on 3 conversations)")

	dialogue.conversation_completed.emit(&"caroline")
	dialogue.conversation_completed.emit(&"chad")
	await get_tree().process_frame
	_expect(not state.brownout_fired, "2 of 3 distinct conversations does not fire the brownout beat")

	dialogue.conversation_completed.emit(&"oleg")
	await get_tree().process_frame
	_expect(state.brownout_fired, "3rd distinct conversation fires the brownout beat")
	_expect(runner.has_fired("the_call"), "BeatRunner marks the brownout beat as fired")
	_expect(not runner.has_fired("decide"), "closing decision beat has not fired yet (waiting on 3 conversations since the brownout)")

	dialogue.conversation_completed.emit(&"ramsey")
	dialogue.conversation_completed.emit(&"nic")
	await get_tree().process_frame
	_expect(not runner.has_fired("decide"), "2 of 3 post-brownout conversations does not fire the closing decision beat")

	dialogue.conversation_completed.emit(&"conner")
	await get_tree().process_frame
	_expect(runner.has_fired("decide"), "3rd distinct post-brownout conversation fires the closing decision beat")
	_expect(dialogue.visible, "closing decision beat opens the DialogueUI choice prompt")

	var container: VBoxContainer = dialogue.get_node(^"%ChoicesContainer")
	_expect(container.visible, "closing decision choice prompt is showing")
	var visible_count := 0
	var button_texts: Dictionary = {}
	for i in container.get_child_count():
		var button: Button = container.get_child(i)
		if button.visible:
			visible_count += 1
			button_texts[button.text] = true
	_expect(visible_count == 4, "closing decision presents exactly 4 options (saw %d)" % visible_count)
	_expect(button_texts.size() == 4, "all 4 visible choice buttons carry distinct text")

	# Pick the first option ("organize", chapter-zero.json's own choice order).
	var chosen_button: Button = container.get_child(0)
	chosen_button.pressed.emit()
	await get_tree().process_frame

	_expect(state.closing_decision == &"organize",
			"selecting the 1st option sets the typed GameState.closing_decision (got '%s')" % state.closing_decision)
	_expect(state.get_flag("ziggys_chapter_zero.closing_decision") == "organize",
			"get_flag() reads the reserved key back off the typed field, not a stray flags entry")
	_expect(not container.visible, "choice buttons hide once the decision is made")

	var saved: Variant = _read_save(save_mgr)
	_expect(saved != null, "a save file exists after the decision")
	if saved != null:
		var keys: Array = saved.keys()
		var reserved_count := 0
		for key in keys:
			if String(key) in ["version", "saved_at", save_mgr.KEY_CLOSING_DECISION, save_mgr.KEY_SELECTED_MECKIE, save_mgr.KEY_BROWNOUT_SEEN]:
				reserved_count += 1
		_expect(keys.size() == reserved_count,
				"save file carries only the original reserved keys, no new generic flag entry (got %s)" % [keys])
		_expect(saved.get(save_mgr.KEY_CLOSING_DECISION) == "organize",
				"the exact chosen id is persisted under the original closing_decision key")

	_expect(runner.has_fired("wrap"), "the 'end' beat fires once the closing decision has been acknowledged")
	_expect(ended_ids.has("chapter-zero"), "'end' beat emits chapter_ended for 'chapter-zero'")
	_expect(not dialogue.visible, "no dialogue panel is left open once the chapter has ended")

	runner.queue_free()
	room.queue_free()
	await get_tree().process_frame


## No chapter loaded (the room's default "" chapter_id, same as any probe
## that instantiates ziggys_room.tscn directly without going through
## chapter select): F10 falls all the way through to
## ClosingTimeDirector.fire(true) directly, firing the real brownout first
## since it hasn't happened yet, matching the pre-Phase-5 debug key exactly.
func _check_debug_key_fallback_no_chapter(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	_expect(not state.brownout_fired, "brownout has not fired before the debug key")
	_expect(not state.closing_time_reached, "closing time has not been reached before the debug key")

	var bd: Node = room.get_node(^"BrownoutDirector")
	var fired_signal := [false]
	bd.brownout_started.connect(func() -> void: fired_signal[0] = true)

	_press_key(KEY_F10)
	await _settle_seconds(0.3)

	_expect(fired_signal[0], "debug_closing_time also fires the real brownout beat when it hadn't happened yet")
	_expect(state.brownout_fired, "GameState.brownout_fired is true after the debug key")
	_expect(state.closing_time_reached, "GameState.closing_time_reached is true after the debug key")

	# Idempotency: a second press must not re-fire anything.
	fired_signal[0] = false
	_press_key(KEY_F10)
	await _settle_seconds(0.2)
	_expect(not fired_signal[0], "a second debug key press does not re-fire the brownout beat")
	_expect(state.closing_time_reached, "closing_time_reached remains true after a repeat trigger")

	room.queue_free()
	await get_tree().process_frame


## A chapter IS loaded, with its closing decision beat still pending (its
## `after` trigger not yet satisfied): F10 force-fires that beat directly,
## the same as _debug_force_brownout() already does for a pending `lighting`
## beat, skipping the conversation count entirely for QA.
func _check_debug_key_force_fires_pending_decision(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var runner: Node = room.get_node(^"BeatRunner")
	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	runner.auto_return_to_title = false
	runner.start("chapter-zero")
	await get_tree().process_frame

	_expect(not runner.has_fired("decide"), "closing decision beat has not organically fired yet")

	_press_key(KEY_F10)
	await _settle_seconds(0.3)

	_expect(runner.has_fired("decide"), "F10 force-fires the still-pending closing decision beat")
	_expect(dialogue.visible, "force-fired closing decision beat opens the choice prompt")

	runner.queue_free()
	room.queue_free()
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


func _settle_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


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
		print("CLOSING TIME PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("CLOSING TIME PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
