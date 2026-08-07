## Phase 6 windowed QA capture (not a deliverable test - just screenshots for
## visual review of the requires-gating story end to end). Needs a real GPU
## window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_gating_probe.tscn
##
## Walks the real flow: on a completely fresh save, chapter select shows
## Chapter Zero playable and "the-morning-after" greyed out with a reason
## naming the unmet Chapter Zero decision requirement (acceptance criteria 1).
## After simulating a completed Chapter Zero with the "organize" decision,
## relaunching chapter select shows both chapters playable (acceptance
## criterion 2). Picking "the-morning-after" and entering the room proves its
## smaller cast (caroline/oleg/tonya/grant) is actually filtered down from
## the full ten-NPC roster. Finally, re-drives Chapter Zero itself end to end
## (brownout via F9, four-option decision via F10) exactly like Phase 5's
## qa_ch0_data_probe.gd, so the brownout and four-option-decision screenshots
## can be compared by eye against .turkey/screenshots/phase-5/'s baseline for
## regressions.
##
## change_scenes is left false on every UI screen so a real scene swap never
## tears down this probe tree; the room is added as a plain child, same as
## every earlier windowed probe. Saves to
## res://.turkey/screenshots/phase-6/<name>-desktop.png.
extends Node

const ChapterSelectScene := preload("res://scenes/ui/chapter_select.tscn")
const MeckieSelectScene := preload("res://scenes/ui/meckie_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://.turkey/screenshots/phase-6"

const SECOND_CHAPTER_ID := "the-morning-after"
const SECOND_CHAPTER_CAST: Array[StringName] = [&"caroline", &"oleg", &"tonya", &"grant"]

const SAVE_PATH := "user://ziggys_chapter_zero_save.json"
const BACKUP_PATH := "user://ziggys_chapter_zero_save.probe_backup.json"

const EXPECTED_CHOICE_IDS := ["organize", "quiet_watch", "wait_it_out", "not_my_problem"]
const PICKED_CHOICE_INDEX := 0

var _frames := 0
var _state := &"wait_chapter_select_fresh"
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
	_set_window_size(Vector2i(1920, 1080))
	_backup_existing_save()
	var state := get_node(^"/root/GameState")
	state.reset()

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

	if _state == &"wait_chapter_select_fresh":
		# Clears chapter_select's own entrance fade before the shot.
		if _frames - _wait_start >= 50:
			_shot("1_chapter_select_fresh_locked_unlocked")
			_check_fresh_chapter_select()
			# fixture-*.json content also loads into the real ChapterDB (see
			# tests/chapter_validation_probe.gd's own header comment), so the
			# second real chapter sorts alphabetically last and is scrolled
			# out of the first shot above - scroll it into view for a second
			# shot that actually shows its locked row/reason, per acceptance
			# criterion 1 ("states its reason"). ScrollContainer applies the
			# new scroll_vertical value on its own next internal update, not
			# synchronously within this same call, so a couple of settle
			# frames sit between the scroll and the shot below.
			_scroll_row_into_view(SECOND_CHAPTER_ID)
			_state = &"wait_scroll_fresh"
			_wait_start = _frames
		return

	if _state == &"wait_scroll_fresh":
		if _frames - _wait_start >= 5:
			_shot("1b_chapter_select_fresh_the_morning_after_locked")
			_select.queue_free()
			_state = &"simulate_completed_chapter_zero"
			_wait_start = _frames
		return

	if _state == &"simulate_completed_chapter_zero":
		if _frames - _wait_start >= 5:
			# Acceptance criterion 2: relaunching after Chapter Zero recorded
			# "organize" shows both chapters playable.
			get_node(^"/root/GameState").closing_decision = StringName("organize")
			_select = ChapterSelectScene.instantiate()
			_select.change_scenes = false
			add_child(_select)
			_state = &"wait_chapter_select_both_unlocked"
			_wait_start = _frames
		return

	if _state == &"wait_chapter_select_both_unlocked":
		if _frames - _wait_start >= 50:
			_shot("2_chapter_select_both_unlocked")
			_check_both_unlocked_chapter_select()
			_scroll_row_into_view(SECOND_CHAPTER_ID)
			_state = &"wait_scroll_unlocked"
			_wait_start = _frames
		return

	if _state == &"wait_scroll_unlocked":
		if _frames - _wait_start >= 5:
			_shot("2b_chapter_select_both_unlocked_the_morning_after")
			var row: Button = _select.row_button(SECOND_CHAPTER_ID)
			if row != null:
				row.pressed.emit()
			if get_node(^"/root/GameState").active_chapter_id != SECOND_CHAPTER_ID:
				printerr("QA GATING PROBE FAIL: picking '%s' never set GameState.active_chapter_id" % SECOND_CHAPTER_ID)
				_ok = false
			_select.queue_free()
			_meckie_select = MeckieSelectScene.instantiate()
			_meckie_select.change_scenes = false
			add_child(_meckie_select)
			_state = &"wait_meckie_select"
			_wait_start = _frames
		return

	if _state == &"wait_meckie_select":
		if _frames - _wait_start >= 50:
			var droid_button: Button = _meckie_select.get_node(^"%DroidButton")
			droid_button.pressed.emit()
			_meckie_select.queue_free()
			_spawn_room(SECOND_CHAPTER_ID)
			_state = &"settle_second_chapter_room"
			_wait_start = _frames
		return

	if _state == &"settle_second_chapter_room":
		# CSG/shader compile stalls the first several dozen frames plus
		# _filter_cast()'s queue_free() calls need a frame to actually leave
		# the tree.
		if _frames - _wait_start >= 90:
			_cam.current = true
			_check_cast_filtered_to_second_chapter()
			_state = &"wait_second_chapter_room_shot"
			_wait_start = _frames
		return

	if _state == &"wait_second_chapter_room_shot":
		if _frames - _wait_start >= 5:
			_shot("3_room_cast_filtered_the_morning_after")
			_room.queue_free()
			_cam.queue_free()
			_state = &"start_chapter_zero_regression"
			_wait_start = _frames
		return

	if _state == &"start_chapter_zero_regression":
		if _frames - _wait_start >= 5:
			# Regression: re-drive Chapter Zero itself end to end, entering
			# the same way chapter_select.gd's reset_chapter() does, so the
			# brownout/four-option-decision shots below can be compared by
			# eye against .turkey/screenshots/phase-5/'s baseline.
			get_node(^"/root/GameState").reset_chapter("chapter-zero")
			_spawn_room("chapter-zero")
			_state = &"settle_chapter_zero_room"
			_wait_start = _frames
		return

	if _state == &"settle_chapter_zero_room":
		if _frames - _wait_start >= 90:
			var player: CharacterBody3D = null
			for child in _room.get_children():
				if child is MeckiePlayerController:
					player = child
			if player == null:
				printerr("QA GATING PROBE FAIL: player not found in chapter-zero regression room")
				_ok = false
				_report()
				return
			player.global_position = Vector3(0, 6, 0)
			player.velocity = Vector3.ZERO
			_cam.current = true
			_state = &"wait_pre_brownout"
			_wait_start = _frames
		return

	if _state == &"wait_pre_brownout":
		if _frames - _wait_start >= 5:
			_press_key(KEY_F9)
			_fired_at = 0.0
			_state = &"brownout"
		return

	if _state == &"brownout":
		_fired_at += delta
		if _fired_at >= _bd.fade_duration + 0.3 and _fired_at - delta < _bd.fade_duration + 0.3:
			_shot("4_regression_room_full_brownout")
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
				printerr("QA GATING PROBE FAIL: four-option decision prompt did not appear (visible=%s, children=%d)" % [container.visible, container.get_child_count()])
				_ok = false
				_report()
				return
			_shot("5_regression_decision_four_choices")
			(container.get_child(PICKED_CHOICE_INDEX) as Button).pressed.emit()
			_state = &"wait_chapter_end"
			_wait_start = _frames
		return

	if _state == &"wait_chapter_end":
		if _frames - _wait_start >= 20:
			if not _chapter_ended_fired:
				printerr("QA GATING PROBE FAIL: chapter_ended never fired for the chapter-zero regression run")
				_ok = false
			var state: Node = get_node(^"/root/GameState")
			if String(state.closing_decision) != EXPECTED_CHOICE_IDS[PICKED_CHOICE_INDEX]:
				printerr("QA GATING PROBE FAIL: GameState.closing_decision is '%s', expected '%s'" % [state.closing_decision, EXPECTED_CHOICE_IDS[PICKED_CHOICE_INDEX]])
				_ok = false
			if state.get_flag("ziggys.the-morning-after.decision") != "":
				printerr("QA GATING PROBE FAIL: completing Chapter Zero's own decision beat altered the-morning-after's flag")
				_ok = false
			_report()
		return


## Brings `chapter_id`'s row into the visible scroll window - the list has
## more rows than fit on screen (real content plus fixture-*.json files
## other phases' probes rely on ChapterDB loading from the same directory),
## so a row sorted near the bottom is off-screen until scrolled.
func _scroll_row_into_view(chapter_id: String) -> void:
	var row: Button = _select.row_button(chapter_id)
	if row == null:
		return
	var scroll: ScrollContainer = _select.get_node(^"Column/Scroll")
	scroll.ensure_control_visible(row)


func _check_fresh_chapter_select() -> void:
	var zero_row: Button = _select.row_button("chapter-zero")
	if zero_row == null or zero_row.disabled:
		printerr("QA GATING PROBE FAIL: 'chapter-zero' is not a normal unlocked row on a fresh save")
		_ok = false

	var second_row: Button = _select.row_button(SECOND_CHAPTER_ID)
	if second_row == null:
		printerr("QA GATING PROBE FAIL: '%s' has no row on a fresh save (should be visible, greyed)" % SECOND_CHAPTER_ID)
		_ok = false
		return
	if not second_row.disabled:
		printerr("QA GATING PROBE FAIL: '%s' is enabled on a fresh save; its requires should be unmet" % SECOND_CHAPTER_ID)
		_ok = false
	var reason: Label = second_row.find_child("ReasonLabel", true, false)
	if reason == null:
		printerr("QA GATING PROBE FAIL: '%s' locked row has no reason label" % SECOND_CHAPTER_ID)
		_ok = false
	elif reason.text.find("organis") == -1:
		printerr("QA GATING PROBE FAIL: '%s' reason text does not name the unmet Chapter Zero decision requirement (got '%s')" % [SECOND_CHAPTER_ID, reason.text])
		_ok = false


func _check_both_unlocked_chapter_select() -> void:
	var zero_row: Button = _select.row_button("chapter-zero")
	if zero_row == null or zero_row.disabled:
		printerr("QA GATING PROBE FAIL: 'chapter-zero' is not still playable/replayable after completing it")
		_ok = false
	var second_row: Button = _select.row_button(SECOND_CHAPTER_ID)
	if second_row == null or second_row.disabled:
		printerr("QA GATING PROBE FAIL: '%s' is still locked after simulating a completed Chapter Zero with 'organize'" % SECOND_CHAPTER_ID)
		_ok = false
	elif second_row.find_child("ReasonLabel", true, false) != null:
		printerr("QA GATING PROBE FAIL: '%s' unlocked row still shows a reason label" % SECOND_CHAPTER_ID)
		_ok = false


func _check_cast_filtered_to_second_chapter() -> void:
	var npcs: Node3D = _room.get_node(^"Npcs")
	var remaining: Array[StringName] = []
	for child in npcs.get_children():
		if child is NpcHuman:
			remaining.append(child.npc_id)
	remaining.sort()
	var expected := SECOND_CHAPTER_CAST.duplicate()
	expected.sort()
	if remaining != expected:
		printerr("QA GATING PROBE FAIL: room cast is %s, expected exactly %s" % [remaining, expected])
		_ok = false
	if _beat_runner.chapter_id != SECOND_CHAPTER_ID or not _beat_runner.has_fired("settle"):
		printerr("QA GATING PROBE FAIL: BeatRunner never started '%s' from ChapterDB" % SECOND_CHAPTER_ID)
		_ok = false


func _spawn_room(chapter_id: String) -> void:
	_room = RoomScene.instantiate()
	add_child(_room)
	_beat_runner = _room.get_node(^"BeatRunner")
	_beat_runner.auto_return_to_title = false
	if not _beat_runner.chapter_ended.is_connected(_on_chapter_ended):
		_beat_runner.chapter_ended.connect(_on_chapter_ended)
	_bd = _room.get_node(^"BrownoutDirector")
	_dialogue = _room.get_node(^"UI/DialogueUI")
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	# Same establishing framing qa_ch0_data_probe.gd uses.
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
	var file_name := "%s-desktop.png" % name
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false
	else:
		print("saved ", file_name)


func _backup_existing_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var src := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	dst.store_string(text)
	dst.close()


func _restore_existing_save() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var src := FileAccess.open(BACKUP_PATH, FileAccess.READ)
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	dst.store_string(text)
	dst.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))


func _report() -> void:
	_restore_existing_save()
	if _ok:
		print("QA GATING PROBE DONE")
		get_tree().quit(0)
	else:
		printerr("QA GATING PROBE FAIL")
		get_tree().quit(1)
