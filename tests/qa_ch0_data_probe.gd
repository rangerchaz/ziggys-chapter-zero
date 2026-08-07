## Phase 5 windowed QA capture (not a deliverable test - just screenshots for
## visual review of Chapter Zero as data). Needs a real GPU window, so run
## WITHOUT --headless:
##
##     godot --path . res://tests/qa_ch0_data_probe.tscn          (desktop)
##     godot --path . res://tests/qa_ch0_data_probe_mobile.tscn   (mobile)
##
## Walks the REAL flow the phase's deliverables are about: chapter_select.gd
## lists "chapter-zero" as a normal ChapterDB row (no hardcoded special case
## left - see chapter_select.gd's header), picking it hands off to meckie
## select, picking a Meckie enters the room with GameState.active_chapter_id
## already wired up so ziggys_room.gd loads chapter-zero.json from ChapterDB
## and BeatRunner (scripts/systems/beat_runner.gd) drives its beats: ambience
## warm -> lighting brownout (F9, debug_brownout) -> Caroline's four-choice
## decision (F10, debug_closing_time) -> end. change_scenes is left false on
## both UI screens so a real scene swap never tears down this probe tree;
## the room is instead added as a plain child, same as every earlier
## windowed probe (qa_phase4/6/16_probe.gd). The BeatRunner's own real
## change_scene_to_file() on the "end" beat is disabled the same way (see
## auto_return_to_title below) for the same reason, then a title screen
## instance is added by hand to represent "what end looks like" without
## actually killing this running scene.
##
## Saves to res://.turkey/screenshots/phase-5/<name>-<file_suffix>.png. Exits
## 0 once everything is written for whichever window_size/file_suffix this
## instance was configured with (see qa_ch0_data_probe.tscn /
## qa_ch0_data_probe_mobile.tscn).
extends Node

