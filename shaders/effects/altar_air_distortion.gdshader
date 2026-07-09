shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float distortion_strength : hint_range(0.0, 0.04, 0.0005) = 0.004;
uniform float wave_scale : hint_range(1.0, 80.0, 0.1) = 18.0;
uniform float wave_speed : hint_range(0.0, 8.0, 0.01) = 0.22;
uniform float mask_radius : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float mask_softness : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.38;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= 1.16;
	float dist = length(centered);
	float mask = 1.0 - smoothstep(mask_radius, mask_radius + mask_softness, dist);

	float wave_x = sin((UV.y + TIME * wave_speed) * wave_scale) * distortion_strength;
	float wave_y = cos((UV.x - TIME * wave_speed * 0.7) * wave_scale * 0.75) * distortion_strength * 0.55;
	vec2 screen_uv = SCREEN_UV + vec2(wave_x, wave_y) * mask;
	vec4 warped = texture(screen_texture, screen_uv);
	vec4 original = texture(screen_texture, SCREEN_UV);
	COLOR = mix(original, warped, mask * opacity);
}
