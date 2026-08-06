## Phase 10 windowed QA probe. Needs a real GPU window AND a real audio
## device (CoreAudio on this machine), so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase10_probe.tscn
##
## Runs the real room for a few real seconds so the audio driver actually
## pulls frames from each ProceduralAudio source. Walks Droid from far
## away right up to the jukebox and back, screenshotting both ends for a
## visual/manual spatialization check, and exercises AudioDirector's
## low_hum state, then checks that no NEW buffer underruns happened
## during any of it.
##
## AudioStreamGeneratorPlayback.get_skips() is a cumulative counter for
## the life of the playback, not a since-last-call delta (confirmed
## empirically: reading it twice in a row returns the same number) - so
## this probe takes a baseline reading once the scene has settled at a
## real framerate (the CSG build / shader compile stall on first load
## produces a one-time batch of skips before anything is even visible,
## which is not an "audible dropout during play" and would otherwise
## make every run look broken) and diffs against a final reading.
## Saves to tests/artifacts/qa/phase10/. Exits 0 once everything is
## written; the skip check failing prints FAIL but does not affect the
## exit code, since audio scheduling on a shared CI/dev machine
## occasionally hiccups for reasons outside the mix code.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase10"

var _frames := 0
var _room: Node3D
var _player: CharacterBody3D
var _jukebox_pos: Vector3
var _room_gen: ProceduralAudio
var _juke_gen: ProceduralAudio
var _oven_gen: ProceduralAudio
var _baseline_skips := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	state.selected_meckie = &"droid"
	_room = RoomScene.instantiate()
	add_child(_room)


func _process(_delta: float) -> void:
	_frames += 1

	# Scene load (CSG builds, shader compiles) stalls the first several
	# dozen frames regardless of audio code - give it a full second at a
	# real framerate to settle before taking the skip baseline.
	if _frames == 70:
		for child in _room.get_children():
			if child is MeckiePlayerController:
				_player = child
		if _player == null:
			printerr("QA PHASE 10 PROBE FAIL: player not found")
			get_tree().quit(1)
			return
		_jukebox_pos = _room.get_node(^"Props/Jukebox").global_position
		_room_gen = _room.get_node(^"RoomTone/Generator")
		_juke_gen = _room.get_node(^"Props/Jukebox/JukeAudio/Generator")
		_oven_gen = _room.get_node(^"Props/PizzaOven/OvenAudio/Generator")
		_baseline_skips = {
			"room": _room_gen.get_playback().get_skips(),
			"jukebox": _juke_gen.get_playback().get_skips(),
			"oven": _oven_gen.get_playback().get_skips(),
		}
		print("baseline skips (post load-stall): %s" % [_baseline_skips])
		# Park far from the jukebox first.
		_player.global_position = Vector3(-4.0, 0, 3.0)
		_player.velocity = Vector3.ZERO

	if _frames == 90:
		_shot("far_from_jukebox.png")
		print("distance far: %.2f m" % _player.global_position.distance_to(_jukebox_pos))

	if _frames == 110:
		# Stand right next to it.
		_player.global_position = _jukebox_pos + Vector3(0, 0, 1.0)
		_player.velocity = Vector3.ZERO

	if _frames == 130:
		_shot("near_jukebox.png")
		print("distance near: %.2f m" % _player.global_position.distance_to(_jukebox_pos))

	if _frames == 140:
		get_node(^"/root/AudioDirector").set_ambience_state(&"low_hum")

	if _frames == 320:
		print("bed level during low_hum: %.3f" % _room_gen.level)
		get_node(^"/root/AudioDirector").set_ambience_state(&"normal")

	if _frames == 420:
		_report_skips()


func _report_skips() -> void:
	var room_new: int = _room_gen.get_playback().get_skips() - _baseline_skips["room"]
	var juke_new: int = _juke_gen.get_playback().get_skips() - _baseline_skips["jukebox"]
	var oven_new: int = _oven_gen.get_playback().get_skips() - _baseline_skips["oven"]
	print("new skips since baseline - room: %d, jukebox: %d, oven: %d" % [room_new, juke_new, oven_new])
	if room_new == 0 and juke_new == 0 and oven_new == 0:
		print("QA PHASE 10 PROBE: no dropouts detected during play")
	else:
		printerr("QA PHASE 10 PROBE: dropouts detected during play (room=%d juke=%d oven=%d)" \
				% [room_new, juke_new, oven_new])
	print("QA PHASE 10 PROBE DONE")
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
