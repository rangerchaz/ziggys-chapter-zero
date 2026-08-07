## Phase 5 windowed QA visual probe (Chapter Zero -> data, hardcoded path
## deleted). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_visual_phase5_probe.tscn
##
## Walks the real front door - title's chapter select -> meckie select ->
## room - the same way a player reaches Chapter Zero now that it is just
## another ChapterDB entry (no hardcoded chapter_select.gd row, no
## chapter-specific code path). Once in the room, forces chapter-zero.json's
## `lighting` and `decision` beats via the real debug_brownout (F9) /
## debug_closing_time (F10) input paths BeatRunner now owns end-to-end, to
## show the room-controller/BeatRunner data-driven flow still produces the
## same brownout fade and Caroline decision prompt BrownoutDirector/
## ClosingTimeDirector used to self-trigger. Saves to
## tests/artifacts/qa/phase5/, at two window sizes (this is a native
## canvas_items/keep-stretch window, not a reflowing web layout - the
## second size is a letterbox/scale check, not a responsive-design one).
## Exits 0 once every screenshot is written, 1 otherwise.
extends Node

const ChapterSelectScene := preload("res://scenes/ui/chapter_select.tscn")
const MeckieSelectScene := preload("res://scenes/ui/meckie_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase5"
const CHAPTER_ID := "chapter-zero"

var _ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _run_pass(Vector2i(1280, 800), "desktop")
	await _run_pass(Vector2i(375, 667), "mobile")
	if _ok:
		print("QA VISUAL PHASE 5 PROBE PASS")
		get_tree().quit(0)
	else:
		printerr("QA VISUAL PHASE 5 PROBE FAIL")
		get_tree().quit(1)


func _run_pass(size: Vector2i, tag: String) -> void:
	DisplayServer.window_set_size(size)
	var state: Node = get_node(^"/root/GameState")
	state.reset()

	var select := ChapterSelectScene.instantiate()
	select.change_scenes = false
	add_child(select)
	# Entrance fade tween (~0.5-0.7s) - wait comfortably past it before
	# screenshotting freshly-added UI (Phase 6 lesson).
	await _settle_seconds(0.9)
	_shot("1_chapter_select_%s.png" % tag)
	select.queue_free()
	await get_tree().process_frame

	# Same call chapter_select.gd's own row-press makes: sets
	# GameState.active_chapter_id and clears this chapter's own progress.
	state.reset_chapter(CHAPTER_ID)

	var meckie := MeckieSelectScene.instantiate()
	meckie.change_scenes = false
	add_child(meckie)
	await _settle_seconds(0.9)
	_shot("2_meckie_select_%s.png" % tag)
	meckie.queue_free()
	await get_tree().process_frame

	var room := RoomScene.instantiate()
	room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(room)
	# CSG build / shader compile stalls the first several dozen frames
	# regardless of the beat (Phase 10/11 lesson) - settle at a real
	# framerate before trusting any screenshot.
	await _settle_seconds(1.5)
	_shot("3_room_chapter_zero_start_%s.png" % tag)

	var beat_runner: Node = room.get_node(^"BeatRunner")
	if not beat_runner.has_fired("settle"):
		printerr("  FAIL (%s): 'settle' ambience beat never fired on room entry" % tag)
		_ok = false

	var brownout_director: Node = room.get_node(^"BrownoutDirector")
	_press_key(KEY_F9)
	await _settle_seconds(brownout_director.fade_duration + 0.3)
	_shot("4_room_brownout_%s.png" % tag)
	if not beat_runner.has_fired("the_call"):
		printerr("  FAIL (%s): 'the_call' lighting beat never fired via debug_brownout" % tag)
		_ok = false
	await _settle_seconds(brownout_director.effect_hold + brownout_director.effect_release + 0.3)

	_press_key(KEY_F10)
	await _settle_seconds(0.4)
	_shot("5_decision_prompt_%s.png" % tag)
	if not beat_runner.has_fired("decide"):
		printerr("  FAIL (%s): 'decide' decision beat never fired via debug_closing_time" % tag)
		_ok = false

	room.queue_free()
	await get_tree().process_frame


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


func _settle_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false
	else:
		print("saved " + file_name)
