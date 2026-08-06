## Versioned JSON save/load for A Night at Ziggy's chapter state.
##
## SAVE FORMAT VERSION 1 (this file is the convention's only definition -
## see docs/SAVE_FORMAT.md for the human-readable copy). Written to
## user://ziggys_chapter_zero_save.json - NEVER res://, which is read-only
## once exported and would not survive a real install anyway. The file is
## a flat JSON object:
##
##   {
##     "version": 1,
##     "saved_at": "2026-08-06T18:04:00",
##     "ziggys_chapter_zero.closing_decision": "organize",
##     "ziggys_chapter_zero.selected_meckie": "droid",
##     "ziggys_chapter_zero.brownout_seen": true
##   }
##
## "version" is a plain integer and must be checked before anything else
## is trusted - load_save() rejects any file whose version isn't exactly
## SAVE_VERSION rather than guessing at a migration, since no prior version
## of this format has ever existed. A later separate campaign project
## reading this file should do the same: check "version" first, then read
## the "ziggys_chapter_zero.*" keys verbatim (they are deliberately flat,
## dotted string keys, not a nested "ziggys_chapter_zero" object).
##
## ziggys_chapter_zero.closing_decision is a STRING, one of exactly four
## enumerated ids (never a bare integer index, so the meaning survives even
## if this chapter's choice ORDER ever changes): "organize", "quiet_watch",
## "wait_it_out", "not_my_problem" (see CLOSING_DECISION_VALUES below, and
## content/dialogue/caroline.json which is where these ids originate). An
## empty string means "not decided yet" and is not itself one of the four.
##
## Registered as the SaveManager autoload (see project.godot), after
## GameState so GameState already exists when this runs. Saves itself
## automatically whenever GameState's Meckie pick, brownout flag, or
## closing decision changes, and loads once at boot, before the title
## screen's _ready() runs - so GameState already reflects a prior run's
## save by the time any UI reads it.
extends Node

## Emitted after a save file has been successfully parsed and applied to
## GameState. Nothing currently listens, but it's the hook a title-screen
## or room readout would use instead of polling.
signal save_loaded

const SAVE_PATH := "user://ziggys_chapter_zero_save.json"
const SAVE_VERSION := 1

## Flat, dotted, namespaced keys - see the header comment above for why
## they are flat strings rather than a nested object.
const KEY_CLOSING_DECISION := "ziggys_chapter_zero.closing_decision"
const KEY_SELECTED_MECKIE := "ziggys_chapter_zero.selected_meckie"
const KEY_BROWNOUT_SEEN := "ziggys_chapter_zero.brownout_seen"

## The only valid ziggys_chapter_zero.closing_decision values. Matches the
## four choice ids authored in content/dialogue/caroline.json (Phase 13).
const CLOSING_DECISION_VALUES: Array[String] = [
	"organize",
	"quiet_watch",
	"wait_it_out",
	"not_my_problem",
]

## Player-facing summaries of each enumerated value, for a title-screen or
## in-room "last time, the room decided..." readout. Kept next to the
## enumeration itself so the two can never drift out of sync.
const CLOSING_DECISION_SUMMARIES := {
	"organize": "The room decided to organize.",
	"quiet_watch": "The room decided to keep an eye on each other, quietly.",
	"wait_it_out": "The room decided to wait it out.",
	"not_my_problem": "The room decided it wasn't their fight.",
}

## Empty string, not a possible closing_decision id: means "no decision
## recorded yet" both in GameState.closing_decision (GameState.NONE) and
## in a save file written before the closing prompt was ever answered.
const CLOSING_DECISION_UNSET := ""

## Set by load_save() on a rejected/unreadable file; empty after a clean
## load or when there was nothing to load. Exposed for tests and for any
## UI that wants to surface why a save didn't apply.
var last_load_error: String = ""


func _ready() -> void:
	var state := get_node(^"/root/GameState")
	state.meckie_selected.connect(func(_v): save())
	state.brownout_changed.connect(func(_v): save())
	state.closing_decision_made.connect(func(_v): save())
	load_save()


## Writes GameState's persisted fields to SAVE_PATH via a temp-file-then-
## rename so an interrupted write can never leave a half-written or
## corrupted save in place - a reader either sees the old file or the
## fully-written new one, never a partial one.
func save() -> void:
	var state := get_node(^"/root/GameState")
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		KEY_CLOSING_DECISION: String(state.closing_decision),
		KEY_SELECTED_MECKIE: String(state.selected_meckie),
		KEY_BROWNOUT_SEEN: state.brownout_fired,
	}
	_write_atomic(payload)


func _write_atomic(payload: Dictionary) -> bool:
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open %s for writing (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp_path, SAVE_PATH)
	if err != OK:
		push_warning("SaveManager: could not rename %s into place (error %d)" % [SAVE_PATH, err])
		return false
	return true


## Reads SAVE_PATH if present and applies it to GameState. A missing file
## is the ordinary "fresh chapter" case, not an error: it's silently
## skipped and GameState keeps its just-initialized defaults. A file that
## exists but fails to parse, or whose "version" isn't SAVE_VERSION, is
## reported via push_error() and last_load_error and otherwise ignored -
## GameState is left at defaults rather than partially applied.
func load_save() -> void:
	last_load_error = ""
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		last_load_error = "could not open %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()]
		push_error("SaveManager: %s" % last_load_error)
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_load_error = "%s does not contain a valid JSON object" % SAVE_PATH
		push_error("SaveManager: %s" % last_load_error)
		return

	var data: Dictionary = parsed
	if not data.has("version"):
		last_load_error = "%s is missing its version field" % SAVE_PATH
		push_error("SaveManager: %s" % last_load_error)
		return
	var version: Variant = data["version"]
	if not (version is int or version is float) or int(version) != SAVE_VERSION:
		last_load_error = "%s has unsupported version %s (expected %d)" % [SAVE_PATH, str(version), SAVE_VERSION]
		push_error("SaveManager: %s" % last_load_error)
		return

	_apply_to_game_state(data)
	save_loaded.emit()


func _apply_to_game_state(data: Dictionary) -> void:
	var state := get_node(^"/root/GameState")

	var meckie := String(data.get(KEY_SELECTED_MECKIE, ""))
	if meckie != "" and StringName(meckie) in state.MECKIES:
		state.selected_meckie = StringName(meckie)

	state.brownout_fired = bool(data.get(KEY_BROWNOUT_SEEN, false))

	var decision := String(data.get(KEY_CLOSING_DECISION, ""))
	if decision in CLOSING_DECISION_VALUES:
		state.closing_decision = StringName(decision)
