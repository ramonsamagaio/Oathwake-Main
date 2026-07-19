// Procedural world-anchored adaptation of the requested CC0 2D Fog Overlay shader:
// https://godotshaders.com/shader/2d-fog-overlay-2/
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform bool enabled = true;
uniform float density : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform vec2 speed = vec2(0.018, 0.007);
uniform vec4 fog_color : source_color = vec4(0.62, 0.68, 0.72, 0.18);
uniform float fog_scale : hint_range(0.25, 12.0, 0.05) = 3.25;
uniform float coverage : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float softness : hint_range(0.01, 0.75, 0.01) = 0.24;
uniform float detail_mix : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform vec2 camera_offset = vec2(0.0);
uniform float world_anchor_strength : hint_range(0.0, 2.0, 0.01) = 1.0;

float fog_hash(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 33.33);
	return fract((point3.x + point3.y) * point3.z);
}

float fog_value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float bottom_left = fog_hash(cell);
	float bottom_right = fog_hash(cell + vec2(1.0, 0.0));
	float top_left = fog_hash(cell + vec2(0.0, 1.0));
	float top_right = fog_hash(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, smooth_fraction.x),
		mix(top_left, top_right, smooth_fraction.x),
		smooth_fraction.y
	);
}

float fog_fbm(vec2 point) {
	float result = 0.0;
	result += fog_value_noise(point) * 0.50;
	result += fog_value_noise(point * 2.03 + vec2(7.1, 3.7)) * 0.25;
	result += fog_value_noise(point * 4.07 + vec2(2.4, 9.2)) * 0.125;
	result += fog_value_noise(point * 8.11 + vec2(5.8, 1.6)) * 0.0625;
	return result / 0.9375;
}

void fragment() {
	vec4 output_color = vec4(0.0);
	if (enabled && density > 0.0 && fog_color.a > 0.0) {
		vec2 drift = TIME * speed;
		vec2 anchored_uv = UV + camera_offset * world_anchor_strength;
		vec2 primary_position = anchored_uv * fog_scale + drift;
		vec2 secondary_position = anchored_uv * (fog_scale * 1.73) - drift * 0.63 + vec2(4.7, 8.1);
		float primary_noise = fog_fbm(primary_position);
		float secondary_noise = fog_fbm(secondary_position);
		float combined_noise = mix(primary_noise, secondary_noise, detail_mix);
		float safe_softness = max(softness, 0.001);
		float fog_amount = smoothstep(coverage - safe_softness, coverage + safe_softness, combined_noise);
		float final_alpha = clamp(fog_color.a * density * fog_amount, 0.0, 0.32);
		output_color = vec4(fog_color.rgb, final_alpha);
	}
	COLOR = output_color;
}
