shader_type canvas_item;

uniform float phase = 0.0;
uniform float sway_scale = 1.0;
uniform float wind_strength_pixels = 0.5;
uniform float wind_speed = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);

void vertex() {
	float top_influence = pow(1.0 - UV.y, 2.0);
	float gust = sin(TIME * wind_speed * 2.2 + phase + VERTEX.y * 0.035);
	VERTEX.x += gust * wind_strength_pixels * sway_scale * top_influence * wind_direction.x;
	VERTEX.y += gust * wind_strength_pixels * sway_scale * top_influence * wind_direction.y * 0.25;
}
