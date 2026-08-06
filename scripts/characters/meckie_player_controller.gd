## Third-person driver for a Meckie. Extends the base Meckie body with
## camera-relative WASD movement and the official follow-camera pattern:
## CharacterBody3D -> SpringArm3D (top_level, ~3.5 m, collides with room
## geometry so it pulls in at walls) -> Camera3D.
##
## The mouse yaws/pitches the arm; the body accelerates in the camera's
## ground plane and turns to face its travel direction. In the "player"
## group so InteractionArea overlaps and InteractionManager can tell this
## body apart from the idle Meckies, which share the same collision layer.
## Escape itself is not read here - opening the pause menu (which frees
## the mouse itself) is UiStateMachine's job, the single project-wide
## Escape owner; this script only recaptures the mouse on a click while it
## happens to be visible (e.g. right after the pause menu resumes).
class_name MeckiePlayerController
extends Meckie

@export var max_speed := 4.2
@export var acceleration := 16.0
@export var friction := 22.0
## How fast the body turns toward its travel direction, higher = snappier.
@export var turn_speed := 10.0
@export var mouse_sensitivity := 0.0028
@export var pitch_min := -1.1
@export var pitch_max := 0.45
## Height above the body origin the camera orbits around.
@export var pivot_height := 1.35
## How quickly the detached rig glides after the body.
@export var follow_speed := 24.0

@onready var _rig: SpringArm3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D

## False while the dialogue UI is open: movement input is ignored, mouse
## look is ignored, and the pause/recapture mouse-mode toggle is inert.
## Restored the instant the dialogue closes.
var _input_enabled := true


func _ready() -> void:
	super()
	add_to_group(&"player")
	# The arm must never collide with the body it follows.
	_rig.add_excluded_object(get_rid())
	_rig.global_position = global_position + Vector3(0, pivot_height, 0)
	_rig.rotation = Vector3(-0.32, rotation.y, 0)
	_camera.make_current()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## InteractionManager calls this while the dialogue UI is open (false) and
## the moment it closes (true).
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if DisplayServer.get_name() == "headless":
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if not enabled else Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if event is InputEventMouseMotion \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		var pitch := clampf(_rig.rotation.x - motion.y * mouse_sensitivity,
				pitch_min, pitch_max)
		var yaw := _rig.rotation.y - motion.x * mouse_sensitivity
		_rig.rotation = Vector3(pitch, yaw, 0)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input := Input.get_vector(&"move_left", &"move_right",
			&"move_forward", &"move_back") if _input_enabled else Vector2.ZERO
	var forward := -_rig.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _rig.basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := forward * -input.y + right * input.x

	var planar := Vector3(velocity.x, 0, velocity.z)
	if direction != Vector3.ZERO:
		planar = planar.move_toward(direction * max_speed, acceleration * delta)
	else:
		planar = planar.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if planar.length_squared() > 0.09:
		rotation.y = lerp_angle(rotation.y, atan2(-planar.x, -planar.z),
				1.0 - exp(-turn_speed * delta))

	move_and_slide()

	# top_level detaches the arm from the body transform; glide it after the
	# body each physics step so mouse yaw stays fully independent.
	_rig.global_position = _rig.global_position.lerp(
			global_position + Vector3(0, pivot_height, 0),
			1.0 - exp(-follow_speed * delta))
