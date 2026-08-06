// Final world-space pixelation pass for Oathwake.
// Runs after fog, shafts, bloom, grading and transient screen effects, but below
// the gameplay UI. Pixel blocks therefore affect the composed world without
// degrading inventory text, HUD or editor controls.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform bool enabled = false;
uniform float pixel_size : hint_range(1.0, 32.0, 1.0) = 4.0;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float pixel_aspect : hint_range(0.5, 2.0, 0.01) = 1.0;
uniform int color_steps : hint_range(0, 32, 1) = 0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

float oath_pixel_hash(vec2 cell_index) {
	return fract(sin(dot(cell_index, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 oath_quantize(vec3 color_value, vec2 cell_index) {
	if (color_steps < 2) {
		return color_value;
	}
	float levels = max(float(color_steps), 2.0);
	float denominator = levels - 1.0;
	float dither = (oath_pixel_hash(cell_index) - 0.5) * dither_strength / denominator;
	vec3 shifted = clamp(color_value + vec3(dither), vec3(0.0), vec3(1.0));
	return floor(shifted * denominator + vec3(0.5)) / denominator;
}

void fragment() {
	vec4 original = texture(screen_texture, SCREEN_UV);
	if (!enabled || strength <= 0.0) {
		COLOR = original;
		return;
	}

	vec2 block_pixels = vec2(
		max(pixel_size * pixel_aspect, 1.0),
		max(pixel_size, 1.0)
	);
	vec2 block_uv = max(SCREEN_PIXEL_SIZE * block_pixels, SCREEN_PIXEL_SIZE);
	vec2 cell_index = floor(SCREEN_UV / block_uv);
	vec2 snapped_uv = (cell_index + vec2(0.5)) * block_uv;
	snapped_uv = clamp(snapped_uv, vec2(0.0), vec2(1.0));

	vec4 pixelated = texture(screen_texture, snapped_uv);
	pixelated.rgb = oath_quantize(pixelated.rgb, cell_index);
	COLOR = mix(original, pixelated, clamp(strength, 0.0, 1.0));
}
