shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 shadow_color : source_color = vec4(0.02, 0.024, 0.035, 1.0);
uniform float shadow_opacity : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float softness : hint_range(0.0, 16.0, 0.1) = 0.0;

float sample_mask(vec2 uv_value) {
	return textureLod(screen_texture, uv_value, 0.0).a;
}

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE * softness;
	float center = sample_mask(SCREEN_UV);
	float alpha = center;
	if (softness > 0.001) {
		alpha = center * 0.24;
		alpha += sample_mask(SCREEN_UV + vec2(pixel.x, 0.0)) * 0.10;
		alpha += sample_mask(SCREEN_UV - vec2(pixel.x, 0.0)) * 0.10;
		alpha += sample_mask(SCREEN_UV + vec2(0.0, pixel.y)) * 0.10;
		alpha += sample_mask(SCREEN_UV - vec2(0.0, pixel.y)) * 0.10;
		alpha += sample_mask(SCREEN_UV + pixel) * 0.06;
		alpha += sample_mask(SCREEN_UV - pixel) * 0.06;
		alpha += sample_mask(SCREEN_UV + vec2(pixel.x, -pixel.y)) * 0.06;
		alpha += sample_mask(SCREEN_UV + vec2(-pixel.x, pixel.y)) * 0.06;
		vec2 half_pixel = pixel * 0.5;
		alpha += sample_mask(SCREEN_UV + vec2(half_pixel.x, 0.0)) * 0.03;
		alpha += sample_mask(SCREEN_UV - vec2(half_pixel.x, 0.0)) * 0.03;
		alpha += sample_mask(SCREEN_UV + vec2(0.0, half_pixel.y)) * 0.03;
		alpha += sample_mask(SCREEN_UV - vec2(0.0, half_pixel.y)) * 0.03;
	}
	alpha = clamp(alpha, 0.0, 1.0);
	if (alpha <= 0.001 || shadow_opacity <= 0.001) {
		discard;
	}
	COLOR = vec4(shadow_color.rgb, alpha * shadow_opacity * shadow_color.a);
}
