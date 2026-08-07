## Chapter-wide state for A Night at Ziggy's.
##
## Registered as the GameState autoload (see project.godot), so it is
## reachable from any script as `GameState`. Holds the flags a later
## chapter will read back; the save format wiring lands in a later sprint,
## so for now this is the in-memory source of truth.
extends Node

## Emitted when the player picks (or clears) their Meckie.
signal meckie_selected(meckie: StringName)
## Emitted when the brownout beat fires or is reset.
signal brownout_changed(fired: bool)
## Emitted when the chapter reaches closing time.
signal closing_time_changed(reached: bool)
## Emitted when Caroline's closing question gets an answer.
signal closing_decision_made(decision: StringName)
## Emitted whenever a chapter-namespaced flag is written (decision beats,
## via BeatRunner) - alongside, not replacing, the three typed fields below.
## SaveManager listens to this the same way it listens to their own signals,
## autosaving on every write.
signal flag_changed(key: String, value: String)

## Valid Meckie ids, matched to the cast in spec.md.
const MECKIES: Array[StringName] = [&"droid", &"eva", &"sid"]
## Sentinel for "not chosen / not answered yet".
const NONE: StringName = &""

## Which Meckie the player is controlling this chapter. NONE until the
## pick-a-Meckie flow (later sprint) sets it.
var selected_meckie: StringName = NONE:
	set(value):
		if value == selected_meckie:
			return
		selected_meckie = value
		meckie_selected.emit(value)

## True once the scripted brownout beat has happened this run.
var brownout_fired: bool = false:
	set(value):
		if value == brownout_fired:
			return
		brownout_fired = value
		brownout_changed.emit(value)

## True once the chapter has progressed into closing time (brownout fired
## plus enough post-brownout conversations, or the debug jump). Set by
## ClosingTimeDirector.
var closing_time_reached: bool = false:
	set(value):
		if value == closing_time_reached:
			return
		closing_time_reached = value
		closing_time_changed.emit(value)

## The room's answer at closing time. NONE until the decision prompt
## records one of its four options.
var closing_decision: StringName = NONE:
	set(value):
		if value == closing_decision:
			return
		closing_decision = value
		closing_decision_made.emit(value)

## Chapter-namespaced key/value pairs written by `decision` beats (e.g.
## "ziggys.the-morning-after.decision" -> "stay_open") - see
## docs/SAVE_FORMAT.md's generic-flag convention. SaveManager persists every
## entry here as its own additional top-level dotted key, alongside (never
## replacing) the three typed fields above.
var flags: Dictionary = {}

## Matches SaveManager.KEY_CLOSING_DECISION - duplicated as a literal
## rather than a live SaveManager reference, since SaveManager already
## depends on GameState and this would invert that. Chapter Zero's own
## `decision` beat (content/chapters/chapter-zero.json) writes exactly this
## key via set_flag(); without this redirect the value would land in
## `flags` instead of the typed `closing_decision` field above, and
## SaveManager.save() would then drop it entirely (its reserved-key
## collision guard sees `flags` and the typed field disagree and keeps the
## typed field, still NONE) - silently losing the decision from the save
## file. Routing it here keeps the save format's three reserved keys
## exactly as they were before this chapter existed as data.
const _CLOSING_DECISION_FLAG_KEY := "ziggys_chapter_zero.closing_decision"

## The chapter id (ChapterDB key) the room should run this session, set by
## chapter_select.gd right before the meckie-select/room hop. Empty string
## is the sentinel for "no chapter wired up" (no ChapterDB entry, no
## BeatRunner start, no cast filtering, full ten-NPC roster) - matching
## BeatRunner's own "" default for a chapter_id that was never set. Every
## chapter select row, including Chapter Zero's own (chapter-zero.json,
## Phase 5), sets a real ChapterDB id; "" is only ever seen by a probe that
## instantiates ziggys_room.tscn directly, bypassing chapter select.
var active_chapter_id: String = ""


## Records `key` = `value` and, unless it's already exactly that value,
## emits flag_changed so SaveManager autosaves it - the same pattern the
## typed fields above use via their own property setters. `key` equal to
## Chapter Zero's own reserved closing-decision key routes to the
## closing_decision typed field instead (see _CLOSING_DECISION_FLAG_KEY),
## so a chapter-zero.json `decision` beat persists exactly like the
## pre-data-format hardcoded path did; every other chapter's own
## `writes` key is unaffected and stored generically as before.
func set_flag(key: String, value: String) -> void:
	if key == _CLOSING_DECISION_FLAG_KEY:
		closing_decision = StringName(value)
		return
	if String(flags.get(key, "")) == value:
		return
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: String, default_value: String = "") -> String:
	if key == _CLOSING_DECISION_FLAG_KEY:
		return String(closing_decision)
	return String(flags.get(key, default_value))


## Returns the chapter state to its pre-run defaults (new game / retry).
## Wipes every generic flag regardless of which chapter wrote it - correct
## for "blank slate" call sites (tests, a real new-game-plus wipe), but NOT
## what entering one specific chapter should do; see reset_chapter() below.
func reset() -> void:
	selected_meckie = NONE
	brownout_fired = false
	closing_time_reached = false
	closing_decision = NONE
	flags.clear()
	active_chapter_id = ""


## Chapter-scoped counterpart to reset(): starting `chapter_id` clears this
## run's shared progress fields (selected_meckie, brownout_fired,
## closing_time_reached, closing_decision - the brownout/decision
## equivalents every chapter, including Chapter Zero itself, shares) plus
## ONLY the flags `chapter_id`'s own beats declare via `writes`
## (ChapterDB.writes_keys_for()). Every other flag survives - including one
## a different, already-completed chapter wrote to satisfy a future
## chapter's `requires` - per spec-chapters.md's "entering a chapter resets
## that chapter's state, never another's". Chapter Zero's own `writes` key
## (ziggys_chapter_zero.closing_decision) routes through set_flag() straight
## to the closing_decision typed field rather than `flags` (see
## _CLOSING_DECISION_FLAG_KEY), so erasing it here is always a harmless
## no-op; the typed-field reset three lines up is what actually clears it.
func reset_chapter(chapter_id: String) -> void:
	active_chapter_id = chapter_id
	selected_meckie = NONE
	brownout_fired = false
	closing_time_reached = false
	closing_decision = NONE
	var chapter_db := get_node_or_null(^"/root/ChapterDB")
	if chapter_db == null:
		return
	var erased_any := false
	for key in chapter_db.writes_keys_for(chapter_id):
		if flags.has(key):
			flags.erase(key)
			erased_any = true
	# flags.erase() (unlike set_flag()) emits nothing on its own, so if none
	# of the typed fields above actually changed (their setters early-return
	# on a no-op, same as set_flag() would) SaveManager would never see this
	# erasure and the on-disk save would keep the stale key - a real gap for
	# "verified by inspecting the save file before and after" (deliverable
	# 4). One flag_changed pulse forces that autosave. Reused generically:
	# SaveManager's handler ignores both arguments and just re-persists
	# GameState's current fields/flags wholesale, so this correctly captures
	# the erasure regardless of which specific key changed or whether any
	# typed field's own signal already fired one first.
	if erased_any:
		flag_changed.emit("", "")
