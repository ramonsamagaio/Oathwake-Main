// Unified world compositor for Oathwake.
// Performs time-aware color grading and a bounded, emissive-selective bloom in
// one screen pass. The selective gate favors bright or chromatic authored glow
// sources without making neutral terrain and ordinary grass radiate.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform bool bloom_enabled = true;
uniform bool selective_bloom_enabled = true;
uniform float bloom_threshold : hint_range(0.0, 2.0, 0.01) = 0.68;
uniform float bloom_intensity : hint_range(0.0, 5.0, 0.01) = 0.78;
uniform int blur_iterations : hint_range(1, 4, 1) = 1;
uniform float blur_size : hint_range(0.0, 0.03, 0.0001) = 0.0040;
uniform int blur_subdivisions : hint_range(4, 16, 1) = 8;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float colored_glow_boost : hint_range(0.0, 2.0, 0.01) = 0.12;
uniform float emissive_chroma_threshold : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float emissive_luminance_threshold : hint_range(0.0, 2.0, 0.01) = 0.62;
uniform float neutral_suppression : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float warm_emissive_boost : hint_range(0.0, 2.0, 0.01) = 0.24;

uniform bool grading_enabled = true;
uniform float night_strength : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform vec4 day_tint : source_color = vec4(1.02, 1.00, 0.96, 1.0);
uniform vec4 night_tint : source_color = vec4(0.66, 0.76, 1.08, 1.0);
uniform float day_saturation : hint_range(0.0, 2.0, 0.01) = 1.02;
uniform float night_saturation : hint_range(0.0, 2.0, 0.01) = 0.82;
uniform float day_contrast : hint_range(0.5, 2.0, 0.01) = 1.03;
uniform float night_contrast : hint_range(0.5, 2.0, 0.01) = 1.10;
uniform float day_brightness : hint_range(-0.5, 0.5, 0.01) = 0.0;
uniform float night_brightness : hint_range(-0.5, 0.5, 0.01) = -0.035;
uniform float warm_light_preservation : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float night_shadow_lift : hint_range(0.0, 0.25, 0.005) = 0.035;
uniform float night_cool_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.32;

uniform bool local_light_grading_mask_enabled = true;
uniform bool local_light_source_active = false;
uniform vec2 local_light_screen_position = vec2(0.5, 0.5);
uniform float local_light_radius_uv : hint_range(0.001, 1.0, 0.001) = 0.16;
uniform float local_light_source_strength : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float local_light_grading_protection : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float local_light_mask_softness : hint_range(0.01, 1.0, 0.01) = 0.42;
uniform float local_light_scene_lift : hint_range(0.0, 0.25, 0.005) = 0.035;

float oath_luminance(vec3 color_value) {
	return dot(color_value, vec3(0.2126, 0.7152, 0.0722));
}

float oath_chroma(vec3 color_value) {
	return max(max(color_value.r, color_value.g), color_value.b) - min(min(color_value.r, color_value.g), color_value.b);
}

float oath_warm_mask(vec3 color_value) {
	float red_dominance = color_value.r - max(color_value.g * 0.82, color_value.b);
	float amber_presence = min(color_value.r, color_value.g * 1.28) - color_value.b * 0.42;
	return smoothstep(0.015, 0.30, max(red_dominance, amber_presence))
		* smoothstep(0.10, 0.76, max(max(color_value.r, color_value.g), color_value.b));
}

float oath_local_light_mask(vec2 uv) {
	if (!local_light_grading_mask_enabled || !local_light_source_active) {
		return 0.0;
	}
	vec2 delta = uv - local_light_screen_position;
	float viewport_aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	delta.x *= viewport_aspect;
	float radius = max(local_light_radius_uv, 0.001);
	float softness = clamp(local_light_mask_softness, 0.01, 1.0);
	float inner_radius = radius * (1.0 - softness);
	float radial = 1.0 - smoothstep(inner_radius, radius, length(delta));
	return radial * clamp(local_light_source_strength, 0.0, 1.0) * clamp(night_strength, 0.0, 1.0);
}

