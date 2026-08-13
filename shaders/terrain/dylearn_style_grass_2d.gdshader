shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grass_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform sampler2D wind_noise : filter_linear, repeat_enable;

// Four-colour palette sampled from the supplied image-3 reference.
// No shader multiplication is allowed after palette selection, so overlapping
// cards cannot manufacture intermediate greens.
uniform vec4 palette_shadow : source_color = vec4(0.278431, 0.364706, 0.117647, 1.0);
uniform vec4 palette_dark_mid : source_color = vec4(0.513725, 0.643137, 0.211765, 1.0);
uniform vec4 palette_mid_light : source_color = vec4(0.650980, 0.749020, 0.294118, 1.0);
uniform vec4 palette_highlight : source_color = vec4(0.764706, 0.827451, 0.356863, 1.0);

uniform float palette_field_scale_a : hint_range(0.0001, 0.01, 0.0001) = 0.00058;
uniform float palette_field_scale_b : hint_range(0.0001, 0.01, 0.0001) = 0.00145;
uniform float palette_threshold_1 : hint_range(0.0, 1.0, 0.001) = 0.30;
uniform float palette_threshold_2 : hint_range(0.0, 1.0, 0.001) = 0.50;
uniform float palette_threshold_3 : hint_range(0.0, 1.0, 0.001) = 0.68;

uniform float stepped_time = 0.0;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength_pixels : hint_range(0.0, 12.0, 0.1) = 3.2;
uniform float wind_noise_scale : hint_range(0.0001, 0.02, 0.0001) = 0.00145;
uniform float wind_noise_speed : hint_range(0.0, 0.25, 0.001) = 0.046;
uniform float wind_noise_threshold : hint_range(0.0, 1.0, 0.001) = 0.35;
uniform float wind_gust_width : hint_range(0.001, 0.5, 0.001) = 0.20;
uniform float noise_diverge_angle : hint_range(0.0, 1.2, 0.01) = 0.23;
uniform float fake_perspective_scale : hint_range(-0.5, 0.75, 0.01) = 0.08;

uniform vec3 displacer = vec3(-100000.0, -100000.0, 1.0);
uniform float displacement_strength_pixels : hint_range(0.0, 20.0, 0.1) = 6.0;
uniform float radius_exponent : hint_range(0.1, 6.0, 0.1) = 1.55;
uniform vec2 quad_size_pixels = vec2(40.0, 28.0);

varying vec2 object_origin;
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


float shared_palette_field(vec2 world_position) {
	float broad = texture(
		patch_noise,
		world_position * palette_field_scale_a + vec2(0.13, 0.31)
	).r;
	float detail = texture(
		patch_noise,
		world_position * palette_field_scale_b + vec2(0.67, 0.19)
	).r;
	// Bright-field bias matches the reference, where the open meadow is mostly
	// the two lightest greens and darker tones form islands/grass silhouettes.
	return clamp(broad * 0.76 + detail * 0.24 + 0.10, 0.0, 1.0);
}


float palette_index_from_field(float field) {
	if (field < palette_threshold_1) {
		return 0.0;
	}
	if (field < palette_threshold_2) {
		return 1.0;
	}
	if (field < palette_threshold_3) {
		return 2.0;
	}
	return 3.0;
}


vec3 palette_colour(float index) {
	if (index < 0.5) {
		return palette_shadow.rgb;
	}
	if (index < 1.5) {
		return palette_dark_mid.rgb;
	}
	if (index < 2.5) {
		return palette_mid_light.rgb;
	}
	return palette_highlight.rgb;
}


float family_wind_scale(float sprite_index) {
	// 0-5 carpet, 6-8 broad ground leaves, 9-10 tall grass, 11 tall weed.
	if (sprite_index < 5.5) {
		return 0.42;
	}
	if (sprite_index < 8.5) {
		return 0.16;
	}
	if (sprite_index < 10.5) {
		return 1.0;
	}
	return 1.16;
}


