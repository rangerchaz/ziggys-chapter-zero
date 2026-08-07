## Phase 11's scripted brownout beat, the chapter's centrepiece: warm
## interior lighting fails over a short fade, the ambient bed ducks to a
## low hum in lockstep, camera sway and screen chromatic aberration spike
## and ease back, and the room is left lit only by the cold #00d4ff
## DataCenterWash exterior light.
##
## Phase 2: this node no longer decides WHEN to fire. BeatRunner owns the
## trigger - distinct-conversation counting, the `after` evaluation, and
## the debug_brownout key - and calls run_brownout_sequence() once a
## `lighting: brownout` beat's trigger is satisfied (see
## scripts/systems/beat_runner.gd). GameState.brownout_fired is
## BeatRunner's idempotency guard now, not this node's:
## run_brownout_sequence() always runs the sequence when called, so it is
## the caller's job to only call it once. This node is now purely the
## sequence itself.
##
## Recovery/settle (documented choice): the warm rig does NOT come back -
## once it fails it stays dark for the rest of the chapter, matching a
## real brownout, right through to closing time. Only camera sway and
## chromatic aberration are temporary: they spike during the beat and ease
## back to baseline once the room has settled into the dark.
class_name BrownoutDirector
extends Node

## Emitted the instant the beat is committed to (before any tween starts).
signal brownout_started

@export var aberration_overlay_path: NodePath
@export var exterior_light_path: NodePath

## Unused by this node since Phase 2 (BeatRunner owns the distinct-
## conversation count generically) - kept exported only because other
## nodes/probes still set it defensively to keep themselves isolated from
## any organic brownout trigger.
@export var trigger_npc_count := 3
## Warm-light-and-audio fade duration; matches AudioDirector's low_hum
## state duration so light and sound land together.
@export var fade_duration := 2.0
## The exterior wash is left untouched by default (factor 1.0 = no boost)
## but can be nudged up so it visibly reads as the room's one remaining
## light source once the warm rig is gone.
@export var exterior_boost := 1.15
## How long camera sway / chromatic aberration take to ramp up to peak.
@export var effect_attack := 0.6
## How long the peak effect window holds before easing off.
@export var effect_hold := 4.0
## How long sway/aberration take to ease back to baseline after the hold.
@export var effect_release := 2.0

@onready var _aberration: Node = get_node_or_null(aberration_overlay_path)
@onready var _exterior_light: Light3D = get_node_or_null(exterior_light_path)

var _fade_tween: Tween
var _effect_tween: Tween


## Runs the fade/effect sequence unconditionally. Callers own the
## idempotency guard (BeatRunner checks/sets GameState.brownout_fired
## before calling this); calling it twice restarts and stacks tweens, so
## nothing here re-guards against that on its own.
func run_brownout_sequence() -> void:
	brownout_started.emit()
	_fade_lights_and_audio()
	_run_effect_sequence()


func _fade_lights_and_audio() -> void:
	if _exterior_light != null:
		if not _exterior_light.has_meta(&"brownout_base_energy"):
			_exterior_light.set_meta(&"brownout_base_energy", _exterior_light.light_energy)
		var base_energy: float = _exterior_light.get_meta(&"brownout_base_energy")
		create_tween().tween_property(_exterior_light, "light_energy",
				base_energy * exterior_boost, fade_duration) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var tree := get_tree()
	_fade_tween = create_tween()
	_fade_tween.tween_method(
			func(factor: float) -> void: LightRegistry.scale_warm_lights(tree, factor),
			1.0, 0.0, fade_duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	var audio: Node = get_node_or_null(^"/root/AudioDirector")
	if audio != null:
		audio.set_ambience_state(&"low_hum")


## Ramps camera sway and chromatic aberration intensity up together, holds,
## then eases both back down together - a single Tween with a shared
## timeline so the two effects never drift out of sync with each other.
func _run_effect_sequence() -> void:
	var sway: Node = get_tree().get_first_node_in_group(&"camera_sway")
	var targets: Array[Node] = []
	if sway != null:
		targets.append(sway)
	if _aberration != null:
		targets.append(_aberration)
	if targets.is_empty():
		return

	if _effect_tween != null and _effect_tween.is_valid():
		_effect_tween.kill()
	_effect_tween = create_tween()

	for i in targets.size():
		var attack := _effect_tween.tween_property(targets[i], "intensity", 1.0, effect_attack) \
				if i == 0 else \
				_effect_tween.parallel().tween_property(targets[i], "intensity", 1.0, effect_attack)
		attack.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	_effect_tween.tween_interval(effect_hold)

	for i in targets.size():
		var release := _effect_tween.tween_property(targets[i], "intensity", 0.0, effect_release) \
				if i == 0 else \
				_effect_tween.parallel().tween_property(targets[i], "intensity", 0.0, effect_release)
		release.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
