shader_type canvas_item;
render_mode unshaded;

uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform vec4 grass_base : source_color = vec4(0.180, 0.310, 0.095, 1.0);
uniform vec4 grass_patch_a : source_color = vec4(0.230, 0.370, 0.105, 1.0);
uniform vec4 grass_patch_b : source_color = vec4(0.135, 0.245, 0.075, 1.0);
uniform float macro_scale : hint_range(0.0001, 0.01, 0.0001) = 0.00075;
uniform float detail_scale : hint_range(0.0001, 0.01, 0.0001) = 0.0021;
uniform float patch_threshold_a : hint_range(0.0, 1.0, 0.001) = 0.58;
uniform float patch_threshold_b : hint_range(0.0, 1.0, 0.001) = 0.72;
uniform float pixel_block_pixels : hint_range(1.0, 8.0, 1.0) = 3.0;
uniform float tonal_variation : hint_range(0.0, 0.2, 0.001) = 0.045;
uniform float world_seed = 91373.0;

varying vec2 world_position;


void vertex() {
	world_position = (
		MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)
	).xy;
}


void fragment() {
	float block_size = max(pixel_block_pixels, 1.0);
	vec2 snapped_world = floor(world_position / block_size) * block_size;
	vec2 seed_offset = vec2(
		fract(world_seed * 0.000013),
		fract(world_seed * 0.000029)
	);

	float macro_noise = texture(
		patch_noise,
		snapped_world * macro_scale + seed_offset
	).r;
	float detail_noise = texture(
		patch_noise,
		snapped_world * detail_scale + seed_offset.yx + vec2(0.41, 0.17)
	).r;

	vec3 tint = grass_base.rgb;
	if (macro_noise > patch_threshold_a) {
		tint = grass_patch_a.rgb;
	}
	if (detail_noise > patch_threshold_b) {
		tint = grass_patch_b.rgb;
	}

	float tone = (macro_noise - 0.5) * tonal_variation;
	tint *= 1.0 + tone;
	COLOR = vec4(tint, 1.0);
}
