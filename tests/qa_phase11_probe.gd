## Phase 11 windowed QA probe. Needs a real GPU window AND a real audio
## device, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase11_probe.tscn
##
## Fires the real brownout beat via the actual debug_brownout (F9) input
## path in the assembled room and screenshots three moments: before the
## beat (warm rig lit), mid-fade (proving the transition is gradual, not
## a one-frame cut), and the dark window (the room lit only by the cold
## #00d4ff exterior wash - the acceptance bar for "unmistakable in a
## single screenshot"). Reuses the room's own default Camera3D and the
## same warm/cold pixel-sampling thresholds as Phase 4's
## lighting_render_probe for a directly comparable read. Player auto-spawn
## is disabled so that fixed, already-tuned establishing camera stays
## current instead of a fresh MeckiePlayerController camera (same reason
## lighting_render_probe disables it). Also confirms AudioDirector ducked
## to low_hum in sync with the dark window. Saves to
## tests/artifacts/qa/phase11/. Exits 0 only if every visual/audio check
## passes.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase11"

var _frames := 0
var _elapsed := 0.0
var _fired_at := -1.0
var _room: Node3D
var _bd: Node
var _before_warm := 0.0
var _ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	_room = RoomScene.instantiate()
	_room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(_room)
	_bd = _room.get_node(^"BrownoutDirector")


func _process(delta: float) -> void:
	_frames += 1

	# CSG build / shader compile stalls the first several dozen frames
	# regardless of the beat - settle at a real framerate before trusting
	# any screenshot or timing (same lesson as Phase 10's probe).
	if _frames < 90:
		return
	if _frames == 90:
		var before := _shot_and_measure("before_beat.png", "before beat")
		_before_warm = before["warm"]
		_ok = _ok and before["warm"] > 4.0 and before["cold"] > 0.8
		_press_key(KEY_F9)
		_fired_at = 0.0
		return

	if _fired_at < 0.0:
		return
	_fired_at += delta

	if _fired_at >= _bd.fade_duration * 0.5 and _fired_at - delta < _bd.fade_duration * 0.5:
		var mid := _shot_and_measure("mid_fade.png", "mid-fade")
		# Gradual, not an instant cut: measurably dimmer than the baseline
		# but not yet at the dark-window floor.
		var mid_warm: float = mid["warm"]
		var partial: bool = mid_warm < _before_warm * 0.85 and mid_warm > _before_warm * 0.05
		_ok = _ok and partial
		print("  mid-fade partial dim check: %s (%.2f%% of baseline %.2f%%)" \
				% ["ok" if partial else "FAIL", mid_warm, _before_warm])

	if _fired_at >= _bd.fade_duration + 0.3 and _fired_at - delta < _bd.fade_duration + 0.3:
		var dark := _shot_and_measure("dark_window.png", "dark window")
		# Unambiguous: warm contribution effectively gone, cold wash still
		# reads clearly as the room's only light source.
		var dark_warm: float = dark["warm"]
		var dark_cold: float = dark["cold"]
		var unmistakable: bool = dark_warm < 0.5 and dark_cold > 0.8
		_ok = _ok and unmistakable
		print("  dark-window unmistakable check: %s" % ("ok" if unmistakable else "FAIL"))
		_check_audio()

	if _fired_at >= _bd.fade_duration + _bd.effect_hold + _bd.effect_release + 0.3:
		_shot_and_measure("after_settle.png", "settled")
		_report()


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


func _shot_and_measure(file_name: String, label: String) -> Dictionary:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false

	var warm := 0
	var cold := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c := image.get_pixel(x, y)
			total += 1
			if c.r > 0.22 and c.r > c.b * 1.5:
				warm += 1
			if c.b > 0.25 and c.b > c.r * 1.6 and c.g > c.r:
				cold += 1
	var warm_pct := 100.0 * warm / total
	var cold_pct := 100.0 * cold / total
	print("%s: warm %.2f%%, cold %.2f%% (saved %s)" % [label, warm_pct, cold_pct, file_name])
	return {"warm": warm_pct, "cold": cold_pct}


func _check_audio() -> void:
	var audio: Node = get_node(^"/root/AudioDirector")
	var duck_ok: bool = audio.current_state == &"low_hum"
	_ok = _ok and duck_ok
	if duck_ok:
		print("  AudioDirector ducked to low_hum in sync with the dark window: ok")
	else:
		printerr("  AudioDirector state is '%s', expected 'low_hum'" % audio.current_state)


func _report() -> void:
	var state: Node = get_node(^"/root/GameState")
	var flag_ok: bool = state.brownout_fired
	_ok = _ok and flag_ok
	print("GameState.brownout_fired: %s" % flag_ok)
	if _ok:
		print("QA PHASE 11 PROBE PASS")
		get_tree().quit(0)
	else:
		printerr("QA PHASE 11 PROBE FAIL")
		get_tree().quit(1)
