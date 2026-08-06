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


func _report() -> void:
	if _failures.is_empty():
		print("DIALOGUE CONTENT PROBE PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("DIALOGUE CONTENT PROBE FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
