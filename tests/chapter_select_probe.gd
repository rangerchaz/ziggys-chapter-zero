## Phase 4 probe, runnable headless:
##
##     godot --headless --path . res://tests/chapter_select_probe.tscn
##
## Verifies acceptance criteria 2, 3 and 5: on a fresh save, a chapter
## with no `requires` lists as an enabled, focusable row; a chapter with
## an unmet `requires` lists as a VISIBLE but disabled row carrying a
## "needs: ..." reason naming the unmet flag; picking an enabled row
## calls GameState.reset_chapter(id) and fires chapter_chosen; and
## Escape resolves through UiStateMachine's "chapter_select" context
## without crashing. Runs with change_scenes = false so choosing a row
## never tears down this probe with a real scene change.
extends Node

const ChapterSelectScene := preload("res://scenes/ui/chapter_select.tscn")

const UNLOCKED_ID := "fixture-cast-caroline-chad"
const LOCKED_ID := "fixture-requires-locked"
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
	print("=== chapter select probe ===")
	_backup_existing_save()
	_run()
	_restore_existing_save()
	_report()


func _run() -> void:
	var state := get_node(^"/root/GameState")
	var save_mgr := get_node(^"/root/SaveManager")

	# A completely fresh save: no closing decision recorded yet, so
	# LOCKED_ID's requires (closing_decision == "organize") is unmet.
	state.closing_decision = state.NONE
	_check(save_mgr.current_flag_value(save_mgr.KEY_CLOSING_DECISION) == "",
			"fresh save has no closing decision (precondition)")

	var select: Control = ChapterSelectScene.instantiate()
	select.change_scenes = false
	add_child(select)

	var unlocked_button: Button = select.row_button(UNLOCKED_ID)
	_check(unlocked_button != null, "no-requires fixture chapter has a row")
	if unlocked_button != null:
		_check(not unlocked_button.disabled, "no-requires fixture chapter is enabled on a fresh save")
		_check(unlocked_button.focus_mode != Control.FOCUS_NONE, "enabled row is focusable")

	var locked_button: Button = select.row_button(LOCKED_ID)
	_check(locked_button != null, "unmet-requires fixture chapter still has a row (visible, not hidden)")
	if locked_button != null:
		_check(locked_button.disabled, "unmet-requires fixture chapter is disabled")
		var reason_label: Label = locked_button.find_child("ReasonLabel", true, false)
		_check(reason_label != null, "disabled row shows a reason label")
		if reason_label != null:
			_check(reason_label.text.begins_with("needs:"),
					"reason text states what's needed (got '%s')" % reason_label.text)
			_check(reason_label.text.find("organis") != -1,
					"reason text names the unmet closing-decision requirement (got '%s')" % reason_label.text)

	# Picking the enabled row: resets that chapter and fires chapter_chosen.
	var chosen_ids: Array[String] = []
	select.chapter_chosen.connect(func(id: String): chosen_ids.append(id))
	state.set_flag("some.other.chapter.flag", "kept")
	if unlocked_button != null:
		unlocked_button.pressed.emit()
	_check(chosen_ids == [UNLOCKED_ID], "picking the row fires chapter_chosen(%s)" % UNLOCKED_ID)
	_check(state.active_chapter_id == UNLOCKED_ID, "GameState.active_chapter_id is set to the chosen chapter")
	_check(state.get_flag("some.other.chapter.flag") == "kept",
			"reset_chapter() leaves an unrelated chapter's flag alone")

	# Escape: resolved by the "chapter_select" context this screen pushed,
	# not a crash and not a second registration stacking on top of it.
	_check(UiStateMachine.active_context() == &"chapter_select",
			"chapter select owns the active Escape context")
	var back_fired := [false]
	select.back_requested.connect(func(): back_fired[0] = true)
	select._go_back()
	_check(back_fired[0], "Escape's registered handler fires back_requested")

	select.queue_free()


func _report() -> void:
	if _failures.is_empty():
		print("chapter select probe: PASS")
	else:
		print("chapter select probe: FAIL (", _failures.size(), ")")
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
