shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grass_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform sampler2D wind_noise : filter_linear, repeat_enable;

uniform vec4 grass_color_base : source_color = vec4(0.195, 0.355, 0.082, 1.0);
uniform vec4 grass_color_patch_a : source_color = vec4(0.285, 0.455, 0.105, 1.0);
uniform vec4 grass_color_patch_b : source_color = vec4(0.115, 0.255, 0.060, 1.0);
uniform vec4 accent_color_a : source_color = vec4(0.355, 0.510, 0.105, 1.0);
uniform vec4 accent_color_b : source_color = vec4(0.285, 0.420, 0.082, 1.0);

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

uniform float stepped_time = 0.0;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength_pixels : hint_range(0.0, 12.0, 0.1) = 3.6;
uniform float wind_noise_scale : hint_range(0.0001, 0.02, 0.0001) = 0.00155;
uniform float wind_noise_speed : hint_range(0.0, 0.25, 0.001) = 0.050;
uniform float wind_noise_threshold : hint_range(0.0, 1.0, 0.001) = 0.34;
uniform float wind_gust_width : hint_range(0.001, 0.5, 0.001) = 0.19;
uniform float noise_diverge_angle : hint_range(0.0, 1.2, 0.01) = 0.23;
uniform float fake_perspective_scale : hint_range(-0.5, 0.75, 0.01) = 0.16;

uniform vec3 displacer = vec3(-100000.0, -100000.0, 1.0);
uniform float displacement_strength_pixels : hint_range(0.0, 20.0, 0.1) = 7.0;
uniform float radius_exponent : hint_range(0.1, 6.0, 0.1) = 1.55;
uniform vec2 quad_size_pixels = vec2(40.0, 28.0);

varying vec2 object_origin;
varying float tuft_variation;
varying float sprite_index_v;
varying float fake_perspective_amount;


vec2 rotate_vec2(vec2 value, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(
		value.x * c - value.y * s,
		value.x * s + value.y * c
	);
}


vec2 rotate_around_base(vec2 vertex, float angle) {
	vec2 base = vec2(0.0, quad_size_pixels.y * 0.5);
	vec2 local = vertex - base;
	float c = cos(angle);
	float s = sin(angle);
	local = vec2(
		local.x * c - local.y * s,
		local.x * s + local.y * c
	);
	return base + local;
}


float shared_toon_factor(vec2 world_position) {
	float primary = texture(
		patch_noise,
		world_position * toon_field_scale + vec2(0.17, 0.41)
	).r;
	float secondary = texture(
		patch_noise,
		world_position * (toon_field_scale * 0.47) + vec2(0.71, 0.13)
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
	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	tuft_variation = INSTANCE_CUSTOM.r;
	sprite_index_v = round(INSTANCE_CUSTOM.g * 7.0);

	vec2 wind_dir = wind_direction;
	if (length(wind_dir) < 0.0001) {
		wind_dir = vec2(1.0, 0.0);
	}
	wind_dir = normalize(wind_dir);

	vec2 wind_dir_1 = rotate_vec2(wind_dir, noise_diverge_angle);
	vec2 wind_dir_2 = rotate_vec2(wind_dir, -noise_diverge_angle);
	vec2 wind_uv_1 = (
		object_origin * wind_noise_scale
		+ wind_dir_1 * stepped_time * wind_noise_speed
	);
	vec2 wind_uv_2 = (
		object_origin * (wind_noise_scale * 0.81)
		+ wind_dir_2 * stepped_time * wind_noise_speed * 0.91
		+ vec2(0.37, 0.61)
	);

	float noise_1 = texture(wind_noise, wind_uv_1).r;
	float noise_2 = texture(wind_noise, wind_uv_2).r;
	float combined_noise = noise_1 * noise_2;
	float gust = smoothstep(
		wind_noise_threshold,
		wind_noise_threshold + max(wind_gust_width, 0.001),
		combined_noise
	);

	// Dylearn's field reads as one organism: all instances share the exact same
	// stepped clock and world-space gust map. Individual susceptibility only
	// nudges amplitude; it never gives a tuft its own animation phase.
	float susceptibility = mix(0.82, 1.0, INSTANCE_CUSTOM.b);
	float background_sway = (noise_1 - 0.5) * 0.18;
	float wind_sample = clamp(
		(background_sway + gust * 0.88) * susceptibility,
		-0.16,
		0.95
	);

	// Keep the lower edge planted while the upper pixels flex together.
	float top_influence = UV.y;
	float top_curve = top_influence * top_influence;
	float shape_stiffness = mix(0.92, 1.08, INSTANCE_CUSTOM.a);
	float sway_angle = wind_sample * wind_dir.x * 0.115 * shape_stiffness;
	VERTEX = rotate_around_base(VERTEX, sway_angle);
	VERTEX.x += (
		wind_dir.x
		* wind_sample
		* wind_strength_pixels
		* top_curve
		* shape_stiffness
	);
	VERTEX.y += (
		wind_dir.y
		* abs(wind_sample)
		* wind_strength_pixels
		* 0.18
		* top_curve
	);

	vec2 away_from_displacer = object_origin - displacer.xy;
	float radius = max(displacer.z, 0.001);
	float distance_normalized = length(away_from_displacer) / radius;
	float displacement = pow(
		max(0.0, 1.0 - distance_normalized),
		radius_exponent
	);
	vec2 displacement_dir = vec2(0.0, 1.0);
	if (length(away_from_displacer) > 0.001) {
		displacement_dir = normalize(away_from_displacer);
	}

	VERTEX.x += (
		displacement_dir.x
		* displacement
		* displacement_strength_pixels
		* top_curve
	);
	VERTEX.y += (
		displacement_dir.y
		* displacement
		* displacement_strength_pixels
		* 0.34
		* top_curve
	);

	fake_perspective_amount = (
		wind_sample * wind_dir.y * fake_perspective_scale
		- displacement_dir.y * displacement * 0.28
	);
}


void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	uv.x -= 0.5;
	uv.x *= (1.0 - uv.y) * fake_perspective_amount + 1.0;
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 1.0);

	float atlas_index = clamp(sprite_index_v, 0.0, 7.0);
	vec2 atlas_uv = vec2(
		(uv.x + atlas_index) / 8.0,
		uv.y
	);
	vec4 albedo_tex = texture(grass_atlas, atlas_uv);
	if (albedo_tex.a < 0.5) {
		discard;
	}

	float patch_a = texture(
		patch_noise,
		object_origin * patch_scale_a + vec2(0.13, 0.31)
	).r;
	float patch_b = texture(
		patch_noise,
		object_origin * patch_scale_b + vec2(0.67, 0.19)
	).r;

	vec3 tint = grass_color_base.rgb;
	if (patch_a > patch_threshold_a) {
		tint = grass_color_patch_a.rgb;
	}
	if (patch_b > patch_threshold_b) {
		tint = grass_color_patch_b.rgb;
	}
	if (atlas_index > 6.5) {
		tint = accent_color_b.rgb;
	} else if (atlas_index > 5.5) {
		tint = accent_color_a.rgb;
	}

	// Keep per-card tint differences tiny. The shared world-space toon field does
	// the large visual grouping, which is what makes overlapping cards fuse.
	float instance_variation = mix(0.975, 1.025, tuft_variation);
	float toon_factor = shared_toon_factor(object_origin);
	COLOR = vec4(
		tint * instance_variation * toon_factor * albedo_tex.rgb,
		albedo_tex.a
	);
}
