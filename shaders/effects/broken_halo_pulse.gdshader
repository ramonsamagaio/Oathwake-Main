shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 halo_color : source_color = vec4(1.0, 0.62, 0.18, 0.55);
uniform float glow_strength : hint_range(0.0, 3.0, 0.01) = 0.72;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.01) = 0.42;
uniform float flicker_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float broken_noise_scale : hint_range(1.0, 120.0, 0.1) = 34.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.05;

float hash(vec2 p) {
	p = fract(p * vec2(91.7, 243.1));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float source = smoothstep(alpha_cutoff, 1.0, tex.a);
	float pulse = 0.82 + sin(TIME * pulse_speed) * 0.18;
	float broken = step(0.18, hash(floor(UV * broken_noise_scale) + floor(TIME * 3.0)));
	float flicker = mix(1.0, broken, flicker_strength);
	COLOR = vec4(halo_color.rgb, halo_color.a * source * glow_strength * pulse * flicker);
}
