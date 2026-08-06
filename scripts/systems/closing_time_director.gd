## Phase 13's chapter-progression beat: carries the room from the
## post-brownout stretch into closing time, when Caroline is ready to ask
## the room what it's going to do about the data centers.
##
## Deterministic trigger (documented choice, mirrors BrownoutDirector):
## fires once GameState.brownout_fired is true AND `trigger_conversation_count`
## distinct NPCs' conversations have been completed (DialogueUI's
## conversation_completed signal, same source BrownoutDirector counts
## against) since the beat fired - repeatable for QA by finishing that many
## post-brownout conversations in any order. Conversations completed before
## the brownout fired don't count, so this always trails the brownout beat
## rather than racing it.
##
## The debug_closing_time key (F10) jumps straight to closing time for QA,
## regardless of conversation count. If the brownout hasn't fired yet, it
## fires that first (via BrownoutDirector.fire(), so the room's lighting/
## audio/camera state stays consistent with GameState.brownout_fired)
## before flagging closing time reached, rather than leaving the two out of
## sync. Idempotent via GameState.closing_time_reached, exactly like
## BrownoutDirector.fire(): a second debug press or a further completed
## conversation after the beat has already fired is a no-op.
class_name ClosingTimeDirector
extends Node

@export var dialogue_ui_path: NodePath
@export var brownout_director_path: NodePath

## Distinct post-brownout conversations the player must fully finish
## before closing time arrives on its own; the debug key bypasses this.
@export var trigger_conversation_count := 3

@onready var _dialogue: Control = get_node_or_null(dialogue_ui_path)
@onready var _brownout: Node = get_node_or_null(brownout_director_path)

## npc_id -> true for every NPC whose conversation has been completed
## since the brownout fired.
var _completed_npcs: Dictionary = {}


func _ready() -> void:
	if _dialogue != null and _dialogue.has_signal(&"conversation_completed"):
		_dialogue.conversation_completed.connect(_on_conversation_completed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_closing_time"):
		fire(true)


func _on_conversation_completed(npc_id: StringName) -> void:
	var state: Node = get_node(^"/root/GameState")
	if not state.brownout_fired:
		return
	_completed_npcs[npc_id] = true
	if _completed_npcs.size() >= trigger_conversation_count:
		fire()


## Runs the beat exactly once per run. `force` (the debug key path) also
## fires the brownout first if it hasn't happened yet, so closing time is
## never reached in a room that still looks pre-brownout.
func fire(force: bool = false) -> void:
	var state: Node = get_node(^"/root/GameState")
	if state.closing_time_reached:
		return
	if not state.brownout_fired:
		if not force:
			return
		if _brownout != null and _brownout.has_method(&"fire"):
			_brownout.fire()
		else:
			state.brownout_fired = true
	state.closing_time_reached = true
