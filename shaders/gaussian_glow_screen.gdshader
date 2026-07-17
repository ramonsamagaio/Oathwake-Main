// Scene-filter adaptation of the CC0 Gaussian Glow shader:
// https://godotshaders.com/shader/gaussian-glow/
// Godot 4 screen filters must use hint_screen_texture and SCREEN_UV.
shader_type canvas_item;
render_mode unshaded;

uniform bool enabled = true;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float bloom_threshold : hint_range(0.0, 2.0, 0.01) = 0.82;
uniform float bloom_intensity : hint_range(0.0, 5.0, 0.01) = 0.38;
uniform int blur_iterations : hint_range(1, 4, 1) = 1;
uniform float blur_size : hint_range(0.0, 0.03, 0.0001) = 0.0025;
uniform int blur_subdivisions : hint_range(4, 16, 1) = 8;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 0.28;

vec3 extract_hdr(vec3 color_value) {
	return max((color_value - bloom_threshold) * bloom_intensity, vec3(0.0));
}

vec3 gaussian_glow(vec2 uv) {
	vec3 sum = vec3(0.0);
	float sample_count = 0.0;

	for (int iteration = 0; iteration < 4; iteration++) {
		if (iteration >= blur_iterations) {
			break;
		}
		float distance_value = blur_size * float(iteration + 1) / float(max(blur_iterations, 1));
		for (int subdivision = 0; subdivision < 16; subdivision++) {
			if (subdivision >= blur_subdivisions) {
				break;
			}
			float angle = TAU * float(subdivision) / float(max(blur_subdivisions, 1));
			vec2 offset = vec2(cos(angle), sin(angle)) * distance_value;
			sum += extract_hdr(texture(screen_texture, uv + offset).rgb);
			sample_count += 1.0;
		}
	}

	return sum / max(sample_count, 1.0);
}

vec3 screen_blend(vec3 base, vec3 glow) {
	return 1.0 - (1.0 - base) * (1.0 - glow);
}

void fragment() {
	vec4 base = texture(screen_texture, SCREEN_UV);
	if (!enabled || mix_amount <= 0.0 || bloom_intensity <= 0.0) {
		COLOR = base;
		return;
	}

	vec3 glow = gaussian_glow(SCREEN_UV) * bloom_intensity;
	vec3 combined = screen_blend(base.rgb, glow);
	COLOR = vec4(mix(base.rgb, combined, mix_amount), base.a);
}
