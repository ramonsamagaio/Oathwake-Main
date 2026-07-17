// Renderer-safe screen glow based on the requested CC0 Gaussian Glow shader:
// https://godotshaders.com/shader/gaussian-glow/
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = false;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float bloom_threshold : hint_range(0.0, 2.0, 0.01) = 0.82;
uniform float bloom_intensity : hint_range(0.0, 5.0, 0.01) = 0.38;
uniform int blur_iterations : hint_range(1, 4, 1) = 1;
uniform float blur_size : hint_range(0.0, 0.03, 0.0001) = 0.0025;
uniform int blur_subdivisions : hint_range(4, 16, 1) = 8;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 0.28;

vec3 oathwake_bright_pass(vec3 color_value) {
	return max(color_value - vec3(bloom_threshold), vec3(0.0)) * bloom_intensity;
}

void fragment() {
	vec4 base_color = texture(screen_texture, SCREEN_UV);
	vec4 output_color = base_color;
	if (enabled && mix_amount > 0.0 && bloom_intensity > 0.0) {
		float iteration_scale = 0.75 + float(blur_iterations) * 0.25;
		float subdivision_scale = 0.75 + float(blur_subdivisions) / 32.0;
		vec2 sample_offset = SCREEN_PIXEL_SIZE * max(blur_size * 900.0 * iteration_scale, 0.5);
		vec2 diagonal_offset = sample_offset * 0.70710678;

		vec3 glow_color = oathwake_bright_pass(base_color.rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV + vec2(sample_offset.x, 0.0)).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV - vec2(sample_offset.x, 0.0)).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV + vec2(0.0, sample_offset.y)).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV - vec2(0.0, sample_offset.y)).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV + diagonal_offset).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV - diagonal_offset).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV + vec2(diagonal_offset.x, -diagonal_offset.y)).rgb);
		glow_color += oathwake_bright_pass(texture(screen_texture, SCREEN_UV + vec2(-diagonal_offset.x, diagonal_offset.y)).rgb);
		glow_color = glow_color / 9.0 * subdivision_scale;

		vec3 clamped_glow = clamp(glow_color, vec3(0.0), vec3(1.0));
		vec3 combined_color = vec3(1.0) - (vec3(1.0) - base_color.rgb) * (vec3(1.0) - clamped_glow);
		output_color = vec4(mix(base_color.rgb, combined_color, mix_amount), base_color.a);
	}
	COLOR = output_color;
}
