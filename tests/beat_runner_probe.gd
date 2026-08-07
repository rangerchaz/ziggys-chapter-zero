## Phase 2 probe, runnable headless:
##
##     godot --headless --path . res://tests/beat_runner_probe.tscn
##
## Exercises BeatRunner's sequencing/trigger engine directly: an on_start
## beat fires the instant it's reached, an `after: {conversations: N}`
## beat waits for N distinct conversations, an `after: {conversations: N,
## since: <beat_id>}` beat only starts counting once the named beat has
## fired (acceptance criterion 3), and firing the same lighting beat twice
## - via a further matching conversation or a repeated debug key press -
## is a no-op (acceptance criterion 2). State/timing only; the visual/
## audio result of the brownout sequence itself is covered by
## brownout_probe.gd and (windowed) beat_runner_render_probe.tscn.
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
	state.reset()
	await _check_since_trigger(state)
	state.reset()
	await _check_debug_key_idempotent_and_fallback(state)
	state.reset()


## Synthetic beats (not from a content file) so the `since` semantics can
## be checked in isolation: beat 'b' fires after 1 conversation from
## start; beat 'c' needs 1 conversation but only counting *after* 'b'
## fired. If `since` were implemented as "1 distinct conversation from
## chapter start" instead, 'c' would incorrectly fire in lockstep with 'b'
## on the very same conversation that satisfies 'b'.
func _check_since_trigger(state: Node) -> void:
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

	var beats: Array = [
		{"id": "a", "kind": "ambience", "preset": "warm"},
		{"id": "b", "kind": "lighting", "preset": "brownout", "after": {"conversations": 1}},
		{"id": "c", "kind": "ambience", "preset": "cold", "after": {"conversations": 1, "since": "b"}},
	]
	runner.load_beats(beats)

	_expect(runner.has_fired("a"), "on_start beat 'a' fires the instant load_beats() runs")
	_expect(not runner.has_fired("b"), "beat 'b' (needs 1 conversation) has not fired yet")
	_expect(not runner.has_fired("c"), "beat 'c' (since 'b') has not fired yet")

	dialogue.conversation_completed.emit(&"caroline")
	await get_tree().process_frame
	_expect(runner.has_fired("b"), "1st distinct conversation fires beat 'b'")
	_expect(state.brownout_fired, "firing 'b' (lighting: brownout) sets GameState.brownout_fired")
	_expect(not runner.has_fired("c"),
			"beat 'c' has NOT fired yet: the conversation that satisfied 'b' must not also count for 'since: b'")

	dialogue.conversation_completed.emit(&"chad")
	await get_tree().process_frame
	_expect(runner.has_fired("c"),
			"a conversation completed AFTER 'b' fired satisfies 'c's since-scoped trigger")

	runner.queue_free()
	room.queue_free()
	await get_tree().process_frame


## Debug key path: force-fires the current chapter's next pending lighting
## beat; a second press once it has already fired is a no-op (no restarted
## tween, no second brownout_started emission). Also checks the no-chapter
## fallback (BeatRunner's default chapter_id is "" in the shipped room) so
## F9 still works for scenes with no chapter wired up yet.
func _check_debug_key_idempotent_and_fallback(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var runner: Node = room.get_node(^"BeatRunner")
	var bd: Node = room.get_node(^"BrownoutDirector")
	_expect(runner.chapter_id == "", "shipped room's BeatRunner has no chapter wired up by default")

	var fire_count := [0]
	bd.brownout_started.connect(func() -> void: fire_count[0] += 1)

	_press_key(KEY_F9)
	await _settle_seconds(0.2)
	_expect(fire_count[0] == 1, "F9 with no chapter loaded falls back to firing brownout directly (got %d fires)" % fire_count[0])
	_expect(state.brownout_fired, "GameState.brownout_fired is true after the fallback fire")

	_press_key(KEY_F9)
	await _settle_seconds(0.2)
	_expect(fire_count[0] == 1, "a second F9 press does not re-fire brownout_started (still %d)" % fire_count[0])

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
		print("BEAT RUNNER PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("BEAT RUNNER PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
