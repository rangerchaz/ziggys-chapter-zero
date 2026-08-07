## Phase 2's generic beat-sequencing engine: walks a loaded chapter's
## `beats` array in declaration order, evaluates each beat's `after`
## trigger, and runs the two beat kinds this phase implements - `ambience`
## (a static lighting/audio preset switch) and `lighting` (a named
## scripted sequence; `brownout` is the only one that exists today, and it
## delegates to BrownoutDirector.run_brownout_sequence()).
##
## Replaces BrownoutDirector's own self-triggering: the distinct-
## conversation counting that used to live inside BrownoutDirector's
## _on_conversation_completed() now lives here, generically, against
## `_conversation_log` - any beat's `after: {conversations, since}` can use
## it, not just the brownout one. GameState.brownout_fired is the
## idempotency guard against a lighting beat re-firing, and this node sets
## it (see _fire_brownout()), not BrownoutDirector.
##
## Phase 3 completes the closed beat-kind set: `dialogue` (a scripted
## one-off NPC line, sourced from that NPC's existing DialogueDB content -
## no new authoring path), `decision` (an N-option prompt built from the
## beat's own `choices` array, writing the chosen id to GameState.flags
## under the beat's `writes` key via DialogueUI.open_decision() - never
## DialogueUI.get_closing_choices()' hardcoded Caroline path), and `end`
## (the chapter is over: emits chapter_ended and returns to the title
## screen). Like every other kind, firing one of these three only means
## "reached" - _fired[beat_id] is set and the walk continues immediately;
## the dialogue/decision UI itself resolves later, on the player's own
## time, and its completion re-enters the trigger system exactly like any
## other conversation (DialogueUI.conversation_completed), so a later
## beat's `after: {conversations: 1, since: <this beat>}` is what actually
## waits for the player to finish it.
##
## Phase 5 converts Chapter Zero itself to data (content/chapters/
## chapter-zero.json) and, with it, absorbs ClosingTimeDirector's own
## self-wiring the same way it already absorbed BrownoutDirector's: a
## chapter's `decision` beat `after` trigger replaces ClosingTimeDirector's
## own distinct-conversation counting, and debug_closing_time (F10) moves
## here alongside debug_brownout (see _debug_force_closing_time()).
## ClosingTimeDirector.fire() remains as the callable action for the no-
## chapter-loaded fallback (see the room's default "" chapter_id, used by
## probes that instantiate it directly rather than through chapter select).
class_name BeatRunner
extends Node

## Emitted once an `end` beat fires. `auto_return_to_title` (default true)
## drives BeatRunner's own transition back to the title screen right after;
## tests set it false and assert this signal instead, so checking "end"
## fired never has to survive an actual scene swap out from under a running
## test tree.
signal chapter_ended(chapter_id: String)

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"

@export var chapter_id: String = ""
@export var dialogue_ui_path: NodePath
@export var brownout_director_path: NodePath
@export var closing_time_director_path: NodePath
@export var auto_return_to_title: bool = true

## Named `ambience` presets: a warm-rig scale factor plus an AudioDirector
## state, applied directly through LightRegistry.scale_warm_lights() /
## AudioDirector.set_ambience_state() - a static preset switch, not an
## animated transition BeatRunner authors itself. Only two AudioDirector
## states exist today (normal/low_hum), so `cold` and `dark` both duck
## audio the same way; `cold` leaves a dim wash of warm light, `dark` cuts
## it entirely.
const AMBIENCE_PRESETS := {
	"warm": {"light_factor": 1.0, "audio_state": &"normal"},
	"cold": {"light_factor": 0.4, "audio_state": &"low_hum"},
	"dark": {"light_factor": 0.0, "audio_state": &"low_hum"},
}

## The only implemented named `lighting` beat.
const LIGHTING_BROWNOUT := "brownout"

@onready var _dialogue: Control = get_node_or_null(dialogue_ui_path)
@onready var _brownout: Node = get_node_or_null(brownout_director_path)
@onready var _closing_time: Node = get_node_or_null(closing_time_director_path)

var _beats: Array = []
## beat id (String) -> true once that beat has run.
var _fired: Dictionary = {}
## beat id (String) -> _conversation_log.size() at the moment it fired -
## the checkpoint an `after.since` trigger on a later beat counts forward
## from, per acceptance criterion 3.
var _checkpoints: Dictionary = {}
## Every conversation_completed npc_id, in arrival order, since this
## runner started - the single source of truth every `after.conversations`
## trigger counts distinct entries out of.
var _conversation_log: Array = []
var _cursor: int = 0


