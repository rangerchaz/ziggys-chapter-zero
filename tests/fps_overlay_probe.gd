## Phase 16 FPS overlay probe, runnable headless:
##
##     godot --headless --path . res://tests/fps_overlay_probe.tscn
##
## Verifies the debug overlay starts hidden (so it never appears in an
## ordinary playthrough or screenshot), the debug_fps_overlay key (F3)
## toggles it on and back off, and the label text updates to a live
## "N fps  N.N ms" reading while visible. Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var room: Node3D = RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	await _settle_seconds(0.3)

	var overlay: Control = room.get_node(^"UI/FpsOverlay")
	if overlay == null:
		_fail("Room has no UI/FpsOverlay node")
		room.queue_free()
		return

	if overlay.visible:
		_fail("FPS overlay is visible by default; it should start hidden")

	_press_key(KEY_F3)
	await _settle_seconds(0.2)
	if not overlay.visible:
		_fail("F3 did not show the FPS overlay")
	else:
		await _settle_seconds(0.2)
		var label: Label = overlay.get_node(^"%FpsLabel")
		if label == null:
			_fail("FPS overlay has no FpsLabel")
		elif not label.text.contains("fps") or not label.text.contains("ms"):
			_fail("FPS overlay label doesn't read as a fps/ms readout: '%s'" % label.text)

	_press_key(KEY_F3)
	await _settle_seconds(0.2)
	if overlay.visible:
		_fail("F3 did not hide the FPS overlay again")

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
		print("FPS OVERLAY PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("FPS OVERLAY PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
