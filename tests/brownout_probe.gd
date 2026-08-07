## Phase 11 probe, runnable headless:
##
##     godot --headless --path . res://tests/brownout_probe.tscn
##
## Drives the real room and a real player through both trigger paths for
## the brownout beat - the debug_brownout key (F9) and completing three
## distinct NPCs' conversations - and checks the deterministic mechanics:
## GameState.brownout_fired flips exactly once, the warm rig fades to
## dark while the cold exterior wash is untouched (or boosted), the
## ambient bed ducks to low_hum, camera sway / chromatic aberration ramp
## up then ease back down, and firing twice (debug key spam, or a fourth
## conversation) never restarts or double-applies the beat. Exits 0 on
## pass, 1 on failure. Visual/audio confirmation is windowed-only, see
## qa_phase11_probe.tscn / beat_runner_render_probe.tscn - this probe is
## state and timing only.
##
## Phase 2: BrownoutDirector no longer self-triggers - the debug key falls
## through BeatRunner (which force-fires the room's next pending lighting
## beat, or the brownout sequence directly when no chapter is loaded, see
## beat_runner.gd's _debug_force_brownout()), and the conversation-count
## trigger is driven by loading content/chapters/fixture-beatrunner.json
## into the room's own BeatRunner rather than emitting straight at
## BrownoutDirector.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const PlayerScene := preload("res://scenes/characters/meckie_player.tscn")

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

	await _check_debug_key_trigger(state)
	state.reset()
	await _check_conversation_trigger(state)
	state.reset()


