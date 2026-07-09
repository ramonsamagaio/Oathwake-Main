shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 palette_color_1 : source_color = vec4(0.46, 0.14, 0.82, 0.24);
uniform vec4 palette_color_2 : source_color = vec4(0.18, 0.08, 0.36, 0.18);
uniform vec4 palette_color_3 : source_color = vec4(0.08, 0.14, 0.16, 0.16);
uniform vec4 palette_color_4 : source_color = vec4(0.55, 0.08, 0.18, 0.12);
uniform vec4 palette_color_5 : source_color = vec4(0.18, 0.18, 0.10, 0.12);
uniform vec4 palette_color_6 : source_color = vec4(1.00, 1.00, 1.00, 0.10);
uniform float palette_count : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float color_cycle_speed : hint_range(-10.0, 10.0, 0.01) = 0.12;
uniform float palette_blend : hint_range(0.0, 1.0, 0.01) = 0.75;

uniform float opacity : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float evolution_speed : hint_range(-4.0, 4.0, 0.01) = 0.18;
uniform float drift_speed_x : hint_range(-2.0, 2.0, 0.01) = 0.035;
uniform float drift_speed_y : hint_range(-2.0, 2.0, 0.01) = 0.012;
uniform float noise_scale : hint_range(1.0, 80.0, 0.1) = 13.0;
uniform float noise_contrast : hint_range(0.0, 2.0, 0.01) = 0.72;
uniform float softness : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float edge_fade : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float pixel_steps : hint_range(8.0, 256.0, 1.0) = 96.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec4 palette_at(float index) {
	if (index < 0.5) { return palette_color_1; }
	if (index < 1.5) { return palette_color_2; }
	if (index < 2.5) { return palette_color_3; }
	if (index < 3.5) { return palette_color_4; }
	if (index < 4.5) { return palette_color_5; }
	return palette_color_6;
}

vec4 sample_palette(float phase) {
	float count = clamp(palette_count, 1.0, 6.0);
	float wrapped = mod(phase, count);
	float low_index = floor(wrapped);
	float high_index = mod(low_index + 1.0, count);
	float t = fract(wrapped) * palette_blend;
	return mix(palette_at(low_index), palette_at(high_index), t);
}

void fragment() {
	vec2 pixel_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	vec2 drift = vec2(TIME * drift_speed_x, TIME * drift_speed_y);
	float n1 = noise((pixel_uv + drift) * noise_scale + TIME * evolution_speed);
	float n2 = noise((pixel_uv * 1.9 - drift * 0.7) * noise_scale * 0.55 - TIME * evolution_speed * 0.61);
	float cloud = smoothstep(softness, 1.0, mix(n1, n2, 0.45));
	cloud = pow(clamp(cloud, 0.0, 1.0), max(0.01, noise_contrast));

	float tex_alpha = texture(TEXTURE, UV).a;
	float dist = distance(UV, vec2(0.5));
	float edge = 1.0 - smoothstep(0.5 - edge_fade, 0.5, dist);
	vec4 pal = sample_palette(TIME * color_cycle_speed + n1 * palette_count);
	COLOR = vec4(pal.rgb, pal.a * tex_alpha * cloud * edge * opacity);
}
