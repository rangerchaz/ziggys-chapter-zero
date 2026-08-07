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
## `dialogue`, `decision` and `end` beat kinds are not implemented yet
## (later work, per spec-chapters.md) - a beat of any of those kinds is
## treated as satisfied the instant its own trigger fires, so the walk is
## never blocked waiting on a kind this phase doesn't run, but nothing
## plays for it either.
class_name BeatRunner
extends Node

@export var chapter_id: String = ""
@export var dialogue_ui_path: NodePath
@export var brownout_director_path: NodePath

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
		_:
			pass  # dialogue/decision/end: engine work for a later phase.


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
