// Stable Godot 4 screen-space adaptation of the requested Gaussian Glow shader:
// https://godotshaders.com/shader/gaussian-glow/
// Uses the engine-generated mip chain from hint_screen_texture instead of
// dynamic loops or repeated manual blur passes.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float bloom_threshold : hint_range(0.0, 2.0, 0.01) = 0.68;
uniform float bloom_intensity : hint_range(0.0, 5.0, 0.01) = 0.78;
uniform int blur_iterations : hint_range(1, 4, 1) = 1;
uniform float blur_size : hint_range(0.0, 0.03, 0.0001) = 0.0040;
uniform int blur_subdivisions : hint_range(4, 16, 1) = 8;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 0.18;

void fragment() {
	vec4 base_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = base_color.rgb;
	if (enabled && bloom_intensity > 0.0 && mix_amount > 0.0) {
		float blur_lod = clamp(
			0.65 + float(blur_iterations) * 0.45 + blur_size * 260.0 + float(blur_subdivisions) * 0.025,
			0.5,
			5.5
		);
		vec3 blur_near = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
		vec3 blur_far = textureLod(screen_texture, SCREEN_UV, min(blur_lod + 1.0, 6.0)).rgb;
		vec3 blurred_color = mix(blur_near, blur_far, 0.32);
		float brightest_channel = max(max(blurred_color.r, blurred_color.g), blurred_color.b);
		float threshold_gate = smoothstep(bloom_threshold, bloom_threshold + 0.16, brightest_channel);
		vec3 bloom_color = max(blurred_color - vec3(bloom_threshold), vec3(0.0));
		bloom_color *= bloom_intensity * threshold_gate;
		vec3 clamped_bloom = clamp(bloom_color, vec3(0.0), vec3(1.0));
		vec3 screen_blend = vec3(1.0) - (vec3(1.0) - base_color.rgb) * (vec3(1.0) - clamped_bloom);
		output_rgb = mix(base_color.rgb, screen_blend, mix_amount);
	}
	COLOR = vec4(output_rgb, base_color.a);
}
