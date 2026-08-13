shader_type canvas_item;
render_mode unshaded;

uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform vec4 palette_shadow : source_color = vec4(0.392157, 0.474510, 0.176471, 1.0);
uniform vec4 palette_dark_mid : source_color = vec4(0.537255, 0.682353, 0.227451, 1.0);
uniform vec4 palette_mid_light : source_color = vec4(0.650980, 0.756863, 0.294118, 1.0);
uniform vec4 palette_highlight : source_color = vec4(0.768627, 0.827451, 0.349020, 1.0);
uniform float palette_field_scale_a = 0.00024;
uniform float palette_field_scale_b = 0.00072;
uniform float palette_threshold_1 = 0.24;
uniform float palette_threshold_2 = 0.43;
uniform float palette_threshold_3 = 0.68;
uniform float sample_pixel_size = 4.0;
varying vec2 world_position;

float meadow_field(vec2 position) {
	float broad = texture(patch_noise, position * palette_field_scale_a + vec2(0.13, 0.31)).r;
	float secondary = texture(patch_noise, position * palette_field_scale_b + vec2(0.67, 0.19)).r;
	return clamp(broad * 0.88 + secondary * 0.12 + 0.16, 0.0, 1.0);
}

vec3 palette_colour(float field) {
	float index = step(palette_threshold_1, field) + step(palette_threshold_2, field) + step(palette_threshold_3, field);
	vec3 colour = palette_shadow.rgb;
	colour = mix(colour, palette_dark_mid.rgb, step(0.5, index));
	colour = mix(colour, palette_mid_light.rgb, step(1.5, index));
	colour = mix(colour, palette_highlight.rgb, step(2.5, index));
	return colour;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float safe_pixel_size = max(sample_pixel_size, 1.0);
	vec2 position = floor(world_position / safe_pixel_size) * safe_pixel_size;
	COLOR = vec4(palette_colour(meadow_field(position)), 1.0);
}
