## Loads and serves the chapter content layer for A Night at Ziggy's.
##
## Registered as the ChapterDB autoload (see project.godot), so it runs
## before any scene that needs chapter data. Every content/chapters/*.json
## file is read and validated against chapter.schema.json via
## ChapterSchemaValidator on boot, then run through check_chapter_valid()
## for two business-logic checks the schema alone cannot express: every
## cast id must be a real NPC with loaded dialogue content, and every
## beat's kind must be one of the closed five (ambience, lighting,
## dialogue, decision, end). A chapter that fails either schema validation
## or these checks is loud, not silent - push_error names the file and the
## exact violation (the offending cast id or beat kind) - and is excluded
## from the loaded set. One bad chapter file never blocks its siblings.
##
## No beat execution lives here yet (that is later work); this is purely
## the load/validate/query layer, mirroring how DialogueDB loads
## content/dialogue/*.json.
extends Node

const CHAPTERS_DIR := "res://content/chapters/"
const SCHEMA_FILENAME := "chapter.schema.json"
const KNOWN_BEAT_KINDS: Array[String] = ["ambience", "lighting", "dialogue", "decision", "end"]

## chapter id (String, from the file's "id" field) -> parsed, validated
## chapter Dictionary.
var _chapters: Dictionary = {}
## chapter id (String) -> true once that file has loaded and validated clean.
var _valid: Dictionary = {}
## Every push_error message produced by the most recent _load_all(), in
## order, for QA/debug introspection.
var _errors: Array[String] = []


func _ready() -> void:
	_load_all()


## Reloads every content file from disk and re-validates. Exposed so a dev
## test can re-run this without restarting the game; edits to JSON take
## effect on the next call with no code change.
func _load_all() -> void:
	_chapters.clear()
	_valid.clear()
	_errors.clear()
	var schema := ChapterSchemaValidator.load_schema()
	if schema.is_empty():
		_report_error("ChapterDB: could not load chapter.schema.json; no chapter content will be available")
		return

	for path in _list_chapter_files():
		var result := ChapterSchemaValidator.validate_file(path, schema)
		if not result["ok"]:
			for error in result["errors"]:
				_report_error("ChapterDB: %s" % error)
			_report_error("ChapterDB: '%s' failed schema validation (%d error(s)); it will not be loaded" % [path, (result["errors"] as Array).size()])
			continue

		var data: Dictionary = result["data"]
		var chapter_id: String = data.get("id", "")
		var business_errors := check_chapter_valid(path, data)
		if not business_errors.is_empty():
			for error in business_errors:
				_report_error("ChapterDB: %s" % error)
			_report_error("ChapterDB: '%s' failed content checks (%d error(s)); it will not be loaded" % [path, business_errors.size()])
			continue

		if _valid.has(chapter_id):
			_report_error("ChapterDB: '%s' declares id '%s', which is already used by another loaded chapter file; it will not be loaded" % [path, chapter_id])
			continue

		_chapters[chapter_id] = data
		_valid[chapter_id] = true


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


func _report_error(message: String) -> void:
	push_error(message)
	_errors.append(message)


