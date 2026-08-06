## Phase 13 probe, runnable headless:
##
##     godot --headless --path . res://tests/closing_time_probe.tscn
##
## Drives the real room's ClosingTimeDirector through both trigger paths
## for reaching closing time - completing enough distinct post-brownout
## conversations, and the debug_closing_time key (F10) - and checks the
## deterministic mechanics: conversations completed before the brownout
## fires don't count, GameState.closing_time_reached flips exactly once,
## the debug key also fires the brownout first (via the real
## BrownoutDirector) if it hasn't happened yet so the two flags never end
## up out of sync, and firing twice (a second debug press, or a further
## conversation) never re-fires or re-triggers anything. Exits 0 on pass,
## 1 on failure.
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
	state.reset()

	await _check_conversation_trigger(state)
	state.reset()
	await _check_debug_key_fires_brownout_first(state)
	state.reset()
	await _check_debug_key_idempotent_once_reached(state)
	state.reset()


## Distinct post-brownout conversations reach closing time on their own;
## pre-brownout conversations (before the beat has fired) must not count,
## even if there are enough of them.
func _check_conversation_trigger(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var ctd: Node = room.get_node(^"ClosingTimeDirector")
	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	_expect(ctd.trigger_conversation_count == 3, "trigger_conversation_count defaults to 3 distinct conversations")

	# This test drives conversation_completed directly to control exactly
	# when the brownout flag flips, same as ClosingTimeDirector's own
	# _on_conversation_completed guard checks it - the real BrownoutDirector
	# living in this same room also listens to that signal and would
	# organically fire itself (and flip GameState.brownout_fired) after 3
	# distinct completions of its own, muddying which emit is "the one that
	# made brownout_fired true first". Pin it out of the way so this test
	# stays scoped to ClosingTimeDirector's own counting.
	var bd: Node = room.get_node(^"BrownoutDirector")
	bd.trigger_npc_count = 999

	dialogue.conversation_completed.emit(&"caroline")
	dialogue.conversation_completed.emit(&"chad")
	dialogue.conversation_completed.emit(&"oleg")
	await get_tree().process_frame
	_expect(not state.closing_time_reached,
			"3 distinct conversations before the brownout fires do not reach closing time")

	state.brownout_fired = true
	dialogue.conversation_completed.emit(&"ramsey")
	await get_tree().process_frame
	_expect(not state.closing_time_reached, "1 of 3 post-brownout conversations does not reach closing time")

	dialogue.conversation_completed.emit(&"ramsey")
	await get_tree().process_frame
	_expect(not state.closing_time_reached,
			"repeating the same NPC's post-brownout conversation does not count as a second distinct one")

	dialogue.conversation_completed.emit(&"nic")
	await get_tree().process_frame
	_expect(not state.closing_time_reached, "2 of 3 post-brownout conversations does not reach closing time")

	dialogue.conversation_completed.emit(&"conner")
	await get_tree().process_frame
	_expect(state.closing_time_reached, "3rd distinct post-brownout conversation reaches closing time")

	room.queue_free()
	await get_tree().process_frame


## The debug key jumps straight to closing time for QA even before the
## brownout has fired on its own - it fires the real BrownoutDirector
## first so the room's state stays consistent (lights/audio/camera match
## GameState.brownout_fired) rather than just flipping flags out of sync.
func _check_debug_key_fires_brownout_first(state: Node) -> void:
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

	room.queue_free()
	await get_tree().process_frame


## Once closing time has been reached, a second debug press (or the
## conversation trigger firing again) must not re-fire anything.
func _check_debug_key_idempotent_once_reached(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var bd: Node = room.get_node(^"BrownoutDirector")
	var fired_signal := [false]
	bd.brownout_started.connect(func() -> void: fired_signal[0] = true)

	_press_key(KEY_F10)
	await _settle_seconds(0.3)
	_expect(state.closing_time_reached, "closing time reached from the first debug key press")

	fired_signal[0] = false
	_press_key(KEY_F10)
	await _settle_seconds(0.2)
	_expect(not fired_signal[0], "a second debug key press does not re-fire the brownout beat")
	_expect(state.closing_time_reached, "closing_time_reached remains true after a repeat trigger")

	room.queue_free()
	await get_tree().process_frame


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
