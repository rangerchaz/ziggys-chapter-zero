## Phase 6 probe, runnable headless:
##
##     godot --headless --path . res://tests/phase6_probe.tscn
##
## Covers the selection screen and the idle Meckies:
##   1. the selection screen offers three cards labelled and colored from
##      MeckieDefs, picking one writes GameState.selected_meckie and fires
##      meckie_chosen, and Escape fires back_requested,
##   2. with Eva selected, the room spawns an Eva player at the Eva marker
##      plus Droid and Sid idles at theirs, with matching signature colors
##      and cast lights,
##   3. over a simulated observation window both idles visibly move and
##      their accent glow varies, they never sit on the player's transform,
##      and they stay near their own markers,
##   4. a fresh run with Sid selected produces a Sid player and a
##      Droid + Eva idle pair.
## Exits 0 on pass, 1 on failure.
extends Node

const SelectScene := preload("res://scenes/ui/meckie_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

## ~6 simulated seconds at 60 physics FPS; plenty for at least one wander
## leg given the idle controller's short first pause.
const OBSERVE_FRAMES := 360
const SAMPLE_EVERY := 20

var _failures: Array[String] = []


func _ready() -> void:
	await _check_selection_screen()
	await _check_room(&"eva", [&"droid", &"sid"], true)
	await _check_room(&"sid", [&"droid", &"eva"], false)
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _check_selection_screen() -> void:
	var state: Node = get_node(^"/root/GameState")
	state.reset()

	var screen: Control = SelectScene.instantiate()
	screen.change_scenes = false
	add_child(screen)
	await get_tree().process_frame

	var buttons := {
		&"droid": screen.get_node_or_null("%DroidButton"),
		&"eva": screen.get_node_or_null("%EvaButton"),
		&"sid": screen.get_node_or_null("%SidButton"),
	}
	for id: StringName in buttons:
		var button: Button = buttons[id]
		if button == null or not button.visible:
			_fail("Selection screen is missing a visible card for %s" % id)
			continue
		var name_label: Label = button.get_node_or_null(^"Card/NameLabel")
		if name_label == null:
			_fail("%s card has no name label" % id)
			continue
		if name_label.text != MeckieDefs.display_name_of(id):
			_fail("%s card is labelled '%s', expected '%s'" % \
					[id, name_label.text, MeckieDefs.display_name_of(id)])
		var label_color := name_label.get_theme_color(&"font_color")
		if not label_color.is_equal_approx(MeckieDefs.color_of(id)):
			_fail("%s card name is not in the signature color" % id)
		if button.pressed.get_connections().is_empty():
			_fail("%s card pressed signal is not connected" % id)

	if buttons[&"eva"] == null:
		screen.queue_free()
		await get_tree().process_frame
		return

	# Picking a card must land on GameState and fire meckie_chosen.
	var chosen: Array = []
	screen.meckie_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	buttons[&"eva"].pressed.emit()
	if chosen != [&"eva"]:
		_fail("Pressing the Eva card fired meckie_chosen %s, expected [eva]" % [chosen])
	if state.selected_meckie != &"eva":
		_fail("Pressing the Eva card left selected_meckie as '%s'" % state.selected_meckie)

	# Escape must request the way back to the title.
	var backed: Array = []
	screen.back_requested.connect(func() -> void: backed.append(true))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	var esc_up := InputEventKey.new()
	esc_up.keycode = KEY_ESCAPE
	esc_up.physical_keycode = KEY_ESCAPE
	esc_up.pressed = false
	Input.parse_input_event(esc_up)
	await get_tree().process_frame
	await get_tree().process_frame
	if backed.is_empty():
		_fail("Escape on the selection screen did not fire back_requested")

	screen.queue_free()
	await get_tree().process_frame
	state.reset()


func _check_room(choice: StringName, idle_ids: Array, observe: bool) -> void:
	var state: Node = get_node(^"/root/GameState")
	state.selected_meckie = choice

	var room: Node3D = RoomScene.instantiate()
	add_child(room)
	for i in 14:
		await get_tree().physics_frame

	var player: CharacterBody3D = null
	var idles: Array = []
	for child in room.get_children():
		if child is MeckiePlayerController:
			player = child
		elif child is MeckieIdleController:
			idles.append(child)

	if player == null:
		_fail("[%s run] no player-controlled Meckie spawned" % choice)
	elif player.meckie_id != choice:
		_fail("[%s run] player is %s, expected %s" % [choice, player.meckie_id, choice])

	if idles.size() != 2:
		_fail("[%s run] expected 2 idle Meckies, found %d" % [choice, idles.size()])
	else:
		var found_ids: Array = [idles[0].meckie_id, idles[1].meckie_id]
		found_ids.sort()
		var expected := idle_ids.duplicate()
		expected.sort()
		if found_ids != expected:
			_fail("[%s run] idle pair is %s, expected %s" % [choice, found_ids, expected])

	for idle: CharacterBody3D in idles:
		var id: StringName = idle.meckie_id
		var color: Color = MeckieDefs.color_of(id)
		if not idle.signature_color.is_equal_approx(color):
			_fail("[%s run] idle %s does not wear its signature color" % [choice, id])
		var light: OmniLight3D = idle.get_node_or_null(^"SignatureLight")
		if light == null:
			_fail("[%s run] idle %s has no SignatureLight" % [choice, id])
		elif not light.light_color.is_equal_approx(color):
			_fail("[%s run] idle %s cast light is not its signature color" % [choice, id])
		var marker: Marker3D = room.get_node_or_null(
				"Markers/MeckieSpawns/MeckieSpawn" + MeckieDefs.display_name_of(id))
		if marker != null \
				and idle.global_position.distance_to(marker.global_position) > 0.5:
			_fail("[%s run] idle %s did not spawn at its marker (at %s)" % \
					[choice, id, idle.global_position])

	if observe and player != null and idles.size() == 2:
		await _observe_idles(player, idles, choice)

	room.queue_free()
	await get_tree().process_frame


## Watches the idle pair over a simulated window: both must visibly move,
## their glow must breathe, and neither may ever sit on the player.
func _observe_idles(player: CharacterBody3D, idles: Array, choice: StringName) -> void:
	var starts: Array = []
	var max_moved: Array = [0.0, 0.0]
	var min_energy: Array = [99.0, 99.0]
	var max_energy: Array = [-99.0, -99.0]
	var min_player_gap := 999.0
	for idle: CharacterBody3D in idles:
		starts.append(idle.global_position)

	for frame in OBSERVE_FRAMES:
		await get_tree().physics_frame
		if frame % SAMPLE_EVERY != 0:
			continue
		for i in idles.size():
			var idle: CharacterBody3D = idles[i]
			max_moved[i] = maxf(max_moved[i], idle.global_position.distance_to(starts[i]))
			min_energy[i] = minf(min_energy[i], idle.accent_energy)
			max_energy[i] = maxf(max_energy[i], idle.accent_energy)
			min_player_gap = minf(min_player_gap,
					idle.global_position.distance_to(player.global_position))

	for i in idles.size():
		var id: StringName = idles[i].meckie_id
		if max_moved[i] < 0.2:
			_fail("[%s run] idle %s barely moved over the observation (%.2f m)" % \
					[choice, id, max_moved[i]])
		if max_energy[i] - min_energy[i] < 0.15:
			_fail("[%s run] idle %s accent glow never varied" % [choice, id])
		var home: Vector3 = starts[i]
		if idles[i].global_position.distance_to(home) > 3.0:
			_fail("[%s run] idle %s wandered %.2f m from its marker" % \
					[choice, id, idles[i].global_position.distance_to(home)])
	if min_player_gap < 1.0:
		_fail("[%s run] an idle came within %.2f m of the player" % [choice, min_player_gap])


func _report() -> void:
	if _failures.is_empty():
		print("PHASE 6 PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PHASE 6 PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
