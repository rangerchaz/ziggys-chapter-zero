## Phase 15 probe, runnable headless:
##
##     godot --headless --path . res://tests/ui_state_machine_probe.tscn
##
## Exercises Escape at every reachable chapter state and checks
## UiStateMachine (the single project-wide Escape owner) always resolves
## it to exactly one sensible action:
##   - title: first Escape shows the quit-confirm plate, a second Escape
##     (not Quit) cancels back to the title rather than quitting
##   - selection: Escape fires back_requested
##   - in-room, nothing else open: Escape opens the pause menu and
##     freezes gameplay (get_tree().paused, movement input has no effect)
##   - pause open: Escape resumes and hands control back with no errors
##   - settings opened from pause: Escape returns to pause, not to the
##     title and not straight to resume
##   - dialogue open (including Caroline's closing-decision CHOICE mode):
##     Escape closes the dialogue WITHOUT also opening the pause menu on
##     the same press - the single-consumer guarantee - and without
##     recording a decision
##   - mid-brownout: pausing and resuming leaves the warm-light fade and
##     the audio duck exactly where they were (frozen while paused, not
##     jumped or corrupted), since both ride Tween.TWEEN_PAUSE_BOUND on a
##     node that is not process_mode ALWAYS
## Exits 0 on pass, 1 on failure.
extends Node

const TitleScene := preload("res://scenes/ui/title_screen.tscn")
const SelectScene := preload("res://scenes/ui/meckie_select.tscn")
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
	UiStateMachine.clear()
	await _check_title_quit_confirm()
	UiStateMachine.clear()
	await _check_selection_back()
	UiStateMachine.clear()
	await _check_room_flows()
	UiStateMachine.clear()


## First Escape at the title shows the quit-confirm plate rather than
## quitting outright; a second Escape while it's up cancels back to the
## title (Cancel/Quit are the only ways to leave it - both already
## covered by direct button wiring elsewhere, this is Escape's path).
func _check_title_quit_confirm() -> void:
	var title: Control = TitleScene.instantiate()
	add_child(title)
	await get_tree().process_frame

	var confirm: Control = title.get_node(^"%QuitConfirm")
	_expect(not confirm.visible, "title: quit-confirm starts hidden")
	_expect(UiStateMachine.active_context() == &"title", "title: 'title' context active on load")

	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_expect(confirm.visible, "title: first Escape shows the quit-confirm plate")
	_expect(UiStateMachine.active_context() == &"title_quit_confirm",
			"title: quit-confirm context takes over while shown")

	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_expect(not confirm.visible, "title: second Escape cancels the quit-confirm plate")
	_expect(UiStateMachine.active_context() == &"title", "title: back to the base 'title' context")
	_expect(is_instance_valid(self) and get_tree() != null,
			"title: Escape never actually quit the process")

	title.queue_free()
	await get_tree().process_frame


## Escape on the selection screen requests the way back to the title,
## same behavior phase6_probe.gd checks directly on the screen's own
## signal - this confirms it still holds true routed through
## UiStateMachine instead of a local _unhandled_input.
func _check_selection_back() -> void:
	var select: Control = SelectScene.instantiate()
	select.change_scenes = false
	var backed := [false]
	select.back_requested.connect(func() -> void: backed[0] = true)
	add_child(select)
	await get_tree().process_frame

	_expect(UiStateMachine.active_context() == &"selection", "selection: context active on load")
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_expect(backed[0], "selection: Escape fires back_requested")

	select.queue_free()
	await get_tree().process_frame


