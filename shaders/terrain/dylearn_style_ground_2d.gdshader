shader_type canvas_item;
render_mode unshaded;

uniform sampler2D patch_noise : filter_linear, repeat_enable;

uniform vec4 grass_base : source_color = vec4(0.160, 0.305, 0.070, 1.0);
uniform vec4 grass_patch_a : source_color = vec4(0.225, 0.390, 0.085, 1.0);
uniform vec4 grass_patch_b : source_color = vec4(0.100, 0.220, 0.052, 1.0);
uniform float patch_scale_a : hint_range(0.0001, 0.01, 0.0001) = 0.00065;
uniform float patch_scale_b : hint_range(0.0001, 0.01, 0.0001) = 0.00165;
uniform float patch_threshold_a : hint_range(0.0, 1.0, 0.001) = 0.60;
uniform float patch_threshold_b : hint_range(0.0, 1.0, 0.001) = 0.73;

uniform float toon_field_scale : hint_range(0.0001, 0.01, 0.0001) = 0.00072;
uniform float toon_shadow_threshold : hint_range(0.0, 1.0, 0.001) = 0.38;
uniform float toon_highlight_threshold : hint_range(0.0, 1.0, 0.001) = 0.64;
uniform float toon_transition : hint_range(0.001, 0.2, 0.001) = 0.028;
uniform float toon_shadow_factor : hint_range(0.1, 2.0, 0.01) = 0.68;
uniform float toon_mid_factor : hint_range(0.1, 2.0, 0.01) = 0.92;
uniform float toon_highlight_factor : hint_range(0.1, 2.0, 0.01) = 1.14;
uniform float sample_pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

varying vec2 world_position;


float shared_toon_factor(vec2 position) {
	float primary = texture(
		patch_noise,
		position * toon_field_scale + vec2(0.17, 0.41)
	).r;
	float secondary = texture(
		patch_noise,
		position * (toon_field_scale * 0.47) + vec2(0.71, 0.13)
	).r;
	float field = clamp(primary * 0.78 + secondary * 0.22, 0.0, 1.0);
	float shadow_to_mid = smoothstep(
		toon_shadow_threshold - toon_transition,
		toon_shadow_threshold + toon_transition,
		field
	);
	float mid_to_high = smoothstep(
		toon_highlight_threshold - toon_transition,
		toon_highlight_threshold + toon_transition,
		field
	);
	float factor = mix(toon_shadow_factor, toon_mid_factor, shadow_to_mid);
	return mix(factor, toon_highlight_factor, mid_to_high);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	float safe_pixel_size = max(sample_pixel_size, 1.0);
	vec2 position = floor(world_position / safe_pixel_size) * safe_pixel_size;

	float patch_a = texture(
		patch_noise,
		position * patch_scale_a + vec2(0.13, 0.31)
	).r;
	float patch_b = texture(
		patch_noise,
		position * patch_scale_b + vec2(0.67, 0.19)
	).r;

	vec3 tint = grass_base.rgb;
	if (patch_a > patch_threshold_a) {
		tint = grass_patch_a.rgb;
	}
	if (patch_b > patch_threshold_b) {
		tint = grass_patch_b.rgb;
	}

	float toon_factor = shared_toon_factor(position);
	COLOR = vec4(tint * toon_factor, grass_base.a);
}
