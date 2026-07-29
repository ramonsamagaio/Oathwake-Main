shader_type canvas_item;
render_mode unshaded;

uniform float mask_weight : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform bool wind_enabled = false;
uniform float wind_amplitude : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float wind_time_scale : hint_range(0.0, 5.0, 0.01) = 0.20;
uniform float wind_noise_scale : hint_range(0.0001, 2.0, 0.0001) = 0.004;
uniform float wind_rotation_strength : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform vec2 wind_rotation_pivot = vec2(0.5, 1.0);
uniform vec2 wind_direction = vec2(1.0, 0.16);
uniform float wind_strength : hint_range(0.0, 4.0, 0.01) = 0.85;
uniform float wind_gust_strength : hint_range(0.0, 1.5, 0.01) = 0.34;
uniform float wind_gust_speed : hint_range(0.01, 4.0, 0.01) = 0.42;
uniform float wind_phase_offset : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform vec2 source_world_origin = vec2(0.0);
uniform vec2 source_world_size = vec2(64.0);

float shadow_hash(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 33.33);
	return fract((point3.x + point3.y) * point3.z);
}

float shadow_value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float bottom_left = shadow_hash(cell);
	float bottom_right = shadow_hash(cell + vec2(1.0, 0.0));
	float top_left = shadow_hash(cell + vec2(0.0, 1.0));
	float top_right = shadow_hash(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, smooth_fraction.x),
		mix(top_left, top_right, smooth_fraction.x),
		smooth_fraction.y
	);
}

vec2 shadow_rotate_uv(vec2 uv_value, vec2 pivot_value, float rotation_value) {
	float cosine_value = cos(rotation_value);
	float sine_value = sin(rotation_value);
	uv_value -= pivot_value;
	return vec2(
		cosine_value * uv_value.x - sine_value * uv_value.y,
		cosine_value * uv_value.y + sine_value * uv_value.x
	) + pivot_value;
}

void fragment() {
	vec2 sample_uv = UV;
	if (wind_enabled) {
		float safe_noise_scale = max(wind_noise_scale, 0.0001);
		vec2 safe_direction = length(wind_direction) > 0.0001 ? normalize(wind_direction) : vec2(1.0, 0.0);
		vec2 world_position = source_world_origin + (UV - vec2(0.5)) * source_world_size;
		vec2 spatial_position = world_position * safe_noise_scale * 42.0;
		float time_value = TIME * wind_time_scale;
		float directional_time = time_value * (0.55 + wind_gust_speed);
		float smooth_noise = shadow_value_noise(spatial_position + safe_direction * directional_time + vec2(wind_phase_offset));
		float gust_wave = sin(
			time_value * (1.4 + wind_gust_speed * 2.2)
			+ dot(world_position, safe_direction) * safe_noise_scale * 24.0
			+ wind_phase_offset
		) * 0.5 + 0.5;
		float base_wind = mix(smooth_noise, gust_wave, 0.38) - 0.5;
		float gust_multiplier = 1.0 + ((gust_wave - 0.5) * 2.0 * wind_gust_strength);
		float wind_amount = base_wind * wind_strength * gust_multiplier;
		float rotation_value = wind_amplitude * wind_amount;
		vec2 rotated_uv = shadow_rotate_uv(UV, wind_rotation_pivot, rotation_value);
		float pivot_distance = clamp(distance(UV, wind_rotation_pivot) * wind_rotation_strength, 0.0, 1.35);
		vec2 directional_bend = vec2(safe_direction.x, -abs(safe_direction.y)) * wind_amount * 0.0035 * pivot_distance;
		sample_uv = mix(UV, rotated_uv, pivot_distance) - directional_bend;
	}
	float mask_alpha = texture(TEXTURE, sample_uv).a * clamp(mask_weight, 0.0, 1.0);
	if (mask_alpha <= 0.001) {
		discard;
	}
	COLOR = vec4(1.0, 1.0, 1.0, mask_alpha);
}