## Debug key path: F9 fires the beat instantly, independent of any
## dialogue. Checks the full mechanics list against this path since it is
## the fastest to drive deterministically in a headless run.
func _check_debug_key_trigger(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.meckie_id = &"droid"
	add_child(player)
	for i in 8:
		await get_tree().physics_frame

	var bd: Node = room.get_node(^"BrownoutDirector")
	var audio: Node = get_node(^"/root/AudioDirector")
	var exterior: Light3D = room.get_node(^"DataCenterWash")
	var sway: Node = get_tree().get_first_node_in_group(&"camera_sway")
	var aberration: Node = room.get_node(^"PostProcess/ChromaticAberration")

	_expect(not state.brownout_fired, "brownout_fired starts false")
	_expect(sway != null, "player camera registered in 'camera_sway' group")
	_expect(aberration.intensity == 0.0, "chromatic aberration starts at 0 intensity")

	var warm_before := _warm_energy_sum()
	_expect(warm_before > 0.0, "warm lights start lit (sum energy %.2f)" % warm_before)
	var exterior_before := exterior.light_energy

	var fired_signal := [false]
	bd.brownout_started.connect(func() -> void: fired_signal[0] = true)

	# Simulate the real debug key (F9), not a direct fire() call, so this
	# covers the actual player-facing input path end to end. GOTCHA: input
	# dispatch to _unhandled_input is not reliably caught up within a small
	# fixed count of physics_frame ticks headless (physics and idle frames
	# are not 1:1) - settle by elapsed idle time instead, generously, same
	# as every other wait in this probe.
	var settle_before_check := maxf(bd.effect_attack * 0.4, 0.3)
	_press_key(KEY_F9)
	await _settle_seconds(settle_before_check)

	_expect(fired_signal[0], "brownout_started signal fired from the debug key")
	_expect(state.brownout_fired, "GameState.brownout_fired is true shortly after fire")

	# Sampled partway through the (shorter) effect attack, well before the
	# light fade completes: sway/aberration should already be mid-ramp.
	_expect(sway.intensity > 0.0 and sway.intensity < 1.0,
			"camera sway is ramping (early intensity %.3f)" % sway.intensity)
	_expect(aberration.intensity > 0.0 and aberration.intensity < 1.0,
			"chromatic aberration is ramping (early intensity %.3f)" % aberration.intensity)

	# Mid-fade: gradual, not an instant cut. Sample partway through
	# fade_duration (2.0s default) and expect a partially-dimmed rig.
	await _settle_seconds(maxf(bd.fade_duration * 0.5 - settle_before_check, 0.1))
	var warm_mid := _warm_energy_sum()
	_expect(warm_mid < warm_before * 0.85 and warm_mid > warm_before * 0.05,
			"mid-fade warm energy is partial, not instant (before %.2f, mid %.2f)" \
			% [warm_before, warm_mid])

	# Past the fade: dark window. Warm rig at (near) zero, exterior wash
	# untouched or boosted, audio ducked, effects at peak.
	await _settle_seconds(bd.fade_duration * 0.5 + 0.1)
	var warm_dark := _warm_energy_sum()
	_expect(warm_dark < warm_before * 0.02,
			"warm rig is effectively dark after the fade (got %.4f of %.2f)" \
			% [warm_dark, warm_before])
	_expect(exterior.light_energy >= exterior_before,
			"exterior wash is untouched or boosted, never dimmed (%.2f -> %.2f)" \
			% [exterior_before, exterior.light_energy])
	_expect(audio.current_state == &"low_hum",
			"AudioDirector ducked to low_hum in sync with the fade")
	_expect(is_equal_approx(sway.intensity, 1.0) or sway.intensity > 0.9,
			"camera sway is at (near) peak during the dark window (%.3f)" % sway.intensity)
	_expect(aberration.intensity > 0.9,
			"chromatic aberration is at (near) peak during the dark window (%.3f)" % aberration.intensity)

	# Past the hold + release window: sway/aberration ease back, lights
	# stay out (documented recovery choice: no relight this chapter).
	await _settle_seconds(bd.effect_hold + bd.effect_release + 0.2)
	_expect(sway.intensity < 0.1, "camera sway eased back after the beat (%.3f)" % sway.intensity)
	_expect(aberration.intensity < 0.1,
			"chromatic aberration eased back after the beat (%.3f)" % aberration.intensity)
	_expect(_warm_energy_sum() < warm_before * 0.02,
			"warm rig stays dark after the effects settle (documented: no relight)")

	# Idempotency: a second debug key press must not restart the beat,
	# re-fire the signal, or perturb the settled state.
	fired_signal[0] = false
	_press_key(KEY_F9)
	await _settle_seconds(0.3)
	_expect(not fired_signal[0], "a second debug key press does not re-fire brownout_started")
	_expect(state.brownout_fired, "brownout_fired remains true after a repeat trigger")

	room.queue_free()
	player.queue_free()
	await get_tree().process_frame


## Conversation-completion path: three distinct NPCs' DialogueUI
## conversation_completed emissions fire the beat with no debug key
## involved; a repeat completion for an already-counted NPC, or one that
## closes early (never emitted here), must not count. Phase 2: this now
## goes through the room's BeatRunner, loaded with
## content/chapters/fixture-beatrunner.json - the same [ambience(warm)
## on_start, lighting(brownout) after 3 conversations] shape acceptance
## criterion 1 specifies - rather than emitting straight at
## BrownoutDirector, which no longer listens for it itself.
func _check_conversation_trigger(state: Node) -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	for i in 4:
		await get_tree().physics_frame

	var runner: Node = room.get_node(^"BeatRunner")
	var dialogue: Control = room.get_node(^"UI/DialogueUI")
	runner.start("fixture-beatrunner")
	_expect(runner.has_fired("settle"), "the on_start ambience beat fires immediately on start()")

	dialogue.conversation_completed.emit(&"caroline")
	await get_tree().process_frame
	_expect(not state.brownout_fired, "1 of 3 distinct conversations does not fire the beat")

	dialogue.conversation_completed.emit(&"caroline")
	await get_tree().process_frame
	_expect(not state.brownout_fired,
			"repeating the same NPC's conversation does not count as a second distinct one")

	dialogue.conversation_completed.emit(&"chad")
	await get_tree().process_frame
	_expect(not state.brownout_fired, "2 of 3 distinct conversations does not fire the beat")

	dialogue.conversation_completed.emit(&"oleg")
	await get_tree().process_frame
	_expect(state.brownout_fired, "3rd distinct completed conversation fires the beat")
	_expect(runner.has_fired("the_call"), "BeatRunner marks the lighting beat as fired")

	# Idempotency: a 4th distinct conversation must not re-fire the beat.
	dialogue.conversation_completed.emit(&"nic")
	await get_tree().process_frame
	_expect(state.brownout_fired, "a 4th distinct conversation leaves brownout_fired true (still, not re-flipped)")

	room.queue_free()
	await get_tree().process_frame


func _warm_energy_sum() -> float:
	var total := 0.0
	for node in LightRegistry.get_warm_lights(get_tree()):
		if node is Light3D:
			total += (node as Light3D).light_energy
		elif node is GeometryInstance3D and "material" in node:
			var mat: Material = node.material
			if mat is StandardMaterial3D:
				total += (mat as StandardMaterial3D).emission_energy_multiplier
	return total


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
		print("BROWNOUT PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("BROWNOUT PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
