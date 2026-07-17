// Safe CanvasItem outline based on the requested CC0 shader:
// https://godotshaders.com/shader/configurable-canvasitem-outline-shader/
// Uses fixed samples to remain stable across Godot renderers.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.04, 0.95);
uniform float outline_size : hint_range(0.0, 0.2, 0.001) = 0.018;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform int samples : hint_range(4, 32, 1) = 12;

void fragment() {
	if (!enabled) {
		COLOR = vec4(0.0);
		return;
	}

	vec4 base = texture(TEXTURE, UV);
	if (base.a > alpha_threshold) {
		COLOR = vec4(0.0);
		return;
	}

	float thickness_pixels = max(outline_size * 64.0, 0.0);
	vec2 offset_size = TEXTURE_PIXEL_SIZE * thickness_pixels;
	float maximum_alpha = 0.0;

	maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(offset_size.x, 0.0)).a);
	maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - vec2(offset_size.x, 0.0)).a);
	maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(0.0, offset_size.y)).a);
	maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - vec2(0.0, offset_size.y)).a);

	if (samples > 4) {
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + offset_size).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - offset_size).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(offset_size.x, -offset_size.y)).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(-offset_size.x, offset_size.y)).a);
	}

	COLOR = vec4(outline_color.rgb, outline_color.a * maximum_alpha);
}
