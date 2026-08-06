## Sprint 2 smoke test, runnable headless:
##
##     godot --headless --path . res://tests/smoke_test.tscn
##
## Checks the GameState autoload (Sprint 1 regression), the SettingsManager
## autoload (bus volumes applied via linear-to-db, values persisted to
## user://settings.cfg), the settings screen's controls driving the manager,
## and the full navigation chain: title -> Settings -> settings screen ->
## Escape -> title -> Start -> chapter entry. Exits 0 on pass, 1 on failure.
##
## Window resizing needs a real GPU context and is covered separately by
## res://tests/resolution_probe.tscn (run WITHOUT --headless).
extends Node

const TitleScreenScene := preload("res://scenes/ui/title_screen.tscn")
const SettingsScreenScene := preload("res://scenes/ui/settings_screen.tscn")

## Bus names map to unique node names in the settings scene.
const SLIDER_NODES := {
	&"Master": "%MasterSlider",
	&"Music": "%MusicSlider",
	&"SFX": "%SfxSlider",
	&"Ambient": "%AmbientSlider",
}

var _failures: Array[String] = []


func _ready() -> void:
	_check_game_state()
	_check_settings_manager()
	await _check_title_screen()
	await _check_settings_screen()
	await _trigger_navigation_flow()


func _fail(message: String) -> void:
	_failures.append(message)


func _check_game_state() -> void:
	# Looked up by path (not the GameState global) so this script also
	# compiles under `--check-only -s`, where autoloads are absent.
	var state: Node = get_node_or_null("/root/GameState")
	if state == null:
		_fail("GameState autoload is not reachable at /root/GameState")
		return

	if state.selected_meckie != state.NONE:
		_fail("selected_meckie default is %s, expected NONE" % state.selected_meckie)
	if state.brownout_fired != false:
		_fail("brownout_fired default is true, expected false")
	if state.closing_decision != state.NONE:
		_fail("closing_decision default is %s, expected NONE" % state.closing_decision)

	var received: Array = []
	var on_selected := func(meckie: StringName) -> void: received.append(meckie)
	state.meckie_selected.connect(on_selected)
	state.selected_meckie = &"droid"
	state.meckie_selected.disconnect(on_selected)
	if received != [&"droid"]:
		_fail("meckie_selected signal did not fire on assignment (got %s)" % [received])

	state.reset()
	if state.selected_meckie != state.NONE:
		_fail("reset() did not restore selected_meckie to NONE")


func _check_settings_manager() -> void:
	var settings: Node = get_node_or_null("/root/SettingsManager")
	if settings == null:
		_fail("SettingsManager autoload is not reachable at /root/SettingsManager")
		return

	# A slider value must land on the real audio bus, via linear-to-db.
	settings.set_volume(&"Music", 0.5)
	var music_index := AudioServer.get_bus_index("Music")
	if music_index < 0:
		_fail("Music bus is missing from the bus layout")
	else:
		var applied := db_to_linear(AudioServer.get_bus_volume_db(music_index))
		if absf(applied - 0.5) > 0.01:
			_fail("Music at 0.5 read back from AudioServer as %.4f" % applied)

	# Zero must be flat silence, not linear_to_db(0) = -inf.
	settings.set_volume(&"SFX", 0.0)
	var sfx_index := AudioServer.get_bus_index("SFX")
	if sfx_index >= 0 and AudioServer.get_bus_volume_db(sfx_index) > -79.0:
		_fail("SFX at 0.0 left bus at %.1f db, expected silence" % \
			AudioServer.get_bus_volume_db(sfx_index))

	# Every change must persist to user://settings.cfg immediately.
	settings.set_resolution(Vector2i(1600, 900))
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		_fail("user://settings.cfg was not written after a settings change")
	else:
		var stored_music: Variant = cfg.get_value("audio", "Music", null)
		if stored_music == null or absf(float(stored_music) - 0.5) > 0.001:
			_fail("settings.cfg stored Music as %s, expected 0.5" % [stored_music])
		var stored_res: Variant = cfg.get_value("display", "resolution", null)
		if stored_res != Vector2i(1600, 900):
			_fail("settings.cfg stored resolution as %s, expected (1600, 900)" % [stored_res])


func _check_title_screen() -> void:
	var title: Control = TitleScreenScene.instantiate()
	add_child(title)
	await get_tree().process_frame

	var start: Button = title.get_node_or_null("%StartButton")
	var settings: Button = title.get_node_or_null("%SettingsButton")
	var quit: Button = title.get_node_or_null("%QuitButton")

	if start == null or not start.visible:
		_fail("StartButton is missing or hidden")
	elif start.pressed.get_connections().is_empty():
		_fail("StartButton pressed signal is not connected")

	if settings == null or not settings.visible or settings.disabled:
		_fail("SettingsButton must be visible and enabled in Sprint 2")
	elif settings.pressed.get_connections().is_empty():
		_fail("SettingsButton pressed signal is not connected")

	if quit == null or not quit.visible:
		_fail("QuitButton is missing or hidden")
	elif quit.pressed.get_connections().is_empty():
		_fail("QuitButton pressed signal is not connected")

	title.queue_free()
	await get_tree().process_frame


