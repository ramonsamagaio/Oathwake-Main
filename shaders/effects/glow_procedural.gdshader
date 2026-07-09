shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.68, 0.24, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.75;
uniform float softness : hint_range(0.01, 1.0) = 0.65;
uniform float inner_size : hint_range(0.0, 1.0) = 0.12;
uniform vec2 stretch = vec2(1.0, 1.0);

void fragment() {
	vec2 centered_uv = (UV - vec2(0.5)) * max(stretch, vec2(0.001));
	float distance_from_center = length(centered_uv) * 2.0;
	float core = 1.0 - smoothstep(inner_size, inner_size + softness, distance_from_center);
	float feather = 1.0 - smoothstep(0.0, 1.0, distance_from_center);
	float glow_alpha = clamp(max(core, feather * 0.65) * alpha * intensity, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb * intensity, glow_alpha);
}
