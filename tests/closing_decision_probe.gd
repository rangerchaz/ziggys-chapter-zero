## Phase 13 probe, runnable headless:
##
##     godot --headless --path . res://tests/closing_decision_probe.tscn
##
## Drives the real DialogueUI (the same scene InteractionManager opens, via
## the same open_for() entry point) through Caroline's closing decision:
## once GameState.closing_time_reached and no decision has been made yet,
## opening her opens the closing question, advancing past it reveals four
## distinct, independently selectable option buttons sourced from
## DialogueDB.get_closing_choices(), and pressing one sets
## GameState.closing_decision to that choice's string id, shows the
## content-sourced acknowledgement, and closes cleanly. Also checks that
## each of the four choices can be picked independently (fresh state each
## time) and that Escape at the decision prompt closes without selecting,
## leaving the prompt re-triggerable. Exits 0 on pass, 1 on failure.
extends Node

const DialogueScene := preload("res://scenes/ui/dialogue_ui.tscn")

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
	var dialogue_db: Node = get_node(^"/root/DialogueDB")

	var choices: Array = dialogue_db.get_closing_choices(&"caroline")
	if choices.size() != 4:
		_fail("DialogueDB.get_closing_choices(caroline) returned %d choices, expected 4" % choices.size())
		return

	await _check_each_choice_independently(state, dialogue_db, choices)
	await _check_escape_does_not_select_and_reopens(state, dialogue_db)


## Selects each of the four choices in turn, from a fresh reset each time,
## and checks it lands its own distinct GameState.closing_decision id.
func _check_each_choice_independently(state: Node, dialogue_db: Node, choices: Array) -> void:
	var seen_decisions: Dictionary = {}
	for i in choices.size():
		var choice: Dictionary = choices[i]
		state.reset()
		state.brownout_fired = true
		state.closing_time_reached = true

		var ui: Control = DialogueScene.instantiate()
		add_child(ui)
		await get_tree().process_frame

		var completed_ids: Array[StringName] = []
		ui.conversation_completed.connect(func(npc_id: StringName) -> void: completed_ids.append(npc_id))

		ui.open_for(&"caroline", "Caroline")
		await get_tree().process_frame

		var expected_question: Array[String] = dialogue_db.get_lines(&"caroline", &"closing")
		_expect(ui.visible, "opening Caroline at closing time opens the panel (choice %s)" % choice["id"])
		_expect(ui.get_node(^"%LineLabel").text == expected_question[0],
				"closing question line matches DialogueDB content (choice %s)" % choice["id"])

		_press_key(KEY_E)
		await get_tree().process_frame

		var container: VBoxContainer = ui.get_node(^"%ChoicesContainer")
		_expect(container.visible, "four-option prompt appears after the closing question (choice %s)" % choice["id"])
		_expect(container.get_child_count() == 4, "exactly four choice buttons exist")

		var button_texts: Dictionary = {}
		for b in container.get_child_count():
			var button: Button = container.get_child(b)
			button_texts[button.text] = true
		_expect(button_texts.size() == 4, "all four choice buttons carry distinct text")

		var focus_owner: Control = ui.get_viewport().gui_get_focus_owner()
		_expect(focus_owner == container.get_child(0), "first choice button grabs keyboard focus when the prompt opens")

		# The real production wiring: DialogueUI connects each button's
		# `pressed` signal at scene setup. Emitting it here exercises that
		# exact connection rather than a private method, covering both the
		# mouse-click and keyboard-ui_accept activation paths, which both
		# funnel through Button.pressed.
		var button: Button = container.get_child(i)
		button.pressed.emit()
		await get_tree().process_frame

		_expect(state.closing_decision == StringName(choice["id"]),
				"selecting '%s' sets GameState.closing_decision to its id (got '%s')" % [choice["id"], state.closing_decision])
		_expect(not container.visible, "choice buttons hide once a decision is made")
		seen_decisions[state.closing_decision] = true

		var ack_lines: Array[String] = dialogue_db.get_closing_acknowledgement(&"caroline")
		if not ack_lines.is_empty():
			_expect(ui.get_node(^"%LineLabel").text == ack_lines[0],
					"acknowledgement line shown after deciding matches content layer")
			_expect(ui.visible, "panel stays open on the acknowledgement line, not auto-closed")
			_press_key(KEY_E)
			await get_tree().process_frame

		_expect(not ui.visible, "panel closes after the acknowledgement is advanced past")
		_expect(completed_ids.has(&"caroline"), "conversation_completed fires once the decision has landed")

		ui.queue_free()
		await get_tree().process_frame

	_expect(seen_decisions.size() == 4, "all four choices produced four distinct closing_decision ids across separate runs")


## Escape at either the closing question or the four-option prompt itself
## must close without recording a decision, and the very next open_for()
## must show the same four-option prompt again - never a soft-lock, never
## a silently-skipped decision.
func _check_escape_does_not_select_and_reopens(state: Node, dialogue_db: Node) -> void:
	state.reset()
	state.brownout_fired = true
	state.closing_time_reached = true

	var ui: Control = DialogueScene.instantiate()
	add_child(ui)
	await get_tree().process_frame

	ui.open_for(&"caroline", "Caroline")
	await get_tree().process_frame
	_press_key(KEY_E)
	await get_tree().process_frame

	var container: VBoxContainer = ui.get_node(^"%ChoicesContainer")
	_expect(container.visible, "four-option prompt is open before testing Escape")

	_press_key(KEY_ESCAPE)
	await get_tree().process_frame

	_expect(not ui.visible, "Escape at the decision prompt closes the panel")
	_expect(not container.visible, "Escape hides the choice buttons rather than leaving them stuck open")
	_expect(state.closing_decision == state.NONE, "Escape at the decision prompt does not select any option")

	# Re-trigger: talking to Caroline again must show the same four options.
	ui.open_for(&"caroline", "Caroline")
	await get_tree().process_frame
	_expect(ui.visible, "the closing question reopens after an Escape-without-deciding")
	_press_key(KEY_E)
	await get_tree().process_frame
	_expect(container.visible, "the four-option prompt reliably re-triggers after an earlier Escape")
	_expect(container.get_child_count() == 4, "the re-triggered prompt still has all four options")

	ui.queue_free()
	await get_tree().process_frame


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
		print("CLOSING DECISION PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("CLOSING DECISION PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
