// Renderer-safe speed lines based on the requested CC0 shader:
// https://godotshaders.com/shader/speed-lines-shader-for-godot-4/
// Uses a procedural radial pattern with no custom helper functions or dynamic loops.
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

void fragment() {
	if (!enabled) {
		COLOR = vec4(0.0);
		return;
	}

	vec2 centered_uv = UV - vec2(0.5);
	float radius = length(centered_uv);
	float angle = atan(centered_uv.y, centered_uv.x);
	float normalized_angle = (angle + PI) / TAU;
	float spoke_count = max(line_count * 96.0, 1.0);
	float animated_phase = fract(normalized_angle * spoke_count - TIME * animation_speed);
	float stripe_start = clamp(1.0 - line_density, 0.0, 0.999);
	float stripe = smoothstep(stripe_start, 1.0, animated_phase);
	float safe_mask_edge = max(mask_edge, mask_size + 0.001);
	float center_mask = smoothstep(mask_size, safe_mask_edge, radius);
	float radial_strength = pow(clamp(radius * 2.0, 0.0, 1.0), max(line_falloff * 4.0, 0.25));
	float outer_fade = 1.0 - smoothstep(0.48, 0.78, radius);
	float alpha = stripe * center_mask * radial_strength * outer_fade * line_color.a;

	COLOR = vec4(line_color.rgb, alpha);
}
