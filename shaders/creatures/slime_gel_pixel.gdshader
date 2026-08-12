shader_type canvas_item;
render_mode unshaded;

uniform vec4 palette_shadow : source_color;
uniform vec4 palette_deep : source_color;
uniform vec4 palette_mid : source_color;
uniform vec4 palette_light : source_color;
uniform vec4 palette_accent : source_color;
uniform float band_strength : hint_range(0.0, 1.0) = 0.92;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.55;
uniform float seed_phase = 0.0;
uniform float gel_phase = 0.0;
uniform float translucency = 0.74;
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.35;

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

float checker(vec2 p) {
	vec2 c = mod(floor(p), 2.0);
	return mod(c.x + c.y, 2.0);
}

float gel_cell(vec2 p, float phase) {
	vec2 q = floor(p + vec2(seed_phase * 13.0, seed_phase * 7.0));
	float a = sin((q.x * 0.37 + q.y * 0.61) + floor(phase * 3.0) * 0.75);
	float b = sin((q.x * -0.19 + q.y * 0.43) - floor(phase * 2.0) * 0.55);
	return (a + b) * 0.25 + 0.5;
}

void fragment() {
	vec4 source = COLOR;
	if (source.a <= 0.001) {
		COLOR = source;
		return;
	}

	if (source.a < 0.34) {
		COLOR = source;
		return;
	}

	vec3 snapped = nearest_palette(source.rgb);
	float internal = gel_cell(local_pixel, gel_phase);
	float c = checker(local_pixel + vec2(floor(gel_phase * 2.0) + floor(seed_phase * 5.0), 0.0));
	float light_gate = step(0.67, internal) * detail_strength;
	float deep_gate = step(internal, 0.30) * detail_strength;

	vec3 material_color = snapped;
	material_color = mix(material_color, palette_light.rgb, light_gate * 0.22);
	material_color = mix(material_color, palette_deep.rgb, deep_gate * 0.18);
	material_color = mix(material_color, palette_accent.rgb, c * light_gate * refraction_strength * 0.13);
	vec3 final_rgb = mix(source.rgb, nearest_palette(material_color), band_strength);

	float body_alpha = min(source.a, translucency + (source.a - translucency) * 0.45);
	float alpha_variation = (c - 0.5) * 0.045 * refraction_strength;
	float final_alpha = clamp(body_alpha + alpha_variation, 0.0, 1.0);
	COLOR = vec4(final_rgb, final_alpha);
}
