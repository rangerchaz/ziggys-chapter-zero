## Phase 13's chapter-progression beat: carries the room from the
## post-brownout stretch into closing time, when Caroline is ready to ask
## the room what it's going to do about the data centers.
##
## Phase 2 (BrownoutDirector) and Phase 5 (this node) both moved WHEN to
## fire out of the director and into BeatRunner: the distinct-conversation
## counting this node used to do itself in _on_conversation_completed() is
## superseded for a data-driven chapter by that chapter's own `decision`
## beat `after` trigger (see scripts/systems/beat_runner.gd), and the
## debug_closing_time key (F10) is now BeatRunner's own input handling too -
## it force-fires the current chapter's next pending `decision` beat, or
## falls back to calling fire(true) directly here when no chapter is loaded
## (see BeatRunner._debug_force_closing_time()), exactly mirroring how F9
## falls back to run_brownout_sequence(). This node is now purely the
## callable action: fire() sets GameState.closing_time_reached, firing the
## brownout first (via BrownoutDirector.run_brownout_sequence()) if `force`
## is set and it hasn't happened yet, so the two flags never end up out of
## sync. Idempotent via GameState.closing_time_reached: calling fire() again
## once it's already true is a no-op.
class_name ClosingTimeDirector
extends Node

@export var brownout_director_path: NodePath

@onready var _brownout: Node = get_node_or_null(brownout_director_path)


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
		state.brownout_fired = true
		if _brownout != null and _brownout.has_method(&"run_brownout_sequence"):
			_brownout.run_brownout_sequence()
	state.closing_time_reached = true
