// Three-layer, world-anchored 2D fog. A broad base mist, low ground ribbons and
// subtle distance haze share one procedural pass, avoiding stacked full-screen
// canvases while giving the map distinct depth planes.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform bool enabled = true;
uniform float density : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform vec2 speed = vec2(0.018, 0.007);
uniform vec4 fog_color : source_color = vec4(0.62, 0.68, 0.72, 0.16);
uniform float fog_scale : hint_range(0.25, 12.0, 0.05) = 3.25;
uniform float coverage : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float softness : hint_range(0.01, 0.75, 0.01) = 0.26;
uniform float detail_mix : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform vec2 camera_offset = vec2(0.0);
uniform float world_anchor_strength : hint_range(0.0, 2.0, 0.01) = 1.0;

uniform float ground_density : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float ground_height : hint_range(0.05, 1.0, 0.01) = 0.42;
uniform float ground_scale : hint_range(0.25, 16.0, 0.05) = 5.2;
uniform vec2 ground_speed = vec2(-0.010, 0.004);
uniform float middle_density : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float middle_band_center : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform float middle_band_width : hint_range(0.05, 1.0, 0.01) = 0.40;
uniform float depth_density : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float depth_falloff : hint_range(0.1, 4.0, 0.05) = 1.35;
uniform float night_strength : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float day_multiplier : hint_range(0.0, 3.0, 0.01) = 0.72;
uniform float night_multiplier : hint_range(0.0, 3.0, 0.01) = 1.18;

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
	if (enabled && fog_color.a > 0.0) {
		vec2 anchored_uv = UV + camera_offset * world_anchor_strength;
		vec2 primary_drift = TIME * speed;
		vec2 primary_position = anchored_uv * fog_scale + primary_drift;
		vec2 secondary_position = anchored_uv * (fog_scale * 1.73) - primary_drift * 0.63 + vec2(4.7, 8.1);
		float primary_noise = fog_fbm(primary_position);
		float secondary_noise = fog_fbm(secondary_position);
		float combined_noise = mix(primary_noise, secondary_noise, detail_mix);
		float safe_softness = max(softness, 0.001);
		float base_fog = smoothstep(coverage - safe_softness, coverage + safe_softness, combined_noise) * density;

		vec2 ground_position = anchored_uv * ground_scale + TIME * ground_speed + vec2(11.3, 2.7);
		float ground_noise = fog_fbm(ground_position);
		float ground_vertical = smoothstep(1.0 - ground_height - 0.16, 1.0 - ground_height + 0.18, UV.y);
		float ground_ribbons = smoothstep(0.44, 0.70, ground_noise) * ground_vertical * ground_density;

		float half_band = max(middle_band_width * 0.5, 0.025);
		float band_distance = abs(UV.y - middle_band_center);
		float middle_mask = 1.0 - smoothstep(half_band * 0.45, half_band, band_distance);
		float middle_noise = fog_fbm(anchored_uv * (fog_scale * 0.72) - primary_drift * 0.38 + vec2(1.8, 13.2));
		float middle_mist = smoothstep(0.48, 0.76, middle_noise) * middle_mask * middle_density;

		float distance_from_center = length((UV - vec2(0.5)) * vec2(0.74, 1.0));
		float distance_haze = pow(clamp(distance_from_center * 1.45, 0.0, 1.0), max(depth_falloff, 0.1)) * depth_density;
		float time_multiplier = mix(day_multiplier, night_multiplier, clamp(night_strength, 0.0, 1.0));
		float fog_amount = clamp((base_fog + ground_ribbons + middle_mist + distance_haze) * time_multiplier, 0.0, 1.0);
		float final_alpha = clamp(fog_color.a * fog_amount, 0.0, 0.34);
		output_color = vec4(fog_color.rgb, final_alpha);
	}
	COLOR = output_color;
}
