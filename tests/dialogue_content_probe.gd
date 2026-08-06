## Phase 8 dev/test entry point, runnable headless:
##
##     godot --headless --path . res://tests/dialogue_content_probe.tscn
##
## Validates every content/dialogue/<npc_id>.json against
## dialogue.schema.json via DialogueSchemaValidator, prints a per-NPC
## pass/fail table, and checks the content-layer acceptance criteria that
## span multiple files: all ten NPCs present with a pre_brownout and a
## post_brownout line, no two NPCs sharing an identical post_brownout
## string, and Caroline's closing entry carrying exactly four distinct
## choices, each with an id and answer text. Exits 0 on pass, 1 on failure.
##
## Phase 12 extends this with two more checks: an explicit "exactly ten
## distinct, non-empty post_brownout reaction strings" assertion (the
## per-NPC/uniqueness checks above imply it, but the acceptance criterion
## asks for it named directly), and a check that DialogueDB's content-
## completeness guard actually fires loud on synthetic data missing
## post_brownout, rather than trusting that it would.
extends Node

const DIALOGUE_DIR := "res://content/dialogue/"

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	var schema := DialogueSchemaValidator.load_schema()
	if schema.is_empty():
		_fail("Could not load dialogue.schema.json")
		return

	var ids: Array[StringName] = NpcDefs.ids()
	var parsed_by_id: Dictionary = {}
	var rows: Array[String] = []

	for npc_id in ids:
		var path := "%s%s.json" % [DIALOGUE_DIR, String(npc_id)]
		var result := DialogueSchemaValidator.validate_file(path, schema)
		if result["ok"]:
			rows.append("  %-10s PASS" % String(npc_id))
			parsed_by_id[npc_id] = result["data"]
		else:
			rows.append("  %-10s FAIL" % String(npc_id))
			for error in result["errors"]:
				_fail("%s: %s" % [npc_id, error])

	print("Dialogue content validation (%d NPCs):" % ids.size())
	for row in rows:
		print(row)

	_check_pre_and_post_lines(ids, parsed_by_id)
	_check_unique_post_brownout(ids, parsed_by_id)
	_check_caroline_closing(parsed_by_id)
	_check_ten_distinct_post_brownout(ids, parsed_by_id)
	_check_missing_post_brownout_guard()


func _check_pre_and_post_lines(ids: Array[StringName], parsed_by_id: Dictionary) -> void:
	for npc_id in ids:
		if not parsed_by_id.has(npc_id):
			continue  # Already failed schema validation above.
		var data: Dictionary = parsed_by_id[npc_id]
		var entries: Dictionary = data.get("entries", {})
		for state in ["pre_brownout", "post_brownout"]:
			var lines: Array = entries.get(state, {}).get("lines", [])
			if lines.is_empty():
				_fail("%s: missing a non-empty '%s' line" % [npc_id, state])


func _check_unique_post_brownout(ids: Array[StringName], parsed_by_id: Dictionary) -> void:
	var seen: Dictionary = {}  # line text -> npc_id that used it first
	for npc_id in ids:
		if not parsed_by_id.has(npc_id):
			continue
		var data: Dictionary = parsed_by_id[npc_id]
		var lines: Array = data.get("entries", {}).get("post_brownout", {}).get("lines", [])
		for line in lines:
			if seen.has(line):
				_fail("post_brownout line is identical between '%s' and '%s': \"%s\"" % [seen[line], npc_id, line])
			else:
				seen[line] = npc_id


func _check_caroline_closing(parsed_by_id: Dictionary) -> void:
	if not parsed_by_id.has(&"caroline"):
		_fail("caroline: no valid content to check closing choices against")
		return
	var data: Dictionary = parsed_by_id[&"caroline"]
	var closing: Dictionary = data.get("entries", {}).get("closing", {})
	if closing.is_empty():
		_fail("caroline: missing a 'closing' entry")
		return
	var choices: Array = closing.get("choices", [])
	if choices.size() != 4:
		_fail("caroline: closing entry has %d choice(s), expected exactly 4" % choices.size())

	var ids_seen: Dictionary = {}
	for raw in choices:
		var choice: Dictionary = raw
		var choice_id: String = choice.get("id", "")
		var text: String = choice.get("text", "")
		if choice_id.is_empty():
			_fail("caroline: a closing choice is missing a non-empty 'id'")
		elif ids_seen.has(choice_id):
			_fail("caroline: duplicate closing choice id '%s'" % choice_id)
		else:
			ids_seen[choice_id] = true
		if text.is_empty():
			_fail("caroline: closing choice '%s' is missing non-empty answer text" % choice_id)


## Deliverable 5 / acceptance criterion 4, asserted directly rather than
## just implied by the two checks above: exactly ten NPCs each carry a
## non-empty post_brownout reaction, and all ten are distinct from each
## other (a Dictionary keyed by line text collapses duplicates, so its size
## after inserting all ten must still be ten).
func _check_ten_distinct_post_brownout(ids: Array[StringName], parsed_by_id: Dictionary) -> void:
	var reactions: Dictionary = {}  # reaction text -> npc_id
	for npc_id in ids:
		if not parsed_by_id.has(npc_id):
			continue  # Already failed schema validation above.
		var data: Dictionary = parsed_by_id[npc_id]
		var lines: Array = data.get("entries", {}).get("post_brownout", {}).get("lines", [])
		if lines.is_empty() or String(lines[0]).is_empty():
			_fail("%s: post_brownout reaction is empty, expected a distinct non-empty line" % npc_id)
			continue
		reactions[String(lines[0])] = npc_id

	if ids.size() != 10:
		_fail("Expected exactly 10 NPCs in the roster, found %d" % ids.size())
	if reactions.size() != 10:
		_fail("Expected exactly 10 distinct non-empty post_brownout reactions, found %d" % reactions.size())


## Deliverable 3 / acceptance criterion 5: DialogueDB.check_content_complete()
## must surface a loud, non-empty error for an NPC missing post_brownout
## (synthetic data here, so this doesn't depend on any real content file
## staying broken) and must NOT flag a real NPC's actual content, which
## already has post_brownout, as incomplete.
func _check_missing_post_brownout_guard() -> void:
	var incomplete_data: Dictionary = {
		"schema_version": 1,
		"npc_id": "synthetic",
		"display_name": "Synthetic",
		"entries": {
			"pre_brownout": {"lines": ["Only a pre-brownout line."]},
		},
	}
	var errors := DialogueDB.check_content_complete(&"synthetic", incomplete_data)
	if errors.is_empty():
		_fail("DialogueDB.check_content_complete() did not flag an NPC with no post_brownout entry")

	var complete_data: Dictionary = {
		"schema_version": 1,
		"npc_id": "synthetic",
		"display_name": "Synthetic",
		"entries": {
			"pre_brownout": {"lines": ["Pre line."]},
			"post_brownout": {"lines": ["Post line."]},
		},
	}
	var no_errors := DialogueDB.check_content_complete(&"synthetic", complete_data)
	if not no_errors.is_empty():
		_fail("DialogueDB.check_content_complete() flagged a complete NPC as incomplete: %s" % no_errors)


func _report() -> void:
	if _failures.is_empty():
		print("DIALOGUE CONTENT PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("DIALOGUE CONTENT PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
