shader_type canvas_item;
render_mode unshaded;

uniform vec4 grass_base : source_color = vec4(0.190, 0.320, 0.090, 1.0);
uniform vec4 grass_patch_a : source_color = vec4(0.275, 0.440, 0.120, 1.0);
uniform vec4 grass_patch_b : source_color = vec4(0.125, 0.235, 0.065, 1.0);

uniform float macro_scale : hint_range(0.0001, 0.05, 0.0001) = 0.0045;
uniform float detail_scale : hint_range(0.0001, 0.1, 0.0001) = 0.013;
uniform float patch_threshold_a : hint_range(0.0, 1.0, 0.001) = 0.57;
uniform float patch_threshold_b : hint_range(0.0, 1.0, 0.001) = 0.68;
uniform float pixel_block_pixels : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float speckle_amount : hint_range(0.0, 0.25, 0.001) = 0.035;
uniform float world_seed = 91373.0;

varying vec2 world_position;

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
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 pixel_world = floor(world_position / max(pixel_block_pixels, 1.0)) * max(pixel_block_pixels, 1.0);
	float macro = fbm(pixel_world * macro_scale);
	float detail = fbm(pixel_world * detail_scale + vec2(world_seed * 0.00037, world_seed * 0.00019));
	vec3 final_color = grass_base.rgb;
	if (macro > patch_threshold_a) {
		final_color = grass_patch_a.rgb;
	}
	if (detail > patch_threshold_b) {
		final_color = grass_patch_b.rgb;
	}
	float speckle = hash21(floor(pixel_world / 4.0));
	if (speckle > 1.0 - speckle_amount) {
		final_color *= 1.12;
	} else if (speckle < speckle_amount * 0.55) {
		final_color *= 0.88;
	}
	COLOR = vec4(final_color, 1.0);
}
