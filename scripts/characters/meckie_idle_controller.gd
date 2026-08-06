## Idle driver for the two Meckies the player did not choose.
##
## Keeps a robot reading as on-shift staff instead of a prop: it drifts
## between waypoints inside a small radius around its spawn marker, pauses
## like it is taking an order, hover-bobs its whole shell, and lets the
## faceplate glow breathe with an occasional flicker dip. Everything is
## driven by a RandomNumberGenerator seeded from the meckie id, so a QA
## rerun sees the same drift while Droid, Eva and Sid each walk their own
## pattern.
class_name MeckieIdleController
extends Meckie

## How far from the spawn marker a waypoint may land.
@export var wander_radius := 1.25
## Cruising speed between waypoints; well below the player's 4.2.
@export var wander_speed := 0.85
## How fast the body turns toward its travel direction.
@export var turn_speed := 6.0
@export var pause_min := 1.4
@export var pause_max := 3.2

var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _pause_left := 0.0
var _blocked_time := 0.0
var _idle_time := 0.0
var _phase := 0.0
var _visual: Node3D
var _visual_rest_y := 0.0


func _ready() -> void:
	super()
	_rng.seed = hash(meckie_id)
	_phase = _rng.randf_range(0.0, TAU)
	_visual = get_node_or_null(^"Visual")
	if _visual != null:
		_visual_rest_y = _visual.position.y
	_home = global_position
	_target = _home
	# Short first pause so any observation window sees a walk quickly.
	_pause_left = _rng.randf_range(0.3, 0.9)


func _process(delta: float) -> void:
	super(delta)
	if _visual == null:
		return
	_idle_time += delta
	# The whole shell rides the hover ring, on top of the faceplate's own
	# float from the base class.
	_visual.position.y = _visual_rest_y + 0.03 * sin(_idle_time * 1.6 + _phase)
	# Slow breathing glow with a short flicker dip every few seconds - but
	# once the brownout has fired, the warm rig (this Meckie's own accent
	# glow included, now tagged into warm_lights) does not come back, so
	# stop fighting LightRegistry's fade-to-zero every frame.
	var state: Node = get_node_or_null(^"/root/GameState")
	if state != null and state.brownout_fired:
		return
	var energy := 3.0 + 0.55 * sin(_idle_time * 0.8 + _phase)
	if fmod(_idle_time + _phase, 6.5) < 0.1:
		energy = 1.1
	accent_energy = energy


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var planar := Vector3(velocity.x, 0, velocity.z)
	if _pause_left > 0.0:
		_pause_left -= delta
		planar = planar.move_toward(Vector3.ZERO, 8.0 * delta)
		if _pause_left <= 0.0:
			_pick_target()
	else:
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() < 0.18:
			_start_pause()
			planar = planar.move_toward(Vector3.ZERO, 8.0 * delta)
		else:
			var direction := to_target.normalized()
			planar = planar.move_toward(direction * wander_speed, 6.0 * delta)
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z),
					1.0 - exp(-turn_speed * delta))
	velocity.x = planar.x
	velocity.z = planar.z

	var before := global_position
	move_and_slide()

	# A prop or wall in the way: commanded to cruise but barely moving.
	# Give up on this waypoint rather than shoving at the obstacle.
	if _pause_left <= 0.0 and planar.length() > wander_speed * 0.5:
		var moved := (global_position - before).length() / maxf(delta, 0.0001)
		if moved < wander_speed * 0.3:
			_blocked_time += delta
		else:
			_blocked_time = 0.0
		if _blocked_time > 0.7:
			_blocked_time = 0.0
			_start_pause()


## Some spawn markers sit in tight gaps (e.g. the back-bar corridor), so a
## purely random angle can repeatedly point into a wall or prop. Probe a
## handful of candidates with test_move and take the first clear one;
## if every candidate this round is blocked, hold position rather than
## walking straight into an obstacle.
func _pick_target() -> void:
	for _attempt in 8:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(wander_radius * 0.4, wander_radius)
		var candidate := _home + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		var motion := candidate - global_position
		motion.y = 0.0
		if not test_move(global_transform, motion):
			_target = candidate
			return
	_target = global_position


func _start_pause() -> void:
	_pause_left = _rng.randf_range(pause_min, pause_max)
