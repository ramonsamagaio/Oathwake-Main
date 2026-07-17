// Adapted from the CC0 2D Foliage Wind Effect:
// https://godotshaders.com/shader/2d-foliage-wind-effect/
shader_type canvas_item;

uniform bool enabled = true;
uniform bool render_noise = false;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float amplitude : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float time_scale : hint_range(0.0, 5.0, 0.01) = 0.20;
uniform float noise_scale : hint_range(0.0, 2.0, 0.0001) = 0.004;
uniform float rotation_strength : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform vec2 rotation_pivot = vec2(0.5, 1.0);

varying vec2 world_position;
varying vec4 vertex_color;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_color = COLOR;
}

vec2 foliage_sample_position(vec2 position_value, float scale_value, float offset_value) {
	return position_value * scale_value + vec2(offset_value);
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
		vec2 noise_sample_position = foliage_sample_position(world_position, noise_scale, TIME * time_scale);
		float noise_amount = texture(noise_texture, noise_sample_position).r - 0.5;
		float rotation_value = amplitude * noise_amount;
		vec2 rotated_uv = foliage_rotate_uv(UV, rotation_pivot, rotation_value);
		float pivot_distance = distance(UV, rotation_pivot) * rotation_strength;
		vec2 result_uv = mix(UV, rotated_uv, pivot_distance);
		output_color = texture(TEXTURE, result_uv) * vertex_color;
		if (render_noise) {
			output_color = texture(noise_texture, noise_sample_position);
		}
	}
	COLOR = output_color;
}
