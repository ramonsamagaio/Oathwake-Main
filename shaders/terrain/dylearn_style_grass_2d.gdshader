shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grass_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D accent_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 grass_color_base : source_color = vec4(0.235, 0.390, 0.105, 1.0);
uniform vec4 grass_color_patch_a : source_color = vec4(0.315, 0.500, 0.135, 1.0);
uniform vec4 grass_color_patch_b : source_color = vec4(0.145, 0.270, 0.075, 1.0);
uniform vec4 accent_color : source_color = vec4(0.500, 0.650, 0.170, 1.0);
uniform float patch_scale_a : hint_range(0.0001, 0.05, 0.0001) = 0.0046;
uniform float patch_scale_b : hint_range(0.0001, 0.05, 0.0001) = 0.0082;
uniform float patch_threshold_a : hint_range(0.0, 1.0, 0.001) = 0.59;
uniform float patch_threshold_b : hint_range(0.0, 1.0, 0.001) = 0.66;
uniform float accent_frequency : hint_range(0.0, 0.35, 0.001) = 0.075;
uniform float framerate : hint_range(1.0, 16.0, 1.0) = 5.0;
uniform bool quantised = true;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength_pixels : hint_range(0.0, 12.0, 0.1) = 5.4;
uniform float wind_noise_scale : hint_range(0.001, 0.2, 0.001) = 0.032;
uniform float wind_noise_speed : hint_range(0.0, 80.0, 0.1) = 14.0;
uniform float wind_noise_threshold : hint_range(-1.0, 1.0, 0.001) = 0.34;
uniform float noise_diverge_angle : hint_range(0.0, 1.2, 0.01) = 0.42;
uniform float fake_perspective_scale : hint_range(-0.5, 0.75, 0.01) = 0.28;
uniform vec3 displacer = vec3(-100000.0, -100000.0, 1.0);
uniform float displacement_strength_pixels : hint_range(0.0, 20.0, 0.1) = 9.0;
uniform float radius_exponent : hint_range(0.1, 6.0, 0.1) = 1.4;
uniform vec2 quad_size_pixels = vec2(18.0, 18.0);
uniform float world_seed = 91373.0;

varying vec2 object_origin;
varying float tuft_seed;
varying float tuft_variation;
varying float wind_noise_sample_v;
varying float fake_perspective_amount;
varying float accent_selector;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32 + world_seed * 0.0001);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 3; octave++) {
		value += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

vec2 rotate_vec2(vec2 value, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(value.x * c - value.y * s, value.x * s + value.y * c);
}

vec2 rotate_around_base(vec2 vertex, float angle) {
	vec2 base = vec2(0.0, quad_size_pixels.y * 0.5);
	vec2 local = vertex - base;
	float c = cos(angle);
	float s = sin(angle);
	local = vec2(local.x * c - local.y * s, local.x * s + local.y * c);
	return base + local;
}

void vertex() {
	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	tuft_seed = hash21(floor(object_origin * 0.25) + vec2(INSTANCE_CUSTOM.r * 13.7, INSTANCE_CUSTOM.g * 29.3));
	tuft_variation = INSTANCE_CUSTOM.g;
	accent_selector = hash21(floor(object_origin * 0.19) + vec2(INSTANCE_CUSTOM.b * 41.0, INSTANCE_CUSTOM.r * 17.0));
	float safe_framerate = max(framerate, 1.0);
	float frame_time = 1.0 / safe_framerate;
	float phase = mod(tuft_seed * 7.31, frame_time);
	float stepped_time = TIME;
	if (quantised) {
		stepped_time += phase;
		stepped_time = round(stepped_time * safe_framerate) / safe_framerate;
	}
	vec2 wind_dir = normalize(length(wind_direction) > 0.0001 ? wind_direction : vec2(1.0, 0.0));
	vec2 wind_dir_1 = rotate_vec2(wind_dir, noise_diverge_angle);
	vec2 wind_dir_2 = rotate_vec2(wind_dir, -noise_diverge_angle);
	float noise_1 = fbm(object_origin * wind_noise_scale + wind_dir_1 * stepped_time * wind_noise_speed);
	float noise_2 = fbm(object_origin * (wind_noise_scale * 0.8) + wind_dir_2 * stepped_time * wind_noise_speed * 0.89 + vec2(11.7, 37.3));
	float wind_sample = clamp((noise_1 * noise_2) + wind_noise_threshold, 0.0, 1.0);
	wind_sample = (wind_sample - 0.5) * 2.0;
	wind_noise_sample_v = wind_sample;
	float top_influence = UV.y;
	float top_curve = top_influence * top_influence;
	float sway_angle = wind_sample * wind_dir.x * 0.26;
	VERTEX = rotate_around_base(VERTEX, sway_angle);
	VERTEX.x += wind_dir.x * wind_sample * wind_strength_pixels * top_curve;
	VERTEX.y += wind_dir.y * abs(wind_sample) * wind_strength_pixels * 0.32 * top_curve;
	vec2 away_from_displacer = object_origin - displacer.xy;
	float radius = max(displacer.z, 0.001);
	float distance_normalized = length(away_from_displacer) / radius;
	float displacement = pow(max(0.0, 1.0 - distance_normalized), radius_exponent);
	vec2 displacement_dir = vec2(0.0, 1.0);
	if (length(away_from_displacer) > 0.001) {
		displacement_dir = normalize(away_from_displacer);
	}
	VERTEX.x += displacement_dir.x * displacement * displacement_strength_pixels * top_curve;
	VERTEX.y += displacement_dir.y * displacement * displacement_strength_pixels * 0.42 * top_curve;
	fake_perspective_amount = (wind_sample * wind_dir.y * fake_perspective_scale) - (displacement_dir.y * displacement * 0.42);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	uv.x -= 0.5;
	uv.x *= (1.0 - uv.y) * fake_perspective_amount + 1.0;
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 1.0);
	vec4 albedo_tex = texture(grass_texture, uv);
	if (accent_selector < accent_frequency) {
		albedo_tex = texture(accent_texture, uv);
	}
	if (albedo_tex.a < 0.5) {
		discard;
	}
	float patch_a = fbm(object_origin * patch_scale_a);
	float patch_b = fbm(object_origin * patch_scale_b + vec2(world_seed * 0.00021, world_seed * 0.00039));
	vec3 tint = grass_color_base.rgb;
	if (patch_a > patch_threshold_a) {
		tint = grass_color_patch_a.rgb;
	}
	if (patch_b > patch_threshold_b) {
		tint = grass_color_patch_b.rgb;
	}
	if (accent_selector < accent_frequency) {
		tint = accent_color.rgb;
	}
	float instance_variation = mix(0.90, 1.10, tuft_variation);
	tint *= instance_variation;
	COLOR = vec4(tint * albedo_tex.rgb, albedo_tex.a);
}
