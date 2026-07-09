shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 vignette_color : source_color = vec4(0.015, 0.01, 0.028, 0.9);
uniform float inner_radius : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float outer_radius : hint_range(0.0, 1.4, 0.01) = 0.82;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.74;
uniform float vertical_bias : hint_range(-1.0, 1.0, 0.01) = 0.02;
uniform float pixel_steps : hint_range(16.0, 256.0, 1.0) = 128.0;

void fragment() {
	vec2 stepped_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	vec2 centered = stepped_uv - vec2(0.5, 0.5 + vertical_bias);
	centered.x *= 1.25;
	float dist = length(centered);
	float mask = smoothstep(inner_radius, outer_radius, dist) * intensity;
	COLOR = vec4(vignette_color.rgb, vignette_color.a * mask);
}
