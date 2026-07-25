// Procedural 2D foliage wind shared by authored props and content resources.
// Uses world position and one common wind profile so nearby vegetation moves as
// part of the same weather system without generating runtime noise textures.
shader_type canvas_item;

uniform bool enabled = true;
uniform bool render_noise = false;
uniform float amplitude : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float time_scale : hint_range(0.0, 5.0, 0.01) = 0.20;
uniform float noise_scale : hint_range(0.0, 2.0, 0.0001) = 0.004;
uniform float rotation_strength : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform vec2 rotation_pivot = vec2(0.5, 1.0);
uniform vec2 wind_direction = vec2(1.0, 0.16);
uniform float wind_strength : hint_range(0.0, 4.0, 0.01) = 0.85;
uniform float gust_strength : hint_range(0.0, 1.5, 0.01) = 0.34;
uniform float gust_speed : hint_range(0.01, 4.0, 0.01) = 0.42;
uniform float phase_offset : hint_range(0.0, 6.28318, 0.01) = 0.0;

varying vec2 world_position;
varying vec4 vertex_color;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_color = COLOR;
}

float foliage_hash(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 33.33);
	return fract((point3.x + point3.y) * point3.z);
}

float foliage_value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float bottom_left = foliage_hash(cell);
	float bottom_right = foliage_hash(cell + vec2(1.0, 0.0));
	float top_left = foliage_hash(cell + vec2(0.0, 1.0));
	float top_right = foliage_hash(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, smooth_fraction.x),
		mix(top_left, top_right, smooth_fraction.x),
		smooth_fraction.y
	);
}

vec2 foliage_rotate_uv(vec2 uv_value, vec2 pivot_value, float rotation_value) {
	float cosine_value = cos(rotation_value);
	float sine_value = sin(rotation_value);
	uv_value -= pivot_value;
	return vec2(
		cosine_value * uv_value.x - sine_value * uv_value.y,
		cosine_value * uv_value.y + sine_value * uv_value.x
	) + pivot_value;
}

void fragment() {
	vec4 output_color = texture(TEXTURE, UV) * vertex_color;
	if (enabled) {
		float safe_noise_scale = max(noise_scale, 0.0001);
		vec2 safe_direction = length(wind_direction) > 0.0001 ? normalize(wind_direction) : vec2(1.0, 0.0);
		vec2 spatial_position = world_position * safe_noise_scale * 42.0;
		float time_value = TIME * time_scale;
		float directional_time = time_value * (0.55 + gust_speed);
		float smooth_noise = foliage_value_noise(spatial_position + safe_direction * directional_time + vec2(phase_offset));
		float gust_wave = sin(
			time_value * (1.4 + gust_speed * 2.2)
			+ dot(world_position, safe_direction) * safe_noise_scale * 24.0
			+ phase_offset
		) * 0.5 + 0.5;
		float base_wind = mix(smooth_noise, gust_wave, 0.38) - 0.5;
		float gust_multiplier = 1.0 + ((gust_wave - 0.5) * 2.0 * gust_strength);
		float wind_amount = base_wind * wind_strength * gust_multiplier;
		float rotation_value = amplitude * wind_amount;
		vec2 rotated_uv = foliage_rotate_uv(UV, rotation_pivot, rotation_value);
		float pivot_distance = clamp(distance(UV, rotation_pivot) * rotation_strength, 0.0, 1.35);
		vec2 directional_bend = vec2(safe_direction.x, -abs(safe_direction.y)) * wind_amount * 0.0035 * pivot_distance;
		vec2 result_uv = mix(UV, rotated_uv, pivot_distance) - directional_bend;
		output_color = texture(TEXTURE, result_uv) * vertex_color;
		if (render_noise) {
			output_color = vec4(vec3(wind_amount * 0.5 + 0.5), 1.0);
		}
	}
	COLOR = output_color;
}