func _ready() -> void:
	if _dialogue != null and _dialogue.has_signal(&"conversation_completed"):
		_dialogue.conversation_completed.connect(_on_conversation_completed)
	if chapter_id != "":
		start(chapter_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_brownout"):
		_debug_force_brownout()
	elif event.is_action_pressed(&"debug_closing_time"):
		_debug_force_closing_time()


## Loads `id`'s beats from ChapterDB and starts walking them from the top.
func start(id: String) -> void:
	chapter_id = id
	load_beats(ChapterDB.get_chapter(id).get("beats", []))


## Test/direct entry point: runs `beats` (already-parsed beat Dictionaries,
## the same shape ChapterDB produces) without going through ChapterDB -
## mirrors ChapterDB.check_chapter_valid()'s pure-function testability, so
## trigger/sequencing logic can be exercised against synthetic data.
func load_beats(beats: Array) -> void:
	_beats = beats
	_fired.clear()
	_checkpoints.clear()
	_conversation_log.clear()
	_cursor = 0
	_advance()


## True once `beat_id` has run (for tests/QA introspection).
func has_fired(beat_id: String) -> bool:
	return _fired.has(beat_id)


func _on_conversation_completed(npc_id: StringName) -> void:
	_conversation_log.append(npc_id)
	_advance()


## Walks forward from `_cursor`, firing every beat whose trigger is
## already satisfied, and stops at the first one that is still waiting.
func _advance() -> void:
	while _cursor < _beats.size():
		var beat: Dictionary = _beats[_cursor]
		if not _trigger_met(beat):
			break
		_fire_beat_at(_cursor)
		_cursor += 1


## `after` absent/empty = on_start, fires the instant it's reached.
## `{conversations: N}` = N distinct conversations completed since this
## runner started. `{conversations: N, since: <beat_id>}` = N distinct
## conversations completed since `since` fired - not yet met at all if
## `since` hasn't fired yet.
func _trigger_met(beat: Dictionary) -> bool:
	var after: Dictionary = beat.get("after", {})
	if after.is_empty():
		return true
	var needed := int(after.get("conversations", 0))
	var since_id: String = after.get("since", "")
	var start_index := 0
	if since_id != "":
		if not _checkpoints.has(since_id):
			return false
		start_index = _checkpoints[since_id]
	var distinct: Dictionary = {}
	for i in range(start_index, _conversation_log.size()):
		distinct[_conversation_log[i]] = true
	return distinct.size() >= needed


func _fire_beat_at(index: int) -> void:
	var beat: Dictionary = _beats[index]
	var beat_id: String = beat.get("id", "")
	_run_beat(beat)
	_fired[beat_id] = true
	_checkpoints[beat_id] = _conversation_log.size()


func _run_beat(beat: Dictionary) -> void:
	match String(beat.get("kind", "")):
		"ambience":
			_run_ambience(beat)
		"lighting":
			_run_lighting(beat)
		"dialogue":
			_run_dialogue(beat)
		"decision":
			_run_decision(beat)
		"end":
			_run_end(beat)
		_:
			pass


func _run_ambience(beat: Dictionary) -> void:
	var preset_name: String = beat.get("preset", "warm")
	if not AMBIENCE_PRESETS.has(preset_name):
		push_warning("BeatRunner: unknown ambience preset '%s'" % preset_name)
		return
	var preset: Dictionary = AMBIENCE_PRESETS[preset_name]
	LightRegistry.scale_warm_lights(get_tree(), preset["light_factor"])
	var audio: Node = get_node_or_null(^"/root/AudioDirector")
	if audio != null:
		audio.set_ambience_state(preset["audio_state"])


func _run_lighting(beat: Dictionary) -> void:
	var preset_name: String = beat.get("preset", "")
	if preset_name != LIGHTING_BROWNOUT:
		push_warning("BeatRunner: unknown lighting preset '%s'" % preset_name)
		return
	_fire_brownout()


## Makes `npc` say a line straight from their existing DialogueDB content -
## no new dialogue authoring path. Resolves pre/post-brownout state exactly
## as DialogueUI.open_for() would, but calls open_with_lines() directly
## (bypassing open_for()'s Caroline-closing-time special case, which has no
## business firing from a chapter's own scripted `dialogue` beat).
func _run_dialogue(beat: Dictionary) -> void:
	var beat_id: String = beat.get("id", "")
	if _dialogue == null:
		push_warning("BeatRunner: dialogue beat '%s' has no DialogueUI wired up" % beat_id)
		return
	var npc_id := StringName(beat.get("npc", ""))
	if npc_id == &"":
		push_warning("BeatRunner: dialogue beat '%s' has no 'npc'" % beat_id)
		return
	var dialogue_db: Node = get_node(^"/root/DialogueDB")
	var state: Node = get_node(^"/root/GameState")
	var dstate: StringName = dialogue_db.STATE_POST_BROWNOUT if state.brownout_fired else dialogue_db.STATE_PRE_BROWNOUT
	var lines: Array[String] = dialogue_db.get_lines(npc_id, dstate)
	var display_name := NpcDefs.display_name_of(npc_id)
	_dialogue.open_with_lines(display_name if display_name != "" else String(npc_id), lines)


## Opens an N-option prompt built from the beat's own `choices` array
## (DialogueUI.open_decision(), never get_closing_choices()' hardcoded
## Caroline path) and, on selection, writes the chosen id to GameState.flags
## under `writes` - a chapter-namespaced key the beat's author is
## responsible for naming (see spec-chapters.md), persisted by SaveManager
## alongside Chapter Zero's three existing keys.
func _run_decision(beat: Dictionary) -> void:
	var beat_id: String = beat.get("id", "")
	if _dialogue == null:
		push_warning("BeatRunner: decision beat '%s' has no DialogueUI wired up" % beat_id)
		return
	var npc_id := StringName(beat.get("npc", ""))
	var display_name := NpcDefs.display_name_of(npc_id)
	if display_name == "":
		display_name = String(npc_id)
	var choice_ids: Array[String] = []
	for raw_choice in beat.get("choices", []):
		choice_ids.append(String(raw_choice))
	var writes_key: String = beat.get("writes", "")
	if writes_key == "":
		push_warning("BeatRunner: decision beat '%s' has no 'writes' key" % beat_id)
	var state: Node = get_node(^"/root/GameState")
	_dialogue.open_decision(npc_id, display_name, choice_ids, func(chosen_id: StringName) -> void:
		if writes_key != "":
			state.set_flag(writes_key, String(chosen_id))
	)


## The chapter is over: emits chapter_ended (so anything already listening,
## including tests, knows this beat ran) and, unless a test has opted out
## via auto_return_to_title, hands control back to the title screen -
## chapter select does not exist yet, so the title screen is the front door
## this returns to. Nothing here needs its own Escape handling: whatever UI
## was open when this beat fired (a dialogue/decision panel) has already
## popped its own UiStateMachine context by the time it finished and
## triggered the `after` trigger that reached this beat, so there is
## nothing left registered to leak across the scene change.
func _run_end(beat: Dictionary) -> void:
	chapter_ended.emit(chapter_id)
	if not auto_return_to_title:
		return
	var err := get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		push_error("BeatRunner: could not return to title screen after 'end' beat '%s' (error %d)" % [beat.get("id", ""), err])


## GameState.brownout_fired is the idempotency guard against a `lighting:
## brownout` beat re-firing - BeatRunner checks and sets it (BrownoutDirector
## no longer does either), so a beat that already ran, whether via the
## organic trigger or a debug key force-fire, never restarts or stacks the
## sequence's tweens no matter how many more times it's asked.
func _fire_brownout() -> void:
	var state: Node = get_node(^"/root/GameState")
	if state.brownout_fired:
		return
	state.brownout_fired = true
	if _brownout != null and _brownout.has_method(&"run_brownout_sequence"):
		_brownout.run_brownout_sequence()


## debug_brownout (F9): force-fires the current chapter's next pending
## `lighting` beat - the same call an organic trigger would make - so
## debug and organic firing always go through the same path and can never
## disagree about what happened. If no chapter is loaded, or none of its
## `lighting` beats is still pending, this falls back to firing the
## brownout sequence directly: brownout is the only lighting sequence in
## the game today, and the fallback keeps the debug key working in scenes
## with no chapter wired up yet (chapter content authoring is later work).
func _debug_force_brownout() -> void:
	for i in _beats.size():
		var beat: Dictionary = _beats[i]
		if String(beat.get("kind", "")) == "lighting" and not _fired.has(beat.get("id", "")):
			_fire_beat_at(i)
			if i == _cursor:
				_cursor += 1
				_advance()
			return
	_fire_brownout()


## debug_closing_time (F10): the same idea as _debug_force_brownout() above,
## for a chapter's `decision` beat instead of its `lighting` one. If no
## chapter is loaded, or none of its `decision` beats is still pending, this
## falls back to ClosingTimeDirector.fire(true) directly - the pre-chapter-
## data behaviour every windowed QA probe that instantiates the room without
## going through chapter select still relies on, and it stays consistent
## with GameState.brownout_fired exactly as ClosingTimeDirector's own fire()
## always has (firing the brownout first via BrownoutDirector if needed).
func _debug_force_closing_time() -> void:
	for i in _beats.size():
		var beat: Dictionary = _beats[i]
		if String(beat.get("kind", "")) == "decision" and not _fired.has(beat.get("id", "")):
			_fire_beat_at(i)
			if i == _cursor:
				_cursor += 1
				_advance()
			return
	if _closing_time != null and _closing_time.has_method(&"fire"):
		_closing_time.fire(true)
