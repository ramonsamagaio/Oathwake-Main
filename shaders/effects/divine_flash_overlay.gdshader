shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 flash_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float flash_intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float center_bias : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float edge_bloom : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float pixel_steps : hint_range(16.0, 256.0, 1.0) = 96.0;

void fragment() {
	vec2 stepped_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	float dist = distance(stepped_uv, vec2(0.5));
	float center = 1.0 - smoothstep(center_bias, 0.88, dist);
	float edge = smoothstep(0.45, 0.95, dist) * edge_bloom;
	float mask = clamp(center + edge, 0.0, 1.0);
	COLOR = vec4(flash_color.rgb, flash_color.a * flash_intensity * mask);
}
