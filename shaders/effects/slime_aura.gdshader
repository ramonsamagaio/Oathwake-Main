shader_type canvas_item;
render_mode unshaded, blend_add;

uniform bool enabled = true;
uniform vec4 glow_color : source_color = vec4(0.28, 1.0, 0.48, 0.42);
uniform float intensity : hint_range(0.0, 4.0, 0.01) = 1.15;
uniform float pulse_speed : hint_range(0.0, 12.0, 0.01) = 2.2;
uniform float pulse_strength : hint_range(0.0, 0.8, 0.01) = 0.12;

void fragment() {
	vec4 radial = texture(TEXTURE, UV);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	float alpha = radial.a * glow_color.a * intensity * pulse;
	if (!enabled) {
		alpha = 0.0;
	}
	COLOR = vec4(glow_color.rgb * intensity, clamp(alpha, 0.0, 1.0));
}
