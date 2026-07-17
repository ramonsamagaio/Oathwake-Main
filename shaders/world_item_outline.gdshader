// Adapted from the requested CC0 Configurable CanvasItem Outline Shader:
// https://godotshaders.com/shader/configurable-canvasitem-outline-shader/
// The vertex stage expands the sprite quad so the outline can exist outside
// the original sprite bounds. The runtime supplies an exact-frame AtlasTexture.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.04, 0.95);
uniform float outline_size : hint_range(0.0, 1.0, 0.001) = 0.025;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform int samples : hint_range(4, 32, 1) = 12;

float outline_alpha_at(vec2 uv_value) {
	if (uv_value.x < 0.0 || uv_value.y < 0.0 || uv_value.x > 1.0 || uv_value.y > 1.0) {
		return 0.0;
	}
	return texture(TEXTURE, uv_value).a;
}

void vertex() {
	float padding_pixels = max(outline_size * 64.0, 0.0);
	VERTEX += (UV * 2.0 - vec2(1.0)) * padding_pixels;
}

void fragment() {
	float padding_pixels = max(outline_size * 64.0, 0.0);
	vec2 texture_size_pixels = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 padded_size_pixels = texture_size_pixels + vec2(padding_pixels * 2.0);
	vec2 source_pixel = UV * padded_size_pixels - vec2(padding_pixels);
	vec2 source_uv = source_pixel / texture_size_pixels;
	float base_alpha = outline_alpha_at(source_uv);
	float maximum_alpha = 0.0;

	if (enabled && padding_pixels > 0.0 && base_alpha <= alpha_threshold) {
		vec2 full_radius = TEXTURE_PIXEL_SIZE * padding_pixels;
		vec2 half_radius = full_radius * 0.5;

		maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(full_radius.x, 0.0)));
		maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv - vec2(full_radius.x, 0.0)));
		maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(0.0, full_radius.y)));
		maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv - vec2(0.0, full_radius.y)));

		if (samples > 4) {
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + full_radius));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv - full_radius));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(full_radius.x, -full_radius.y)));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(-full_radius.x, full_radius.y)));
		}

		if (samples > 8) {
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(half_radius.x, 0.0)));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv - vec2(half_radius.x, 0.0)));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv + vec2(0.0, half_radius.y)));
			maximum_alpha = max(maximum_alpha, outline_alpha_at(source_uv - vec2(0.0, half_radius.y)));
		}
	}

	float outline_alpha = step(alpha_threshold, maximum_alpha) * outline_color.a;
	COLOR = vec4(outline_color.rgb, outline_alpha);
}
