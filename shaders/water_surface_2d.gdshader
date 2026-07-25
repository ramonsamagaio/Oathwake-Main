// Lightweight top-down water presentation for authored polygons, sprites and
// TileMapLayers. Uses fixed analytic waves, so it requires no generated noise
// texture and stays stable under pixel-art camera scaling.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform bool enabled = true;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.43, 0.53, 0.88);
uniform vec4 deep_color : source_color = vec4(0.08, 0.19, 0.30, 0.94);
uniform vec4 highlight_color : source_color = vec4(0.58, 0.82, 0.88, 0.72);
uniform vec2 flow_direction = vec2(1.0, 0.18);
uniform float flow_speed : hint_range(0.0, 4.0, 0.01) = 0.36;
uniform float ripple_scale : hint_range(1.0, 96.0, 0.5) = 28.0;
uniform float ripple_strength : hint_range(0.0, 0.08, 0.0005) = 0.008;
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float caustic_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float edge_fade : hint_range(0.0, 0.5, 0.01) = 0.06;
uniform float night_strength : hint_range(0.0, 1.0, 0.001) = 0.0;

float water_wave(vec2 point, float time_value) {
	float first = sin(point.x * 1.13 + point.y * 0.47 + time_value * 1.70);
	float second = sin(point.x * -0.52 + point.y * 1.38 - time_value * 1.12);
	float third = sin((point.x + point.y) * 0.73 + time_value * 0.66);
	return (first * 0.48 + second * 0.34 + third * 0.18);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (!enabled) {
		COLOR = source * COLOR;
	} else {
		vec2 direction = length(flow_direction) > 0.0001 ? normalize(flow_direction) : vec2(1.0, 0.0);
		float time_value = TIME * flow_speed;
		vec2 wave_point = UV * ripple_scale + direction * time_value * 3.0;
		float wave = water_wave(wave_point, time_value);
		vec2 distortion = vec2(wave, water_wave(wave_point.yx + vec2(4.2, 1.7), -time_value)) * ripple_strength;
		vec4 distorted_source = texture(TEXTURE, clamp(UV + distortion, vec2(0.001), vec2(0.999)));
		float vertical_depth = smoothstep(0.0, 1.0, UV.y);
		vec3 water_base = mix(shallow_color.rgb, deep_color.rgb, vertical_depth * 0.72 + night_strength * 0.16);
		float source_detail = dot(distorted_source.rgb, vec3(0.3333));
		water_base = mix(water_base, water_base * distorted_source.rgb * 1.32, clamp(source_detail, 0.0, 0.56));
		float ridge = pow(clamp(wave * 0.5 + 0.5, 0.0, 1.0), 7.0);
		float moving_band = smoothstep(0.78, 0.96, sin((UV.x * 31.0 - UV.y * 17.0) + time_value * 2.3) * 0.5 + 0.5);
		float highlight = clamp(ridge * reflection_strength + moving_band * caustic_strength, 0.0, 1.0);
		vec3 result_rgb = mix(water_base, highlight_color.rgb, highlight);
		float edge_mask = smoothstep(0.0, max(edge_fade, 0.001), UV.x)
			* smoothstep(0.0, max(edge_fade, 0.001), UV.y)
			* smoothstep(0.0, max(edge_fade, 0.001), 1.0 - UV.x)
			* smoothstep(0.0, max(edge_fade, 0.001), 1.0 - UV.y);
		float authored_alpha = max(distorted_source.a, source.a);
		float result_alpha = mix(shallow_color.a, deep_color.a, vertical_depth) * edge_mask * authored_alpha;
		COLOR = vec4(result_rgb, result_alpha) * COLOR;
	}
}
