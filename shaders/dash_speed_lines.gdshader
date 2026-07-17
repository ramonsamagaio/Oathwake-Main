// Adapted from the CC0 Speed Lines Shader for Godot 4:
// https://godotshaders.com/shader/speed-lines-shader-for-godot-4/
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec4 line_color : source_color = vec4(0.72, 0.88, 1.0, 0.12);
uniform float line_count : hint_range(0.05, 2.0, 0.05) = 0.45;
uniform float line_density : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float line_falloff : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float mask_size : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float mask_edge : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float animation_speed : hint_range(0.1, 20.0, 0.1) = 7.0;

float inverse_lerp(float from_value, float to_value, float value) {
	return (value - from_value) / max(to_value - from_value, 0.0001);
}

vec2 polar_coordinates(vec2 uv, vec2 center, float zoom, float repeat_value) {
	vec2 direction = uv - center;
	float radius = length(direction) * 2.0;
	float angle = atan(direction.y, direction.x) / TAU;
	return mod(vec2(radius * zoom, angle * repeat_value), 1.0);
}

vec2 rotate_uv(vec2 uv, vec2 pivot, float rotation) {
	float cosine = cos(rotation);
	float sine = sin(rotation);
	uv -= pivot;
	return vec2(
		cosine * uv.x - sine * uv.y,
		cosine * uv.y + sine * uv.x
	) + pivot;
}

void fragment() {
	if (!enabled) {
		COLOR = vec4(0.0);
		return;
	}

	float rotation = floor(fract(TIME) * animation_speed);
	vec2 polar_uv = polar_coordinates(rotate_uv(UV, vec2(0.5), rotation), vec2(0.5), 0.01, line_count);
	float line_noise = texture(noise, polar_uv).r;
	float mask_value = length(UV - vec2(0.5));
	float mask = inverse_lerp(mask_size, mask_edge, mask_value);
	float result = 1.0 - mask * line_density;
	result = smoothstep(result, result + line_falloff, line_noise);
	COLOR = vec4(line_color.rgb, min(line_color.a, result * line_color.a));
}
