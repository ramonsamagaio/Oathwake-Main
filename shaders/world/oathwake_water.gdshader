shader_type canvas_item;
// Romestead-native water restore.
//
// The world keeps ONE Polygon2D behind the terrain, so there is no ocean tile
// grid and no 25k+ Sprite2D cost. The old Oathwake shader evaluated procedural
// FBM/noise for every visible water pixel. This version simply samples the
// original Romestead 256x256 water texture once and maps it to the native dark
// teal palette. The source texture is assigned by RomesteadNativeWaterRestore.

uniform vec4 deep_color : source_color = vec4(0.105, 0.205, 0.275, 1.0);
uniform vec4 mid_color : source_color = vec4(0.150, 0.305, 0.365, 1.0);
uniform vec4 light_color : source_color = vec4(0.220, 0.405, 0.445, 1.0);
uniform float texture_world_size = 256.0;
uniform float flow_speed = 1.5;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// One source sample, gently translated so the water is alive without a
	// procedural-noise pass. Sampling is world-space, so lakes and ocean share
	// one continuous surface even though only the exposed pixels are visible.
	vec2 drift = vec2(TIME * flow_speed, TIME * flow_speed * 0.42);
	vec2 source_uv = fract((world_position + drift) / texture_world_size);
	float source_value = texture(TEXTURE, source_uv).r;

	// Romestead's source texture is grayscale modulation. Quantize it lightly so
	// it stays crisp next to the 16px world art rather than reading as a smooth
	// modern shader.
	float stepped = floor(clamp(source_value, 0.0, 0.9999) * 5.0) / 4.0;
	vec4 water = mix(deep_color, mid_color, smoothstep(0.18, 0.68, stepped));
	water = mix(water, light_color, smoothstep(0.68, 1.0, stepped) * 0.45);
	water.rgb *= mix(0.34, 1.0, daylight);
	COLOR = water;
}
