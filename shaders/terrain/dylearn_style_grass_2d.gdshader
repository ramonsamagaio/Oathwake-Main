shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grass_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform sampler2D wind_noise : filter_linear, repeat_enable;
uniform vec4 palette_shadow : source_color = vec4(0.392157, 0.474510, 0.176471, 1.0);
uniform vec4 palette_dark_mid : source_color = vec4(0.537255, 0.682353, 0.227451, 1.0);
uniform vec4 palette_mid_light : source_color = vec4(0.650980, 0.756863, 0.294118, 1.0);
uniform vec4 palette_highlight : source_color = vec4(0.768627, 0.827451, 0.349020, 1.0);
uniform float palette_field_scale_a = 0.00024;
uniform float palette_field_scale_b = 0.00072;
uniform float palette_threshold_1 = 0.24;
uniform float palette_threshold_2 = 0.43;
uniform float palette_threshold_3 = 0.68;
uniform float stepped_time = 0.0;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength_pixels = 3.0;
uniform float wind_noise_scale = 0.00135;
uniform float wind_noise_speed = 0.044;
uniform float wind_noise_threshold = 0.36;
uniform float wind_gust_width = 0.21;
uniform float noise_diverge_angle = 0.23;
uniform float fake_perspective_scale = 0.05;
uniform vec3 displacer = vec3(-100000.0, -100000.0, 1.0);
uniform float displacement_strength_pixels = 6.0;
uniform float radius_exponent = 1.55;
uniform vec2 quad_size_pixels = vec2(40.0, 28.0);

varying vec2 object_origin;
varying float sprite_index_v;
varying float fake_perspective_amount;

vec2 rotate_vec2(vec2 value, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(value.x * c - value.y * s, value.x * s + value.y * c);
}

float shared_palette_field(vec2 world_position) {
	float broad = texture(patch_noise, world_position * palette_field_scale_a + vec2(0.13, 0.31)).r;
	float secondary = texture(patch_noise, world_position * palette_field_scale_b + vec2(0.67, 0.19)).r;
	return clamp(broad * 0.88 + secondary * 0.12 + 0.16, 0.0, 1.0);
}

float palette_index_from_field(float field) {
	return step(palette_threshold_1, field) + step(palette_threshold_2, field) + step(palette_threshold_3, field);
}

vec3 palette_colour(float index) {
	vec3 colour = palette_shadow.rgb;
	colour = mix(colour, palette_dark_mid.rgb, step(0.5, index));
	colour = mix(colour, palette_mid_light.rgb, step(1.5, index));
	colour = mix(colour, palette_highlight.rgb, step(2.5, index));
	return colour;
}

float family_wind_scale(float sprite_index) {
	float scale_value = 0.14;
	scale_value = mix(scale_value, 0.04, step(4.5, sprite_index));
	float tall_scale = mix(0.72, 1.0, clamp((sprite_index - 8.0) / 4.0, 0.0, 1.0));
	scale_value = mix(scale_value, tall_scale, step(7.5, sprite_index));
	scale_value = mix(scale_value, 1.12, step(12.5, sprite_index));
	return scale_value;
}

float family_palette_bias(float sprite_index) {
	float bias = 0.0;
	bias = mix(bias, -1.0, step(1.5, sprite_index));
	bias = mix(bias, -2.0, step(7.5, sprite_index));
	return bias;
}

void vertex() {
	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	sprite_index_v = round(INSTANCE_CUSTOM.g * 13.0);
	vec2 wind_dir = normalize(wind_direction + vec2(0.00001, 0.0));
	vec2 direction_a = rotate_vec2(wind_dir, noise_diverge_angle);
	vec2 direction_b = rotate_vec2(wind_dir, -noise_diverge_angle);
	vec2 wind_uv_a = object_origin * wind_noise_scale + direction_a * stepped_time * wind_noise_speed;
	vec2 wind_uv_b = object_origin * (wind_noise_scale * 0.81) + direction_b * stepped_time * wind_noise_speed * 0.91 + vec2(0.37, 0.61);
	float noise_a = texture(wind_noise, wind_uv_a).r;
	float noise_b = texture(wind_noise, wind_uv_b).r;
	float gust = smoothstep(wind_noise_threshold, wind_noise_threshold + max(wind_gust_width, 0.001), noise_a * noise_b);
	float wind_sample = clamp(((noise_a - 0.5) * 0.10 + gust * 0.84) * mix(0.88, 1.0, INSTANCE_CUSTOM.r), -0.10, 0.90);
	float family_motion = family_wind_scale(sprite_index_v);
	float top_curve = UV.y * UV.y;
	vec2 wind_offset = vec2(
		wind_dir.x * wind_sample * wind_strength_pixels * top_curve * family_motion,
		wind_dir.y * abs(wind_sample) * wind_strength_pixels * 0.14 * top_curve * family_motion
	);
	VERTEX += round(wind_offset);
	vec2 away_from_displacer = object_origin - displacer.xy;
	float distance_to_displacer = length(away_from_displacer);
	float radius = max(displacer.z, 0.001);
	float displacement = pow(max(0.0, 1.0 - distance_to_displacer / radius), radius_exponent);
	vec2 displacement_dir = away_from_displacer / max(distance_to_displacer, 0.001);
	vec2 local_displacement = vec2(
		displacement_dir.x * displacement * displacement_strength_pixels * top_curve * family_motion,
		displacement_dir.y * displacement * displacement_strength_pixels * 0.28 * top_curve * family_motion
	);
	VERTEX += round(local_displacement);
	fake_perspective_amount = (wind_sample * wind_dir.y * fake_perspective_scale - displacement_dir.y * displacement * 0.12) * family_motion;
}

void fragment() {
	vec2 source_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 uv = source_uv;
	uv.x -= 0.5;
	uv.x *= (1.0 - uv.y) * fake_perspective_amount + 1.0;
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 0.9999);
	float atlas_index = clamp(sprite_index_v, 0.0, 13.0);
	vec2 atlas_uv = vec2((uv.x + atlas_index) / 14.0, uv.y);
	vec4 albedo_tex = texture(grass_atlas, atlas_uv);
	vec2 fragment_world = object_origin + vec2(
		(source_uv.x - 0.5) * quad_size_pixels.x,
		(0.5 - source_uv.y) * quad_size_pixels.y
	);
	float palette_index = palette_index_from_field(shared_palette_field(fragment_world));
	palette_index = clamp(palette_index + family_palette_bias(atlas_index), 0.0, 3.0);
	COLOR = vec4(palette_colour(palette_index), step(0.5, albedo_tex.a));
}
