## Phase 11's scripted brownout beat, the chapter's centrepiece: warm
## interior lighting fails over a short fade, the ambient bed ducks to a
## low hum in lockstep, camera sway and screen chromatic aberration spike
## and ease back, and the room is left lit only by the cold #00d4ff
## DataCenterWash exterior light.
##
## Deterministic trigger (documented choice): fires the first time the
## player has reached the natural end of a conversation (not an Escape-out)
## with `trigger_npc_count` distinct NPCs, listening to DialogueUI's
## conversation_completed signal - repeatable for QA by talking to that
## many people in any order. The debug_brownout key (F9) fires it
## instantly regardless of conversation count, for QA and screenshots.
## Either path is idempotent: GameState.brownout_fired guards a second
## fire, so replays and repeated debug presses always reproduce the exact
## same beat and never restart or stack tweens.
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

@export var dialogue_ui_path: NodePath
@export var aberration_overlay_path: NodePath
@export var exterior_light_path: NodePath

## Distinct NPCs the player must fully finish talking to before the beat
## fires on its own; the debug key bypasses this entirely.
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

@onready var _dialogue: Control = get_node_or_null(dialogue_ui_path)
@onready var _aberration: Node = get_node_or_null(aberration_overlay_path)
@onready var _exterior_light: Light3D = get_node_or_null(exterior_light_path)

## npc_id -> true for every NPC whose conversation has been fully finished.
var _completed_npcs: Dictionary = {}
var _fade_tween: Tween
var _effect_tween: Tween


func _ready() -> void:
	if _dialogue != null and _dialogue.has_signal(&"conversation_completed"):
		_dialogue.conversation_completed.connect(_on_conversation_completed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_brownout"):
		fire()


func _on_conversation_completed(npc_id: StringName) -> void:
	_completed_npcs[npc_id] = true
	if _completed_npcs.size() >= trigger_npc_count:
		fire()


## Runs the beat exactly once per run. A second call - a further
## conversation completing, or another debug key press - is a no-op, so
## the beat is always identical no matter how it gets triggered.
func fire() -> void:
	var state: Node = get_node(^"/root/GameState")
	if state.brownout_fired:
		return
	state.brownout_fired = true
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