float family_palette_bias(float sprite_index) {
	// Half of the carpet variants intentionally fuse with the floor. The other
	// half are one palette step darker. Leaves/tall grass remain readable using
	// the same four colours rather than new tints.
	if (sprite_index < 2.5) {
		return 0.0;
	}
	if (sprite_index < 8.5) {
		return -1.0;
	}
	return -2.0;
}


void vertex() {
	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	sprite_index_v = round(INSTANCE_CUSTOM.g * 11.0);

	vec2 wind_dir = wind_direction;
	if (length(wind_dir) < 0.0001) {
		wind_dir = vec2(1.0, 0.0);
	}
	wind_dir = normalize(wind_dir);

	vec2 wind_dir_1 = rotate_vec2(wind_dir, noise_diverge_angle);
	vec2 wind_dir_2 = rotate_vec2(wind_dir, -noise_diverge_angle);
	vec2 wind_uv_1 = object_origin * wind_noise_scale + wind_dir_1 * stepped_time * wind_noise_speed;
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

	float susceptibility = mix(0.82, 1.0, INSTANCE_CUSTOM.r);
	float background_sway = (noise_1 - 0.5) * 0.16;
	float wind_sample = clamp(
		(background_sway + gust * 0.86) * susceptibility,
		-0.14,
		0.92
	);
	float family_motion = family_wind_scale(sprite_index_v);

	// Root stays planted. All card movement is snapped to whole pixels, which
	// keeps the blades reading as pixel art instead of sub-pixel hairlines.
	float top_influence = UV.y;
	float top_curve = top_influence * top_influence;
	vec2 wind_offset = vec2(
		wind_dir.x * wind_sample * wind_strength_pixels * top_curve * family_motion,
		wind_dir.y * abs(wind_sample) * wind_strength_pixels * 0.16 * top_curve * family_motion
	);
	VERTEX += round(wind_offset);

	vec2 away_from_displacer = object_origin - displacer.xy;
	float radius = max(displacer.z, 0.001);
	float distance_normalized = length(away_from_displacer) / radius;
	float displacement = pow(max(0.0, 1.0 - distance_normalized), radius_exponent);
	vec2 displacement_dir = vec2(0.0, 1.0);
	if (length(away_from_displacer) > 0.001) {
		displacement_dir = normalize(away_from_displacer);
	}

	vec2 local_displacement = vec2(
		displacement_dir.x * displacement * displacement_strength_pixels * top_curve * family_motion,
		displacement_dir.y * displacement * displacement_strength_pixels * 0.30 * top_curve * family_motion
	);
	VERTEX += round(local_displacement);

	fake_perspective_amount = (
		wind_sample * wind_dir.y * fake_perspective_scale
		- displacement_dir.y * displacement * 0.16
	) * family_motion;
}


void fragment() {
	vec2 source_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 uv = source_uv;
	uv.x -= 0.5;
	uv.x *= (1.0 - uv.y) * fake_perspective_amount + 1.0;
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 1.0);

	float atlas_index = clamp(sprite_index_v, 0.0, 11.0);
	vec2 atlas_uv = vec2((uv.x + atlas_index) / 12.0, uv.y);
	vec4 albedo_tex = texture(grass_atlas, atlas_uv);
	if (albedo_tex.a < 0.5) {
		discard;
	}

	// Sample the same world-space colour field as the floor at the approximate
	// pixel occupied by this fragment. Adjacent/overlapping cards therefore tend
	// to choose the same palette entry and visually knit into one mass.
	vec2 fragment_world = object_origin + vec2(
		(source_uv.x - 0.5) * quad_size_pixels.x,
		(0.5 - source_uv.y) * quad_size_pixels.y
	);
	float field = shared_palette_field(fragment_world);
	float palette_index = palette_index_from_field(field);
	palette_index = clamp(palette_index + family_palette_bias(atlas_index), 0.0, 3.0);

	COLOR = vec4(palette_colour(palette_index), 1.0);
}