func _check_room_flows() -> void:
	var state: Node = get_node(^"/root/GameState")
	state.reset()

	var room: Node3D = RoomScene.instantiate()
	add_child(room)
	for i in 12:
		await get_tree().physics_frame
	await get_tree().process_frame  # PlayerSpawner's add_child is deferred.
	for i in 6:
		await get_tree().physics_frame

	var pause_menu: CanvasLayer = room.get_node(^"PauseMenu")
	var dialogue_ui: Control = room.get_node(^"UI/DialogueUI")
	var player: CharacterBody3D = null
	for child in room.get_children():
		if child is MeckiePlayerController:
			player = child
	_expect(player != null, "room: PlayerSpawner produced a real player")
	if player == null:
		return

	await _check_open_and_resume(room, pause_menu, player)
	await _check_settings_from_pause(pause_menu)
	await _check_dialogue_beats_pause(room, dialogue_ui, pause_menu)
	await _check_closing_decision_beats_pause(state, dialogue_ui, pause_menu)
	await _check_pause_mid_brownout(room, pause_menu)

	room.queue_free()
	await get_tree().process_frame


## Deliverable 1 + acceptance criterion 1: Escape in the room (nothing
## else open) opens the pause menu, freezes gameplay, and Resume hands
## control back cleanly.
func _check_open_and_resume(room: Node3D, pause_menu: CanvasLayer, player: CharacterBody3D) -> void:
	_expect(not pause_menu.visible and not get_tree().paused,
			"room: starts unpaused with the pause menu hidden")
	_expect(UiStateMachine.active_context() == &"room", "room: base 'room' context active")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(pause_menu.visible, "room: Escape opens the pause menu")
	_expect(get_tree().paused, "room: opening pause sets get_tree().paused")
	_expect(UiStateMachine.active_context() == &"pause", "room: 'pause' context takes over while open")

	var before: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	for i in 16:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	_expect(player.global_position.distance_to(before) < 0.001,
			"room: paused game does not move the player on held input")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(not pause_menu.visible, "room: Escape on the pause menu resumes (hides it)")
	_expect(not get_tree().paused, "room: resuming clears get_tree().paused")
	_expect(UiStateMachine.active_context() == &"room", "room: back to the base 'room' context")

	before = player.global_position
	Input.action_press(&"move_forward")
	for i in 16:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	_expect(player.global_position.distance_to(before) > 0.05,
			"room: resumed game responds to input again with no errors")


## Deliverable 2 + acceptance criterion 2: Settings reachable from pause,
## and Escape/Back from there returns to pause, not the title.
func _check_settings_from_pause(pause_menu: CanvasLayer) -> void:
	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(pause_menu.visible and get_tree().paused, "settings: pause open before requesting settings")

	var menu_root: Control = pause_menu.get_node(^"%MenuRoot")
	var settings_button: Button = pause_menu.get_node(^"%SettingsButton")
	settings_button.pressed.emit()
	await get_tree().process_frame

	_expect(not menu_root.visible, "settings: pause buttons hide while settings is open")
	_expect(UiStateMachine.active_context() == &"settings", "settings: 'settings' context takes over")
	var settings: Control = null
	for child in pause_menu.get_children():
		if child.has_method(&"_go_back"):
			settings = child
	_expect(settings != null and settings.return_target == &"pause",
			"settings: instance opened from pause carries return_target = &pause")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(menu_root.visible, "settings: Escape returns to the pause menu, not the title")
	_expect(get_tree().paused, "settings: still paused after returning from settings")
	_expect(UiStateMachine.active_context() == &"pause", "settings: 'pause' context active again")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(not get_tree().paused, "settings: leftover Escape resumes cleanly afterward")


## Deliverable 4 + acceptance criterion 5: a single Escape press while
## dialogue is open closes ONLY the dialogue, never also opening pause.
func _check_dialogue_beats_pause(room: Node3D, dialogue_ui: Control, pause_menu: CanvasLayer) -> void:
	_expect(not get_tree().paused and not pause_menu.visible,
			"dialogue: starts unpaused with pause menu hidden")
	dialogue_ui.open_for(&"chad", "Chad")
	await get_tree().process_frame
	_expect(dialogue_ui.visible, "dialogue: open_for shows the panel")
	_expect(UiStateMachine.active_context() == &"dialogue", "dialogue: 'dialogue' context takes over")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(not dialogue_ui.visible, "dialogue: Escape closes the dialogue")
	_expect(not pause_menu.visible and not get_tree().paused,
			"dialogue: the same Escape press did NOT also open the pause menu")
	_expect(UiStateMachine.active_context() == &"room", "dialogue: back to the base 'room' context")


