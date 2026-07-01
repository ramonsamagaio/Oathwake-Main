shader_type canvas_item;

uniform float wind_strength = 1.5;
uniform float wind_speed = 1.2;
uniform float wind_frequency = 0.04;
uniform float vertical_mask_power = 1.0;

void vertex() {
	float mask = clamp((-VERTEX.y) / 40.0, 0.0, 1.0);
	mask = pow(mask, vertical_mask_power);
	float sway = sin(TIME * wind_speed + VERTEX.y * wind_frequency) * wind_strength * mask;
	VERTEX.x += sway;
}
