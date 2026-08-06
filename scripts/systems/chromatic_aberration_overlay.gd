## Full-screen post-process overlay driving shaders/chromatic_aberration.gdshader.
## Exposes `intensity` (0..1) as a plain property so BrownoutDirector can
## tween it exactly the way AudioDirector tweens ProceduralAudio's `level`
## - the tween never has to know it is secretly a shader parameter under
## the hood.
class_name ChromaticAberrationOverlay
extends ColorRect

@export_range(0.0, 1.0) var intensity: float = 0.0:
	set(value):
		intensity = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"intensity", value)
