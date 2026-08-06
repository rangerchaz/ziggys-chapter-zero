## Sprint 1 smoke test, runnable headless:
##
##     godot --headless --path . res://tests/smoke_test.tscn
##
## Checks the GameState autoload defaults and signals, the title screen's
## structure (Start and Quit visible and wired, Settings hidden and disabled
## until Sprint 2), and that pressing Start actually lands in the chapter
## entry scene. Exits 0 on pass, 1 on any failure.
extends Node

const TitleScreenScene := preload("res://scenes/ui/title_screen.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_check_game_state()
	await _check_title_screen()
	await _trigger_start_flow()


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

	if quit == null or not quit.visible:
		_fail("QuitButton is missing or hidden")
	elif quit.pressed.get_connections().is_empty():
		_fail("QuitButton pressed signal is not connected")

	if settings == null:
		_fail("SettingsButton node is missing (Sprint 2 expects it in the scene)")
	elif settings.visible or not settings.disabled:
		_fail("SettingsButton must stay hidden and disabled until Sprint 2 wires it")

	title.queue_free()
	await get_tree().process_frame


func _trigger_start_flow() -> void:
	# The reporter lives on /root so it survives the scene change that
	# pressing Start causes; this test scene itself gets freed by it.
	var reporter := Reporter.new()
	reporter.failures = _failures.duplicate()
	get_tree().root.add_child.call_deferred(reporter)
	await get_tree().process_frame

	var title: Control = TitleScreenScene.instantiate()
	add_child(title)
	await get_tree().process_frame
	var start: Button = title.get_node("%StartButton")
	start.pressed.emit()


class Reporter:
	extends Node

	const EXPECTED_SCENE := "ZiggysRoom"

	var failures: Array[String] = []

	func _ready() -> void:
		for i in 30:
			await get_tree().process_frame
		var current := get_tree().current_scene
		if current == null:
			failures.append("No current scene after pressing Start")
		elif current.name != EXPECTED_SCENE:
			failures.append("Start landed on '%s', expected '%s'" % [current.name, EXPECTED_SCENE])

		if failures.is_empty():
			print("SMOKE TEST PASS")
			get_tree().quit(0)
		else:
			for failure in failures:
				printerr("FAIL: " + failure)
			printerr("SMOKE TEST FAIL (%d failures)" % failures.size())
			get_tree().quit(1)
