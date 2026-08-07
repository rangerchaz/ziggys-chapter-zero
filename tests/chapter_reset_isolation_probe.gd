## Phase 4 probe, runnable headless:
##
##     godot --headless --path . res://tests/chapter_reset_isolation_probe.tscn
##
## Verifies acceptance criterion 4: starting one chapter (via
## GameState.reset_chapter()) clears only that chapter's own `writes`
## flags and shared progress fields, never a different, already-
## completed chapter's persisted flag - and that the surviving flag is
## still there after a save/quit and reload, not just in memory.
## fixture-valid writes "ziggys.fixture-valid.decision";
## fixture-beatrunner-kinds writes "demo.chapter.decision" - two loaded
## chapters with distinct writes keys, exactly what reset_chapter()
## needs to disambiguate against.
extends Node

const CHAPTER_A := "fixture-valid"
const CHAPTER_B := "fixture-beatrunner-kinds"
const SAVE_PATH := "user://ziggys_chapter_zero_save.json"
const BACKUP_PATH := "user://ziggys_chapter_zero_save.probe_backup.json"

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _ready() -> void:
	print("=== chapter reset isolation probe ===")
	_backup_existing_save()
	_run()
	_restore_existing_save()
	_report()


func _run() -> void:
	var state := get_node(^"/root/GameState")
	var chapter_db := get_node(^"/root/ChapterDB")
	var save_mgr := get_node(^"/root/SaveManager")

	var keys_a: Array = chapter_db.writes_keys_for(CHAPTER_A)
	var keys_b: Array = chapter_db.writes_keys_for(CHAPTER_B)
	_check(keys_a.size() == 1 and keys_a[0] == "ziggys.fixture-valid.decision",
			"fixture-valid's own writes key (got %s)" % [keys_a])
	_check(keys_b.size() == 1 and keys_b[0] == "demo.chapter.decision",
			"fixture-beatrunner-kinds' own writes key (got %s)" % [keys_b])

	# CHAPTER_B already completed and wrote its flag; the player now
	# starts CHAPTER_A, which should not touch it.
	state.set_flag(keys_b[0], "stay_open")
	state.set_flag(keys_a[0], "stale_from_a_prior_playthrough")
	state.brownout_fired = true
	state.closing_decision = &"wait_it_out"

	state.reset_chapter(CHAPTER_A)

	_check(state.active_chapter_id == CHAPTER_A, "active_chapter_id is set to the entered chapter")
	_check(state.get_flag(keys_a[0]) == "", "entering chapter A clears chapter A's own flag")
	_check(state.get_flag(keys_b[0]) == "stay_open",
			"entering chapter A leaves chapter B's already-completed flag untouched")
	_check(not state.brownout_fired, "entering a chapter resets the shared brownout progress field")
	_check(String(state.closing_decision) == String(state.NONE),
			"entering a chapter resets the shared closing-decision progress field")

	# Persist across a save/reload, matching "preserved across quit/relaunch".
	save_mgr.save()
	state.flags.clear()
	save_mgr.load_save()
	_check(state.get_flag(keys_b[0]) == "stay_open",
			"chapter B's flag survives a save/reload after entering chapter A")
	_check(state.get_flag(keys_a[0]) == "",
			"chapter A's cleared flag stays cleared across a save/reload")

	# Round-trip once more, entering chapter B this time, to confirm the
	# isolation holds symmetrically and not just in the one direction.
	state.set_flag(keys_a[0], "call_it")
	state.reset_chapter(CHAPTER_B)
	_check(state.get_flag(keys_b[0]) == "", "entering chapter B clears chapter B's own flag")
	_check(state.get_flag(keys_a[0]) == "call_it",
			"entering chapter B leaves chapter A's already-completed flag untouched")


func _report() -> void:
	if _failures.is_empty():
		print("chapter reset isolation probe: PASS")
	else:
		print("chapter reset isolation probe: FAIL (", _failures.size(), ")")
		for f in _failures:
			print("   - ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)


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
