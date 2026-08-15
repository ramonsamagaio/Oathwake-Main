shader_type canvas_item;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;
uniform float world_time = 0.0;
uniform vec3 reference_grade = vec3(1.0);

void fragment() {
	// In a CanvasItem fragment COLOR already contains the sampled tile texture.
	// Sampling TEXTURE again squares the pixel and destroys the native palette.
	vec4 tex = COLOR;
	tex.rgb *= reference_grade;
	float blue_bias = smoothstep(0.02, 0.20, tex.b - max(tex.r, tex.g * 0.72));
	float water_shimmer = (sin((UV.x + UV.y) * 180.0 + world_time * 2.4) * 0.5 + 0.5) * blue_bias;
	vec3 wet_color = tex.rgb * vec3(0.68, 0.76, 0.84);
	wet_color += vec3(0.035, 0.055, 0.070) * water_shimmer;
	tex.rgb = mix(tex.rgb, wet_color, wetness * 0.58);
	tex.rgb += vec3(lightning_flash * 0.72, lightning_flash * 0.80, lightning_flash);
	COLOR = tex;
}
