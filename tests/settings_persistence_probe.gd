## Relaunch-restore probe for Sprint 2, runnable headless AFTER any run
## that saved settings (the smoke test leaves non-default values behind):
##
##     godot --headless --path . res://tests/settings_persistence_probe.tscn
##
## This is a fresh process, so if whatever user://settings.cfg recorded is
## already live on the SettingsManager autoload and the audio buses by the
## time this scene's _ready runs, the settings survived a relaunch. Resets
## settings to defaults afterwards so repeated runs and real play sessions
## start clean. Exits 0 on pass, 1 on failure.
extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var settings: Node = get_node_or_null("/root/SettingsManager")
	if settings == null:
		_fail("SettingsManager autoload is not reachable at /root/SettingsManager")
	else:
		_check_boot_state_matches_file(settings)
		settings.reset_to_defaults()

	if _failures.is_empty():
		print("PERSISTENCE PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PERSISTENCE PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check_boot_state_matches_file(settings: Node) -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		_fail("user://settings.cfg does not exist; run the smoke test first")
		return

	for bus_name: String in ["Master", "Music", "SFX", "Ambient"]:
		var stored: Variant = cfg.get_value("audio", bus_name, null)
		if stored == null:
			_fail("settings.cfg has no volume for the %s bus" % bus_name)
			continue
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			_fail("%s bus is missing from the bus layout" % bus_name)
			continue
		var applied := db_to_linear(AudioServer.get_bus_volume_db(index))
		# A stored 0.0 boots as the -80 db silence floor, which reads back
		# as db_to_linear(-80) = 0.0001; compare against that floor.
		var expected := maxf(float(stored), 0.0001)
		if absf(applied - expected) > 0.01:
			_fail("%s: cfg stored %.2f but boot applied %.4f" % [bus_name, float(stored), applied])

	var stored_res: Variant = cfg.get_value("display", "resolution", null)
	if stored_res == null:
		_fail("settings.cfg has no resolution entry")
	elif settings.resolution != stored_res:
		_fail("cfg stored resolution %s but boot restored %s" % [stored_res, settings.resolution])

	var stored_fullscreen: Variant = cfg.get_value("display", "fullscreen", null)
	if stored_fullscreen == null:
		_fail("settings.cfg has no fullscreen entry")
	elif settings.fullscreen != bool(stored_fullscreen):
		_fail("cfg stored fullscreen=%s but boot restored %s" % [stored_fullscreen, settings.fullscreen])
