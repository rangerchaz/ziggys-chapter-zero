## Phase 2 windowed QA probe, acceptance criterion 1. Needs a real GPU
## window, so run WITHOUT --headless:
##
##     godot --path . res://tests/beat_runner_render_probe.tscn
##
## Loads content/chapters/fixture-beatrunner.json - [ambience(warm)
## on_start, lighting(brownout) after 3 conversations] - into the real
## room's BeatRunner, then completes 3 distinct NPCs' conversations (no
## debug key) and screenshots the same before/mid-fade/dark-window moments
## qa_phase11_probe.tscn checks for the old F9-driven path, with the same
## warm/cold pixel thresholds, to prove BeatRunner's organic trigger
## reproduces the identical visual/audio result. Saves to
## tests/artifacts/qa/phase2/. Exits 0 only if every check passes.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase2"

var _frames := 0
var _elapsed := 0.0
var _fired_at := -1.0
var _room: Node3D
var _runner: Node
var _bd: Node
var _dialogue: Control
var _before_warm := 0.0
var _ok := true
var _talked := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.reset()
	_room = RoomScene.instantiate()
	_room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(_room)
	_runner = _room.get_node(^"BeatRunner")
	_bd = _room.get_node(^"BrownoutDirector")
	_dialogue = _room.get_node(^"UI/DialogueUI")


func _process(delta: float) -> void:
	_frames += 1

	# CSG build / shader compile stalls the first several dozen frames
	# regardless of the beat - settle at a real framerate before trusting
	# any screenshot or timing (same lesson as Phase 10/11's probes).
	if _frames < 90:
		return
	if _frames == 90:
		_runner.start("fixture-beatrunner")
		var before := _shot_and_measure("before_beat.png", "before beat")
		_before_warm = before["warm"]
		_ok = _ok and before["warm"] > 4.0 and before["cold"] > 0.8
		_ok = _ok and _runner.has_fired("settle")
		return
	if _frames == 91:
		_dialogue.conversation_completed.emit(&"caroline")
		_dialogue.conversation_completed.emit(&"chad")
		_dialogue.conversation_completed.emit(&"oleg")
		_talked = true
		_fired_at = 0.0
		return

	if not _talked:
		return
	_fired_at += delta

	if _fired_at >= _bd.fade_duration * 0.5 and _fired_at - delta < _bd.fade_duration * 0.5:
		var mid := _shot_and_measure("mid_fade.png", "mid-fade")
		var mid_warm: float = mid["warm"]
		var partial: bool = mid_warm < _before_warm * 0.85 and mid_warm > _before_warm * 0.05
		_ok = _ok and partial
		print("  mid-fade partial dim check: %s (%.2f%% of baseline %.2f%%)" \
				% ["ok" if partial else "FAIL", mid_warm, _before_warm])

	if _fired_at >= _bd.fade_duration + 0.3 and _fired_at - delta < _bd.fade_duration + 0.3:
		var dark := _shot_and_measure("dark_window.png", "dark window")
		var dark_warm: float = dark["warm"]
		var dark_cold: float = dark["cold"]
		var unmistakable: bool = dark_warm < 0.5 and dark_cold > 0.8
		_ok = _ok and unmistakable
		print("  dark-window unmistakable check: %s" % ("ok" if unmistakable else "FAIL"))
		_check_audio()

	if _fired_at >= _bd.fade_duration + _bd.effect_hold + _bd.effect_release + 0.3:
		_shot_and_measure("after_settle.png", "settled")
		_report()


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
	_ok = _ok and flag_ok and _runner.has_fired("the_call")
	print("GameState.brownout_fired: %s, BeatRunner fired 'the_call': %s" % [flag_ok, _runner.has_fired("the_call")])
	if _ok:
		print("BEAT RUNNER RENDER PROBE PASS")
		get_tree().quit(0)
	else:
		printerr("BEAT RUNNER RENDER PROBE FAIL")
		get_tree().quit(1)
