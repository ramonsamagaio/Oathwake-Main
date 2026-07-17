// Adapted from the CC0 2D Fog Overlay shader:
// https://godotshaders.com/shader/2d-fog-overlay-2/
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D noise_texture : repeat_enable, filter_nearest;
uniform float density : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform vec2 speed = vec2(0.008, 0.004);

void fragment() {
	if (!enabled) {
		COLOR = vec4(0.0);
		return;
	}

	vec2 moving_uv = UV + speed * TIME;
	float noise_value = texture(noise_texture, moving_uv).r;
	float fog = clamp(noise_value * 2.0 - 1.0, 0.0, 1.0);
	vec4 base_color = COLOR;
	COLOR = vec4(base_color.rgb, base_color.a * fog * density);
}
