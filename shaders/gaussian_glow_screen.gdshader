// Stable Godot 4 screen-space adaptation of the requested Gaussian Glow shader:
// https://godotshaders.com/shader/gaussian-glow/
// Uses the engine-generated mip chain plus fixed displaced taps. This creates
// an actual halo outside bright pixels without dynamic loops.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float bloom_threshold : hint_range(0.0, 2.0, 0.01) = 0.68;
uniform float bloom_intensity : hint_range(0.0, 5.0, 0.01) = 0.78;
uniform int blur_iterations : hint_range(1, 4, 1) = 1;
uniform float blur_size : hint_range(0.0, 0.03, 0.0001) = 0.0040;
uniform int blur_subdivisions : hint_range(4, 16, 1) = 8;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 0.18;

vec3 glow_bright_pass(vec3 color_value) {
	float brightest_channel = max(max(color_value.r, color_value.g), color_value.b);
	float threshold_gate = smoothstep(bloom_threshold, bloom_threshold + 0.16, brightest_channel);
	return max(color_value - vec3(bloom_threshold), vec3(0.0)) * threshold_gate;
}

void fragment() {
	vec4 base_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = base_color.rgb;
	if (enabled && bloom_intensity > 0.0 && mix_amount > 0.0) {
		float blur_lod = clamp(
			0.45 + float(blur_iterations) * 0.35 + blur_size * 180.0 + float(blur_subdivisions) * 0.018,
			0.5,
			4.8
		);
		float radius_pixels = clamp(2.5 + blur_size * 1450.0 + float(blur_iterations) * 1.6, 3.0, 34.0);
		vec2 axis_offset = SCREEN_PIXEL_SIZE * radius_pixels;
		vec2 diagonal_offset = axis_offset * 0.70710678;

		vec3 bloom_color = glow_bright_pass(textureLod(screen_texture, SCREEN_UV, blur_lod).rgb) * 0.24;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV + vec2(axis_offset.x, 0.0), blur_lod).rgb) * 0.11;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV - vec2(axis_offset.x, 0.0), blur_lod).rgb) * 0.11;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV + vec2(0.0, axis_offset.y), blur_lod).rgb) * 0.11;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV - vec2(0.0, axis_offset.y), blur_lod).rgb) * 0.11;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV + diagonal_offset, blur_lod).rgb) * 0.08;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV - diagonal_offset, blur_lod).rgb) * 0.08;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV + vec2(diagonal_offset.x, -diagonal_offset.y), blur_lod).rgb) * 0.08;
		bloom_color += glow_bright_pass(textureLod(screen_texture, SCREEN_UV + vec2(-diagonal_offset.x, diagonal_offset.y), blur_lod).rgb) * 0.08;
		bloom_color *= bloom_intensity;

		vec3 clamped_bloom = clamp(bloom_color, vec3(0.0), vec3(1.0));
		vec3 screen_blend = vec3(1.0) - (vec3(1.0) - base_color.rgb) * (vec3(1.0) - clamped_bloom);
		output_rgb = mix(base_color.rgb, screen_blend, mix_amount);
	}
	COLOR = vec4(output_rgb, base_color.a);
}
