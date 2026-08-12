shader_type canvas_item;
render_mode unshaded;

uniform vec4 palette_shadow : source_color = vec4(0.10, 0.13, 0.12, 1.0);
uniform vec4 palette_deep : source_color = vec4(0.20, 0.28, 0.22, 1.0);
uniform vec4 palette_mid : source_color = vec4(0.34, 0.48, 0.34, 1.0);
uniform vec4 palette_light : source_color = vec4(0.55, 0.68, 0.43, 1.0);
uniform vec4 palette_accent : source_color = vec4(0.76, 0.83, 0.55, 1.0);
uniform float band_strength : hint_range(0.0, 1.0) = 0.78;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float seed_phase = 0.0;

varying vec2 local_pixel;

void vertex() {
	local_pixel = floor(VERTEX + vec2(0.5));
}

float color_distance(vec3 a, vec3 b) {
	vec3 d = a - b;
	return dot(d, d);
}

vec3 nearest_palette(vec3 source) {
	vec3 best = palette_shadow.rgb;
	float best_d = color_distance(source, best);
	float d = color_distance(source, palette_deep.rgb);
	if (d < best_d) { best = palette_deep.rgb; best_d = d; }
	d = color_distance(source, palette_mid.rgb);
	if (d < best_d) { best = palette_mid.rgb; best_d = d; }
	d = color_distance(source, palette_light.rgb);
	if (d < best_d) { best = palette_light.rgb; best_d = d; }
	d = color_distance(source, palette_accent.rgb);
	if (d < best_d) { best = palette_accent.rgb; }
	return best;
}

float ordered_cell(vec2 p) {
	vec2 c = mod(floor(p), 4.0);
	float i = c.x + c.y * 4.0;
	float threshold = 0.0;
	if (i == 0.0) threshold = 0.0;
	else if (i == 1.0) threshold = 8.0;
	else if (i == 2.0) threshold = 2.0;
	else if (i == 3.0) threshold = 10.0;
	else if (i == 4.0) threshold = 12.0;
	else if (i == 5.0) threshold = 4.0;
	else if (i == 6.0) threshold = 14.0;
	else if (i == 7.0) threshold = 6.0;
	else if (i == 8.0) threshold = 3.0;
	else if (i == 9.0) threshold = 11.0;
	else if (i == 10.0) threshold = 1.0;
	else if (i == 11.0) threshold = 9.0;
	else if (i == 12.0) threshold = 15.0;
	else if (i == 13.0) threshold = 7.0;
	else if (i == 14.0) threshold = 13.0;
	else threshold = 5.0;
	return threshold / 15.0;
}

void fragment() {
	vec4 source = COLOR;
	if (source.a <= 0.001) {
		COLOR = source;
		return;
	}

	// Low-alpha shadows/trails stay restrained. Opaque creature mass receives
	// palette banding and sparse one-cell variation only.
	if (source.a < 0.46) {
		COLOR = source;
		return;
	}

	vec3 snapped = nearest_palette(source.rgb);
	float cell = ordered_cell(local_pixel + vec2(seed_phase * 7.0, seed_phase * 3.0));
	float grain = (cell - 0.5) * detail_strength;
	vec3 neighbor = grain > 0.08 ? palette_light.rgb : palette_deep.rgb;
	float grain_mix = step(0.32, abs(grain)) * abs(grain) * 0.16;
	vec3 banded = mix(snapped, neighbor, grain_mix);
	vec3 final_rgb = mix(source.rgb, banded, band_strength);
	COLOR = vec4(final_rgb, source.a);
}
