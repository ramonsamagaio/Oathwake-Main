shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 aura_color : source_color = vec4(0.025, 0.008, 0.05, 0.58);
uniform float inner_radius : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float outer_radius : hint_range(0.0, 1.2, 0.01) = 0.48;
uniform float irregularity : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float pulse_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float pulse_speed : hint_range(0.0, 6.0, 0.01) = 0.38;
uniform float noise_scale : hint_range(1.0, 80.0, 0.1) = 18.0;

float hash(vec2 p) {
	p = fract(p * vec2(37.2, 71.7));
	p += dot(p, p + 11.11);
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

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= 1.18;
	float n = noise(UV * noise_scale + TIME * 0.06);
	float radius = outer_radius + (n - 0.5) * irregularity;
	float dist = length(centered);
	float ring = smoothstep(radius, inner_radius, dist);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	COLOR = vec4(aura_color.rgb, aura_color.a * ring * pulse);
}