const ChapterSelectScene := preload("res://scenes/ui/chapter_select.tscn")
const MeckieSelectScene := preload("res://scenes/ui/meckie_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const TitleScene := preload("res://scenes/ui/title_screen.tscn")
const OUT_DIR := "res://.turkey/screenshots/phase-5"

## Per-instance config - see qa_ch0_data_probe.tscn (desktop, 1920x1080) and
## qa_ch0_data_probe_mobile.tscn (375x667). This project has no reflowing
## "mobile" layout: a fixed 1920x1080 canvas with canvas_items/keep stretch
## just letterboxes/scales the same layout in a smaller OS window - expected,
## not a bug, per prior QA phases.
@export var window_size := Vector2i(1920, 1080)
@export var file_suffix := "desktop"

## The four choice ids chapter-zero.json's "decide" beat declares
## (content/chapters/chapter-zero.json) - checked against the rendered
## button labels so the screenshot's four-option prompt is verified to
## actually be Chapter Zero's real data, not a stand-in.
const EXPECTED_CHOICE_IDS := ["organize", "quiet_watch", "wait_it_out", "not_my_problem"]
const PICKED_CHOICE_INDEX := 0

var _frames := 0
var _state := &"wait_chapter_select"
var _wait_start := 0
var _fired_at := 0.0
var _ok := true
var _chapter_ended_fired := false

var _select: Control
var _meckie_select: Control
var _room: Node3D
var _cam: Camera3D
var _bd: Node
var _beat_runner: Node
var _dialogue: Control


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_set_window_size(window_size)
	_select = ChapterSelectScene.instantiate()
	_select.change_scenes = false
	add_child(_select)


func _set_window_size(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(origin + (screen_size - size) / 2)


func _process(delta: float) -> void:
	_frames += 1

	if _state == &"wait_chapter_select":
		if _frames - _wait_start >= 20:
			_shot("chapter_select")
			var row: Button = _select.row_button("chapter-zero")
			if row == null:
				printerr("QA CH0 PROBE FAIL: no 'chapter-zero' row in chapter select")
				_ok = false
			else:
				var reason: Label = row.find_child("ReasonLabel", true, false)
				if row.disabled or reason != null:
					printerr("QA CH0 PROBE FAIL: 'chapter-zero' row is not a normal unlocked row (disabled=%s, has ReasonLabel=%s)" % [row.disabled, reason != null])
					_ok = false
				row.pressed.emit()
				if get_node(^"/root/GameState").active_chapter_id != "chapter-zero":
					printerr("QA CH0 PROBE FAIL: picking the row never set GameState.active_chapter_id")
					_ok = false
			_select.queue_free()
			_meckie_select = MeckieSelectScene.instantiate()
			_meckie_select.change_scenes = false
			add_child(_meckie_select)
			_state = &"wait_meckie_select"
			_wait_start = _frames
		return

	if _state == &"wait_meckie_select":
		# Clears meckie_select's own 0.7s entrance fade (ENTRANCE_DURATION in
		# meckie_select.gd) before the shot.
		if _frames - _wait_start >= 50:
			_shot("meckie_select")
			var droid_button: Button = _meckie_select.get_node(^"%DroidButton")
			droid_button.pressed.emit()
			_meckie_select.queue_free()
			_spawn_room()
			_state = &"settle_room"
			_wait_start = _frames
		return

	if _state == &"settle_room":
		# CSG/shader compile stalls the first several dozen frames regardless
		# of the beat - same lesson as every earlier phase's windowed probe.
		if _frames - _wait_start >= 90:
			var player: CharacterBody3D = null
			for child in _room.get_children():
				if child is MeckiePlayerController:
					player = child
			if player == null:
				printerr("QA CH0 PROBE FAIL: player not found in room")
				_ok = false
				_report()
				return
			if _beat_runner.chapter_id != "chapter-zero" or not _beat_runner.has_fired("settle"):
				printerr("QA CH0 PROBE FAIL: BeatRunner never started chapter-zero from ChapterDB (chapter_id=%s, settle fired=%s)" % [_beat_runner.chapter_id, _beat_runner.has_fired("settle")])
				_ok = false
			# Out of frame for the establishing/brownout shots.
			player.global_position = Vector3(0, 6, 0)
			player.velocity = Vector3.ZERO
			_cam.current = true
			_state = &"wait_pre_brownout_shot"
			_wait_start = _frames
		return

	if _state == &"wait_pre_brownout_shot":
		# The renderer draws a frame behind script state - give the
		# reposition above a few settled frames before capturing it.
		if _frames - _wait_start >= 5:
			_shot("room_pre_brownout")
			_press_key(KEY_F9)
			_fired_at = 0.0
			_state = &"brownout"
		return

	if _state == &"brownout":
		_fired_at += delta
		if _fired_at >= _bd.fade_duration * 0.5 and _fired_at - delta < _bd.fade_duration * 0.5:
			_shot("room_mid_fade")
		if _fired_at >= _bd.fade_duration + 0.3 and _fired_at - delta < _bd.fade_duration + 0.3:
			_shot("room_full_brownout")
		if _fired_at >= _bd.fade_duration + _bd.effect_hold + _bd.effect_release + 0.3:
			_state = &"pre_closing_time"
			_wait_start = _frames
		return

	if _state == &"pre_closing_time":
		if _frames - _wait_start >= 15:
			_press_key(KEY_F10)
			_state = &"wait_choices"
			_wait_start = _frames
		return

	if _state == &"wait_choices":
		if _frames - _wait_start >= 15:
			var container: VBoxContainer = _dialogue.get_node(^"%ChoicesContainer")
			if not container.visible or container.get_child_count() != 4:
				printerr("QA CH0 PROBE FAIL: four-option decision prompt did not appear (visible=%s, children=%d)" % [container.visible, container.get_child_count()])
				_ok = false
				_report()
				return
			var labels: Array[String] = []
			for i in container.get_child_count():
				labels.append((container.get_child(i) as Button).text)
			for choice_id in EXPECTED_CHOICE_IDS:
				var readable: String = choice_id.capitalize()
				var found := false
				for label in labels:
					if label.find(readable) != -1:
						found = true
						break
				if not found:
					printerr("QA CH0 PROBE FAIL: choice '%s' (rendered '%s') missing from prompt labels %s" % [choice_id, readable, labels])
					_ok = false
			print("decision prompt labels: ", labels)
			_shot("decision_four_choices")
			(container.get_child(PICKED_CHOICE_INDEX) as Button).pressed.emit()
			_state = &"wait_chapter_end"
			_wait_start = _frames
		return

	if _state == &"wait_chapter_end":
		if _frames - _wait_start >= 20:
			if not _chapter_ended_fired:
				printerr("QA CH0 PROBE FAIL: chapter_ended never fired after picking a closing decision")
				_ok = false
			var state: Node = get_node(^"/root/GameState")
			if String(state.closing_decision) != EXPECTED_CHOICE_IDS[PICKED_CHOICE_INDEX]:
				printerr("QA CH0 PROBE FAIL: GameState.closing_decision is '%s', expected '%s'" % [state.closing_decision, EXPECTED_CHOICE_IDS[PICKED_CHOICE_INDEX]])
				_ok = false
			_shot("chapter_end_room")
			_room.queue_free()
			_cam.queue_free()
			add_child(TitleScene.instantiate())
			_state = &"wait_title"
			_wait_start = _frames
		return

	if _state == &"wait_title":
		# Title screen's own 0.7s entrance fade (ENTRANCE_DURATION in
		# title_screen.gd).
		if _frames - _wait_start >= 50:
			_shot("chapter_end_title")
			_report()
		return


func _spawn_room() -> void:
	_room = RoomScene.instantiate()
	add_child(_room)
	_beat_runner = _room.get_node(^"BeatRunner")
	# Prevents BeatRunner's "end" beat from calling the real
	# get_tree().change_scene_to_file() out from under this running probe
	# tree - chapter_ended (checked below) is still the real Phase 5 signal
	# path, just without the scene swap. A title screen instance is added by
	# hand afterward to represent what "end" looks like without killing this
	# probe.
	_beat_runner.auto_return_to_title = false
	_beat_runner.chapter_ended.connect(_on_chapter_ended)
	_bd = _room.get_node(^"BrownoutDirector")
	_dialogue = _room.get_node(^"UI/DialogueUI")
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	# Same establishing framing ziggys_room.tscn's own default Camera3D uses
	# (and the exact transform qa_phase16_probe.gd's pre_brownout shot used),
	# on a free camera so the player can be moved out of frame without
	# disturbing this view.
	_cam.global_transform = Transform3D(
			Vector3(-0.95906, -0.057131, 0.27739),
			Vector3(0, 0.979453, 0.20174),
			Vector3(-0.28321, 0.193481, -0.93935),
			Vector3(1.9, 2.5, -4.45))


func _on_chapter_ended(_chapter_id: String) -> void:
	_chapter_ended_fired = true


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


func _shot(name: String) -> void:
	var file_name := "%s-%s.png" % [name, file_suffix]
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false
	else:
		print("saved ", file_name)


func _report() -> void:
	if _ok:
		print("QA CH0 DATA PROBE (%s) DONE" % file_suffix)
		get_tree().quit(0)
	else:
		printerr("QA CH0 DATA PROBE (%s) FAIL" % file_suffix)
		get_tree().quit(1)
