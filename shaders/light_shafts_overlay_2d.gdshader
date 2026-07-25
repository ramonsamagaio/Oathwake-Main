// Camera-covering, world-anchored shafts for forest clearings. The beams are
// intentionally broad and low-alpha so they add depth without painting over
// pixel silhouettes or UI.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform bool enabled = true;
uniform vec4 shaft_color : source_color = vec4(1.0, 0.91, 0.66, 0.11);
uniform vec2 direction = vec2(-0.38, 1.0);
uniform float intensity : hint_range(0.0, 2.0, 0.01) = 0.32;
uniform float beam_count : hint_range(1.0, 12.0, 0.1) = 4.0;
uniform float beam_width : hint_range(0.02, 0.8, 0.01) = 0.22;
uniform float softness : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float drift_speed : hint_range(0.0, 2.0, 0.01) = 0.045;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform vec2 camera_offset = vec2(0.0);
uniform float world_anchor_strength : hint_range(0.0, 2.0, 0.01) = 0.65;
uniform float night_strength : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float day_multiplier : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float night_multiplier : hint_range(0.0, 2.0, 0.01) = 0.08;

float shaft_hash(vec2 point) {
	vec3 point3 = fract(vec3(point.xyx) * 0.1031);
	point3 += dot(point3, point3.yzx + 31.32);
	return fract((point3.x + point3.y) * point3.z);
}

float shaft_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(
		mix(shaft_hash(cell), shaft_hash(cell + vec2(1.0, 0.0)), smooth_fraction.x),
		mix(shaft_hash(cell + vec2(0.0, 1.0)), shaft_hash(cell + vec2(1.0, 1.0)), smooth_fraction.x),
		smooth_fraction.y
	);
}

void fragment() {
	vec4 result = vec4(0.0);
	if (enabled && intensity > 0.0 && shaft_color.a > 0.0) {
		vec2 safe_direction = length(direction) > 0.0001 ? normalize(direction) : normalize(vec2(-0.38, 1.0));
		vec2 perpendicular = vec2(-safe_direction.y, safe_direction.x);
		vec2 anchored_uv = UV + camera_offset * world_anchor_strength;
		float across = dot(anchored_uv, perpendicular) * beam_count + TIME * drift_speed;
		float cell = fract(across);
		float distance_to_center = abs(cell - 0.5) * 2.0;
		float width_limit = clamp(beam_width, 0.02, 0.95);
		float beam = 1.0 - smoothstep(width_limit, width_limit + max(softness, 0.001), distance_to_center);
		float along = dot(anchored_uv, safe_direction);
		float breakup = mix(1.0, shaft_noise(vec2(across * 0.72, along * 3.1 - TIME * 0.025)), noise_strength);
		float vertical_fade = smoothstep(-0.18, 0.24, UV.y) * (1.0 - smoothstep(0.72, 1.12, UV.y));
		float side_fade = smoothstep(0.0, 0.10, UV.x) * smoothstep(0.0, 0.10, 1.0 - UV.x);
		float time_multiplier = mix(day_multiplier, night_multiplier, clamp(night_strength, 0.0, 1.0));
		float alpha = beam * breakup * vertical_fade * side_fade * intensity * shaft_color.a * time_multiplier;
		result = vec4(shaft_color.rgb * intensity, clamp(alpha, 0.0, 0.22));
	}
	COLOR = result;
}
