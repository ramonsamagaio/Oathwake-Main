shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform vec4 palette_color_1 : source_color = vec4(0.92, 0.22, 1.00, 0.55);
uniform vec4 palette_color_2 : source_color = vec4(0.50, 0.08, 0.95, 0.50);
uniform vec4 palette_color_3 : source_color = vec4(1.00, 0.58, 0.20, 0.42);
uniform vec4 palette_color_4 : source_color = vec4(0.18, 0.04, 0.40, 0.36);
uniform vec4 palette_color_5 : source_color = vec4(0.08, 0.02, 0.16, 0.28);
uniform vec4 palette_color_6 : source_color = vec4(1.00, 1.00, 1.00, 0.38);
uniform float palette_count : hint_range(1.0, 6.0, 1.0) = 4.0;
uniform float color_cycle_speed : hint_range(-120.0, 120.0, 0.01) = 0.65;
uniform float palette_blend : hint_range(0.0, 1.0, 0.01) = 0.55;

uniform float core_radius : hint_range(0.0, 0.5, 0.01) = 0.14;
uniform float edge_radius : hint_range(0.1, 0.9, 0.01) = 0.5;
uniform float falloff : hint_range(0.5, 8.0, 0.1) = 2.8;
uniform float pixel_steps : hint_range(4.0, 256.0, 1.0) = 28.0;
uniform float opacity : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float glow_intensity : hint_range(0.0, 4.0, 0.01) = 1.0;

uniform float pulse_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float pulse_speed : hint_range(0.0, 120.0, 0.01) = 1.3;
uniform float flicker_strength : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float flicker_speed : hint_range(0.0, 360.0, 0.1) = 12.0;
uniform float flicker_randomness : hint_range(0.0, 6.0, 0.01) = 0.28;
uniform float seed_offset : hint_range(0.0, 1000.0, 0.1) = 17.0;

// 0 Normal, 1 Add, 2 Screen, 3 Multiply, 4 Overlay, 5 Soft Light
uniform float blend_style : hint_range(0.0, 5.0, 1.0) = 1.0;
uniform float blend_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

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

vec3 overlay_blend(vec3 base, vec3 layer) {
	vec3 low = 2.0 * base * layer;
	vec3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - layer);
	return mix(low, high, step(vec3(0.5), base));
}

vec3 soft_light_blend(vec3 base, vec3 layer) {
	vec3 dark = 2.0 * base * layer + base * base * (1.0 - 2.0 * layer);
	vec3 light = sqrt(max(base, vec3(0.0))) * (2.0 * layer - 1.0) + 2.0 * base * (1.0 - layer);
	return mix(dark, light, step(vec3(0.5), layer));
}

vec3 apply_blend_style(vec3 base, vec3 layer, float style) {
	if (style < 0.5) {
		return layer;
	}
	if (style < 1.5) {
		return base + layer;
	}
	if (style < 2.5) {
		return 1.0 - (1.0 - base) * (1.0 - layer);
	}
	if (style < 3.5) {
		return base * layer;
	}
	if (style < 4.5) {
		return overlay_blend(base, layer);
	}
	return soft_light_blend(base, layer);
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
	float effect_alpha = clamp(palette_color.a * glow_mask * base_texture.a * pulse * flicker * glow_intensity * opacity, 0.0, 1.0);

	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 effect_color = palette_color.rgb * glow_intensity;
	vec3 blended_color = apply_blend_style(screen_color, effect_color, blend_style);
	vec3 final_color = mix(screen_color, clamp(blended_color, 0.0, 1.0), effect_alpha * blend_amount);

	COLOR = vec4(final_color, effect_alpha);
}
