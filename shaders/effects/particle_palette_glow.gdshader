shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 palette_color_1 : source_color = vec4(1.00, 0.35, 1.00, 1.0);
uniform vec4 palette_color_2 : source_color = vec4(0.74, 0.10, 1.00, 1.0);
uniform vec4 palette_color_3 : source_color = vec4(0.34, 0.04, 0.80, 1.0);
uniform vec4 palette_color_4 : source_color = vec4(1.00, 0.58, 0.20, 1.0);
uniform vec4 palette_color_5 : source_color = vec4(0.24, 0.02, 0.12, 1.0);
uniform vec4 palette_color_6 : source_color = vec4(1.00, 1.00, 1.00, 1.0);
uniform float palette_count : hint_range(1.0, 6.0, 1.0) = 4.0;
uniform float color_cycle_speed : hint_range(-60.0, 60.0, 0.1) = 18.0;
uniform float palette_blend : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float particle_color_randomness : hint_range(0.0, 1.0, 0.01) = 0.45;

// 0 Square Pixel, 1 Circle/Orb
uniform float particle_shape : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float use_texture_alpha : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float core_radius : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float core_softness : hint_range(0.0, 0.2, 0.005) = 0.0;
uniform float halo_radius : hint_range(0.05, 0.8, 0.01) = 0.34;
uniform float halo_softness : hint_range(0.01, 2.0, 0.01) = 0.75;
uniform float core_intensity : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float glow_intensity : hint_range(0.0, 6.0, 0.01) = 0.45;
uniform float alpha_multiplier : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float pixel_steps : hint_range(4.0, 128.0, 1.0) = 18.0;

uniform float flicker_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float flicker_speed : hint_range(0.0, 80.0, 0.1) = 5.0;
uniform float flicker_randomness : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float seed_offset : hint_range(0.0, 1000.0, 0.1) = 41.0;

varying float particle_seed;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 74.7);
	return fract(p.x * p.y);
}

void vertex() {
	particle_seed = hash(vec2(INSTANCE_CUSTOM.x + seed_offset, INSTANCE_CUSTOM.y + VERTEX.x * 0.013 + VERTEX.y * 0.017));
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

float square_mask(vec2 uv, float radius, float softness) {
	float box_distance = max(abs(uv.x - 0.5), abs(uv.y - 0.5));
	if (softness <= 0.0001) {
		return step(box_distance, radius);
	}
	return 1.0 - smoothstep(radius, radius + softness, box_distance);
}

float circle_mask(vec2 uv, float radius, float softness) {
	float dist = distance(uv, vec2(0.5));
	if (softness <= 0.0001) {
		return step(dist, radius);
	}
	return 1.0 - smoothstep(radius, radius + softness, dist);
}

void fragment() {
	vec2 pixel_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	float tex_alpha = texture(TEXTURE, UV).a;
	float alpha_source = mix(1.0, tex_alpha, use_texture_alpha);

	float square_core = square_mask(pixel_uv, core_radius, core_softness);
	float circle_core = circle_mask(pixel_uv, core_radius, core_softness);
	float core = mix(square_core, circle_core, particle_shape) * core_intensity;

	float halo = 1.0 - smoothstep(core_radius, halo_radius, distance(pixel_uv, vec2(0.5)));
	halo = pow(clamp(halo, 0.0, 1.0), halo_softness) * glow_intensity;

	float seed = particle_seed;
	float cycle_seed = seed * palette_count * particle_color_randomness;
	vec4 chosen_color = sample_palette(TIME * color_cycle_speed + cycle_seed);
	float flicker_phase = TIME * (flicker_speed + seed * flicker_speed * flicker_randomness) + seed * 64.0;
	float flicker = 1.0 - flicker_strength + (sin(flicker_phase) * 0.5 + 0.5) * flicker_strength;

	float alpha = max(core * alpha_source, halo * alpha_source * 0.75) * alpha_multiplier * flicker;
	COLOR = vec4(chosen_color.rgb, chosen_color.a * alpha);
}
