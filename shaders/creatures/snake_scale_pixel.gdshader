shader_type canvas_item;
render_mode unshaded;

uniform vec4 palette_shadow : source_color;
uniform vec4 palette_deep : source_color;
uniform vec4 palette_mid : source_color;
uniform vec4 palette_light : source_color;
uniform vec4 palette_accent : source_color;
uniform float band_strength : hint_range(0.0, 1.0) = 0.88;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.42;
uniform float seed_phase = 0.0;
uniform float scale_phase = 0.0;

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

void fragment() {
	vec4 source = COLOR;
	if (source.a <= 0.001 || source.a < 0.45) {
		COLOR = source;
		return;
	}

	vec2 p = floor(local_pixel + vec2(seed_phase * 11.0, seed_phase * 5.0));
	float row = mod(p.y + floor(scale_phase * 2.0), 4.0);
	float stagger = mod(p.x + floor(row * 0.5), 5.0);
	float scale_glint = step(3.8, stagger) * step(1.0, row) * step(row, 2.9);
	float scale_deep = step(stagger, 0.2) * step(2.8, row);

	vec3 snapped = nearest_palette(source.rgb);
	vec3 detailed = mix(snapped, palette_light.rgb, scale_glint * detail_strength * 0.20);
	detailed = mix(detailed, palette_deep.rgb, scale_deep * detail_strength * 0.16);
	COLOR = vec4(mix(source.rgb, nearest_palette(detailed), band_strength), source.a);
}
