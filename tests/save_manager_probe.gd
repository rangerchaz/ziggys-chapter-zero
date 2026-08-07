## Phase 14 probe, runnable headless:
##
##     godot --headless --path . res://tests/save_manager_probe.tscn
##
## Exercises SaveManager directly against the real user:// filesystem (the
## same directory a real relaunch would read): a decision write lands on
## disk as a versioned JSON document with the enumerated string id (never
## a bare integer), all four closing-decision ids round-trip as distinct
## values, a save never leaves its ".tmp" file behind, a missing save file
## is tolerated as "fresh chapter" with no reported error, and a
## hand-edited unknown version is rejected via SaveManager.last_load_error
## without crashing or partially applying to GameState. Exits 0 on pass,
## 1 on failure.
extends Node

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_fail(label)
		printerr("  FAIL: %s" % label)


func _run() -> void:
	var state: Node = get_node(^"/root/GameState")
	var save_mgr: Node = get_node(^"/root/SaveManager")

	state.reset()
	_delete_save_file(save_mgr)

	_check_never_writes_res(save_mgr)
	await _check_write_basic(state, save_mgr)
	await _check_four_distinct_values(state, save_mgr)
	await _check_atomic_write_leaves_no_temp(state, save_mgr)
	await _check_missing_file_tolerated(state, save_mgr)
	await _check_unknown_version_rejected(state, save_mgr)
	await _check_legacy_save_still_loads(state, save_mgr)
	await _check_generic_flag_round_trips(state, save_mgr)

	state.reset()
	_delete_save_file(save_mgr)


func _check_never_writes_res(save_mgr: Node) -> void:
	_expect(save_mgr.SAVE_PATH.begins_with("user://"),
			"SAVE_PATH is under user:// ('%s')" % save_mgr.SAVE_PATH)
	_expect(not save_mgr.SAVE_PATH.begins_with("res://"),
			"SAVE_PATH is never under res://")


func _check_write_basic(state: Node, save_mgr: Node) -> void:
	state.reset()
	state.selected_meckie = &"droid"
	state.brownout_fired = true
	state.closing_decision = &"organize"
	await get_tree().process_frame

	var data: Variant = _read_save(save_mgr)
	_expect(data != null, "save file parses as JSON after a decision is made")
	if data == null:
		return

	_expect(data.get("version") == 1, "save file has a top-level version field equal to 1")
	_expect(data.has("saved_at") and String(data["saved_at"]) != "", "save file records a saved_at timestamp")

	var decision: Variant = data.get(save_mgr.KEY_CLOSING_DECISION)
	_expect(typeof(decision) == TYPE_STRING, "closing_decision is stored as a string, not an integer index")
	_expect(decision == "organize", "closing_decision matches the selected answer id ('organize'), got '%s'" % [decision])

	_expect(data.get(save_mgr.KEY_SELECTED_MECKIE) == "droid",
			"selected_meckie round-trips through the save file")
	_expect(data.get(save_mgr.KEY_BROWNOUT_SEEN) == true,
			"brownout_seen round-trips through the save file")


func _check_four_distinct_values(state: Node, save_mgr: Node) -> void:
	var seen: Dictionary = {}
	for choice_id in save_mgr.CLOSING_DECISION_VALUES:
		state.reset()
		state.closing_decision = StringName(choice_id)
		await get_tree().process_frame
		var data: Variant = _read_save(save_mgr)
		if data != null:
			seen[data.get(save_mgr.KEY_CLOSING_DECISION)] = true
	_expect(seen.size() == 4,
			"each of the four closing answers produces its own distinct saved string value (saw %s)" % [seen.keys()])
	for choice_id in save_mgr.CLOSING_DECISION_VALUES:
		_expect(seen.has(choice_id), "'%s' appeared as its own distinct saved value" % choice_id)


func _check_atomic_write_leaves_no_temp(state: Node, save_mgr: Node) -> void:
	state.reset()
	state.closing_decision = &"wait_it_out"
	await get_tree().process_frame
	_expect(not FileAccess.file_exists(save_mgr.SAVE_PATH + ".tmp"),
			"no leftover .tmp file remains after an atomic save")
	_expect(FileAccess.file_exists(save_mgr.SAVE_PATH),
			"the real save file exists after the rename")


func _check_missing_file_tolerated(state: Node, save_mgr: Node) -> void:
	_delete_save_file(save_mgr)
	state.reset()
	save_mgr.load_save()
	_expect(save_mgr.last_load_error == "",
			"a missing save file is not reported as a load error")
	_expect(state.selected_meckie == state.NONE, "missing save file leaves selected_meckie at its default")
	_expect(state.closing_decision == state.NONE, "missing save file leaves closing_decision at its default")
	_expect(state.brownout_fired == false, "missing save file leaves brownout_fired at its default")


