## Phase 3 QA-only capture (not a deliverable test - just screenshots for
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase3_probe.tscn
##
## Runs content/chapters/fixture-beatrunner-kinds.json through the real
## room's BeatRunner exactly as tests/beat_runner_kinds_probe.gd does
## headless, but shoots screenshots of each visible moment instead of
## asserting: the `dialogue` beat's panel (Chad's existing line), the
## `decision` beat's 3-choice prompt (Caroline), and the room right after
## the `end` beat fires (dialogue closed, no crash). auto_return_to_title
## is left false, exactly like beat_runner_kinds_probe.gd, so the actual
## scene-swap-to-title doesn't free this probe's own node out from under
## it mid-capture; the title screen's own appearance is unchanged by this
## phase and already covered by earlier phases' QA screenshots. Saves to
## tests/artifacts/qa/phase3/. Exits 0 once everything is written.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const BeatRunnerScript := preload("res://scripts/systems/beat_runner.gd")
const OUT_DIR := "res://tests/artifacts/qa/phase3"

var _frames := 0
var _room: Node3D
var _runner: Node
var _dialogue: Control
var _stage := 0
var _decision_shot_at := -1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var state: Node = get_node(^"/root/GameState")
	var save_mgr: Node = get_node(^"/root/SaveManager")
	state.reset()
	if FileAccess.file_exists(save_mgr.SAVE_PATH):
		DirAccess.remove_absolute(save_mgr.SAVE_PATH)
	_room = RoomScene.instantiate()
	_room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(_room)
	_dialogue = _room.get_node(^"UI/DialogueUI")
	_runner = BeatRunnerScript.new()
	_runner.dialogue_ui_path = _dialogue.get_path()
	_runner.brownout_director_path = _room.get_node(^"BrownoutDirector").get_path()
	_runner.auto_return_to_title = false
	add_child(_runner)


func _process(_delta: float) -> void:
	_frames += 1

	# CSG build / shader compile stalls the first several dozen frames -
	# settle at a real framerate before trusting any screenshot (same
	# lesson as every prior windowed QA probe in this repo).
	if _frames < 90:
		return

	match _stage:
		0:
			_runner.start("fixture-beatrunner-kinds")
			_stage = 1
		1:
			# `say_hi` has no `after`, so it fires the instant start() is
			# reached - one extra frame lets the panel actually render.
			if _frames >= 92:
				_shot("dialogue_chad_says_hi.png")
				_stage = 2
		2:
			# Keep pressing [E] to walk Chad's lines to completion. Once
			# the conversation completes, the decision beat's
			# `after: {conversations: 1}` is satisfied and DialogueUI
			# reopens in CHOICE mode on the very same signal - pressing
			# [E] again is harmless (DialogueUI ignores it outside LINES
			# mode), so this loop doesn't need to detect that handoff
			# itself, just wait for BeatRunner to report the beat fired.
			if _runner.has_fired("demo_decision"):
				_decision_shot_at = _frames
				_stage = 3
			else:
				_advance_lines_once()
				if _frames > 400:
					printerr("QA PHASE 3 PROBE FAIL: decision beat never fired")
					get_tree().quit(1)
		3:
			# Give the CHOICE panel a couple of frames to render before
			# shooting it, then pick the middle option. Selecting it
			# synchronously writes the flag, closes the panel, and (via
			# the completed-conversation trigger) fires the `end` beat -
			# all logically within this same call - but the viewport
			# texture only reflects a render that happened BEFORE this
			# frame's processing, so shooting again immediately would just
			# re-save the same unrendered buffer. Wait for the next frame
			# (auto_return_to_title is false, so nothing frees this node
			# in between) before shooting the after state.
			if _frames >= _decision_shot_at + 2:
				_shot("decision_caroline_three_choices.png")
				var container: VBoxContainer = _dialogue.get_node(^"%ChoicesContainer")
				var chosen: Button = container.get_child(1)
				chosen.pressed.emit()
				if not (_runner.has_fired("wrap_up") and not _dialogue.visible):
					printerr("QA PHASE 3 PROBE FAIL: end beat did not fire immediately after the decision")
					get_tree().quit(1)
					return
				_stage = 4
		4:
			if _frames >= _decision_shot_at + 4:
				_shot("after_decision_end_fired.png")
				print("QA PHASE 3 PROBE DONE")
				get_tree().quit(0)


func _advance_lines_once() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_E
	down.physical_keycode = KEY_E
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = KEY_E
	up.physical_keycode = KEY_E
	up.pressed = false
	Input.parse_input_event(up)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
