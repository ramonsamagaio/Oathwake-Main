shader_type canvas_item;
render_mode unshaded;

uniform sampler2D patch_noise : filter_linear, repeat_enable;

// Exact four-colour meadow palette sampled from the supplied image-3 reference.
uniform vec4 palette_shadow : source_color = vec4(0.278431, 0.364706, 0.117647, 1.0);
uniform vec4 palette_dark_mid : source_color = vec4(0.513725, 0.643137, 0.211765, 1.0);
uniform vec4 palette_mid_light : source_color = vec4(0.650980, 0.749020, 0.294118, 1.0);
uniform vec4 palette_highlight : source_color = vec4(0.764706, 0.827451, 0.356863, 1.0);

uniform float palette_field_scale_a : hint_range(0.0001, 0.01, 0.0001) = 0.00058;
uniform float palette_field_scale_b : hint_range(0.0001, 0.01, 0.0001) = 0.00145;
uniform float palette_threshold_1 : hint_range(0.0, 1.0, 0.001) = 0.30;
uniform float palette_threshold_2 : hint_range(0.0, 1.0, 0.001) = 0.50;
uniform float palette_threshold_3 : hint_range(0.0, 1.0, 0.001) = 0.68;
uniform float sample_pixel_size : hint_range(1.0, 8.0, 1.0) = 4.0;

varying vec2 world_position;


float shared_palette_field(vec2 position) {
	float broad = texture(
		patch_noise,
		position * palette_field_scale_a + vec2(0.13, 0.31)
	).r;
	float detail = texture(
		patch_noise,
		position * palette_field_scale_b + vec2(0.67, 0.19)
	).r;
	return clamp(broad * 0.76 + detail * 0.24 + 0.10, 0.0, 1.0);
}


vec3 palette_colour(float field) {
	if (field < palette_threshold_1) {
		return palette_shadow.rgb;
	}
	if (field < palette_threshold_2) {
		return palette_dark_mid.rgb;
	}
	if (field < palette_threshold_3) {
		return palette_mid_light.rgb;
	}
	return palette_highlight.rgb;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	float safe_pixel_size = max(sample_pixel_size, 1.0);
	vec2 position = floor(world_position / safe_pixel_size) * safe_pixel_size;
	float field = shared_palette_field(position);
	COLOR = vec4(palette_colour(field), 1.0);
}
