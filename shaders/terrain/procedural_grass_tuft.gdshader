shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_color : source_color = vec4(0.105, 0.165, 0.085, 1.0);
uniform vec4 base_color : source_color = vec4(0.175, 0.285, 0.135, 1.0);
uniform vec4 tip_color : source_color = vec4(0.285, 0.405, 0.185, 1.0);
uniform float color_variation_strength : hint_range(0.0, 0.5) = 0.11;
uniform float wind_fps : hint_range(1.0, 24.0) = 7.0;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.15;
uniform float wind_strength_pixels : hint_range(0.0, 8.0) = 1.8;
uniform float wind_world_frequency : hint_range(0.0001, 0.2) = 0.025;
uniform vec2 player_position = vec2(-100000.0, -100000.0);
uniform float interaction_radius_pixels : hint_range(0.0, 96.0) = 28.0;
uniform float interaction_bend_pixels : hint_range(0.0, 12.0) = 4.0;
varying float tuft_variation;
varying float tuft_shape;
varying float blade_height;

float blade_mask(vec2 p, float center_x, float lean, float max_height, float base_width) {
	float height = 1.0 - p.y;
	float within_height = step(height, max_height);
	float normalized_height = clamp(height / max(max_height, 0.001), 0.0, 1.0);
	float shifted_center = center_x + lean * normalized_height;
	float half_width = mix(base_width, 0.025, normalized_height);
	return step(abs(p.x - shifted_center), half_width) * within_height;
}

void vertex() {
	float height = UV.y;
	float stepped_time = floor(TIME * wind_fps) / max(wind_fps, 1.0);
	vec2 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	float phase = INSTANCE_CUSTOM.r * 6.28318530718;
	float world_phase = (world_origin.x + world_origin.y * 0.73) * wind_world_frequency;
	float wind = sin((stepped_time * wind_speed) + world_phase + phase);
	float top_influence = height * height;
	VERTEX.x += wind * wind_strength_pixels * top_influence;
	vec2 from_player = world_origin - player_position;
	float player_distance = length(from_player);
	float interaction = 1.0 - smoothstep(0.0, max(interaction_radius_pixels, 0.001), player_distance);
	float side = sign(from_player.x);
	if (abs(from_player.x) < 0.5) {
		side = sign(sin(phase));
	}
	VERTEX.x += side * interaction * interaction_bend_pixels * top_influence;
	VERTEX.y += interaction * interaction_bend_pixels * 0.35 * top_influence;
	tuft_variation = INSTANCE_CUSTOM.g;
	tuft_shape = INSTANCE_CUSTOM.b;
	blade_height = height;
}

void fragment() {
	vec2 visual_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 pixel_uv = floor(visual_uv * vec2(10.0, 12.0)) / vec2(10.0, 12.0);
	float shape_offset = (tuft_shape - 0.5) * 0.09;
	float left_blade = blade_mask(pixel_uv, 0.29, -0.10 - shape_offset, 0.72, 0.10);
	float center_blade = blade_mask(pixel_uv, 0.50, shape_offset * 0.25, 0.98, 0.115);
	float right_blade = blade_mask(pixel_uv, 0.71, 0.11 + shape_offset, 0.80, 0.095);
	float base_clump = step(0.79, pixel_uv.y) * step(abs(pixel_uv.x - 0.5), 0.28);
	float mask = max(max(left_blade, center_blade), max(right_blade, base_clump));
	if (mask < 0.5) {
		discard;
	}
	float height_t = clamp(blade_height, 0.0, 1.0);
	vec3 grass_color = mix(base_color.rgb, tip_color.rgb, height_t * 0.78);
	grass_color = mix(shadow_color.rgb, grass_color, smoothstep(0.0, 0.35, height_t));
	float variation = (tuft_variation - 0.5) * 2.0 * color_variation_strength;
	grass_color *= 1.0 + variation;
	COLOR = vec4(grass_color, 1.0);
}
