// Renderer-safe foliage wind based on the requested CC0 effect:
// https://godotshaders.com/shader/2d-foliage-wind-effect/
// Uses procedural vertex sway instead of texture-driven UV loops.
shader_type canvas_item;

uniform bool enabled = true;
uniform bool render_noise = false;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float amplitude : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float time_scale : hint_range(0.0, 5.0, 0.01) = 0.20;
uniform float noise_scale : hint_range(0.0, 2.0, 0.0001) = 0.004;
uniform float rotation_strength : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform vec2 rotation_pivot = vec2(0.5, 1.0);

varying vec4 vertex_color;
varying float wind_debug_value;

void vertex() {
	vertex_color = COLOR;
	wind_debug_value = 0.5;

	if (!enabled) {
		return;
	}

	vec2 world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float spatial_phase = (world_position.x + world_position.y * 0.73) * max(noise_scale, 0.0001) * 10.0;
	float time_phase = TIME * time_scale * 2.0;
	float primary_wave = sin(spatial_phase + time_phase);
	float secondary_wave = sin(spatial_phase * 1.71 + time_phase * 0.63 + 1.2) * 0.5;
	float wind = (primary_wave + secondary_wave) / 1.5;
	float pivot_height = max(rotation_pivot.y, 0.001);
	float top_weight = clamp((rotation_pivot.y - UV.y) / pivot_height, 0.0, 1.0);

	VERTEX.x += wind * amplitude * rotation_strength * 12.0 * top_weight;
	wind_debug_value = wind * 0.5 + 0.5;
}

void fragment() {
	if (render_noise) {
		COLOR = vec4(vec3(wind_debug_value), 1.0);
		return;
	}
	COLOR = texture(TEXTURE, UV) * vertex_color;
}
