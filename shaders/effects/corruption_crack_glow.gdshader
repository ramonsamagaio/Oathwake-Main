shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 crack_color : source_color = vec4(0.62, 0.05, 0.12, 0.48);
uniform vec4 corruption_color : source_color = vec4(0.42, 0.05, 0.88, 0.38);
uniform float glow_strength : hint_range(0.0, 3.0, 0.01) = 0.5;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.01) = 0.36;
uniform float pulse_depth : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float ember_scan_speed : hint_range(-4.0, 4.0, 0.01) = 0.14;
uniform float ember_scan_scale : hint_range(1.0, 120.0, 0.1) = 28.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.08;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = smoothstep(alpha_cutoff, 1.0, tex.a);
	float pulse = 1.0 - pulse_depth + (sin(TIME * pulse_speed) * 0.5 + 0.5) * pulse_depth;
	float scan = sin((UV.x - UV.y + TIME * ember_scan_speed) * ember_scan_scale) * 0.5 + 0.5;
	vec3 mixed_color = mix(corruption_color.rgb, crack_color.rgb, scan);
	float alpha = mix(corruption_color.a, crack_color.a, scan) * mask * glow_strength * pulse;
	COLOR = vec4(mixed_color, alpha);
}
