## Phase 1 dev/test entry point, runnable headless:
##
##     godot --headless --path . res://tests/chapter_validation_probe.tscn
##
## Validates every content/chapters/*.json against chapter.schema.json via
## ChapterSchemaValidator, then exercises ChapterDB's own load-time
## business checks and the ChapterDB autoload's actual boot-time result.
##
## content/chapters/ ships four fixtures for this probe only, alongside the
## real shipped content (chapter-zero.json, Phase 5) this sweep also
## validates: fixture-valid.json (should load clean), fixture-bad-cast.json
## (cast names an NPC that does not exist, should fail the cast check with
## that NPC's id named), fixture-bad-kind.json (a beat uses a kind outside
## the closed five, should fail schema validation with that kind and the
## file named), and fixture-malformed.json (invalid JSON syntax, should
## fail to parse). All four sit in the same directory so the "one bad
## chapter never blocks its siblings" behaviour is exercised by ChapterDB's
## real boot-time load, not a synthetic stand-in.
##
## Phase 6 adds two more checks: the second shipped chapter
## (content/chapters/the-morning-after.json) validates cleanly the same way
## chapter-zero.json does, and ChapterDB.first_unmet_requirement()/
## requirements_met() correctly report it locked on a fresh save and
## unlocked once GameState.closing_decision matches the value it requires -
## the gating story end to end, checked against ChapterDB itself rather
## than only through chapter_select.gd's rendering of it.
extends Node

const CHAPTERS_DIR := "res://content/chapters/"
const SCHEMA_FILENAME := "chapter.schema.json"

## Phase 6's shipped second chapter (spec-chapters.md's own worked example):
## requires Chapter Zero's closing_decision == "organize", a four-person
## cast, and its own decision beat writes ziggys.the-morning-after.decision.
const SECOND_CHAPTER_ID := "the-morning-after"

const SAVE_PATH := "user://ziggys_chapter_zero_save.json"
const BACKUP_PATH := "user://ziggys_chapter_zero_save.probe_backup.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var schema := ChapterSchemaValidator.load_schema()
	if schema.is_empty():
		_fail("Could not load chapter.schema.json")
		return

	_sweep_all_chapter_files(schema)
	_check_valid_fixture_loads_clean(schema)
	_check_unknown_cast_npc_named(schema)
	_check_unknown_beat_kind_named(schema)
	_check_malformed_json_rejected(schema)
	_check_chapter_db_boot_state()
	_check_second_chapter_validates_cleanly(schema)
	_check_second_chapter_locked_unlocked()


