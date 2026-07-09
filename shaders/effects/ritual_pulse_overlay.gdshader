shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 glow_color : source_color = vec4(0.58, 0.12, 0.9, 0.42);
uniform float glow_strength : hint_range(0.0, 3.0, 0.01) = 0.55;
uniform float pulse_speed : hint_range(0.0, 6.0, 0.01) = 0.55;
uniform float pulse_min : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float pulse_max : hint_range(0.0, 2.0, 0.01) = 0.72;
uniform float scan_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float scan_speed : hint_range(-4.0, 4.0, 0.01) = 0.18;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.05;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float line_alpha = smoothstep(alpha_cutoff, 1.0, tex.a);
	float pulse = mix(pulse_min, pulse_max, 0.5 + 0.5 * sin(TIME * pulse_speed));
	float scan = sin((UV.x + UV.y + TIME * scan_speed) * 48.0) * 0.5 + 0.5;
	float energy = pulse + scan * scan_strength;
	COLOR = vec4(glow_color.rgb, glow_color.a * line_alpha * glow_strength * energy);
}