func _check_settings_screen() -> void:
	var manager: Node = get_node_or_null("/root/SettingsManager")
	if manager == null:
		return  # Already reported by _check_settings_manager.

	var screen: Control = SettingsScreenScene.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var option: OptionButton = screen.get_node_or_null("%ResolutionOption")
	if option == null:
		_fail("Settings screen has no ResolutionOption")
	else:
		if option.item_count != manager.RESOLUTIONS.size():
			_fail("ResolutionOption offers %d entries, expected %d" % \
				[option.item_count, manager.RESOLUTIONS.size()])
		var expected_index: int = manager.RESOLUTIONS.find(manager.resolution)
		if option.selected != expected_index:
			_fail("ResolutionOption selected %d, expected %d for %s" % \
				[option.selected, expected_index, manager.resolution])
		# Picking an entry must land on the manager (window ops are skipped
		# headless, but the value and the cfg file still change).
		option.item_selected.emit(0)
		if manager.resolution != manager.RESOLUTIONS[0]:
			_fail("Selecting resolution 0 left manager at %s" % manager.resolution)

	var toggle: Button = screen.get_node_or_null("%FullscreenToggle")
	if toggle == null:
		_fail("Settings screen has no FullscreenToggle")
	else:
		toggle.button_pressed = true
		if not manager.fullscreen:
			_fail("Fullscreen toggle did not reach the manager")
		toggle.button_pressed = false
		if manager.fullscreen:
			_fail("Fullscreen toggle did not switch back to windowed")

	for bus_name: StringName in manager.VOLUME_BUSES:
		var slider_name: String = SLIDER_NODES[bus_name]
		var slider: HSlider = screen.get_node_or_null(slider_name)
		if slider == null:
			_fail("Settings screen has no slider for the %s bus" % bus_name)
			continue
		if absf(slider.value - manager.get_volume(bus_name)) > 0.005:
			_fail("%s slider shows %.2f, manager holds %.2f" % \
				[bus_name, slider.value, manager.get_volume(bus_name)])

	# Dragging a slider must move the real bus and the readout label.
	var ambient_slider: HSlider = screen.get_node_or_null("%AmbientSlider")
	var ambient_value: Label = screen.get_node_or_null("%AmbientValue")
	if ambient_slider != null:
		ambient_slider.value = 0.25
		var ambient_index := AudioServer.get_bus_index("Ambient")
		var applied := db_to_linear(AudioServer.get_bus_volume_db(ambient_index))
		if absf(applied - 0.25) > 0.01:
			_fail("Ambient slider at 0.25 read back from AudioServer as %.4f" % applied)
		if ambient_value != null and ambient_value.text != "25%":
			_fail("Ambient readout shows '%s', expected '25%%'" % ambient_value.text)

	var back: Button = screen.get_node_or_null("%BackButton")
	if back == null:
		_fail("Settings screen has no BackButton")
	elif back.pressed.get_connections().is_empty():
		_fail("BackButton pressed signal is not connected")

	screen.queue_free()
	await get_tree().process_frame


func _trigger_navigation_flow() -> void:
	# The reporter lives on /root so it survives the scene changes the
	# navigation chain causes; this test scene itself gets freed by them.
	var reporter := Reporter.new()
	reporter.failures = _failures.duplicate()
	get_tree().root.add_child.call_deferred(reporter)
	await get_tree().process_frame

	var title: Control = TitleScreenScene.instantiate()
	add_child(title)
	await get_tree().process_frame
	var settings_button: Button = title.get_node("%SettingsButton")
	settings_button.pressed.emit()


class Reporter:
	extends Node

	var failures: Array[String] = []

	func _ready() -> void:
		await _settle(30)
		var current := get_tree().current_scene
		if current == null or current.name != "SettingsScreen":
			failures.append("Settings landed on '%s', expected 'SettingsScreen'" % _name_of(current))
			_report()
			return

		# Escape must return to the title, not quit or crash.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		Input.parse_input_event(esc)
		await _settle(30)
		current = get_tree().current_scene
		if current == null or current.name != "TitleScreen":
			failures.append("Escape landed on '%s', expected 'TitleScreen'" % _name_of(current))
			_report()
			return

		var start: Button = current.get_node_or_null("%StartButton")
		if start == null:
			failures.append("Title screen rebuilt without a StartButton")
		else:
			start.pressed.emit()
			await _settle(30)
			current = get_tree().current_scene
			if current == null or current.name != "ZiggysRoom":
				failures.append("Start landed on '%s', expected 'ZiggysRoom'" % _name_of(current))
		_report()

	func _settle(frames: int) -> void:
		for i in frames:
			await get_tree().process_frame

	func _name_of(node: Node) -> String:
		return "null" if node == null else String(node.name)

	func _report() -> void:
		if failures.is_empty():
			print("SMOKE TEST PASS")
			get_tree().quit(0)
		else:
			for failure in failures:
				printerr("FAIL: " + failure)
			printerr("SMOKE TEST FAIL (%d failures)" % failures.size())
			get_tree().quit(1)
