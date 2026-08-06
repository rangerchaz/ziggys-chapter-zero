@tool
## A stylised human regular built entirely from CSG primitives: blocky
## torso and hips, cylinder limbs, a sphere head, no imported or modelled
## character. Strong silhouette over realism, per spec.
##
## One scene serves all ten regulars: `npc_id` + `display_name` are pure
## identity, `pose` swaps between a standing leg pair and a seated
## thigh/shin pair (with the upper body dropped to seat height), and
## `body_color` / `accent_color` drive the two shared materials so every
## instance reads as a distinct person. A small SpotLight3D keys the face
## so it reads under the room's two-temperature lighting. Presentation and
## identity only — zero dialogue strings, per the Phase 7 brief.
class_name NpcHuman
extends CSGCombiner3D

## How far the seated upper body and thigh/shin pair drop below the
## standing hip height, matching the booth cushion authored in this scene.
const SEATED_DROP := 0.35

@export var npc_id: StringName = &""
@export var display_name: String = ""
@export_enum("standing", "seated") var pose: String = "standing":
	set(value):
		pose = value
		_apply_pose()
## A small silhouette accessory (cap) some regulars wear for extra
## distinctiveness; shares the accent material.
@export var has_cap: bool = false:
	set(value):
		has_cap = value
		_apply_cap()
@export var body_color: Color = Color(0.3, 0.32, 0.36, 1):
	set(value):
		body_color = value
		_apply_colors()
@export var accent_color: Color = Color(0.82, 0.74, 0.62, 1):
	set(value):
		accent_color = value
		_apply_colors()
## Approach range for InteractionArea; Phase 9 tunes this per NPC.
@export_range(0.8, 2.5) var interaction_radius := 1.4:
	set(value):
		interaction_radius = value
		_apply_radius()

var _body_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _upper_body: Array[Node3D] = []
var _upper_body_rest_y: Array[float] = []


func _ready() -> void:
	add_to_group(&"npcs")
	for path in [^"Hips", ^"Torso", ^"ArmL", ^"ArmR", ^"Collar", ^"Head", ^"CapBox", ^"FaceLight"]:
		var node: Node3D = get_node_or_null(path)
		if node != null:
			_upper_body.append(node)
			_upper_body_rest_y.append(node.position.y)
	_apply_pose()
	_apply_cap()
	_apply_colors()
	_apply_radius()
	if not Engine.is_editor_hint():
		_aim_face_light()


func _apply_pose() -> void:
	if not is_node_ready():
		return
	var drop := SEATED_DROP if pose == "seated" else 0.0
	for i in _upper_body.size():
		_upper_body[i].position.y = _upper_body_rest_y[i] - drop
	var stand_legs := get_node_or_null(^"LegStandL")
	var stand_legs2 := get_node_or_null(^"LegStandR")
	var thigh_l := get_node_or_null(^"ThighL")
	var thigh_r := get_node_or_null(^"ThighR")
	var shin_l := get_node_or_null(^"ShinL")
	var shin_r := get_node_or_null(^"ShinR")
	for n in [stand_legs, stand_legs2]:
		if n != null:
			n.visible = pose == "standing"
	for n in [thigh_l, thigh_r, shin_l, shin_r]:
		if n != null:
			n.visible = pose == "seated"


func _apply_cap() -> void:
	if not is_node_ready():
		return
	var cap := get_node_or_null(^"CapBox")
	if cap != null:
		cap.visible = has_cap


func _apply_colors() -> void:
	if not is_node_ready():
		return
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		for mesh in find_children("*", "CSGPrimitive3D"):
			if mesh.is_in_group(&"npc_body_mesh"):
				mesh.material = _body_material
	_body_material.albedo_color = body_color
	_body_material.roughness = 0.75
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		for mesh in find_children("*", "CSGPrimitive3D"):
			if mesh.is_in_group(&"npc_accent_mesh"):
				mesh.material = _accent_material
	_accent_material.albedo_color = accent_color
	_accent_material.roughness = 0.5


func _apply_radius() -> void:
	var shape: CollisionShape3D = get_node_or_null(^"InteractionArea/CollisionShape3D")
	if shape != null and shape.shape is CylinderShape3D:
		shape.shape.radius = interaction_radius


## Points the face SpotLight3D at the head from its authored perch so the
## face reads as lit regardless of pose/seat drop, computed once at
## runtime rather than baked per-instance in the scene.
func _aim_face_light() -> void:
	var light: SpotLight3D = get_node_or_null(^"FaceLight")
	var head: Node3D = get_node_or_null(^"Head")
	if light == null or head == null:
		return
	light.look_at(head.global_position + Vector3(0, -0.05, -0.16), Vector3.UP)
