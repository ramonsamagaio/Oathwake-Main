// Adapted from the CC0 2D Foliage Wind Effect:
// https://godotshaders.com/shader/2d-foliage-wind-effect/
// Keeps CanvasItem modulation by passing vertex COLOR into the fragment stage.
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

vec2 get_sample_position(vec2 position_value, float scale_value, float offset_value) {
	return position_value * scale_value + offset_value;
}

vec2 rotate_vector(vec2 vector_value, vec2 pivot, float rotation) {
	float cosine = cos(rotation);
	float sine = sin(rotation);
	vector_value -= pivot;
	return vec2(
		cosine * vector_value.x - sine * vector_value.y,
		cosine * vector_value.y + sine * vector_value.x
	) + pivot;
}

void fragment() {
	if (!enabled) {
		COLOR = texture(TEXTURE, UV) * vertex_color;
		return;
	}

	vec2 noise_sample_position = get_sample_position(world_position, noise_scale, TIME * time_scale);
	float noise_amount = texture(noise_texture, noise_sample_position).r - 0.5;
	float rotation = amplitude * noise_amount;
	vec2 rotated_uv = rotate_vector(UV, rotation_pivot, rotation);
	float pivot_distance = distance(UV, rotation_pivot) * rotation_strength;
	vec2 result_uv = mix(UV, rotated_uv, pivot_distance);
	COLOR = texture(TEXTURE, result_uv) * vertex_color;

	if (render_noise) {
		COLOR = texture(noise_texture, noise_sample_position);
	}
}
