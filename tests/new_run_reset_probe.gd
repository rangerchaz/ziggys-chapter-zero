## Regression probe: Start must begin a FRESH run.
##
## The bug this guards: SaveManager loads user://ziggys_chapter_zero_save.json
## into GameState at boot so the title screen can show last run's decision.
## Nothing cleared that state when a new run began, so a save carrying
## brownout_seen=true started the chapter with the beat already marked spent -
## BrownoutDirector.fire() and ClosingTimeDirector then correctly refused to
## run twice and the chapter's two set pieces silently never played. On any
## machine that had ever finished the chapter, a new game had no brownout and
## no ending.
##
## Writes a COMPLETED save, boots state from it the way SaveManager does,
## runs the title screen's Start path, and asserts the run state is clean.
## Restores whatever save was on disk before it ran.
extends Node

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
	print("=== new-run reset probe ===")
	_backup_existing_save()

	var state: Node = get_node(^"/root/GameState")
	var save_mgr: Node = get_node(^"/root/SaveManager")

	# A save left by a run that saw the whole chapter through. Written as a
	# file rather than via save(), because GameState's setters are wired to
	# autosave - mutating state to build the fixture would overwrite it.
	var fixture := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	fixture.store_string(JSON.stringify({
		"version": save_mgr.SAVE_VERSION,
		"saved_at": "2026-08-06T21:01:56",
		save_mgr.KEY_CLOSING_DECISION: "wait_it_out",
		save_mgr.KEY_SELECTED_MECKIE: "droid",
		save_mgr.KEY_BROWNOUT_SEEN: true,
	}, "\t"))
	fixture.close()

	# Boot: SaveManager loads the file into GameState before the title
	# screen's _ready() runs. This is the path that poisoned the run.
	save_mgr.load_save()

	_check(state.brownout_fired, "save round-trips a completed run (precondition)")
	_check(String(state.closing_decision) == "wait_it_out",
			"decision survives quit/relaunch (existing acceptance bar)")

	# What Start does now.
	state.reset()

	_check(not state.brownout_fired, "Start clears brownout_fired")
	_check(not state.closing_time_reached, "Start clears closing_time_reached")
	_check(String(state.closing_decision) == String(state.NONE),
			"Start clears closing_decision")
	_check(String(state.selected_meckie) == String(state.NONE),
			"Start clears selected_meckie")
	_check(FileAccess.file_exists(SAVE_PATH),
			"Start does NOT delete the save file on disk")

	_restore_existing_save()

	if _failures.is_empty():
		print("new-run reset probe: PASS")
	else:
		print("new-run reset probe: FAIL (", _failures.size(), ")")
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