func _check_unknown_version_rejected(state: Node, save_mgr: Node) -> void:
	var bad := {
		"version": 999,
		"saved_at": "2026-01-01T00:00:00",
		save_mgr.KEY_CLOSING_DECISION: "organize",
		save_mgr.KEY_SELECTED_MECKIE: "droid",
		save_mgr.KEY_BROWNOUT_SEEN: true,
	}
	var file := FileAccess.open(save_mgr.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad))
	file.close()

	state.reset()
	save_mgr.load_save()

	_expect(save_mgr.last_load_error != "",
			"an unknown save version is reported via SaveManager.last_load_error")
	_expect(state.closing_decision == state.NONE,
			"an unknown-version save is not applied to GameState (closing_decision stays default)")
	_expect(state.selected_meckie == state.NONE,
			"an unknown-version save is not applied to GameState (selected_meckie stays default)")


## Acceptance criterion 2: a save file written by a build before generic
## flags existed - only the three original ziggys_chapter_zero.* keys, no
## extra dotted keys at all - must still load without error, and
## GameState.flags must simply come back empty rather than erroring on the
## keys it doesn't recognize as reserved but also doesn't find.
func _check_legacy_save_still_loads(state: Node, save_mgr: Node) -> void:
	var legacy := {
		"version": save_mgr.SAVE_VERSION,
		"saved_at": "2026-01-01T00:00:00",
		save_mgr.KEY_CLOSING_DECISION: "organize",
		save_mgr.KEY_SELECTED_MECKIE: "droid",
		save_mgr.KEY_BROWNOUT_SEEN: true,
	}
	var file := FileAccess.open(save_mgr.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "\t"))
	file.close()

	state.reset()
	save_mgr.load_save()

	_expect(save_mgr.last_load_error == "", "a pre-sprint save (three keys only) loads without a reported error")
	_expect(state.closing_decision == &"organize", "a legacy save's closing_decision still applies to GameState")
	_expect(state.selected_meckie == &"droid", "a legacy save's selected_meckie still applies to GameState")
	_expect(state.brownout_fired == true, "a legacy save's brownout_seen still applies to GameState")
	_expect(state.flags.is_empty(), "a legacy save with no extra keys leaves GameState.flags empty")


## Deliverable 5: GameState.flags round-trips through save()/load_save() as
## additional top-level dotted keys, alongside (not instead of) the three
## reserved keys, which stay exactly as they were.
func _check_generic_flag_round_trips(state: Node, save_mgr: Node) -> void:
	state.reset()
	state.closing_decision = &"quiet_watch"
	await get_tree().process_frame
	state.set_flag("demo.chapter.decision", "b")
	await get_tree().process_frame

	var data: Variant = _read_save(save_mgr)
	_expect(data != null, "save file parses as JSON after a generic flag is written")
	if data == null:
		return
	_expect(data.get("demo.chapter.decision") == "b",
			"a generic flag is written as its own top-level dotted key")
	_expect(data.get(save_mgr.KEY_CLOSING_DECISION) == "quiet_watch",
			"writing a generic flag does not disturb the existing closing_decision key")

	# reset() below changes closing_decision (quiet_watch -> NONE), which
	# fires its own change signal and autosaves a reset snapshot before
	# flags.clear() runs on the next line - re-write the exact bytes this
	# test just wrote afterward, so load_save() reads back what was
	# actually saved above rather than that transient in-between write.
	var snapshot: Dictionary = data.duplicate(true)
	state.reset()
	_expect(state.flags.is_empty(), "reset() clears in-memory flags")
	var f := FileAccess.open(save_mgr.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(snapshot, "\t"))
	f.close()

	save_mgr.load_save()
	_expect(state.get_flag("demo.chapter.decision") == "b",
			"reloading the save file restores the generic flag into GameState.flags")
	_expect(state.closing_decision == &"quiet_watch",
			"reloading the save file also restores the reserved closing_decision key")

	# Regression: _apply_to_game_state()'s field setters (closing_decision,
	# etc.) are each wired to autosave - without a load-in-progress guard, a
	# second consecutive load_save() would trigger a reentrant save() mid-load
	# that writes the file before `flags` is copied over, silently dropping
	# the very flag this test just confirmed above.
	save_mgr.load_save()
	_expect(state.get_flag("demo.chapter.decision") == "b",
			"a second consecutive load_save() does not corrupt the file via reentrant autosave")
	_expect(state.closing_decision == &"quiet_watch",
			"a second consecutive load_save() still restores closing_decision correctly")


func _read_save(save_mgr: Node) -> Variant:
	if not FileAccess.file_exists(save_mgr.SAVE_PATH):
		return null
	var file := FileAccess.open(save_mgr.SAVE_PATH, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else null


func _delete_save_file(save_mgr: Node) -> void:
	if FileAccess.file_exists(save_mgr.SAVE_PATH):
		DirAccess.remove_absolute(save_mgr.SAVE_PATH)
	if FileAccess.file_exists(save_mgr.SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(save_mgr.SAVE_PATH + ".tmp")


func _report() -> void:
	if _failures.is_empty():
		print("SAVE MANAGER PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("SAVE MANAGER PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