## Business-logic checks beyond raw JSON Schema, mirroring DialogueDB's
## check_content_complete(): every cast id must name a real NPC that also
## has a loaded DialogueDB entry, and every beat's kind must be one of the
## closed five - defense in depth alongside the schema's own enum, so this
## still fires even against synthetic data built by hand. Pure function of
## already-parsed data plus DialogueDB/NpcDefs state, so it can be
## exercised directly without touching disk. Returns a list of human-
## readable errors naming `source_label` (empty if `data` passes).
static func check_chapter_valid(source_label: String, data: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	var cast: Array = data.get("cast", [])
	var known_npc_ids: Array[StringName] = NpcDefs.ids()
	for raw_npc_id in cast:
		var npc_id_string := String(raw_npc_id)
		var npc_id := StringName(npc_id_string)
		if not known_npc_ids.has(npc_id):
			errors.append("%s: cast names unknown NPC '%s' (no entry in NpcDefs)" % [source_label, npc_id_string])
		elif not DialogueDB.is_loaded(npc_id):
			errors.append("%s: cast names NPC '%s', which has no loaded DialogueDB entry" % [source_label, npc_id_string])

	var beats: Array = data.get("beats", [])
	for raw_beat in beats:
		var beat: Dictionary = raw_beat
		var kind: String = beat.get("kind", "")
		if not KNOWN_BEAT_KINDS.has(kind):
			errors.append("%s: beat '%s' has unknown kind '%s' (expected one of %s)" % [source_label, beat.get("id", "?"), kind, KNOWN_BEAT_KINDS])

	return errors


## Prefix marking a chapter as test data. Fixtures live alongside real
## chapters because the probes load them through the real loader — but they
## are not content, and a player must never be offered "Fixture: Unknown Beat
## Kind" on the menu. They shipped straight into chapter select.
const FIXTURE_PREFIX := "fixture-"

## Probes that drive the REAL chapter select need the fixtures to appear in
## it — hiding them would mean the greyed-out "needs:" row is never tested
## through the UI it actually ships in. Off by default, so a player never
## sees test data; a probe sets it true in _ready() before the menu builds.
var show_fixtures: bool = false


func is_fixture(id: String) -> bool:
	return id.begins_with(FIXTURE_PREFIX)


## All chapter ids that loaded and validated clean, EXCLUDING test fixtures.
## Probes that need the fixtures ask for all_ids().
func ids() -> Array[String]:
	var result: Array[String] = []
	for id in _chapters.keys():
		if is_fixture(id) and not show_fixtures:
			continue
		result.append(id)
	return result


## Everything that loaded, fixtures included — for the probes only.
func all_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _chapters.keys():
		result.append(id)
	return result


## Returns the parsed chapter Dictionary for `id`, or an empty Dictionary
## if it never loaded/validated. Named get_chapter() rather than get():
## Object already defines a native get(StringName) -> Variant, and
## GDScript refuses to compile an incompatible override of it.
func get_chapter(id: String) -> Dictionary:
	return _chapters.get(id, {})


## True once `id`'s chapter file has loaded and validated with zero errors.
func is_loaded(id: String) -> bool:
	return _valid.get(id, false)


## Every push_error message produced by the most recent load, in order, for
## QA/debug introspection (e.g. a probe asserting a specific failure fired).
func load_errors() -> Array[String]:
	return _errors.duplicate()


## The first entry in `id`'s `requires` array (if any) the current save does
## not satisfy, checked in declaration order via SaveManager.current_flag_value()
## - an empty Dictionary means every requirement is met (including a chapter
## with no `requires` at all, the common case per spec-chapters.md). This is
## the single source of truth chapter_select.gd's locked/unlocked rows and
## reason text are built from, so a probe can assert "locked"/"unlocked"
## against ChapterDB directly rather than only through the UI. An unknown id
## has no requires and is reported met, matching get_chapter()'s own "empty
## Dictionary" answer for that case.
func first_unmet_requirement(id: String) -> Dictionary:
	var save_mgr := get_node_or_null(^"/root/SaveManager")
	for raw_req in get_chapter(id).get("requires", []):
		var req: Dictionary = raw_req
		var flag := String(req.get("flag", ""))
		var equals: Variant = req.get("equals")
		var current_value := "" if save_mgr == null else String(save_mgr.current_flag_value(flag))
		if current_value != String(equals):
			return req
	return {}


## True if every entry in `id`'s `requires` array is satisfied by the
## current save (or `id` has none). See first_unmet_requirement() for the
## actual check.
func requirements_met(id: String) -> bool:
	return first_unmet_requirement(id).is_empty()


## Every distinct `writes` key declared by `id`'s own beats (decision beats
## today; any future beat kind that gains a `writes` key is covered for
## free, since this reads the field generically rather than matching on
## kind). GameState.reset_chapter() uses this to clear only the flags a
## chapter owns on entry, never another chapter's. Empty for an unknown/
## unloaded id - also the correct answer for the "no chapter wired up" ""
## sentinel, which is not a ChapterDB entry and owns no flags dict keys.
func writes_keys_for(id: String) -> Array[String]:
	var keys: Array[String] = []
	for raw_beat in get_chapter(id).get("beats", []):
		var beat: Dictionary = raw_beat
		var writes_key := String(beat.get("writes", ""))
		if writes_key != "" and not keys.has(writes_key):
			keys.append(writes_key)
	return keys
