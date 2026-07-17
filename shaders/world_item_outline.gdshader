// Adapted from the CC0 Configurable CanvasItem Outline Shader:
// https://godotshaders.com/shader/configurable-canvasitem-outline-shader/
// Applied to a dedicated Sprite2D behind the item.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.04, 0.95);
uniform float outline_size : hint_range(0.0, 0.2, 0.001) = 0.025;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform int samples : hint_range(4, 32, 1) = 12;

void fragment() {
	vec4 output_color = vec4(0.0);
	vec4 base_color = texture(TEXTURE, UV);
	if (enabled && base_color.a <= alpha_threshold) {
		float thickness_pixels = max(outline_size * 64.0, 0.0);
		vec2 sample_offset = TEXTURE_PIXEL_SIZE * thickness_pixels;
		float maximum_alpha = 0.0;

		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(sample_offset.x, 0.0)).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - vec2(sample_offset.x, 0.0)).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(0.0, sample_offset.y)).a);
		maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - vec2(0.0, sample_offset.y)).a);

		if (samples > 4) {
			maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + sample_offset).a);
			maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV - sample_offset).a);
			maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(sample_offset.x, -sample_offset.y)).a);
			maximum_alpha = max(maximum_alpha, texture(TEXTURE, UV + vec2(-sample_offset.x, sample_offset.y)).a);
		}

		output_color = vec4(outline_color.rgb, outline_color.a * maximum_alpha);
	}
	COLOR = output_color;
}
