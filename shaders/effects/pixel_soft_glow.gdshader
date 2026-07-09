shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 palette_color_1 : source_color = vec4(0.92, 0.22, 1.00, 0.55);
uniform vec4 palette_color_2 : source_color = vec4(0.50, 0.08, 0.95, 0.50);
uniform vec4 palette_color_3 : source_color = vec4(1.00, 0.58, 0.20, 0.42);
uniform vec4 palette_color_4 : source_color = vec4(0.18, 0.04, 0.40, 0.36);
uniform vec4 palette_color_5 : source_color = vec4(0.08, 0.02, 0.16, 0.28);
uniform vec4 palette_color_6 : source_color = vec4(1.00, 1.00, 1.00, 0.38);
uniform float palette_count : hint_range(1.0, 6.0, 1.0) = 4.0;
uniform float color_cycle_speed : hint_range(-12.0, 12.0, 0.01) = 0.65;
uniform float palette_blend : hint_range(0.0, 1.0, 0.01) = 0.55;

uniform float core_radius : hint_range(0.0, 0.5, 0.01) = 0.14;
uniform float edge_radius : hint_range(0.1, 0.9, 0.01) = 0.5;
uniform float falloff : hint_range(0.5, 8.0, 0.1) = 2.8;
uniform float pixel_steps : hint_range(4.0, 256.0, 1.0) = 28.0;
uniform float opacity : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float glow_intensity : hint_range(0.0, 4.0, 0.01) = 1.0;

uniform float pulse_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float pulse_speed : hint_range(0.0, 12.0, 0.01) = 1.3;
uniform float flicker_strength : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float flicker_speed : hint_range(0.0, 60.0, 0.1) = 12.0;
uniform float flicker_randomness : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float seed_offset : hint_range(0.0, 1000.0, 0.1) = 17.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
	float distance_from_center = distance(pixel_uv, vec2(0.5));
	float glow_mask = 1.0 - smoothstep(core_radius, edge_radius, distance_from_center);
	glow_mask = pow(clamp(glow_mask, 0.0, 1.0), falloff);

	float local_seed = hash(floor(pixel_uv * pixel_steps) + vec2(seed_offset, seed_offset * 0.37));
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	float flicker_phase = TIME * (flicker_speed + local_seed * flicker_speed * flicker_randomness) + local_seed * 31.416;
	float flicker = 1.0 - flicker_strength + (sin(flicker_phase) * 0.5 + 0.5) * flicker_strength;
	vec4 base_texture = texture(TEXTURE, UV);
	vec4 palette_color = sample_palette(TIME * color_cycle_speed + local_seed * palette_count);
	COLOR = vec4(palette_color.rgb, palette_color.a * glow_mask * base_texture.a * pulse * flicker * glow_intensity * opacity);
}
