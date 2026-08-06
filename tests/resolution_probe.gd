## Live-resize probe for Sprint 2. Needs a real window and GPU context, so
## run WITHOUT --headless:
##
##     godot --path . res://tests/resolution_probe.tscn
##
## Steps through every resolution the settings screen offers, confirms the
## OS window actually takes that exact size (skipping sizes that do not fit
## the physical screen, with a note), round-trips the fullscreen toggle,
## then restores defaults. Exits 0 on pass, 1 on failure.
extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var settings: Node = get_node_or_null("/root/SettingsManager")
	if settings == null:
		printerr("FAIL: SettingsManager autoload missing")
		get_tree().quit(1)
		return

	var screen := DisplayServer.window_get_current_screen()
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(screen).size

	settings.set_fullscreen(false)
	await _frames(10)

	for size: Vector2i in settings.RESOLUTIONS:
		if size.x > usable.x or size.y > usable.y:
			print("SKIP %s: larger than usable screen area %s" % [size, usable])
			continue
		settings.set_resolution(size)
		await _frames(15)
		var actual := DisplayServer.window_get_size()
		if actual != size:
			_failures.append("asked for %s, window is %s" % [size, actual])
		else:
			print("OK window resized to %s" % size)

	settings.set_fullscreen(true)
	await _frames(90)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		_failures.append("fullscreen toggle did not enter fullscreen")
	else:
		print("OK fullscreen entered")

	settings.set_fullscreen(false)
	await _frames(90)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		_failures.append("fullscreen toggle did not return to windowed")
	else:
		print("OK back to windowed")

	settings.reset_to_defaults()
	await _frames(5)

	if _failures.is_empty():
		print("RESOLUTION PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("RESOLUTION PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
