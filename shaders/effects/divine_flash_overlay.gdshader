shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 flash_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float flash_intensity : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float flash_speed : hint_range(0.0, 12.0, 0.01) = 1.35;
uniform float flash_width : hint_range(0.02, 1.0, 0.01) = 0.22;
uniform float manual_phase : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float auto_flash_amount : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float center_bias : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float edge_bloom : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float mask_power : hint_range(0.1, 8.0, 0.1) = 1.0;
uniform float use_texture_alpha_mask : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float pixel_steps : hint_range(16.0, 256.0, 1.0) = 96.0;

void fragment() {
	vec2 stepped_uv = floor(UV * pixel_steps) / pixel_steps + vec2(0.5 / pixel_steps);
	float dist = distance(stepped_uv, vec2(0.5));
	float center = 1.0 - smoothstep(center_bias, 0.88, dist);
	float edge = smoothstep(0.45, 0.95, dist) * edge_bloom;
	float shape_mask = clamp(center + edge, 0.0, 1.0);

	float phase = mix(manual_phase, fract(TIME * flash_speed), auto_flash_amount);
	float burst = 1.0 - smoothstep(0.0, flash_width, phase);
	burst *= 1.0 - smoothstep(1.0 - flash_width, 1.0, phase);

	float tex_alpha = texture(TEXTURE, UV).a;
	float texture_mask = pow(max(tex_alpha, 0.0001), mask_power);
	float final_mask = mix(1.0, texture_mask, use_texture_alpha_mask);
	COLOR = vec4(flash_color.rgb, flash_color.a * flash_intensity * burst * shape_mask * final_mask);
}