vec3 apply_world_grading(vec3 input_color) {
	if (!grading_enabled) {
		return input_color;
	}
	float night = clamp(night_strength, 0.0, 1.0);
	vec3 tint = mix(day_tint.rgb, night_tint.rgb, night);
	float saturation = mix(day_saturation, night_saturation, night);
	float contrast = mix(day_contrast, night_contrast, night);
	float brightness = mix(day_brightness, night_brightness, night);
	float input_luma = oath_luminance(input_color);

	vec3 graded = input_color * tint;
	float graded_luma = oath_luminance(graded);
	graded = mix(vec3(graded_luma), graded, saturation);
	graded = (graded - vec3(0.5)) * contrast + vec3(0.5 + brightness);

	float shadow_mask = (1.0 - smoothstep(0.08, 0.58, input_luma)) * night;
	vec3 cool_shadow = vec3(0.04, 0.075, 0.15) * night_cool_shadow_strength;
	graded += cool_shadow * shadow_mask;
	graded += vec3(night_shadow_lift * shadow_mask);

	float warm_mask = oath_warm_mask(input_color) * night * warm_light_preservation;
	vec3 preserved_warm = max(input_color, input_color * vec3(1.08, 1.025, 0.90));
	graded = mix(graded, preserved_warm, clamp(warm_mask, 0.0, 1.0));
	return max(graded, vec3(0.0));
}

vec3 glow_bright_pass(vec3 color_value) {
	float brightest_channel = max(max(color_value.r, color_value.g), color_value.b);
	float luminance = oath_luminance(color_value);
	float chroma = oath_chroma(color_value);
	float luminance_gate = smoothstep(
		emissive_luminance_threshold,
		emissive_luminance_threshold + 0.24,
		max(luminance, brightest_channel * 0.82)
	);
	float threshold_gate = smoothstep(bloom_threshold, bloom_threshold + 0.16, brightest_channel);
	vec3 hard_bloom = max(color_value - vec3(bloom_threshold), vec3(0.0)) * max(threshold_gate, luminance_gate);

	float chroma_gate = smoothstep(emissive_chroma_threshold, emissive_chroma_threshold + 0.26, chroma);
	float color_value_gate = smoothstep(0.18, 0.72, brightest_channel);
	float warm_gate = oath_warm_mask(color_value);
	float selective_gate = max(luminance_gate, chroma_gate * color_value_gate * colored_glow_boost);
	selective_gate += warm_gate * color_value_gate * warm_emissive_boost;
	if (selective_bloom_enabled) {
		float neutral_gate = mix(1.0, chroma_gate, neutral_suppression);
		selective_gate *= max(neutral_gate, luminance_gate);
	}
	vec3 colored_bloom = color_value * clamp(selective_gate, 0.0, 2.0) * colored_glow_boost;
	return hard_bloom + colored_bloom;
}

void fragment() {
	vec4 base_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 graded_rgb = apply_world_grading(base_color.rgb);
	float local_light_mask = oath_local_light_mask(SCREEN_UV);
	vec3 protected_scene = max(base_color.rgb + vec3(local_light_scene_lift * local_light_mask), vec3(0.0));
	graded_rgb = mix(
		graded_rgb,
		protected_scene,
		clamp(local_light_mask * local_light_grading_protection, 0.0, 1.0)
	);
	vec3 output_rgb = graded_rgb;
	if (enabled && bloom_enabled && bloom_intensity > 0.0 && mix_amount > 0.0) {
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
		vec3 screen_blend = vec3(1.0) - (vec3(1.0) - graded_rgb) * (vec3(1.0) - clamped_bloom);
		output_rgb = mix(graded_rgb, screen_blend, mix_amount);
	}
	COLOR = vec4(output_rgb, base_color.a);
}