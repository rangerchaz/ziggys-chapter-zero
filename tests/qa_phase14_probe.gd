## Phase 14 windowed QA probe. Needs a real GPU window, so run WITHOUT
## --headless:
##
##     godot --path . res://tests/qa_phase14_probe.tscn
##
## Shoots the title screen twice: once on a fresh chapter (no save file,
## no readout), then again after a real SaveManager.save() /
## SaveManager.load_save() round-trip through the actual user:// save
## file, to prove the recorded closing decision survives quit/relaunch
## and shows up as the title screen's "Last time: ..." readout - the
## visible half of Phase 14's acceptance bar (the other half, the JSON
## file itself, is covered non-visually by tests/save_manager_probe.tscn).
## Each state is shot at two window sizes; this project has no distinct
## mobile layout (canvas_items/keep stretch just scales the one
## 1920x1080 canvas - see godot-env-and-conventions memory), so the two
## shots are expected to be the same layout scaled, not a reflow.
## Saves to tests/artifacts/qa/phase14/. Exits 0 once both states and
## both sizes are written.
extends Node

const TitleScene := preload("res://scenes/ui/title_screen.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase14"
const SIZE_NAMES := ["desktop", "mobile"]
const SIZES := {
	"desktop": Vector2i(1280, 800),
	"mobile": Vector2i(375, 667),
}
## Matches title_screen.gd's ENTRANCE_DURATION at 60fps, plus margin -
## same lesson as the Phase 6 memory entry about shooting mid-fade.
const ENTRANCE_WAIT_FRAMES := 60
## DisplayServer.window_set_size() does not repaint the frame buffer
## synchronously - a screenshot taken the same frame as a resize call
## captures a stale/black frame. Give the renderer a few frames to catch
## up before every shot, same "settle before trusting a screenshot"
## lesson as the entrance-fade wait above.
const RESIZE_SETTLE_FRAMES := 15

var _frames := 0
var _title: Control
## &"fresh" | &"shoot_fresh" | &"writing_save" | &"restored" |
## &"shoot_restored" | &"done"
var _state := &"fresh"
var _shot_base_name := ""
var _next_state := &""
var _size_index := 0
var _resize_wait_start := 0
var _ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var save_path := "user://ziggys_chapter_zero_save.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	get_node(^"/root/GameState").reset()
	_spawn_title()


func _spawn_title() -> void:
	_title = TitleScene.instantiate()
	add_child(_title)


func _process(_delta: float) -> void:
	_frames += 1

	match _state:
		&"fresh":
			if _frames < ENTRANCE_WAIT_FRAMES:
				return
			_begin_shoot_sequence("title_fresh_no_save", &"writing_save")

		&"shooting":
			_step_shoot_sequence()

		&"writing_save":
			_title.queue_free()
			_title = null
			_write_and_reload_save()
			_spawn_title()
			_frames = 0
			_state = &"restored"

		&"restored":
			if _frames < ENTRANCE_WAIT_FRAMES:
				return
			_begin_shoot_sequence("title_prior_decision_organize", &"done")

		&"done":
			_report()


## Writes a real closing decision through GameState's live setters (so
## SaveManager autosaves it, same as a played run), then simulates the
## process boundary of a real quit/relaunch by resetting GameState and
## calling SaveManager.load_save() to repopulate it from the file that
## now sits on disk.
func _write_and_reload_save() -> void:
	var state: Node = get_node(^"/root/GameState")
	var save_mgr: Node = get_node(^"/root/SaveManager")
	state.selected_meckie = &"droid"
	state.brownout_fired = true
	state.closing_decision = &"organize"

	# A real cold boot never fires GameState's autosave-on-change signals
	# with empty values - GameState just starts at its declared defaults,
	# with no listeners wired to a "reset" that never happens. Unhook
	# SaveManager's connections for the duration of this in-process
	# reset() so it can't stomp the file we just wrote before we get to
	# reload it, then rewire them exactly as they were.
	var conns := {
		"meckie": state.meckie_selected.get_connections(),
		"brownout": state.brownout_changed.get_connections(),
		"closing": state.closing_decision_made.get_connections(),
	}
	for c in conns["meckie"]:
		state.meckie_selected.disconnect(c["callable"])
	for c in conns["brownout"]:
		state.brownout_changed.disconnect(c["callable"])
	for c in conns["closing"]:
		state.closing_decision_made.disconnect(c["callable"])

	state.reset()

	for c in conns["meckie"]:
		state.meckie_selected.connect(c["callable"])
	for c in conns["brownout"]:
		state.brownout_changed.connect(c["callable"])
	for c in conns["closing"]:
		state.closing_decision_made.connect(c["callable"])

	save_mgr.load_save()
	if save_mgr.last_load_error != "":
		printerr("QA PHASE 14 PROBE FAIL: unexpected load error: %s" % save_mgr.last_load_error)
		_ok = false
	if String(state.closing_decision) != "organize":
		printerr("QA PHASE 14 PROBE FAIL: closing_decision did not survive save/load round-trip")
		_ok = false


func _begin_shoot_sequence(base_name: String, next_state: StringName) -> void:
	_shot_base_name = base_name
	_next_state = next_state
	_size_index = 0
	DisplayServer.window_set_size(SIZES[SIZE_NAMES[0]])
	_resize_wait_start = _frames
	_state = &"shooting"


func _step_shoot_sequence() -> void:
	if _frames - _resize_wait_start < RESIZE_SETTLE_FRAMES:
		return
	var size_name: String = SIZE_NAMES[_size_index]
	_shot("%s-%s.png" % [_shot_base_name, size_name])
	_size_index += 1
	if _size_index >= SIZE_NAMES.size():
		_state = _next_state
		return
	DisplayServer.window_set_size(SIZES[SIZE_NAMES[_size_index]])
	_resize_wait_start = _frames


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
		_ok = false
	else:
		print("saved " + file_name)


func _report() -> void:
	if _title:
		_title.queue_free()
	if _ok:
		print("QA PHASE 14 PROBE DONE")
		get_tree().quit(0)
	else:
		printerr("QA PHASE 14 PROBE FAIL")
		get_tree().quit(1)