func _list_chapter_files() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(CHAPTERS_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json") and entry != SCHEMA_FILENAME:
			paths.append(CHAPTERS_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Deliverable 6, first half: validate every content/chapters/*.json against
## the schema plus the cast/kind checks, printing a per-file table. The
## directory intentionally holds broken fixtures, so this prints results
## rather than asserting universal pass; the specific checks below assert
## exactly which files should pass and which should fail, and why.
func _sweep_all_chapter_files(schema: Dictionary) -> void:
	var paths := _list_chapter_files()
	print("Chapter content validation (%d file(s)):" % paths.size())
	for path in paths:
		var result := ChapterSchemaValidator.validate_file(path, schema)
		if not result["ok"]:
			print("  %-30s SCHEMA FAIL (%d error(s))" % [path.get_file(), (result["errors"] as Array).size()])
			continue
		var business_errors := ChapterDB.check_chapter_valid(path, result["data"])
		if business_errors.is_empty():
			print("  %-30s PASS" % path.get_file())
		else:
			print("  %-30s CONTENT FAIL (%d error(s))" % [path.get_file(), business_errors.size()])


func _check_valid_fixture_loads_clean(schema: Dictionary) -> void:
	var path := CHAPTERS_DIR + "fixture-valid.json"
	var result := ChapterSchemaValidator.validate_file(path, schema)
	if not result["ok"]:
		_fail("fixture-valid.json unexpectedly failed schema validation: %s" % [result["errors"]])
		return
	var business_errors := ChapterDB.check_chapter_valid(path, result["data"])
	if not business_errors.is_empty():
		_fail("fixture-valid.json unexpectedly failed cast/kind checks: %s" % [business_errors])


## Acceptance criterion 2 / deliverable 6's first failure mode: a chapter
## naming an NPC with no DialogueDB entry in its cast fails with an error
## string naming that NPC.
func _check_unknown_cast_npc_named(schema: Dictionary) -> void:
	var path := CHAPTERS_DIR + "fixture-bad-cast.json"
	var result := ChapterSchemaValidator.validate_file(path, schema)
	if not result["ok"]:
		_fail("fixture-bad-cast.json unexpectedly failed schema validation (should only fail the cast check): %s" % [result["errors"]])
		return
	var errors := ChapterDB.check_chapter_valid(path, result["data"])
	var named_npc := false
	for error in errors:
		if "ghost" in String(error):
			named_npc = true
	if not named_npc:
		_fail("fixture-bad-cast.json's cast check did not name the unknown NPC 'ghost': %s" % [errors])

	# Same check exercised directly against synthetic data, independent of
	# any real content file, to prove the guard itself (not just this one
	# fixture) fires.
	var synthetic_errors := ChapterDB.check_chapter_valid("synthetic", {
		"cast": ["ghost"],
		"beats": [{"id": "wrap", "kind": "end"}],
	})
	var synthetic_named := false
	for error in synthetic_errors:
		if "ghost" in String(error):
			synthetic_named = true
	if not synthetic_named:
		_fail("ChapterDB.check_chapter_valid() did not flag an unknown cast NPC on synthetic data: %s" % [synthetic_errors])


## Acceptance criterion 3 / deliverable 6's second failure mode: an unknown
## beats[].kind fails validation with an error string naming both the bad
## kind and the file. The closed enum in the schema itself is the primary
## gate; ChapterDB.check_chapter_valid() is also exercised directly here as
## the defense-in-depth business check described in deliverable 3(b).
func _check_unknown_beat_kind_named(schema: Dictionary) -> void:
	var path := CHAPTERS_DIR + "fixture-bad-kind.json"
	var result := ChapterSchemaValidator.validate_file(path, schema)
	if result["ok"]:
		_fail("fixture-bad-kind.json unexpectedly passed schema validation (expected the closed kind enum to reject 'plot_twist')")
		return
	var found_kind := false
	var found_file := false
	for error in (result["errors"] as Array):
		var text := String(error)
		if "plot_twist" in text:
			found_kind = true
		if "fixture-bad-kind.json" in text:
			found_file = true
	if not found_kind:
		_fail("fixture-bad-kind.json's schema errors did not name the bad kind 'plot_twist': %s" % [result["errors"]])
	if not found_file:
		_fail("fixture-bad-kind.json's schema errors did not name the file: %s" % [result["errors"]])

	var synthetic_errors := ChapterDB.check_chapter_valid("synthetic", {
		"cast": [],
		"beats": [{"id": "twist", "kind": "plot_twist"}],
	})
	var synthetic_found := false
	for error in synthetic_errors:
		if "plot_twist" in String(error):
			synthetic_found = true
	if not synthetic_found:
		_fail("ChapterDB.check_chapter_valid() did not flag an unknown beat kind on synthetic data: %s" % [synthetic_errors])


## Deliverable 6's third failure mode: a chapter file with invalid JSON
## syntax fails validation (as a parse error, before schema checks even
## apply) rather than crashing the loader.
func _check_malformed_json_rejected(schema: Dictionary) -> void:
	var path := CHAPTERS_DIR + "fixture-malformed.json"
	var result := ChapterSchemaValidator.validate_file(path, schema)
	if result["ok"]:
		_fail("fixture-malformed.json unexpectedly passed validation despite invalid JSON syntax")
		return
	var found_file := false
	for error in (result["errors"] as Array):
		if "fixture-malformed.json" in String(error):
			found_file = true
	if not found_file:
		_fail("fixture-malformed.json's parse error did not name the file: %s" % [result["errors"]])


## Acceptance criteria 4 & 5, plus deliverable 6's third failure mode:
## exercised against ChapterDB's real boot-time state (the ChapterDB
## autoload already ran _load_all() over content/chapters/ before this
## probe's _ready() fired), not a synthetic stand-in. fixture-bad-cast.json
## and fixture-bad-kind.json must not prevent fixture-valid.json from
## loading, and ChapterDB.get_chapter() must return the parsed Dictionary
## for every loaded id.
func _check_chapter_db_boot_state() -> void:
	var ids := ChapterDB.ids()

	if not ids.has("fixture-valid"):
		_fail("ChapterDB.ids() did not include 'fixture-valid' even though only its siblings are broken: %s" % [ids])
	if not ChapterDB.is_loaded("fixture-valid"):
		_fail("ChapterDB.is_loaded('fixture-valid') is false even though it should have loaded clean")

	if ids.has("fixture-bad-cast"):
		_fail("ChapterDB.ids() incorrectly included 'fixture-bad-cast', which should have failed the cast check")
	if ids.has("fixture-bad-kind"):
		_fail("ChapterDB.ids() incorrectly included 'fixture-bad-kind', which should have failed schema validation")
	if ids.has("fixture-malformed"):
		_fail("ChapterDB.ids() incorrectly included 'fixture-malformed', which should have failed to parse")

	for id in ids:
		var data := ChapterDB.get_chapter(id)
		if data.is_empty():
			_fail("ChapterDB.get_chapter('%s') returned an empty Dictionary despite '%s' being in ids()" % [id, id])
		elif String(data.get("id", "")) != id:
			_fail("ChapterDB.get_chapter('%s') returned a chapter whose own 'id' field is '%s'" % [id, data.get("id", "")])

	if ChapterDB.load_errors().is_empty():
		_fail("ChapterDB.load_errors() is empty even though fixture-bad-cast.json and fixture-bad-kind.json should have produced load errors")


## Deliverable 1 proved end-to-end (2): the second chapter
## (content/chapters/the-morning-after.json) validates cleanly against the
## schema and ChapterDB's cast/kind business checks - the same worked
## example spec-chapters.md itself documents, shipped as real content
## rather than only exercised via a throwaway fixture - and ChapterDB's
## real boot-time load reports it present and loaded.
func _check_second_chapter_validates_cleanly(schema: Dictionary) -> void:
	var path := CHAPTERS_DIR + SECOND_CHAPTER_ID + ".json"
	var result := ChapterSchemaValidator.validate_file(path, schema)
	if not result["ok"]:
		_fail("%s.json unexpectedly failed schema validation: %s" % [SECOND_CHAPTER_ID, result["errors"]])
		return
	var business_errors := ChapterDB.check_chapter_valid(path, result["data"])
	if not business_errors.is_empty():
		_fail("%s.json unexpectedly failed cast/kind checks: %s" % [SECOND_CHAPTER_ID, business_errors])

	if not ChapterDB.ids().has(SECOND_CHAPTER_ID):
		_fail("ChapterDB.ids() did not include '%s' even though it should have loaded clean" % SECOND_CHAPTER_ID)
	if not ChapterDB.is_loaded(SECOND_CHAPTER_ID):
		_fail("ChapterDB.is_loaded('%s') is false even though it should have loaded clean" % SECOND_CHAPTER_ID)


## Deliverable 2: ChapterDB itself - not just chapter_select.gd's rendering
## of it - reports the second chapter as locked on a fresh save (no closing
## decision recorded) and unlocked once a synthetic GameState/save fixture
## matches the "organize" value it requires, matching acceptance criteria 1
## and 2. Backs up/restores the real save file around the mutation, the same
## precaution chapter_select_probe.gd takes, since GameState.closing_decision
## autosaves through SaveManager on every change.
func _check_second_chapter_locked_unlocked() -> void:
	var state := get_node(^"/root/GameState")
	_backup_existing_save()

	state.closing_decision = state.NONE
	if ChapterDB.first_unmet_requirement(SECOND_CHAPTER_ID).is_empty():
		_fail("ChapterDB.first_unmet_requirement('%s') is empty on a fresh save with no closing decision - should report the unmet requirement" % SECOND_CHAPTER_ID)
	if ChapterDB.requirements_met(SECOND_CHAPTER_ID):
		_fail("ChapterDB.requirements_met('%s') is true on a fresh save; should be locked until closing_decision == 'organize'" % SECOND_CHAPTER_ID)

	# A completed Chapter Zero with a DIFFERENT decision still leaves it
	# locked - proves this checks the specific required value, not just
	# "some decision was made."
	state.closing_decision = StringName("wait_it_out")
	if ChapterDB.requirements_met(SECOND_CHAPTER_ID):
		_fail("ChapterDB.requirements_met('%s') is true for closing_decision 'wait_it_out', which does not satisfy the required 'organize'" % SECOND_CHAPTER_ID)

	# The exact value the second chapter's `requires` names: unlocked.
	state.closing_decision = StringName("organize")
	var unmet_after_organize := ChapterDB.first_unmet_requirement(SECOND_CHAPTER_ID)
	if not unmet_after_organize.is_empty():
		_fail("ChapterDB.first_unmet_requirement('%s') is non-empty after simulating a completed Chapter Zero with 'organize': %s" % [SECOND_CHAPTER_ID, unmet_after_organize])
	if not ChapterDB.requirements_met(SECOND_CHAPTER_ID):
		_fail("ChapterDB.requirements_met('%s') is false after simulating a completed Chapter Zero with 'organize'" % SECOND_CHAPTER_ID)

	# Chapter Zero itself never carries `requires` and must stay reported
	# as unlocked throughout, regardless of the second chapter's own state.
	if not ChapterDB.requirements_met("chapter-zero"):
		_fail("ChapterDB.requirements_met('chapter-zero') is false; Chapter Zero has no requires and must always be unlocked")

	state.closing_decision = state.NONE
	_restore_existing_save()


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
	if _failures.is_empty():
		print("CHAPTER VALIDATION PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("CHAPTER VALIDATION PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
