// Adapted from the CC0 Configurable CanvasItem Outline Shader:
// https://godotshaders.com/shader/configurable-canvasitem-outline-shader/
// Applied to a dedicated Sprite2D behind the item so the original sprite remains intact.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.04, 0.95);
uniform lowp float outline_size : hint_range(0.0, 0.2, 0.001) = 0.018;
uniform lowp float alpha_threshold : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform int samples : hint_range(4, 32, 1) = 12;

vec2 rotate2d(vec2 vector, float angle) {
	return vector * mat2(
		vec2(cos(angle), -sin(angle)),
		vec2(sin(angle), cos(angle))
	);
}

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

	vec2 aspect_ratio = vec2(TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y, 1.0);
	vec2 right_vector = vec2(outline_size, 0.0);
	float maximum_alpha = 0.0;

	for (int index = 0; index < 32; index++) {
		if (index >= samples) {
			break;
		}
		vec2 sample_vector = rotate2d(right_vector, float(index) * TAU / float(samples)) * aspect_ratio;
		maximum_alpha = max(texture(TEXTURE, UV + sample_vector).a, maximum_alpha);
	}

	COLOR = outline_color * maximum_alpha;
}
