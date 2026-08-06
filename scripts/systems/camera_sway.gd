## Small procedural handheld-camera jitter, layered on top of whatever the
## SpringArm3D parent (mouse look) is already aiming at. Attaches directly
## to the player's Camera3D - its own `rotation` is otherwise untouched by
## MeckiePlayerController (only the rig's rotation carries mouse yaw/pitch),
## so overwriting it here every frame is safe and never fights player input.
##
## `intensity` (0..1) is a plain exported property, the same pattern
## AudioDirector uses to tween ProceduralAudio's `level` - BrownoutDirector
## tweens this directly without knowing it drives a shader or noise offset.
## Registers into the "camera_sway" group on _ready() so BrownoutDirector
## can find whichever Meckie the player is controlling without a NodePath,
## since the player is spawned into the room after the fact by
## PlayerSpawner.
class_name CameraSway
extends Camera3D

## A small idle sway is always present (subtle handheld breathing); the
## brownout beat multiplies it up to `peak_multiplier` times as strong.
@export var base_amplitude := 0.0025
@export var peak_multiplier := 7.0
@export_range(0.0, 1.0) var intensity := 0.0

var _t := 0.0


func _ready() -> void:
	add_to_group(&"camera_sway")
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var amp := base_amplitude * (1.0 + intensity * peak_multiplier)
	rotation.x = sin(_t * 1.7) * amp + sin(_t * 4.3 + 1.3) * amp * 0.4
	rotation.y = cos(_t * 2.1) * amp + cos(_t * 3.7 + 0.7) * amp * 0.4
	rotation.z = sin(_t * 2.6 + 2.2) * amp * 0.5
