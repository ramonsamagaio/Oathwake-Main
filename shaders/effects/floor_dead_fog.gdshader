shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 fog_color : source_color = vec4(0.12, 0.08, 0.18, 0.22);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float noise_scale : hint_range(1.0, 80.0, 0.1) = 18.0;
uniform float drift_speed : hint_range(-2.0, 2.0, 0.01) = 0.035;
uniform float breathe_speed : hint_range(0.0, 4.0, 0.01) = 0.22;
uniform float softness : hint_range(0.0, 1.0, 0.01) = 0.46;
uniform float center_clear_radius : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float edge_strength : hint_range(0.0, 1.0, 0.01) = 0.72;

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
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV;
	vec2 drift = vec2(TIME * drift_speed, sin(TIME * 0.17) * 0.08);
	float n1 = noise((uv + drift) * noise_scale);
	float n2 = noise((uv * 1.7 - drift * 0.7) * noise_scale * 0.55);
	float fog = smoothstep(softness, 1.0, mix(n1, n2, 0.45));

	float dist = distance(uv, vec2(0.5));
	float edge_mask = smoothstep(center_clear_radius, 0.78, dist) * edge_strength;
	float breathe = 0.85 + sin(TIME * breathe_speed) * 0.15;
	COLOR = vec4(fog_color.rgb, fog_color.a * opacity * fog * edge_mask * breathe);
}
