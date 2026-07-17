// Adapted from the CC0 2D Fog Overlay shader:
// https://godotshaders.com/shader/2d-fog-overlay-2/
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = false;
uniform sampler2D noise_texture : repeat_enable, filter_nearest;
uniform float density : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform vec2 speed = vec2(0.008, 0.004);

void fragment() {
	vec4 output_color = vec4(0.0);
	if (enabled) {
		vec2 moving_uv = UV + speed * TIME;
		float noise_value = texture(noise_texture, moving_uv).r;
		float fog_amount = clamp(noise_value * 2.0 - 1.0, 0.0, 1.0);
		output_color = vec4(COLOR.rgb, COLOR.a * fog_amount * density);
	}
	COLOR = output_color;
}
