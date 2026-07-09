shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 glow_color : source_color = vec4(0.68, 0.18, 1.0, 0.45);
uniform float core_radius : hint_range(0.0, 0.5, 0.01) = 0.14;
uniform float edge_radius : hint_range(0.1, 0.75, 0.01) = 0.5;
uniform float falloff : hint_range(0.5, 8.0, 0.1) = 2.8;
uniform float pixel_steps : hint_range(4.0, 96.0, 1.0) = 28.0;
uniform float pulse_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.1) = 1.3;

void fragment() {
	vec2 pixel_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	float distance_from_center = distance(pixel_uv, vec2(0.5));
	float glow_mask = 1.0 - smoothstep(core_radius, edge_radius, distance_from_center);
	glow_mask = pow(clamp(glow_mask, 0.0, 1.0), falloff);

	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	vec4 base_texture = texture(TEXTURE, UV);
	COLOR = vec4(glow_color.rgb, glow_color.a * glow_mask * pulse * base_texture.a);
}
