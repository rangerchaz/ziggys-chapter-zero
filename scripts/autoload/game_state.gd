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


## Returns the chapter state to its pre-run defaults (new game / retry).
func reset() -> void:
	selected_meckie = NONE
	brownout_fired = false
	closing_time_reached = false
	closing_decision = NONE
