shader_type canvas_item;

// Full-screen post-process RGB split. Reads the frame already rendered
// behind this ColorRect (the whole 3D room) and offsets the red/blue
// channels outward from screen center, scaled by distance from center so
// the effect reads as a lens artifact rather than a uniform smear.
// `intensity` (0..1) is the single knob BrownoutDirector tweens up during
// the beat and back down after - 0 renders bit-identical to the
// unshifted frame.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_offset : hint_range(0.0, 0.05) = 0.016;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float dist = length(dir);
	vec2 offset = dir * dist * max_offset * intensity;

	float r = textureLod(screen_texture, uv - offset, 0.0).r;
	vec4 base = textureLod(screen_texture, uv, 0.0);
	float b = textureLod(screen_texture, uv + offset, 0.0).b;

	COLOR = vec4(r, base.g, b, base.a);
}
