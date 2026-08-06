## Loads and serves the dialogue content layer for A Night at Ziggy's.
##
## Registered as the DialogueDB autoload (see project.godot), so it runs
## before any scene that needs a line. Every content/dialogue/<npc_id>.json
## file is read and validated against dialogue.schema.json via
## DialogueSchemaValidator on boot. An NPC whose file is missing or fails
## validation is loud, not silent: push_error names the file and the exact
## schema violation, and get_lines()/get_closing_choices() return empty for
## that id rather than a placeholder string, so a broken content file shows
## up immediately instead of shipping quietly wrong.
##
## The schema alone allows an NPC to omit post_brownout entirely (`entries`
## only requires minProperties: 1), so check_content_complete() adds the
## Phase 12 rule on top at load time: every NPC must carry a non-empty
## post_brownout entry. An NPC that fails this check is treated exactly
## like a schema failure - loud push_error, excluded from _content, so
## get_lines() returns empty rather than quietly falling back to its
## pre_brownout line once the beat has fired.
extends Node

const DIALOGUE_DIR := "res://content/dialogue/"
const STATE_PRE_BROWNOUT := &"pre_brownout"
const STATE_POST_BROWNOUT := &"post_brownout"
const STATE_CLOSING := &"closing"

## npc_id (StringName) -> parsed, validated content Dictionary.
var _content: Dictionary = {}
## npc_id (StringName) -> true once that file has loaded and validated clean.
var _valid: Dictionary = {}


func _ready() -> void:
	_load_all()


## Reloads every content file from disk and re-validates. Exposed so a dev
## test (or a future "reload content" debug action) can re-run this without
## restarting the game; edits to JSON take effect on the next call with no
## code change.
func _load_all() -> void:
	_content.clear()
	_valid.clear()
	var schema := DialogueSchemaValidator.load_schema()
	if schema.is_empty():
		push_error("DialogueDB: could not load dialogue.schema.json; no dialogue content will be available")
		return

	for npc_id in NpcDefs.ids():
		var path := "%s%s.json" % [DIALOGUE_DIR, String(npc_id)]
		if not FileAccess.file_exists(path):
			push_error("DialogueDB: no content file for npc_id '%s' (expected %s)" % [npc_id, path])
			continue
		var result := DialogueSchemaValidator.validate_file(path, schema)
		if not result["ok"]:
			for error in result["errors"]:
				push_error("DialogueDB: %s" % error)
			push_error("DialogueDB: '%s' failed schema validation (%d error(s)); its lines will not be available" % [npc_id, (result["errors"] as Array).size()])
			continue
		var data: Dictionary = result["data"]
		var content_id: String = data.get("npc_id", "")
		if content_id != String(npc_id):
			push_error("DialogueDB: %s declares npc_id '%s', expected '%s'" % [path, content_id, npc_id])
			continue
		var completeness_errors := check_content_complete(npc_id, data)
		if not completeness_errors.is_empty():
			for error in completeness_errors:
				push_error("DialogueDB: %s" % error)
			push_error("DialogueDB: '%s' failed content-completeness checks (%d error(s)); its lines will not be available" % [npc_id, completeness_errors.size()])
			continue
		_content[npc_id] = data
		_valid[npc_id] = true


## Content-completeness checks beyond raw JSON Schema: every NPC must carry
## at least one non-empty post_brownout line, since dialogue routing serves
## nothing (via get_lines() returning an empty array) rather than silently
## reusing pre_brownout once the beat has fired. Returns a list of
## human-readable errors (empty if `data` passes). Split out from
## _load_all() as a pure function of already-parsed content so it can be
## exercised directly against synthetic data without touching disk.
static func check_content_complete(npc_id: StringName, data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var entries: Dictionary = data.get("entries", {})
	var post: Dictionary = entries.get(String(STATE_POST_BROWNOUT), {})
	var lines: Array = post.get("lines", [])
	if lines.is_empty():
		errors.append("%s: missing a non-empty 'post_brownout' entry (required so dialogue after the brownout beat has content to show)" % npc_id)
	return errors


## True once npc_id's content file has loaded and validated with zero
## schema errors.
func is_loaded(npc_id: StringName) -> bool:
	return _valid.get(npc_id, false)


## Returns the lines for npc_id's given state ("pre_brownout" /
## "post_brownout" / "closing"), or an empty array if the NPC, the state,
## or the content file itself is missing/invalid.
func get_lines(npc_id: StringName, state: StringName) -> Array[String]:
	var lines: Array[String] = []
	var data: Dictionary = _content.get(npc_id, {})
	var entries: Dictionary = data.get("entries", {})
	var entry: Dictionary = entries.get(String(state), {})
	for line in entry.get("lines", []):
		lines.append(String(line))
	return lines


## Returns Caroline's four closing-decision options as an array of
## {"id": StringName, "text": String} dictionaries, or an empty array if
## her content is missing/invalid or has no closing entry.
func get_closing_choices(npc_id: StringName = &"caroline") -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var data: Dictionary = _content.get(npc_id, {})
	var entries: Dictionary = data.get("entries", {})
	var closing: Dictionary = entries.get(String(STATE_CLOSING), {})
	for raw in closing.get("choices", []):
		var choice: Dictionary = raw
		choices.append({"id": StringName(choice.get("id", "")), "text": String(choice.get("text", ""))})
	return choices


## Returns the line(s) shown once the player has picked one of Caroline's
## four closing choices - the chapter-end acknowledgement that the decision
## landed - or an empty array if her content has none.
func get_closing_acknowledgement(npc_id: StringName = &"caroline") -> Array[String]:
	var lines: Array[String] = []
	var data: Dictionary = _content.get(npc_id, {})
	var entries: Dictionary = data.get("entries", {})
	var closing: Dictionary = entries.get(String(STATE_CLOSING), {})
	var ack: Dictionary = closing.get("acknowledgement", {})
	for line in ack.get("lines", []):
		lines.append(String(line))
	return lines
