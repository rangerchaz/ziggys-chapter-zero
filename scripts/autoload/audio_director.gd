## Named ambience states for the room's procedural audio bed.
##
## Registered as the AudioDirector autoload (see project.godot). Exposes
## set_ambience_state(name) so later beats - Phase 11's brownout, most
## importantly - can duck the room tone to a quiet hum and restore it
## without knowing anything about how the bed is synthesized. Finds the
## room-tone ProceduralAudio node via the "ambient_bed" group (same
## pattern LightRegistry uses for the warm-light rig) and tweens its
## `level`/`murmur_level` exports over the state's stated duration.
extends Node

## Emitted once a state change has been kicked off (the tween itself
## keeps running after this fires).
signal ambience_state_changed(state_name: StringName)

const BED_GROUP := "ambient_bed"

## level: overall hum gain, 0..1. murmur: crowd-murmur layer gain, 0..1.
## duration: fade time in seconds, used both entering and leaving the
## state.
const STATES := {
	&"normal": {"level": 1.0, "murmur": 1.0, "duration": 1.5},
	&"low_hum": {"level": 0.32, "murmur": 0.0, "duration": 2.0},
}

var current_state: StringName = &"normal"

var _tween: Tween


## Smoothly transitions the ambient bed to `state_name`'s level/murmur
## targets over its stated duration. Unknown state names are ignored
## (with a warning) rather than crashing a scripted beat.
func set_ambience_state(state_name: StringName) -> void:
	if not STATES.has(state_name):
		push_warning("AudioDirector: unknown ambience state '%s'" % state_name)
		return

	var def: Dictionary = STATES[state_name]
	current_state = state_name

	var bed := get_tree().get_first_node_in_group(BED_GROUP)
	if bed != null:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_parallel()
		_tween.tween_property(bed, "level", def.level, def.duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(bed, "murmur_level", def.murmur, def.duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	ambience_state_changed.emit(state_name)


## How long `state_name`'s fade takes, in seconds. Lets callers (and
## tests) know how long to wait for a transition to settle.
func get_state_duration(state_name: StringName) -> float:
	return STATES.get(state_name, {}).get("duration", 0.0)
