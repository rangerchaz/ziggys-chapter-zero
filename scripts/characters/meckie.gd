@tool
## A Meckie service robot built entirely from primitive meshes: rounded
## hull, floating emissive faceplate with dark eyes, signature accent
## panels, a hover ring, and a real OmniLight3D so the signature color
## lands on the floor around it, not just on the body.
##
## One scene serves the whole cast: set `meckie_id` to a MeckieDefs id
## (droid / eva / sid) to adopt that character's signature color, or set
## `signature_color` directly for a one-off tint. Both drive the shared
## emissive accent material and the light, in the editor and at runtime.
class_name Meckie
extends CharacterBody3D

## Which cast member this instance is. Assigning a known id pulls the
## signature color from MeckieDefs; unknown ids leave the color untouched.
@export var meckie_id: StringName = &"droid":
	set(value):
		meckie_id = value
		if MeckieDefs.DEFS.has(value):
			signature_color = MeckieDefs.color_of(value)

## Drives the emissive faceplate/accents and the cast light together.
@export var signature_color: Color = Color("00d4ff"):
	set(value):
		signature_color = value
		_apply_signature()

## Emission strength of the faceplate and accent panels.
@export_range(0.5, 8.0) var accent_energy := 3.0:
	set(value):
		accent_energy = value
		_apply_signature()

var _accent_material: StandardMaterial3D
var _faceplate: Node3D
var _faceplate_rest_y := 0.0
var _bob_time := 0.0


func _ready() -> void:
	_faceplate = get_node_or_null(^"Visual/Faceplate")
	if _faceplate != null:
		_faceplate_rest_y = _faceplate.position.y
	_apply_signature()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _faceplate == null:
		return
	# The faceplate is attached to nothing; a slow bob sells the float.
	_bob_time += delta
	_faceplate.position.y = _faceplate_rest_y + 0.018 * sin(_bob_time * 2.2)


## Pushes the current signature color into the one shared accent material
## (created lazily and assigned to every mesh in the signature_accents
## group) and into the SignatureLight, keeping emissive and cast light in
## lockstep with no per-instance scene edits.
func _apply_signature() -> void:
	if not is_node_ready():
		return
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.emission_enabled = true
		for mesh in find_children("*", "MeshInstance3D"):
			if mesh.is_in_group(&"signature_accents"):
				mesh.material_override = _accent_material
	_accent_material.albedo_color = Color(
			signature_color.r * 0.04, signature_color.g * 0.04, signature_color.b * 0.04)
	_accent_material.emission = signature_color
	_accent_material.emission_energy_multiplier = accent_energy
	var light: OmniLight3D = get_node_or_null(^"SignatureLight")
	if light != null:
		light.light_color = signature_color