## Deliverable 3 (closing decision) combined with the new pause system:
## Escape at Caroline's four-option prompt dismisses it without picking
## an answer and without opening pause on the same press.
func _check_closing_decision_beats_pause(state: Node, dialogue_ui: Control, pause_menu: CanvasLayer) -> void:
	# closing_time_reached alone (not brownout_fired) is what routes
	# open_for(&"caroline", ...) to the closing prompt - leaving
	# brownout_fired false here keeps _check_pause_mid_brownout's F9 press
	# a real first fire rather than a no-op against an already-fired beat.
	state.closing_time_reached = true
	state.closing_decision = state.NONE

	dialogue_ui.open_for(&"caroline", "Caroline")
	await get_tree().process_frame
	_press_key(KEY_E)
	await get_tree().process_frame
	_expect(dialogue_ui.get_node(^"%ChoicesContainer").visible,
			"closing decision: advancing the question reaches the four-option prompt")

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(not dialogue_ui.visible, "closing decision: Escape dismisses the prompt")
	_expect(state.closing_decision == state.NONE, "closing decision: Escape records no decision")
	_expect(not pause_menu.visible and not get_tree().paused,
			"closing decision: the same Escape press did NOT also open the pause menu")

	state.closing_decision = state.NONE  # leave it re-triggerable, matching closing_decision_probe


## Acceptance criterion 6: pausing while the brownout tween is mid-flight
## and resuming leaves the light fade / audio duck exactly where they
## were - frozen while paused, continuing (not jumping) after resume.
func _check_pause_mid_brownout(room: Node3D, pause_menu: CanvasLayer) -> void:
	var brownout: Node = room.get_node(^"BrownoutDirector")
	var aberration: Node = room.get_node(^"PostProcess/ChromaticAberration")
	var bed: Node = get_tree().get_first_node_in_group(&"ambient_bed")

	_press_key(KEY_F9)  # debug_brownout
	await _settle_seconds(brownout.effect_attack * 0.5)
	_expect(aberration.intensity > 0.0 and aberration.intensity < 1.0,
			"brownout: chromatic aberration is mid-ramp before pausing (%.3f)" % aberration.intensity)

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(pause_menu.visible and get_tree().paused, "brownout: Escape opens pause mid-fade")

	# Baselines are captured only now, once pause is confirmed in effect -
	# the Escape press itself needed a frame or two to be dispatched and
	# for get_tree().paused to take hold, and the tween kept advancing
	# (correctly) during that small gap.
	var aberration_before: float = aberration.intensity
	var bed_level_before: float = bed.level

	await _settle_seconds(0.4)
	_expect(absf(aberration.intensity - aberration_before) < 0.001,
			"brownout: aberration intensity does not advance while paused (%.4f -> %.4f)"
					% [aberration_before, aberration.intensity])
	_expect(absf(bed.level - bed_level_before) < 0.001,
			"brownout: audio duck level does not advance while paused (%.4f -> %.4f)"
					% [bed_level_before, bed.level])

	_press_key(KEY_ESCAPE)
	for i in 4:
		await get_tree().physics_frame
	_expect(not get_tree().paused, "brownout: Escape on the pause menu resumes")

	await _settle_seconds(0.3)
	_expect(aberration.intensity > aberration_before + 0.01,
			"brownout: aberration intensity resumes progressing after resume (%.4f -> %.4f)"
					% [aberration_before, aberration.intensity])
	_expect(aberration.intensity >= 0.0 and aberration.intensity <= 1.0,
			"brownout: aberration intensity stays in-range, not corrupted (%.4f)" % aberration.intensity)


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
		print("UI STATE MACHINE PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("UI STATE MACHINE PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
